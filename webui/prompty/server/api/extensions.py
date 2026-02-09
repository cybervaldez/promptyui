"""
Extensions API Handlers

Endpoints for browsing and retrieving extension files.

GET /api/pu/extensions - List extensions tree from ext/ folder
GET /api/pu/extension/{path} - Get extension file content
"""

import re
import yaml
from pathlib import Path


def get_project_root():
    """Get project root directory (4 levels up from this file)."""
    return Path(__file__).parent.parent.parent.parent.parent


def count_extension_items(data):
    """Count text items and wildcards in extension data."""
    text_count = 0
    wildcard_count = 0

    if not data:
        return text_count, wildcard_count

    # Count text items (text, text2, text3, etc.)
    for key, value in data.items():
        if key == 'text' or re.match(r'^text\d+$', key):
            if isinstance(value, list):
                text_count += len(value)
            elif isinstance(value, str):
                text_count += 1

    # Count wildcards
    wildcards = data.get('wildcards', [])
    if isinstance(wildcards, list):
        wildcard_count = len(wildcards)

    return text_count, wildcard_count


def build_extension_tree(ext_dir):
    """
    Build hierarchical tree structure of extensions directory.

    Returns:
    {
        "themes": {
            "pixel": [
                {"file": "boss_fight.yaml", "textCount": 3, "wildcardCount": 3}
            ],
            "action": [...]
        },
        "defaults": [
            {"file": "camera.yaml", "textCount": 5, "wildcardCount": 0}
        ]
    }
    """
    tree = {}

    if not ext_dir.exists():
        return tree

    def process_directory(dir_path, parent_dict):
        """Recursively process directory and add to tree."""
        items = sorted(dir_path.iterdir())

        # Separate files and directories
        files = []
        subdirs = []

        for item in items:
            if item.is_file() and item.suffix == '.yaml':
                try:
                    with open(item, 'r') as f:
                        data = yaml.safe_load(f)
                    text_count, wildcard_count = count_extension_items(data)
                    ext_id = data.get('id', item.stem) if data else item.stem
                except:
                    text_count, wildcard_count = 0, 0
                    ext_id = item.stem

                files.append({
                    "file": item.name,
                    "id": ext_id,
                    "textCount": text_count,
                    "wildcardCount": wildcard_count
                })
            elif item.is_dir() and not item.name.startswith('.'):
                subdirs.append(item)

        # If this directory has files, add them directly
        if files:
            # Check if parent expects a list (leaf directory with files)
            # or we need to store files separately
            parent_dict["_files"] = files

        # Process subdirectories
        for subdir in subdirs:
            subdir_name = subdir.name
            parent_dict[subdir_name] = {}
            process_directory(subdir, parent_dict[subdir_name])

            # Clean up empty subdirectories
            if not parent_dict[subdir_name]:
                del parent_dict[subdir_name]

    process_directory(ext_dir, tree)
    return tree


def handle_extensions_list(handler, params):
    """
    GET /api/pu/extensions

    List all extensions from ext/ folder as hierarchical tree.

    Response:
    {
        "tree": {
            "themes": {
                "pixel": {
                    "_files": [
                        {"file": "boss_fight.yaml", "id": "boss_fight", "textCount": 3, "wildcardCount": 3}
                    ]
                }
            },
            "defaults": {
                "_files": [
                    {"file": "camera.yaml", "id": "camera", "textCount": 5, "wildcardCount": 0}
                ]
            }
        }
    }
    """
    project_root = get_project_root()
    ext_dir = project_root / "ext"

    tree = build_extension_tree(ext_dir)

    handler.send_json({"tree": tree})


def handle_extension_get(handler, ext_path, params):
    """
    GET /api/pu/extension/{path}

    Get extension file content.

    Path example: themes/pixel/boss_fight

    Response: Full YAML content as JSON object
    """
    project_root = get_project_root()

    # Handle path - add .yaml if not present
    if not ext_path.endswith('.yaml'):
        ext_path = ext_path + '.yaml'

    ext_file = project_root / "ext" / ext_path

    if not ext_file.exists():
        handler.send_json({
            "error": f"Extension not found: {ext_path}"
        }, 404)
        return

    try:
        with open(ext_file, 'r') as f:
            data = yaml.safe_load(f)

        if not data:
            handler.send_json({
                "error": "Extension file is empty"
            }, 400)
            return

        # Add metadata
        data["_path"] = ext_path
        data["_file"] = ext_file.name

        handler.send_json(data)

    except yaml.YAMLError as e:
        error_msg = str(e)
        if hasattr(e, 'problem_mark') and e.problem_mark:
            line = e.problem_mark.line + 1
            error_msg = f"YAML parse error at line {line}"
        handler.send_json({
            "error": error_msg
        }, 400)
    except Exception as e:
        handler.send_json({
            "error": str(e)
        }, 500)
