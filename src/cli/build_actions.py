"""
src/cli/build_actions.py - Build Actions Module

Implements --build covers/configs/variations/all/variants actions.
Contains BuildActionsModule class with parity to WebUI build buttons.

Debug relevance: When build actions return wrong items
"""

import json
import yaml
from pathlib import Path
from typing import Dict, List, Any, Optional

from .utils import load_manifest, load_data_json


class BuildActionsModule:
    """Test module for WebUI build action parity."""

    def __init__(self, job_dir: Path, comp_dir: Path, outputs_dir: Path,
                 debug: bool = True):
        self.job_dir = job_dir
        self.comp_dir = comp_dir
        self.outputs_dir = outputs_dir
        self.debug = debug
        self.manifest = load_manifest(outputs_dir)

    def _get_prompts(self) -> List[str]:
        """Get all prompt directories from outputs."""
        prompts = []
        # Check in outputs directory directly
        if self.comp_dir.exists():
            for prompt_dir in self.comp_dir.iterdir():
                if prompt_dir.is_dir() and prompt_dir.name != '_ops':
                    prompts.append(prompt_dir.name)
        # Fallback: check job prompts directory
        if not prompts:
            prompts_dir = self.job_dir / 'prompts'
            if prompts_dir.exists():
                for prompt_dir in prompts_dir.iterdir():
                    if prompt_dir.is_dir():
                        prompts.append(prompt_dir.name)
        return prompts

    def _get_first_path(self, prompt_id: str) -> str:
        """Get the first path for a prompt."""
        # Check in outputs
        prompt_dir = self.comp_dir / prompt_id
        if prompt_dir.exists():
            for data_json in prompt_dir.rglob('data.json'):
                return str(data_json.parent.relative_to(prompt_dir))

        # Fallback: return a placeholder
        return 'base'

    def _get_all_paths(self, prompt_id: str) -> List[str]:
        """Get all checkpoint paths within a prompt.

        Reads the prompt.json file to get all checkpoint paths.
        Falls back to directory scanning if prompt.json doesn't exist.

        Args:
            prompt_id: The prompt identifier

        Returns:
            List of path strings (e.g., ['icon-of-a[0]', 'rusty-iron-sword', ...])
        """
        paths = []

        # Try to read from prompt.json (authoritative source)
        prompt_dir = self.comp_dir / prompt_id
        prompt_json = prompt_dir / 'prompt.json'

        if prompt_json.exists():
            try:
                with open(prompt_json) as f:
                    data = json.load(f)

                # Extract path_string from each checkpoint
                checkpoints = data.get('checkpoints', [])
                for cp in checkpoints:
                    path_str = cp.get('path_string', '')
                    if path_str and path_str not in paths:
                        paths.append(path_str)

                if paths:
                    return paths
            except Exception as e:
                print(f"   Warning: Failed to read prompt.json: {e}")

        # Fallback: scan for data.json files in subdirectories
        if prompt_dir.exists():
            for data_json in prompt_dir.rglob('data.json'):
                rel_path = str(data_json.parent.relative_to(prompt_dir))
                if rel_path not in paths:
                    paths.append(rel_path)

        # Ultimate fallback
        if not paths:
            paths = ['base']

        return paths

    def _load_configs(self, prompt_id: str = None, path: str = None) -> List[Dict]:
        """Load configs from modal.json if prompt_id/path provided, else from manifest.

        Args:
            prompt_id: Prompt ID to load modal.json from (optional)
            path: Path to load modal.json from (optional)

        Returns:
            List of config dicts
        """
        # If prompt_id and path provided, load from modal.json
        if prompt_id and path:
            data_dir = self.comp_dir / prompt_id / path
            modal_json = data_dir / 'modal.json'
            if modal_json.exists():
                with open(modal_json, 'r') as f:
                    modal_data = json.load(f)
                    configs = modal_data.get('configs', [])
                    if configs:
                        return configs

        # Fallback to manifest
        if self.manifest:
            return self.manifest.get('configs', [])
        return [{'name': 'default'}]

    def _is_image_generated(self, item: dict) -> bool:
        """Check if an image is already generated.

        Checks both:
        1. PNG file existence (most reliable)
        2. data.json status field (fallback)

        Args:
            item: Generation item with prompt_id, path, address_index, config_index

        Returns:
            True if image exists and is generated, False otherwise
        """
        prompt_id = item['prompt_id']
        path_str = item['path']
        address_idx = item['address_index']
        config_idx = item['config_index']

        # Build directory path
        data_dir = self.comp_dir / prompt_id / path_str

        # Check if directory exists
        if not data_dir.exists():
            return False

        # Check for PNG files matching this address and config
        # Filename pattern: {address:04d}_c{config}_*.png
        pattern = f"{address_idx:04d}_c{config_idx}_*.png"
        matching_files = list(data_dir.glob(pattern))

        if matching_files:
            return True  # PNG exists = generated

        # Fallback: check data.json status
        data_json = data_dir / 'data.json'
        if data_json.exists():
            try:
                with open(data_json) as f:
                    data = json.load(f)

                for img in data.get('images', []):
                    if img.get('i') == address_idx:
                        status_list = img.get('status', [])
                        if config_idx < len(status_list):
                            return status_list[config_idx] == 1
            except Exception:
                pass

        return False  # Not found = not generated

    def _filter_pending_items(self, items: list) -> list:
        """Filter items to only include pending (not yet generated) images.

        This is crucial for --max to work correctly: we want to generate
        N NEW images, not take the first N from a list that includes
        already-generated images.

        Args:
            items: List of generation items

        Returns:
            Filtered list containing only pending items
        """
        pending = []
        for item in items:
            is_generated = self._is_image_generated(item)
            # Fix #3: Removed DEBUG print - was cluttering terminal output
            if not is_generated:
                pending.append(item)
        return pending

    def build_covers(self, prompt_id: str = None, config_index: int = 0, rebuild: bool = False) -> List[Dict]:
        """Build cover images (address_index=1) for all checkpoints at current config.

        Parity with WebUI "Build Covers" button.

        Args:
            prompt_id: Optional prompt ID filter
            config_index: Config index to use (default: 0)
            rebuild: Force rebuild even if exists

        Returns:
            List of generation items
        """
        items = []
        prompts = [prompt_id] if prompt_id else self._get_prompts()

        for pid in prompts:
            # Get ALL paths within prompt (not just first)
            paths = self._get_all_paths(pid)

            # Generate one cover for each checkpoint path
            for path in paths:
                items.append({
                    'prompt_id': pid,
                    'path': path,
                    'address_index': 1,  # Cover image
                    'config_index': config_index,
                    'rebuild': rebuild
                })

        return items

    def build_configs(self, prompt_id: str, path: str, config_index: int, rebuild: bool = False) -> List[Dict]:
        """Build specific config for current variation.

        Parity with WebUI "Build Config" button.

        Args:
            prompt_id: Prompt identifier
            path: Checkpoint path
            config_index: Config index to build
            rebuild: Force rebuild even if exists

        Returns:
            List of generation items
        """
        # Get all address indices from data.json
        data_dir = self.comp_dir / prompt_id / path
        data = load_data_json(data_dir)

        if data and 'images' in data:
            # Build all addresses for this config
            addresses = set(img.get('i', 0) for img in data['images'])
            return [{
                'prompt_id': prompt_id,
                'path': path,
                'address_index': addr,
                'config_index': config_index,
                'rebuild': rebuild
            } for addr in sorted(addresses)]

        return [{
            'prompt_id': prompt_id,
            'path': path,
            'address_index': 1,
            'config_index': config_index,
            'rebuild': rebuild
        }]

    def build_variations(self, prompt_id: str, path: str, address_index: int, rebuild: bool = False) -> List[Dict]:
        """Build all variations (configs) for a specific image.

        Parity with WebUI "Build Variations" button.

        Args:
            prompt_id: Prompt identifier
            path: Checkpoint path
            address_index: Address/variation index to build
            rebuild: Force rebuild even if exists

        Returns:
            List of generation items
        """
        items = []
        # Load configs from checkpoint-specific modal.json
        configs = self._load_configs(prompt_id, path)

        for idx, config in enumerate(configs):
            items.append({
                'prompt_id': prompt_id,
                'path': path,
                'address_index': address_index,
                'config_index': idx,
                'rebuild': rebuild
            })

        return items

    def build_all(self, config_index: int = 0, rebuild: bool = False) -> List[Dict]:
        """Build first variation for all base configs x all checkpoints.

        Parity with WebUI "Build All" button.

        Args:
            config_index: Config index to use (default: 0)
            rebuild: Force rebuild even if exists

        Returns:
            List of generation items
        """
        items = []
        prompts = self._get_prompts()

        for prompt_id in prompts:
            # Get all paths from outputs
            prompt_dir = self.comp_dir / prompt_id
            if prompt_dir.exists():
                for data_json in prompt_dir.rglob('data.json'):
                    path = str(data_json.parent.relative_to(prompt_dir))
                    items.append({
                        'prompt_id': prompt_id,
                        'path': path,
                        'address_index': 1,  # First address (images start at 1)
                        'config_index': config_index,
                            'rebuild': rebuild
                    })
                    break  # Only first path per prompt

        return items

    def detect_affected_variants(self, prompt_id: str, path: str) -> List[str]:
        """DEPRECATED: Legacy variants system removed.

        Variants are now handled via wildcard operations.
        Use wildcard_operations module instead.

        Returns:
            Empty list (variants no longer supported)
        """
        return []

    def build_variants(self, prompt_id: str, path: str, config_index: int = 0,
                       address_index: int = 1, rebuild: bool = False) -> List[Dict]:
        """DEPRECATED: Legacy variants system removed.

        Variants are now handled via wildcard operations.
        Use operations build methods instead.

        Returns:
            Empty list (variants no longer supported)
        """
        return []
