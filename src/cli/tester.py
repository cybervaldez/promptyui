"""
src/cli/tester.py - PipelineCLITester Class

Main orchestrator class (slimmed down) including:
- __init__: Setup and module initialization
- Operation methods: get_available_operations, load_operation
- Legacy variant methods (deprecated): get_variant_yaml_path, load_variant_ops, get_available_variants
- Test runners: run_all_tests, run_full_pipeline_test, run_hooks_tests, etc.
- Batch processing coordination

Debug relevance: When test orchestration fails
"""

import os
import json
import yaml
from pathlib import Path
from typing import Dict, List, Optional, Any

from .utils import (
    load_manifest,
    load_data_json,
    load_prompt_json,
    resolve_wildcards,
    build_base_prompt,
    apply_variant_ops
)
from .test_modules import GenerateListModule
from .build_actions import BuildActionsModule
from .generator import (
    generate_single_image,
    get_pending_images,
    setup_batch_for_build,
    finish_batch,
    update_batch_progress,
    generate_test_image
)


class PipelineCLITester:
    """Comprehensive CLI tester for the full image generation pipeline."""

    def __init__(self, job_name: str, composition: int,
                 prompt_id_filter: str = None, debug_images: int = None, rebuild: bool = False,
                 shutdown_event=None, operation: str = None):
        self.root_dir = Path.cwd()
        self.job_name = job_name  # Store job name for hooks
        self.job_dir = self.root_dir / 'jobs' / job_name
        self.outputs_dir = self.job_dir / 'outputs'
        # NOTE: Flat structure - composition ID is used for status files, not folder prefix
        # See build-checkpoints.py line 1762: "No c{composition} prefix - flat structure for runtime composition"
        self.comp_dir = self.outputs_dir
        self.operation = operation  # Wildcard operation
        self.composition = composition
        self.prompt_id_filter = prompt_id_filter
        self.debug_images = debug_images
        self.rebuild = rebuild
        self.shutdown_event = shutdown_event

        # Set DEBUG_MODE env var for AI-readable placeholder image generation
        # debug_images: None=disabled, 0=random 1-3s delay, >0=fixed delay seconds
        if debug_images is not None:
            os.environ['DEBUG_MODE'] = str(debug_images) if debug_images > 0 else '1'
            delay_info = f"{debug_images}s fixed" if debug_images > 0 else "1-3s random"
            print(f"Debug mode: Generating AI-readable placeholder images ({delay_info} delay)")

        # Validate paths
        if not self.job_dir.exists():
            raise ValueError(f"Job not found: {self.job_dir}")
        if not self.outputs_dir.exists():
            raise ValueError(f"Outputs directory not found: {self.outputs_dir}")

        # Load manifest
        self.manifest = load_manifest(self.outputs_dir)
        if not self.manifest:
            raise ValueError(f"manifest.json not found in {self.outputs_dir}")

        # Initialize modules
        self.build_module = BuildActionsModule(
            self.job_dir, self.comp_dir, self.outputs_dir, debug_images
        )
        self.generate_list_module = GenerateListModule(debug_images)

        # Batch context for WebUI integration (source highlighting)
        self.batch_id = None
        self.source = 'cli'  # Source identifier for WebUI events
        self.source_page = {}
        self.generate_list = None

    # -------------------------------------------------------------------------
    # OPERATION METHODS (Wildcard Operations)
    # -------------------------------------------------------------------------

    def load_operation(self, operation_name: str):
        """Load operation from wildcard_operations module.

        Args:
            operation_name: Name of the operation (without .yaml extension)

        Returns:
            WildcardOperation instance, or None if not found
        """
        from src.wildcard_operations import load_operation
        return load_operation(self.job_dir, operation_name)

    def get_available_operations(self) -> List[str]:
        """List available wildcard operations.

        Returns:
            List of operation names
        """
        from src.wildcard_operations import list_operations
        return list_operations(self.job_dir)

    def get_checkpoint_dirs(self, prompt_id: str = None, path_filter: str = None) -> List[Dict]:
        """Get all checkpoint directories."""
        comp_dir = self.comp_dir
        if not comp_dir.exists():
            return []

        dirs = []
        for prompt_dir in comp_dir.iterdir():
            if not prompt_dir.is_dir():
                continue
            # Skip _ops directory
            if prompt_dir.name == '_ops':
                continue
            if prompt_id and prompt_dir.name != prompt_id:
                continue

            for checkpoint_dir in prompt_dir.rglob('data.json'):
                path_string = str(checkpoint_dir.parent.relative_to(prompt_dir))
                if path_filter and path_string != path_filter:
                    continue
                dirs.append({
                    'prompt_id': prompt_dir.name,
                    'path_string': path_string,
                    'checkpoint_dir': checkpoint_dir.parent,
                    'data_json': checkpoint_dir
                })

        return dirs

    # -------------------------------------------------------------------------
    # GENERATION WRAPPERS (delegate to generator module)
    # -------------------------------------------------------------------------

    def _generate_single_image(self, prompt_id: str, path_string: str,
                               address_index: int, config_index: int,
                               wc_indices: dict, rebuild: bool = None) -> bool:
        """Generate a single image using the full HookPipeline."""
        return generate_single_image(
            self, prompt_id, path_string, address_index, config_index,
            wc_indices, rebuild, self.shutdown_event
        )

    def get_pending_images(self, prompt_filter: str = None, max_count: int = None) -> List[Dict]:
        """Find all images with pending status (status=0) from data.json files."""
        return get_pending_images(self, prompt_filter, max_count)

    def setup_batch_for_build(self, items: list, title: str, build_action: str) -> None:
        """Create a batch for build action to enable WebUI source highlighting."""
        setup_batch_for_build(self, items, title, build_action)

    def finish_batch(self) -> None:
        """Mark batch as complete and push event."""
        finish_batch(self)

    def update_batch_progress(self) -> None:
        """Update batch progress after each item."""
        update_batch_progress(self)

    def generate_test_image(self, address_index: int = 1) -> tuple:
        """Generate an actual test image using generate.py."""
        return generate_test_image(self, address_index)

    def _load_wc_indices(self, prompt_id: str, path: str, address_index: int) -> dict:
        """Load wildcard indices for a specific image from data.json."""
        data_json_path = self.comp_dir / prompt_id / path / 'data.json'

        if not data_json_path.exists():
            return {}

        try:
            with open(data_json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                images = data.get('images', [])
                target_img = next((img for img in images if img.get('i') == address_index), None)
                if target_img:
                    return target_img.get('wc', {})
        except Exception as e:
            print(f"       Warning: Could not load wc_indices: {e}")

        return {}

    # -------------------------------------------------------------------------
    # BUILD ACTIONS TESTS
    # -------------------------------------------------------------------------

    def run_build_covers_test(self, prompt_id: str = None, config_index: int = 0) -> List[tuple]:
        """Test Build Covers action."""
        results = []

        print("\n" + "=" * 70)
        print("BUILD COVERS TEST" + (" (DEBUG PLACEHOLDERS)" if self.debug_images else ""))
        print("=" * 70)

        items = self.build_module.build_covers(prompt_id, config_index)
        print(f"\nGenerating cover images (address_index=1) for all checkpoints...")

        # Validate and preview
        all_valid = True
        for item in items:
            valid, missing = self.generate_list_module.validate_item(item)
            if not valid:
                all_valid = False

        self.generate_list_module.preview_queue(items)

        print(f"\nItems validated: {len(items)}/{len(items)} {'PASS' if all_valid else 'FAIL'}")
        results.append(("Build Covers", all_valid))

        return results

    def run_build_configs_test(self, prompt_id: str, path: str, config_index: int) -> List[tuple]:
        """Test Build Configs action."""
        results = []

        print("\n" + "=" * 70)
        print("BUILD CONFIGS TEST" + (" (DEBUG PLACEHOLDERS)" if self.debug_images else ""))
        print("=" * 70)

        items = self.build_module.build_configs(prompt_id, path, config_index)
        print(f"\nBuilding config {config_index} for {prompt_id}/{path}...")

        # Validate and preview
        all_valid = True
        for item in items:
            valid, missing = self.generate_list_module.validate_item(item)
            if not valid:
                all_valid = False

        self.generate_list_module.preview_queue(items)

        print(f"\nItems validated: {len(items)}/{len(items)} {'PASS' if all_valid else 'FAIL'}")
        results.append(("Build Configs", all_valid))

        return results

    def run_build_variations_test(self, prompt_id: str, path: str, address_index: int) -> List[tuple]:
        """Test Build Variations action."""
        results = []

        print("\n" + "=" * 70)
        print("BUILD VARIATIONS TEST" + (" (DEBUG PLACEHOLDERS)" if self.debug_images else ""))
        print("=" * 70)

        items = self.build_module.build_variations(prompt_id, path, address_index)
        print(f"\nBuilding all configs for {prompt_id}/{path} @ address {address_index}...")

        # Validate and preview
        all_valid = True
        for item in items:
            valid, missing = self.generate_list_module.validate_item(item)
            if not valid:
                all_valid = False

        self.generate_list_module.preview_queue(items)

        print(f"\nItems validated: {len(items)}/{len(items)} {'PASS' if all_valid else 'FAIL'}")
        results.append(("Build Variations", all_valid))

        return results

    def run_build_variants_test(self, prompt_id: str, path: str, config_index: int,
                                 address_index: int = 1) -> List[tuple]:
        """Test build variants action."""
        results = []

        print("\n" + "=" * 70)
        print("BUILD VARIANTS TEST" + (" (DEBUG PLACEHOLDERS)" if self.debug_images else ""))
        print("=" * 70)

        items = self.build_module.build_variants(prompt_id, path, config_index, address_index)

        print(f"\nGenerating variant images for {prompt_id}/{path} (i={address_index})...")
        print(f"Detected {len(items)} affected variants")

        # Validate and preview
        all_valid = True
        for item in items:
            valid, missing = self.generate_list_module.validate_item(item)
            if not valid:
                all_valid = False

        self.generate_list_module.preview_queue(items)

        print(f"\nItems validated: {len(items)}/{len(items)} {'PASS' if all_valid else 'FAIL'}")
        results.append(("Build Variants", all_valid))

        return results

    # -------------------------------------------------------------------------
    # BATCH PROCESSING
    # -------------------------------------------------------------------------

    def run_batch_processing(self, max_count: int = None) -> List[tuple]:
        """Process pending images in batch mode."""
        results = []

        print("\n" + "=" * 70)
        print("BATCH PROCESSING MODE")
        print("=" * 70)

        pending = self.get_pending_images(self.prompt_id_filter, max_count)
        print(f"   Found {len(pending)} pending images")

        if not pending:
            print("   No pending images to process")
            return [("Batch Processing", True)]

        # Process each pending image
        for i, item in enumerate(pending):
            print(f"\n   [{i+1}/{len(pending)}] {item['prompt_id']} @ {item['path_string']}")
            print(f"           img:{item['address_index']} cfg:{item['config_index']}")

            # Generate the image (debug mode creates placeholder images)
            success = self._generate_single_image(
                item['prompt_id'],
                item['path_string'],
                item['address_index'],
                item['config_index'],
                item['wc']
            )
            results.append((f"Image {i+1}: {item['prompt_id']}", success))

        return results

    # -------------------------------------------------------------------------
    # EXECUTE BUILD ACTIONS
    # -------------------------------------------------------------------------

    def execute_build_covers(self, prompt_filter: str = None, config_index: int = 0, max_count: int = None) -> List[tuple]:
        """Execute Build Covers: generate cover images (address_index=1) for all checkpoints."""
        results = []

        print("\n" + "=" * 70)
        print("BUILD COVERS - Generating cover images")
        print("=" * 70)

        items = self.build_module.build_covers(prompt_filter, config_index)
        # Filter pending items FIRST (unless rebuilding), then apply max limit
        if not self.rebuild:
            items = self.build_module._filter_pending_items(items)
        if max_count:
            items = items[:max_count]

        # Add rebuild flag to items for batch title and tracking
        for item in items:
            item['rebuild'] = self.rebuild

        print(f"   Generating {len(items)} cover images")

        # Setup batch for WebUI tracking
        self.setup_batch_for_build(items, f"Build Covers - c{config_index}", 'covers')

        for i, item in enumerate(items):
            # Check for shutdown signal
            if self.shutdown_event and self.shutdown_event.is_set():
                print("\n   Shutdown requested, stopping build...")
                break

            print(f"\n   [{i+1}/{len(items)}] {item['prompt_id']} @ {item.get('path', 'root')}")

            success = self._generate_single_image(
                item['prompt_id'],
                item.get('path', ''),
                item.get('address_index', 1),
                item.get('config_index', config_index),
                {}
            )
            results.append((f"Cover: {item['prompt_id']}", success))
            self.update_batch_progress()

        # Finish batch
        self.finish_batch()

        return results

    def execute_build_configs(self, prompt_id: str, path: str, address_index: int = 1, max_count: int = None) -> List[tuple]:
        """Execute Build Configs: generate all configs for a checkpoint."""
        results = []

        print("\n" + "=" * 70)
        print("BUILD CONFIGS - Generating all configs")
        print("=" * 70)

        items = self.build_module.build_variations(prompt_id, path, address_index)  # All configs for specified address
        # Filter pending items FIRST (unless rebuilding), then apply max limit
        if not self.rebuild:
            items = self.build_module._filter_pending_items(items)
        if max_count:
            items = items[:max_count]

        # Add rebuild flag to items for batch title and tracking
        for item in items:
            item['rebuild'] = self.rebuild

        print(f"   Generating {len(items)} config variations")

        # Setup batch for WebUI tracking
        self.setup_batch_for_build(items, f"Build Configs - {prompt_id}/{path}", 'configs')

        for i, item in enumerate(items):
            # Check for shutdown signal
            if self.shutdown_event and self.shutdown_event.is_set():
                print("\n   Shutdown requested, stopping build...")
                break

            print(f"\n   [{i+1}/{len(items)}] cfg:{item['config_index']}")

            # Load wildcard indices from data.json
            wc_indices = self._load_wc_indices(
                item['prompt_id'],
                item['path'],
                item['address_index']
            )

            success = self._generate_single_image(
                item['prompt_id'],
                item['path'],
                item['address_index'],
                item['config_index'],
                wc_indices
            )
            results.append((f"Config {item['config_index']}", success))
            self.update_batch_progress()

        # Finish batch
        self.finish_batch()

        return results

    def execute_build_variations(self, prompt_id: str, path: str, address_index: int, max_count: int = None) -> List[tuple]:
        """Execute Build Variations: generate all variations for an image."""
        results = []

        print("\n" + "=" * 70)
        print("BUILD VARIATIONS - Generating all variations")
        print("=" * 70)

        items = self.build_module.build_variations(prompt_id, path, address_index)
        # Filter pending items FIRST (unless rebuilding), then apply max limit
        if not self.rebuild:
            items = self.build_module._filter_pending_items(items)
        if max_count:
            items = items[:max_count]

        # Add rebuild flag to items for batch title and tracking
        for item in items:
            item['rebuild'] = self.rebuild

        print(f"   Generating {len(items)} variations")

        # Setup batch for WebUI tracking
        self.setup_batch_for_build(items, f"Build Variations - {prompt_id}/{path} img:{address_index}", 'variations')

        for i, item in enumerate(items):
            # Check for shutdown signal
            if self.shutdown_event and self.shutdown_event.is_set():
                print("\n   Shutdown requested, stopping build...")
                break

            print(f"\n   [{i+1}/{len(items)}] cfg:{item['config_index']}")

            # Load wildcard indices from data.json
            wc_indices = self._load_wc_indices(
                item['prompt_id'],
                item['path'],
                item['address_index']
            )

            # Generate the image (debug mode creates placeholder images)
            success = self._generate_single_image(
                item['prompt_id'],
                item['path'],
                item['address_index'],
                item['config_index'],
                wc_indices
            )
            results.append((f"Variation cfg:{item['config_index']}", success))
            self.update_batch_progress()

        # Finish batch
        self.finish_batch()

        return results

    def execute_build_all(self, max_count: int = None) -> List[tuple]:
        """Execute Build All: generate covers for all checkpoints x all base configs."""
        results = []

        print("\n" + "=" * 70)
        print("BUILD ALL - Generating all covers for all configs")
        print("=" * 70)

        items = self.build_module.build_all(config_index=0)
        # Filter pending items FIRST (unless rebuilding), then apply max limit
        if not self.rebuild:
            items = self.build_module._filter_pending_items(items)
        if max_count:
            items = items[:max_count]

        # Add rebuild flag to items for batch title and tracking
        for item in items:
            item['rebuild'] = self.rebuild

        print(f"   Generating {len(items)} images")

        # Setup batch for WebUI tracking
        self.setup_batch_for_build(items, "Build All", 'all')

        for i, item in enumerate(items):
            # Check for shutdown signal
            if self.shutdown_event and self.shutdown_event.is_set():
                print("\n   Shutdown requested, stopping build...")
                break

            print(f"\n   [{i+1}/{len(items)}] {item['prompt_id']} @ {item.get('path', 'root')} cfg:{item['config_index']}")

            # Load wildcard indices from data.json
            wc_indices = self._load_wc_indices(
                item['prompt_id'],
                item.get('path', ''),
                item.get('address_index', 1)
            )

            # Generate the image (debug mode creates placeholder images)
            success = self._generate_single_image(
                item['prompt_id'],
                item.get('path', ''),
                item.get('address_index', 1),
                item['config_index'],
                wc_indices
            )
            results.append((f"{item['prompt_id']} cfg:{item['config_index']}", success))
            self.update_batch_progress()

        # Finish batch
        self.finish_batch()

        return results

    def execute_build_variants(self, prompt_id: str, path: str, config_index: int,
                               address_index: int = 1, max_count: int = None) -> List[tuple]:
        """Execute Build Variants: generate covers for all affected variants."""
        results = []

        print("\n" + "=" * 70)
        print("BUILD VARIANTS - Generating variant covers")
        print("=" * 70)

        items = self.build_module.build_variants(prompt_id, path, config_index, address_index)

        # Filter pending items FIRST (unless rebuilding), then apply max limit
        if not self.rebuild:
            items = self.build_module._filter_pending_items(items)
        if max_count:
            items = items[:max_count]

        # Add rebuild flag to items
        for item in items:
            item['rebuild'] = self.rebuild

        print(f"   Generating {len(items)} variant images (i={address_index})")

        # Setup batch for WebUI tracking
        self.setup_batch_for_build(items, f"Build Variants - {prompt_id}/{path}", 'variants')

        for i, item in enumerate(items):
            # Check for shutdown signal
            if self.shutdown_event and self.shutdown_event.is_set():
                print("\n   Shutdown requested, stopping build...")
                break

            print(f"\n   [{i+1}/{len(items)}] Variant: {item['variant']}")
            print(f"       {item['prompt_id']} @ {item.get('path', 'root')}")

            # Load wildcard indices from data.json in default variant
            item_prompt_id = item['prompt_id']
            item_path = item.get('path', '')
            item_address_index = item.get('address_index', 1)
            item_config_index = item['config_index']

            wc_indices = self._load_wc_indices(item_prompt_id, item_path, item_address_index)

            success = self._generate_single_image(
                item_prompt_id,
                item_path,
                item_address_index,
                item_config_index,
                wc_indices
            )

            results.append((f"Image {item_prompt_id}@{item_path}", success))
            self.update_batch_progress()

        # Finish batch
        self.finish_batch()

        return results
