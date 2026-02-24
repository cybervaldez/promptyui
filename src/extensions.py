"""
src/extensions.py - Extension and Addon Management

This module handles the extension system that allows prompts to inherit and extend
configurations from reusable extension files. Extensions provide shared wildcards,
text snippets, and LoRA configurations that can be referenced across multiple prompts.

CORE CONCEPTS:
--------------
Extensions:
    YAML files in /ext/{theme}/ folders containing shared configurations.
    Each extension has an 'id' and can contain: text, text2, ..., wildcards, loras.

Addons:
    Job-local YAML files that modify global extensions. Found in job directories
    (e.g., jobs/andrea/outfit.yaml). Support three modes: merge, update, replace.

Operations:
    Post-processing filters defined in operations.yaml that modify wildcards
    after all addon processing is complete.

FUNCTIONS:
----------
merge_extension_data(target, source, ext_id):
    Merge source extension into target in-place with deduplication.
    Handles text lists, loras, and wildcard definitions.
    Returns list of change log strings.

process_addons(job_dir, global_conf):
    Scan job directory for addon YAML files and apply them to global config.
    Supports modes: 'merge' (default), 'update', 'replace'.
    Also handles 'blacklist' and 'replace' filtering within addons.

load_and_apply_operations(job_dir, global_conf):
    Load operations.yaml and apply wildcard filters to all extensions.
    Runs AFTER all addon processing is complete.

resolve_extension(path_str, global_conf):
    Resolve an extension path string using the syntax:
    - "id" - All text keys from extension
    - "id.key" - Specific key from extension
    - "id.one" - Random single item from all text keys
    - "id.key.one" - Random single item from specific key
    Returns list of resolved text strings.

is_dynamic_text_key(key):
    Check if a key is a dynamic text key ('text' or 'textN' where N is a number).

EXTENSION PATH SYNTAX:
----------------------
    "sexy-pose"           -> All text/textN values from 'sexy-pose' extension
    "sexy-pose.text"      -> Only 'text' key from extension
    "sexy-pose.pose"      -> Any custom key (like 'pose')
    "sexy-pose.one"       -> Random 1 item from all text keys
    "sexy-pose.text.one"  -> Random 1 item from 'text' key

ADDON MODES:
------------
    merge (default): Add new items, deduplicate existing
    update: Replace matching keys, preserve non-matching
    replace: Completely replace the extension

AI ASSISTANT NOTES:
-------------------
- Extension resolution happens during build_jobs() expansion phase
- Wildcards and loras cannot be resolved as text (raises ExtensionError)
- Addon files are processed in alphabetical order
- Operations.yaml is applied last, after all addons
"""

import re
import yaml
import traceback
from pathlib import Path

from src.config import load_yaml
from src.exceptions import ExtensionError


def is_dynamic_text_key(key):
    """
    Check if a key is 'text' or 'textN' (where N is a number).
    
    Dynamic text keys are special keys that can be merged and permuted
    during prompt expansion. They follow the pattern: text, text2, text3, etc.
    
    Args:
        key: String key name to check
        
    Returns:
        True if key is 'text' or matches 'textN' pattern
        
    Example:
        is_dynamic_text_key('text')    # True
        is_dynamic_text_key('text2')   # True
        is_dynamic_text_key('text99')  # True
        is_dynamic_text_key('pose')    # False
        is_dynamic_text_key('loras')   # False
    """
    return key == 'text' or re.match(r'^text\d+$', key)


def merge_extension_data(target, source, ext_id):
    """
    Merge source extension data into target extension data in-place.
    
    Handles text lists, loras lists, and wildcard definitions.
    Prevents duplicates when merging lists (preserves order).
    
    Args:
        target: Target extension dict to merge INTO (modified in-place)
        source: Source extension dict to merge FROM
        ext_id: Extension ID string for logging
        
    Returns:
        List of log strings describing changes made
        
    Behavior:
        - New keys are added directly
        - Existing text/lora lists are extended with deduplication
        - Wildcards with same name have their text lists merged
        - New wildcard definitions are appended
        
    Example:
        target = {'id': 'pose', 'text': ['standing']}
        source = {'id': 'pose', 'text': ['sitting', 'standing']}
        changes = merge_extension_data(target, source, 'pose')
        # target['text'] is now ['standing', 'sitting']
        # changes = ["Added to 'ext.pose.text':", "- sitting"]
    """
    changes = []

    # 1. Merge generic keys (text, textN, loras)
    for key, value in source.items():
        if key in ['id', 'mode', 'wildcards']:
            continue
            
        if key not in target:
            target[key] = value
            changes.append(f"Added new key 'ext.{ext_id}.{key}' with {len(value) if isinstance(value, list) else 1} items")
        else:
            # Ensure both are lists for extending
            t_val = target[key] if isinstance(target[key], list) else [target[key]]
            s_val = value if isinstance(value, list) else [value]
            
            added_items = []
            # Deduplicate while preserving order
            for item in s_val:
                if item not in t_val:
                    t_val.append(item)
                    added_items.append(item)
            
            target[key] = t_val
            
            if added_items:
                changes.append(f"Added to 'ext.{ext_id}.{key}':")
                for item in added_items:
                    changes.append(f"- {item}")

    # 2. Merge Wildcards
    if 'wildcards' in source:
        if 'wildcards' not in target:
            target['wildcards'] = source['wildcards']
            changes.append(f"Added new key 'ext.{ext_id}.wildcards' with {len(source['wildcards'])} definitions")
        else:
            # Create lookup for existing wildcards to merge content
            target_wc_map = {wc['name']: wc for wc in target['wildcards'] if 'name' in wc}
            
            for src_wc in source['wildcards']:
                name = src_wc.get('name')
                if not name:
                    continue
                
                if name in target_wc_map:
                    # Merge text lists inside the wildcard definition
                    target_wc = target_wc_map[name]
                    src_text = src_wc.get('text', [])
                    if isinstance(src_text, str):
                        src_text = [src_text]
                    
                    tgt_text = target_wc.get('text', [])
                    if isinstance(tgt_text, str):
                        tgt_text = [tgt_text]
                    
                    added_wc_text = []
                    # Deduplicate text inside the wildcard list
                    for item in src_text:
                        if item not in tgt_text:
                            tgt_text.append(item)
                            added_wc_text.append(item)
                    
                    target_wc['text'] = tgt_text
                    
                    if added_wc_text:
                        changes.append(f"Added to 'ext.{ext_id}.wildcards.{name}':")
                        for item in added_wc_text:
                            changes.append(f"- {item}")
                else:
                    # New wildcard definition, append it
                    target['wildcards'].append(src_wc)
                    changes.append(f"Added new wildcard definition 'ext.{ext_id}.wildcards.{name}'")
    
    return changes


def process_addons(job_dir, global_conf):
    """
    Scan job directory for addon YAML files and merge/replace into global config.
    
    Addons are YAML files in the job directory (excluding jobs.yaml) that modify
    global extensions. They support three modes: merge, update, replace.
    
    Args:
        job_dir: Path to job directory to scan for addon files
        global_conf: Global configuration dict (modified in-place)
        
    Side Effects:
        - Modifies global_conf['ext'] based on addon contents
        - Prints processing logs to console
        
    Addon Modes:
        merge (default):
            - Adds new items to existing extension lists
            - Deduplicates to prevent adding existing items
            - Can apply 'replace' filtering to both addon AND global data
            
        update:
            - Replaces matching keys from addon
            - Preserves keys in global that aren't in addon
            
        replace:
            - Completely replaces the existing extension
            
    Addon Format:
        id: extension-id
        mode: merge|update|replace  # optional, default: merge
        replace:                     # optional, word replacement map
          old_word: new_word
        text:                        # data to merge/update/replace
          - item1
          - item2
    """
    if 'ext' not in global_conf:
        global_conf['ext'] = []
    
    # Configuration files that should NOT be treated as addons
    EXCLUDED_FILES = {'jobs.yaml', 'hooks.yaml', 'build_stages.yaml', 'operations.yaml'}
    
    addon_files = sorted([f for f in job_dir.glob("*.yaml") if f.name not in EXCLUDED_FILES])
    
    if not addon_files:
        return

    print(f"   🧩 Scanning for addons...")

    for addon_file in addon_files:
        try:
            addon_data = load_yaml(addon_file)
            if not addon_data or 'id' not in addon_data:
                error_msg = f"Invalid addon '{addon_file.name}' (missing 'id' or empty). Addons must have an 'id' field."
                print(f"      ❌ {error_msg}")
                raise ValueError(error_msg)
                continue
                
            ext_id = addon_data['id']
            mode = addon_data.get('mode', 'merge')
            
            # Clean data (remove mode, replace; id is kept for reference)
            clean_data = {k: v for k, v in addon_data.items() if k not in ['mode', 'replace']}
            
            replace = addon_data.get('replace')

            # ALWAYS apply replace filtering to incoming addon data if replace exists
            if replace:
                from utils import apply_replace_filtering
                apply_replace_filtering(clean_data, replace, source_name="Addon Data")

            # Find existing extension in global config
            existing_idx = next((i for i, item in enumerate(global_conf['ext']) if item['id'] == ext_id), -1)

            if mode == 'replace':
                if existing_idx != -1:
                    print(f"      🔄 Addon '{addon_file.name}': Replacing global extension '{ext_id}'")
                    global_conf['ext'][existing_idx] = clean_data
                    
                    print(f"         Replaced ext.{ext_id} with:")
                    dump = yaml.dump(clean_data, default_flow_style=False, sort_keys=False)
                    for line in dump.splitlines():
                        print(f"         {line}")
                else:
                    print(f"      ➕ Addon '{addon_file.name}': Adding new extension '{ext_id}'")
                    global_conf['ext'].append(clean_data)
                    
                    print(f"         Content:")
                    dump = yaml.dump(clean_data, default_flow_style=False, sort_keys=False)
                    for line in dump.splitlines():
                        print(f"         {line}")
                    
            elif mode == 'update':
                if existing_idx != -1:
                    print(f"      🔄 Addon '{addon_file.name}': Updating extension '{ext_id}' (selective replacement)")
                    
                    target_ext = global_conf['ext'][existing_idx]
                    
                    for key, value in clean_data.items():
                        if key == 'id':
                            continue
                        target_ext[key] = value
                        print(f"         ✓ Updated key '{key}'")
                else:
                    print(f"      ➕ Addon '{addon_file.name}': Adding new extension '{ext_id}' (update mode)")
                    global_conf['ext'].append(clean_data)
                    
                    print(f"         Content:")
                    dump = yaml.dump(clean_data, default_flow_style=False, sort_keys=False)
                    for line in dump.splitlines():
                        print(f"         {line}")
                    
            else:  # mode == 'merge' (default)
                if existing_idx != -1:
                    print(f"      🔗 Addon '{addon_file.name}': Merging into global extension '{ext_id}'")
                    
                    # ALSO apply replace to EXISTING global data (Merge mode only)
                    if replace:
                        print(f"         🔄 Applying addon replace to existing global extension items...")
                        from utils import apply_replace_filtering
                        apply_replace_filtering(global_conf['ext'][existing_idx], replace, source_name="Global Data")

                    changes = merge_extension_data(global_conf['ext'][existing_idx], clean_data, ext_id)
                    
                    if changes:
                        for log in changes:
                            print(f"         {log}")
                    else:
                        print(f"         (No new items added - all duplicates)")
                else:
                    print(f"      ➕ Addon '{addon_file.name}': Adding new extension '{ext_id}' (Merge mode)")
                    global_conf['ext'].append(clean_data)
                    
                    print(f"         Content:")
                    dump = yaml.dump(clean_data, default_flow_style=False, sort_keys=False)
                    for line in dump.splitlines():
                        print(f"         {line}")
                    
        except Exception as e:
            print(f"      ❌ Error loading addon '{addon_file.name}': {e}")
            traceback.print_exc()


def load_and_apply_operations(job_dir, global_conf, variant_id="default"):
    """
    DEPRECATED: Legacy variant operations system removed.

    Wildcard operations (build hooks) are now handled by the
    wildcard_operations module and applied when compositions resolve
    (client-side in the WebUI, or at generation time via hooks).

    Use operations/ directory with wildcard_operations.py instead.

    This function is kept for backward compatibility but does nothing.
    """
    # Legacy variants system removed - operations handled by wildcard_operations module
    pass


def resolve_extension(path_str, global_conf):
    """
    Resolve an extension path string to a list of text values.
    
    Supports the extension path syntax for retrieving text data from extensions.
    Cannot resolve structured data (wildcards, loras) - those are handled separately.
    
    Args:
        path_str: Extension path string (e.g., "sexy-pose", "sexy-pose.text.one")
        global_conf: Global configuration dict containing 'ext' list
        
    Returns:
        List of resolved text strings
        
    Raises:
        ExtensionError: If extension not found or path is invalid
        
    Path Syntax:
        "id"           - All text/textN values from extension
        "id.key"       - Specific key value from extension
        "id.one"       - Random single item from all text keys
        "id.key.one"   - Random single item from specific key
        
    Example:
        # Get all text from 'sexy-pose' extension
        texts = resolve_extension("sexy-pose", global_conf)
        
        # Get random pose from 'sexy-pose.pose' key
        pose = resolve_extension("sexy-pose.pose.one", global_conf)
    """
    import random
    
    parts = path_str.split('.')
    
    # 1. Determine Mode, ID, and Key based on syntax
    is_random = False
    
    if parts[-1] == 'one':
        is_random = True
        parts = parts[:-1]
    
    if len(parts) == 1:
        ext_id = parts[0]
        ext_key = None  # Merges all text keys
    elif len(parts) == 2:
        ext_id = parts[0]
        ext_key = parts[1]
    else:
        raise ExtensionError(f"Invalid extension path format: '{path_str}'. Expected ID or ID.KEY, optionally suffixed by '.one'.")

    # Check for structured data
    if ext_key in ['wildcards', 'loras']:
        raise ExtensionError(f"Extension path '{path_str}' targets structured data ('{ext_key}') and cannot be merged into the text list.")

    extensions = global_conf.get('ext', [])
    
    for entry in extensions:
        if entry.get('id') == ext_id:
            
            resolved_data = []
            
            if ext_key:
                # Specific Key Resolution (ID.Key or ID.Key.one)
                data = entry.get(ext_key)
                if isinstance(data, list):
                    resolved_data.extend([d for d in data if isinstance(d, str)])
                elif isinstance(data, str):
                    resolved_data.append(data)

                if not resolved_data:
                    raise ExtensionError(f"Extension '{path_str}' found, but resolved data list for key '{ext_key}' is empty or contains non-string data.")
            
            else:
                # All Keys Resolution (ID or ID.one)
                for key, data in entry.items():
                    if key == 'id' or key in ['wildcards', 'loras']:
                        continue
                    
                    # Only process dynamic text keys
                    if is_dynamic_text_key(key):
                        if isinstance(data, list):
                            resolved_data.extend([d for d in data if isinstance(d, str)])
                        elif isinstance(data, str):
                            resolved_data.append(data)
                
                if not resolved_data:
                    raise ExtensionError(f"Extension '{path_str}' found, but no valid text data found in any text key (text, textN).")

            print(f"   ➕ Resolved text extension '{path_str}' (Mode: {'Random' if is_random else 'All'}, Count: {len(resolved_data)})")

            if is_random:
                return [random.choice(resolved_data)]
            else:
                return resolved_data
                
    raise ExtensionError(f"Extension ID '{ext_id}' not found in global config 'ext' section.")
