#!/usr/bin/env python3
"""
Favorites Mod - Add items to favorites.txt

Simple mod to bookmark/favorite images or artifacts from the WebUI modal.
Appends selected item details to favorites.txt in the job _artifacts folder.

UI Button: ⭐ Add to Favorites
Supports: Selected artifacts (text/image) or current image

Storage: job_dir/_artifacts/favorites/favorites.txt (job-level artifact)
"""

from pathlib import Path
from datetime import datetime
from src.artifact_manager import ArtifactManager


def ui_hook() -> dict:
    """Define UI button for modal."""
    return {
        'id': 'favorites',
        'button_label': '⭐ Add to Favorites',
        'button_icon': '⭐',
        'button_class': 'btn-mod-tool',
        'tooltip': 'Add this item or selected artifacts to favorites.txt',
        'description': 'Add current image or selected artifacts to favorites',
        'scope': 'image',
        'api_endpoint': '/api/mod/favorites/run',
        'method': 'POST',
        'accepts_artifacts': {
            'types': ['text', 'image'],  # Accept both text and image artifacts
        },
        'requires_artifacts': False,  # Works with or without selection
        'config_ui': {
            'output_file': {
                'type': 'text',
                'label': 'Output File',
                'default': 'favorites.txt',
                'description': 'Filename for favorites list (relative to job dir)'
            },
            'include_timestamp': {
                'type': 'boolean',
                'label': 'Include Timestamps',
                'default': True,
                'description': 'Add timestamp to each entry'
            }
        }
    }


def execute(context: dict, params: dict = None) -> dict:
    """
    Add current item or selected artifacts to favorites.txt.

    Context passed directly from api_mod_run:
        - prompt_id, path_string, address_index, config_index, job_dir
        - selected_artifacts: Array of selected artifact objects (if any)

    Storage: Uses ArtifactManager with scope='job' to write to:
        job_dir/_artifacts/favorites/favorites.txt
    """
    if params is None:
        params = {}

    # Use ArtifactManager for job-level storage (security compliant)
    am = ArtifactManager(context, mod_id='favorites', scope='job')

    if not am.is_available:
        return {
            'status': 'error',
            'message': 'Cannot save favorites: job_dir not available in context'
        }

    # Check for selected artifacts
    selected_artifacts = context.get('selected_artifacts', [])
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    try:
        if selected_artifacts:
            # Artifact mode: save each selected artifact
            entry = f"\n[{timestamp}] === Artifacts ({len(selected_artifacts)}) ===\n"
            for artifact in selected_artifacts:
                name = artifact.get('name', 'unknown')
                atype = artifact.get('type', '?')
                mod = artifact.get('mod', '?')
                path = artifact.get('path', artifact.get('full_path', ''))
                entry += f"  [{atype}] {name} (from: {mod})\n"
                entry += f"    {path}\n"
            am.append('favorites.txt', entry)
        else:
            # Image mode: save current image info
            prompt_id = context.get('prompt_id')
            path = context.get('path_string') or context.get('path', '')
            address_index = context.get('address_index', 1)
            config_index = context.get('config_index', 0)

            if not prompt_id or not path:
                return {
                    'status': 'error',
                    'message': f'Missing params: prompt_id={prompt_id}, path={path}'
                }

            entry = f"[{timestamp}] {prompt_id}/{path} i={address_index} c={config_index}\n"
            am.append('favorites.txt', entry)

        # Count total favorites (lines starting with '[')
        content = am.read('favorites.txt', use_stem=False) or ''
        total = sum(1 for line in content.splitlines() if line.strip().startswith('['))

        if selected_artifacts:
            msg = f'Added {len(selected_artifacts)} artifacts to favorites!'
        else:
            msg = f'Added to favorites! (Total: {total})'

        return {
            'status': 'success',
            'message': msg,
            'data': {
                'favorites_file': str(am.artifacts_dir / 'favorites.txt'),
                'artifacts_added': len(selected_artifacts) if selected_artifacts else 0,
                'total_entries': total
            }
        }
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Failed to add to favorites: {str(e)}'
        }


if __name__ == "__main__":
    # Test the mod
    import tempfile
    import shutil

    # Create temp job dir for testing
    test_job_dir = tempfile.mkdtemp(prefix='test-favorites-')

    try:
        test_context = {
            'prompt_id': 'test-prompt',
            'path_string': 'test/path[1]',
            'address_index': 5,
            'config_index': 2,
            'job_dir': test_job_dir,
            'selected_artifacts': [
                {'name': 'test.txt', 'type': 'text', 'mod': 'caption-gen', 'path': '/tmp/test.txt'},
                {'name': 'test.png', 'type': 'image', 'mod': 'segmentation', 'path': '/tmp/test.png'},
            ]
        }

        result = execute(test_context, {})
        print(f"Test result: {result}")

        # Verify file location
        expected_path = Path(test_job_dir) / '_artifacts' / 'favorites' / 'favorites.txt'
        print(f"File exists at expected location: {expected_path.exists()}")
        if expected_path.exists():
            print(f"Content:\n{expected_path.read_text()}")
    finally:
        # Cleanup
        shutil.rmtree(test_job_dir, ignore_errors=True)

