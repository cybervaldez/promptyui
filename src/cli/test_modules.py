"""
src/cli/test_modules.py - Test Module Classes

Module for CLI queue item validation and simulation.
Contains GenerateListModule for generate-list item validation.

Debug relevance: When validation tests fail
"""

from typing import List, Tuple


class GenerateListModule:
    """Test module for generate-list item validation and simulation."""

    def __init__(self, debug: bool = True):
        self.debug = debug

    def validate_item(self, item: dict) -> Tuple[bool, List[str]]:
        """Validate item structure for generate-list API.

        Args:
            item: The item dict to validate

        Returns:
            Tuple of (is_valid, missing_keys)
        """
        required = ['prompt_id', 'path', 'address_index', 'config_index']
        missing = [k for k in required if k not in item]
        return len(missing) == 0, missing

    def simulate_batch(self, items: list, title: str = None) -> dict:
        """Simulate batch creation (dry-run).

        Args:
            items: List of generation items
            title: Optional batch title

        Returns:
            Simulated batch dict
        """
        # Normalize items
        normalized = []
        for item in items:
            normalized.append({
                'prompt_id': item['prompt_id'],
                'path': item['path'],
                'address_index': item['address_index'],
                'config_index': item['config_index'],
                'variant': item.get('variant', 'default')
            })

        return {
            'id': 'test-batch-id',
            'title': title or 'CLI Test Batch',
            'items': normalized,
            'total': len(normalized),
            'status': 'simulated'
        }

    def preview_queue(self, items: list) -> None:
        """Show what would be queued.

        Args:
            items: List of items to preview
        """
        print(f"\n{'=' * 60}")
        print(f"QUEUE PREVIEW: {len(items)} items")
        print('=' * 60)
        for i, item in enumerate(items):
            print(f"  [{i + 1}] {item['prompt_id']} @ {item['path']}")
            print(f"      img:{item['address_index']} cfg:{item['config_index']} variant:{item.get('variant', 'default')}")
