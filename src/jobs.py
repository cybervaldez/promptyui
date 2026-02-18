"""
src/jobs.py - Job Building and Permutation Generation

This module contains the core job building logic that transforms prompt configurations
into a list of generation jobs. It handles extension resolution, wildcard expansion,
LoRA permutation, sampler configuration, and resolution expressions.

CORE CONCEPTS:
--------------
Job:
    A single image generation task containing:
    - prompt: Final resolved text and metadata
    - loras: List of LoRA configs to apply
    - sampler: Sampler name and parameters
    - params: Generation parameters (width, height, steps, cfg)
    - filename_suffix: Unique identifier for output filename

Build Pipeline:
    1. EXPANSION PHASE: Process extends, resolve wildcards, expand text variants
    2. PERMUTATION PHASE: Generate Cartesian product of LoRAs, samplers, resolutions
    3. FINALIZATION: Assign indices, sort for optimal LoRA loading

MAIN FUNCTION:
--------------
build_jobs(task_conf, lora_root, range_increment, prompts_delimiter, global_conf, ...):
    The main entry point that transforms a job configuration into a list of jobs.
    
    Returns list of job dicts, each containing:
    - prompt: Dict with resolved text and metadata
    - loras: List of LoRA config dicts
    - filename_suffix: String for unique filename
    - sampler: Sampler name (or None)
    - scheduler: Scheduler type (or None)
    - params: Dict with width, height, steps, cfg
    - sampler_params: Dict with additional params like shift
    - original_index: Sequential index for tracking
    - resolution_expressions: (if applicable) [width_expr, height_expr]

EXPANSION PHASE DETAILS:
------------------------
1. Process 'extends' directives to merge extension data:
   - Wildcards: Merge into current prompt's wildcard pool
   - Loras: Extend LoRA combination list
   - Text: Merge into text components (text, text2, etc.)

2. Pre-expand structured text variants based on wildcard consumption mode

3. Substitute wildcards with random values from pools

4. Generate Cartesian product of text components

PERMUTATION PHASE DETAILS:
--------------------------
1. LoRA Permutation: Each lora string expands via parse_lora_combination_string()

2. Sampler Permutation: Each sampler config can have list-valued parameters
   that generate additional combinations (e.g., shift: [1.0, 1.5])

3. Resolution Permutation: Each resolution spec creates a separate job

AI ASSISTANT NOTES:
-------------------
- This is the largest module (~600 lines), handling complex permutation logic
- Uses itertools.product extensively for Cartesian products
- Stores _original_template and _wildcards for batch tracking
- Jobs are sorted by LoRA signature for optimal model loading
- Resolution expressions are stored as-is for runtime evaluation
"""

import sys
import copy
import random
from itertools import product
from pathlib import Path

from src.config import resolve_path
from src.extensions import is_dynamic_text_key, resolve_extension
from src.wildcards import resolve_wildcards, process_text_variant, apply_text_consumption_mode
from src.loras import parse_lora_combination_string, build_suffix_string, generate_job_permutations
from src.exceptions import ExtensionError, WildcardError



def build_text_variations(items, ext_texts, ext_text_max, wildcards_max, wildcard_lookup, current_level=0, default_leaf=False):
    """
    Recursively build text variations from nested content/after structure.
    
    Returns lists of tuples: (text, template, ext_indices_dict, wildcard_indices_dict, wildcard_positions_dict, is_checkpoint)
    """
    import re
    from itertools import product
    
    if not items:
        # Base case: empty list returns empty text (is_checkpoint defaults to False for empty)
        return [('', '', {}, {}, {}, False)]
    
    results = []
    
    for item in items:
        # Tracks variations for this item (before 'after' expansion)
        base = []
        item_level = current_level + 1
        
        if 'content' in item:
            content_text = item['content']
            
            # Find wildcards in content
            wildcard_names = re.findall(r'__([a-zA-Z0-9_-]+)__', content_text)
            unique_wildcards = sorted(list(set(wildcard_names)))
            
            # Record their positions (level)
            wc_positions = {wc_name: item_level for wc_name in unique_wildcards}
            
            if unique_wildcards and wildcard_lookup:
                # EXPAND wildcards as separate variations
                values_map = {}
                for wc_name in unique_wildcards:
                    if wc_name not in wildcard_lookup:
                        values_map[wc_name] = [(f'__{wc_name}__', -1)]  # -1 = unresolved
                    else:
                        wc_values = wildcard_lookup[wc_name]
                        if wildcards_max > 0 and len(wc_values) > wildcards_max:
                            wc_values = wc_values[:wildcards_max]
                        values_map[wc_name] = [(v, i) for i, v in enumerate(wc_values)]

                lists_to_product = [values_map[wc_name] for wc_name in unique_wildcards]
                
                for combo in product(*lists_to_product):
                    expanded_text = content_text
                    wc_indices = {}
                    
                    for i, wc_name in enumerate(unique_wildcards):
                        value, idx = combo[i]
                        expanded_text = expanded_text.replace(f'__{wc_name}__', value)
                        if idx >= 0:
                            wc_indices[wc_name] = idx
                    
                    # Template preserves content_text (unresolved)
                    # is_checkpoint=False for content items (they don't have explicit checkpoint control)
                    base.append((expanded_text, content_text, {}, wc_indices, wc_positions, False))
            else:
                # is_checkpoint=False for simple content
                base.append((content_text, content_text, {}, {}, wc_positions, False))
            
        elif 'ext_text' in item:
            ext_name = item['ext_text']
            values = ext_texts.get(ext_name, [])
            
            if not values:
                print(f"   ⚠️ Warning: ext_text '{ext_name}' not found or empty")
                base = [('', '', {}, {}, {}, False)]
            else:
                if ext_text_max > 0 and len(values) > ext_text_max:
                    values = [(values[i], i) for i in range(ext_text_max)]
                else:
                    values = [(v, i) for i, v in enumerate(values)]
                
                new_base = []
                for v, idx in values:
                    wildcard_names = re.findall(r'__([a-zA-Z0-9_-]+)__', v)
                    unique_wildcards = sorted(list(set(wildcard_names)))
                    wc_positions = {wc_name: item_level for wc_name in unique_wildcards}
                    
                    if unique_wildcards and wildcard_lookup:
                        values_map = {}
                        for wc_name in unique_wildcards:
                            if wc_name not in wildcard_lookup:
                                values_map[wc_name] = [(f'__{wc_name}__', -1)]
                            else:
                                wc_values = wildcard_lookup[wc_name]
                                if wildcards_max > 0 and len(wc_values) > wildcards_max:
                                    wc_values = wc_values[:wildcards_max]
                                values_map[wc_name] = [(val, i) for i, val in enumerate(wc_values)]
                        
                        lists_to_product = [values_map[wc_name] for wc_name in unique_wildcards]
                        
                        for combo in product(*lists_to_product):
                            expanded_text = v
                            wc_indices = {}
                            for i, wc_name in enumerate(unique_wildcards):
                                value, wc_idx = combo[i]
                                expanded_text = expanded_text.replace(f'__{wc_name}__', value)
                                if wc_idx >= 0:
                                    wc_indices[wc_name] = wc_idx
                            # Use 'v' as template (preserves its wildcards)
                            # is_checkpoint=False initially, will be determined after 'after' processing
                            new_base.append((expanded_text, v, {ext_name: idx + 1}, wc_indices, wc_positions, False))
                    else:
                        # is_checkpoint=False initially
                        new_base.append((v, v, {ext_name: idx + 1}, {}, wc_positions, False))
                
                base = new_base
        else:
            # Invalid item - skip
            continue
        
        # Process 'after' continuation if present
        if 'after' in item:
            # Pass all parameters to nested items
            suffixes = build_text_variations(
                item['after'], ext_texts, ext_text_max, wildcards_max,
                wildcard_lookup, current_level=item_level, default_leaf=default_leaf
            )
            
            # Cartesian product: each base × each suffix
            new_base = []
            for b_text, b_tpl, b_indices, b_wc_indices, b_wc_positions, b_is_leaf in base:
                for s_text, s_tpl, s_indices, s_wc_indices, s_wc_positions, s_is_leaf in suffixes:
                    # Merge ext indices from both
                    merged_indices = {**b_indices, **s_indices}
                    
                    # Merge wildcard indices from both
                    merged_wc_indices = {**b_wc_indices, **s_wc_indices}
                    
                    # Merge wildcard positions (later levels override earlier if same name)
                    merged_wc_positions = {**b_wc_positions, **s_wc_positions}
                    
                    # Smart spacing: ensure space between concatenated texts to prevent
                    # wildcard collision (e.g., __foo____bar__ becoming one invalid wildcard)
                    if b_text and s_text:
                        # Only add space if neither has a separator at the boundary
                        if not b_text.rstrip().endswith((',', ' ', '\n', '\t')) and \
                           not s_text.lstrip().startswith((',', ' ', '\n', '\t')):
                            combined = b_text.rstrip() + ' ' + s_text.lstrip()
                        else:
                            combined = b_text + s_text
                    else:
                        combined = b_text + s_text
                        
                    # Smart spacing for TEMPLATE (same logic)
                    if b_tpl and s_tpl:
                        if not b_tpl.rstrip().endswith((',', ' ', '\n', '\t')) and \
                           not s_tpl.lstrip().startswith((',', ' ', '\n', '\t')):
                            combined_tpl = b_tpl.rstrip() + ' ' + s_tpl.lstrip()
                        else:
                            combined_tpl = b_tpl + s_tpl
                    else:
                        combined_tpl = b_tpl + s_tpl
                    
                    # Combined items inherit suffix's checkpoint status (deeper items control)
                    new_base.append((combined, combined_tpl, merged_indices, merged_wc_indices, merged_wc_positions, s_is_leaf))
            
            # If explicit 'checkpoint: true' requested (or default is true), keep the base items as valid outputs too
            # This allows generating the parent prompt (e.g. "waving") AND its children ("waving sitting")
            item_is_leaf = item.get('checkpoint', default_leaf)
            if item_is_leaf:
                # Mark base items as checkpoint and include them
                base_as_leaf = [(t, tpl, ei, wi, wp, True) for t, tpl, ei, wi, wp, _ in base]
                # Include both parent (checkpoint) and children (non-checkpoint unless they set checkpoint: true)
                base = base_as_leaf + new_base
            else:
                # Only keep children, mark them as non-checkpoint (unless their children set it)
                base = new_base
        else:
            # No 'after' - this is a terminal node (final level)
            # Terminal nodes default to checkpoint=True (generate images)
            # Use explicit checkpoint: false to suppress generation at terminal
            item_is_leaf = item.get('checkpoint', True)  # Changed: terminals auto-checkpoint
            base = [(t, tpl, ei, wi, wp, item_is_leaf) for t, tpl, ei, wi, wp, _ in base]
        
        results.extend(base)
    
    return results if results else [('', '', {}, {}, {}, False)]



def build_jobs(task_conf, lora_root, range_increment, prompts_delimiter, global_conf,
               composition_id, wildcards_max=0, ext_text_max=0, default_ext='defaults',
               samplers_config=None, default_params=None, input_images=None):
    """
    Build the complete job list from job configuration.
    
    This is the main entry point for job generation. It processes the job config
    through expansion, permutation, and finalization phases to produce a list
    of ready-to-execute image generation jobs.
    
    Args:
        task_conf: Job configuration dict from jobs.yaml
        lora_root: Path to LoRA directory
        range_increment: Step size for LoRA strength ranges
        prompts_delimiter: String to join text components (e.g., ", ")
        global_conf: Global config dict with extensions and system settings
        wildcards_max: Default wildcard consumption mode (0=all, N=cap all wildcards at N values)
        ext_text_max: Default text consumption mode for extensions
        default_ext: Default extension namespace (e.g., "defaults", "fashion")
        samplers_config: Sampler configuration (None, string, or list)
        default_params: Default generation parameters dict
        input_images: Dict of loaded input images for editing models
        
    Returns:
        List of job dicts, each ready for image generation
        
    Each job contains:
        - prompt: Dict with 'text', 'id', and other prompt metadata
        - loras: List of LoRA config dicts with path, strength, triggers, etc.
        - filename_suffix: Unique suffix for output filename
        - sampler: Sampler name string or None
        - scheduler: Scheduler type string or None
        - params: Dict with width, height, steps, cfg
        - sampler_params: Dict with shift and other sampler-specific params
        - original_index: 1-based sequential index
        - resolution_expressions: (optional) [width_expr, height_expr] for dynamic sizing
        
    Example:
        jobs = build_jobs(
            job_conf,
            lora_root=Path("/loras/flux"),
            range_increment=0.1,
            prompts_delimiter=", ",
            global_conf=global_conf,
            samplers_config=["euler_flow"],
            default_params={"width": 1024, "height": 1024, "steps": 9, "cfg": 1.0}
        )
        
        for job in jobs:
            print(f"Job {job['original_index']}: {job['filename_suffix']}")
    """
    # Set deterministic random seed based on composition ID for consistent job building
    # Different compositions produce different wildcard selections, matching documented behavior
    random.seed(composition_id)
    
    # Build LoRA library from config
    library = {}
    default_loras = [] 
    
    for entry in task_conf.get('loras', []):
        alias = entry.get('alias')
        fname = entry.get('name')
        if alias and fname:
            # Handle new list 'triggers' or fallback to old 'trigger' string
            triggers = entry.get('triggers')
            if not isinstance(triggers, list):
                single_trigger = entry.get('trigger', '')
                triggers = [single_trigger] if single_trigger else []
                
            library[alias] = {
                'path': resolve_path(lora_root, fname),
                'strength': entry.get('strength', 1.0),
                'triggers': [t for t in triggers if t]
            }
            if not entry.get('exclude_from_defaults', False):
                default_loras.append(alias)

    temp_jobs = [] 
    
    # =========================================================================
    # PHASE 1: EXPANSION
    # Handle 'extends', 'wildcards' and dynamic 'text' variants
    # =========================================================================
    
    expanded_prompts = []
    for p_entry in task_conf.get('prompts', []):
        if p_entry.get('skip', False):
            continue

        # Operate on a mutable copy
        p_entry_copy = p_entry.copy() 
        
        # Handle inputs field expansion for nested lists
        if 'inputs' in p_entry_copy:
            inputs_value = p_entry_copy['inputs']
            
            # Check if this is a nested list (list of lists for permutations)
            if isinstance(inputs_value, list) and inputs_value and isinstance(inputs_value[0], list):
                # Replace with first combination
                p_entry_copy['inputs'] = inputs_value[0]
                
                # Add additional entries for remaining combinations
                for input_combo in inputs_value[1:]:
                    extra_entry = p_entry.copy()
                    extra_entry['inputs'] = input_combo
                    task_conf['prompts'].append(extra_entry)
        
        # Initialize text components (dynamic keys: text, text2, ...)
        text_components = {}
        keys_to_delete = []
        
        # Check for new nested text format (list of dicts with ext_text/content/after)
        nested_text_items = None
        raw_text = p_entry_copy.get('text', [])
        if isinstance(raw_text, list) and raw_text:
            first_item = raw_text[0]
            if isinstance(first_item, dict) and ('ext_text' in first_item or 'content' in first_item):
                # New nested format detected
                nested_text_items = raw_text
                keys_to_delete.append('text')

        if not nested_text_items:
            # Old format: process dynamic text keys as before
            for key, value in p_entry_copy.items():
                if is_dynamic_text_key(key):
                    if isinstance(value, list):
                        text_components[key] = value
                        # DEPRECATION WARNING: Legacy text list format
                        if key == 'text' and value and isinstance(value[0], str):
                            print(f"   ⚠️  DEPRECATED: Prompt '{p_entry.get('id')}' uses legacy text list (strings). Please update to {{ content: ... }} dict format.")
                    elif isinstance(value, str):
                        text_components[key] = [value]
                        # DEPRECATION WARNING: Legacy string format
                        if key == 'text':
                             print(f"   ⚠️  DEPRECATED: Prompt '{p_entry.get('id')}' uses legacy text string. Please update to {{ content: ... }} dict format.")
                    keys_to_delete.append(key)
        
        # Delete keys after iteration
        for key in keys_to_delete:
            if key in p_entry_copy:
                del p_entry_copy[key]
        
        # Initialize structured lists (Wildcards, Loras)
        current_wildcards = p_entry_copy.get('wildcards')
        if not isinstance(current_wildcards, list):
            current_wildcards = []
        if 'wildcards' in p_entry_copy:
            del p_entry_copy['wildcards']
            
        current_loras = p_entry_copy.get('loras')
        if not isinstance(current_loras, list):
            current_loras = []
        if 'loras' in p_entry_copy:
            del p_entry_copy['loras']
        
        # Process 'extends' directives
        if p_entry_copy.get('extends'):
            print(f"   🔍 Processing 'extends' for prompt ID: {p_entry_copy.get('id', 'unknown')}")

            try:
                for path_str in p_entry_copy['extends']:
                    
                    # Parse Mapping Syntax (id.key:target_key)
                    source_path = path_str
                    explicit_target_key = None
                    
                    if ':' in path_str:
                        source_path, explicit_target_key = path_str.split(':', 1)
                        source_path = source_path.strip()
                        explicit_target_key = explicit_target_key.strip()
                        
                        if not is_dynamic_text_key(explicit_target_key):
                            raise ExtensionError(f"Extension '{path_str}': Explicit target key '{explicit_target_key}' must be a dynamic text key (text, textN).")

                    # Parse Source Path
                    parts = source_path.split('.')
                    
                    is_random_mode = (parts[-1] == 'one')
                    
                    if is_random_mode:
                        parts_base = parts[:-1]
                    else:
                        parts_base = parts

                    if len(parts_base) == 1:
                        ext_id = parts_base[0]
                        ext_key = None 
                    elif len(parts_base) == 2:
                        ext_id = parts_base[0]
                        ext_key = parts_base[1]
                    else:
                        raise ExtensionError(f"Invalid extension source path: '{source_path}'. Expected ID, ID.one, ID.KEY, or ID.KEY.one.")

                    # Find extension with namespace scoping
                    prompt_ext = p_entry_copy.get('ext', default_ext)
                    extensions = global_conf.get('ext', [])
                    
                    found_entry = next((entry for entry in extensions 
                                       if entry.get('id') == ext_id and entry.get('_ext') == prompt_ext), None)
                    
                    if not found_entry:
                        found_entry = next((entry for entry in extensions if entry.get('id') == ext_id), None)
                    
                    if not found_entry:
                        raise ExtensionError(f"Extension ID '{ext_id}' not found in ext '{prompt_ext}' or global config.")

                    # --- Wildcard Definition Merge ---
                    is_wildcard_target = (ext_key == 'wildcards') or (ext_key is None and not is_random_mode)
                    
                    if is_wildcard_target:
                        if explicit_target_key:
                            raise ExtensionError(f"Extension '{path_str}': Wildcard definitions cannot be mapped to a different target key.")
                            
                        data = found_entry.get('wildcards')
                        
                        if data is not None:
                            if not isinstance(data, list) or not all(isinstance(item, dict) and 'name' in item and 'text' in item for item in data):
                                raise ExtensionError(f"Extension '{path_str}' found, but data for key 'wildcards' is not a valid list of wildcard definitions.")

                            incoming_data = copy.deepcopy(data)
                            curr_wc_map = {wc['name']: wc for wc in current_wildcards if 'name' in wc}
                            
                            count_new = 0
                            count_merged = 0

                            for incoming_wc in incoming_data:
                                name = incoming_wc.get('name')
                                if not name:
                                    continue
                                
                                if name in curr_wc_map:
                                    target_wc = curr_wc_map[name]
                                    tgt_text = target_wc.get('text', [])
                                    if isinstance(tgt_text, str):
                                        tgt_text = [tgt_text]
                                    
                                    src_text = incoming_wc.get('text', [])
                                    if isinstance(src_text, str):
                                        src_text = [src_text]
                                    
                                    for item in src_text:
                                        if item not in tgt_text:
                                            tgt_text.append(item)
                                    
                                    target_wc['text'] = tgt_text
                                    count_merged += 1
                                else:
                                    current_wildcards.append(incoming_wc)
                                    curr_wc_map[name] = incoming_wc
                                    count_new += 1

                            ext_namespace = found_entry.get('_ext', 'unknown')
                            print(f"   🃏 Merged wildcards from '{ext_id}' (namespace: {ext_namespace}): {count_new} new, {count_merged} merged.")
                        elif ext_key == 'wildcards':
                            raise ExtensionError(f"Extension '{path_str}' explicitly requested 'wildcards' key, but it was not found.")
                    
                    # --- LoRAs Merge ---
                    is_loras_target = (ext_key == 'loras') or (ext_key is None)
                    
                    if is_loras_target:
                        if explicit_target_key:
                            raise ExtensionError(f"Extension '{path_str}': LoRA combinations cannot be mapped to a dynamic text key.")

                        data = found_entry.get('loras')
                        
                        if data is not None:
                            if not isinstance(data, list) or not all(isinstance(item, str) for item in data):
                                raise ExtensionError(f"Extension '{path_str}' found, but data for key 'loras' is not a valid list of strings.")

                            items_to_merge = []
                            if is_random_mode and ext_key == 'loras':
                                items_to_merge = [random.choice(data)]
                                print(f"   💊 Merging ONE random LoRA combination from '{ext_id}'.")
                            elif ext_key == 'loras' or (ext_key is None and not is_random_mode):
                                items_to_merge = data
                                print(f"   💊 Merging ALL {len(data)} LoRA combinations from '{ext_id}'.")
                            
                            current_loras.extend(items_to_merge)
                        elif ext_key == 'loras':
                            raise ExtensionError(f"Extension '{path_str}' explicitly requested 'loras' key, but it was not found.")

                    # --- Dynamic Text Merge ---
                    if ext_key not in ['wildcards', 'loras']:
                        extended_data = resolve_extension(source_path, global_conf)
                        
                        prompt_ext_text_max = p_entry_copy.get('ext_text_max', ext_text_max)
                        extended_data = apply_text_consumption_mode(extended_data, prompt_ext_text_max)
                        
                        if explicit_target_key:
                            target_component_key = explicit_target_key
                        else:
                            if ext_key:
                                target_component_key = ext_key
                            elif is_random_mode:
                                target_component_key = 'text'
                            else:
                                target_component_key = 'text'

                        if target_component_key not in text_components:
                            text_components[target_component_key] = []
                            
                        text_components[target_component_key].extend(extended_data)
                        
                        print(f"   ➕ Merged text extension '{path_str}' (Target Key: {target_component_key}, Count: {len(extended_data)})")

            except ExtensionError as e:
                print(f"   ❌ FATAL ERROR: Extension failure for prompt '{p_entry_copy.get('id', 'unknown')}'.")
                sys.exit(f"   Error: {e}")
            
            p_entry_copy['wildcards'] = current_wildcards
            p_entry_copy['loras'] = current_loras

        # =====================================================================
        # PHASE 2: PERMUTATION
        # =====================================================================

        # Pre-expand structured text variants
        if current_wildcards and text_components:
            wildcard_lookup = {wc.get('name'): wc.get('text', []) for wc in current_wildcards if wc.get('name')}
            
            for key in text_components:
                expanded_list = []
                for item in text_components[key]:
                    try:
                        prompt_wildcards_max = p_entry_copy.get('wildcards_max', p_entry_copy.get('ext_wildcards_max', wildcards_max))
                        expanded_list.extend(process_text_variant(item, wildcard_lookup, default_mode=prompt_wildcards_max))
                    except WildcardError as e:
                        print(f"   ❌ FATAL ERROR: Wildcard expansion failure for prompt '{p_entry_copy.get('id', 'unknown')}'.")
                        sys.exit(f"   Error: {e}")
                text_components[key] = expanded_list
                
        # Wildcard Substitution - Track usage for each resolved text
        original_text_components = {}
        wildcard_usage_by_resolved = {}  # resolved_text -> {wc_name: {value, index}}
        if current_wildcards and text_components:
            original_text_components = copy.deepcopy(text_components)
            
            print(f"   🃏 Processing 'wildcards' substitution...")
            keys_to_substitute = list(text_components.keys()) 
            for key in keys_to_substitute:
                text_list = text_components[key]
                try:
                    resolved_texts, usage_list = resolve_wildcards(text_list, current_wildcards, track_usage=True)
                    text_components[key] = resolved_texts
                    # Store usage mapping: resolved_text -> wc_usage dict
                    for resolved_text, usage_dict in zip(resolved_texts, usage_list):
                        if usage_dict:  # Only store if has usage
                            wildcard_usage_by_resolved[resolved_text] = usage_dict
                except WildcardError as e:
                    print(f"   ❌ FATAL ERROR: Wildcard substitution failure for prompt '{p_entry_copy.get('id', 'unknown')}'.")
                    sys.exit(f"   Error: {e}")

        # Generate Text Combinations
        text_combinations = None
        ext_indices_list = None
        
        if nested_text_items:
            # NEW NESTED FORMAT: Use build_text_variations
            # First, build ext_texts lookup from extensions
            ext_texts = {}
            prompt_ext = p_entry_copy.get('ext', default_ext)
            extensions = global_conf.get('ext', [])
            
            # Collect all unique ext_text names from the nested structure
            def collect_ext_names(items):
                names = set()
                for item in items:
                    if 'ext_text' in item:
                        names.add(item['ext_text'])
                    if 'after' in item:
                        names.update(collect_ext_names(item['after']))
                return names
            
            needed_exts = collect_ext_names(nested_text_items)
            
            # Load each extension's text values
            for ext_name in needed_exts:
                # Find extension with namespace scoping
                found_entry = next((entry for entry in extensions 
                                   if entry.get('id') == ext_name and entry.get('_ext') == prompt_ext), None)
                if not found_entry:
                    found_entry = next((entry for entry in extensions if entry.get('id') == ext_name), None)
                
                if found_entry and 'text' in found_entry:
                    text_values = found_entry.get('text', [])
                    if isinstance(text_values, str):
                        text_values = [text_values]
                    ext_texts[ext_name] = text_values
                    print(f"   📝 Loaded ext_text '{ext_name}': {len(text_values)} values")
            
            # Generate variations with ext_text_max and wildcards_max
            prompt_ext_text_max = p_entry_copy.get('ext_text_max', ext_text_max)
            prompt_wildcards_max = p_entry_copy.get('wildcards_max', p_entry_copy.get('ext_wildcards_max', wildcards_max))
            
            # Build wildcard lookup for expansion
            wildcard_lookup = {}
            if current_wildcards:
                wildcard_lookup = {wc.get('name'): wc.get('text', []) for wc in current_wildcards if wc.get('name')}
            
            # Wildcards are now EXPANDED directly in build_text_variations (not random resolution)
            prompt_default_leaf = p_entry_copy.get('checkpoint', False)
            variations = build_text_variations(
                nested_text_items, ext_texts, 
                ext_text_max=prompt_ext_text_max,
                wildcards_max=prompt_wildcards_max,
                wildcard_lookup=wildcard_lookup,
                default_leaf=prompt_default_leaf
            )
            
            # Variations are now 4-tuples: (text, ext_indices, wc_indices, wc_positions)
            # Wildcards are already resolved to explicit values with tracked indices
            unresolved_nested_templates = [v[0] for v in variations]  # These ARE resolved now
            
            # Build usage tracking from the explicit wildcard indices
            for text, _, ext_indices, wc_indices, wc_positions, is_checkpoint in variations:
                if wc_indices:
                    # Convert to the format expected by wildcard_usage_by_resolved
                    usage_dict = {}
                    for wc_name, wc_idx in wc_indices.items():
                        wc_values = wildcard_lookup.get(wc_name, [])
                        if wc_idx < len(wc_values):
                            usage_dict[wc_name] = {
                                'value': wc_values[wc_idx],
                                'index': wc_idx + 1  # 1-based for compatibility
                            }
                        else:
                            usage_dict[wc_name] = {'value': f'__{wc_name}__', 'index': wc_idx + 1}
                    wildcard_usage_by_resolved[text] = usage_dict
            
            # Unpack variations - now 6-tuples (text, template, ext, wc, pos, is_checkpoint)
            text_combinations = [(text,) for text, _, _, _, _, _ in variations]
            unresolved_nested_templates = [tpl for _, tpl, _, _, _, _ in variations]
            ext_indices_list = [ext_indices for _, _, ext_indices, _, _, _ in variations]
            wildcard_indices_list = [wc_indices for _, _, _, wc_indices, _, _ in variations]
            wildcard_positions_list = [wc_pos for _, _, _, _, wc_pos, _ in variations]
            is_leaf_list = [is_checkpoint for _, _, _, _, _, is_checkpoint in variations]
            print(f"   📋 Generated {len(text_combinations)} nested text variations")
        
        else:
            # OLD FORMAT: Cartesian product of text components
            sorted_keys = sorted(text_components.keys(), key=lambda k: (k != 'text', k))
            wildcard_indices_list = None   # Not tracked in old format
            wildcard_positions_list = None  # Not tracked in old format
            is_leaf_list = None  # Not tracked in old format
            
            if not sorted_keys:
                text_combinations = [[""]]
            else:
                text_lists_for_product = [text_components[key] for key in sorted_keys if text_components[key]]
                
                if not text_lists_for_product:
                    text_combinations = [[""]] 
                else:
                    text_combinations = list(product(*text_lists_for_product))
        
        # Create expanded prompt entries with text variation indexing
        new_expanded_prompts = []
        
        for text_var_idx, combination_tuple in enumerate(text_combinations, start=1):
            final_text_string = prompts_delimiter.join(combination_tuple).strip()
            
            # Build template with wildcards preserved for this specific variation
            # We need to map each element in combination_tuple back to its unresolved version
            if nested_text_items and unresolved_nested_templates:
                # NEW NESTED FORMAT: Use captured unresolved template
                if text_var_idx <= len(unresolved_nested_templates):
                    original_template = unresolved_nested_templates[text_var_idx - 1]
                else:
                    original_template = final_text_string
            elif original_text_components and sorted_keys:
                template_parts = []
                for i, key in enumerate(sorted_keys):
                    if i < len(combination_tuple) and key in original_text_components:
                        resolved_value = combination_tuple[i]
                        original_list = original_text_components[key]
                        resolved_list = text_components[key]
                        
                        # Find which index in resolved_list matches this element
                        try:
                            idx = resolved_list.index(resolved_value)
                            # Use the same index from the unresolved list
                            template_parts.append(original_list[idx] if idx < len(original_list) else original_list[0])
                        except (ValueError, IndexError):
                            # Fallback if not found
                            template_parts.append(original_list[0] if original_list else "")
                    else:
                        template_parts.append("")
                original_template = prompts_delimiter.join(template_parts).strip()
            else:
                original_template = final_text_string
            
            new_p_entry = p_entry_copy.copy()
            new_p_entry['text'] = final_text_string
            new_p_entry['_original_template'] = original_template
            new_p_entry['_wildcards'] = current_wildcards
            new_p_entry['loras'] = current_loras
            new_p_entry['_text_variation_index'] = text_var_idx  # 1-based index
            
            # Store tracked wildcard usage for this specific text variation
            # Look up each resolved part and merge their usage dicts
            combined_wc_usage = {}
            for part in combination_tuple:
                if part in wildcard_usage_by_resolved:
                    combined_wc_usage.update(wildcard_usage_by_resolved[part])
            if combined_wc_usage:
                new_p_entry['_wildcard_usage'] = combined_wc_usage
            
            # Add ext_indices for nested text format (for filename generation)
            if ext_indices_list and text_var_idx <= len(ext_indices_list):
                new_p_entry['_ext_indices'] = ext_indices_list[text_var_idx - 1]
            
            # Add wildcard_positions for folder hierarchy ordering
            if wildcard_positions_list and text_var_idx <= len(wildcard_positions_list):
                new_p_entry['_wildcard_positions'] = wildcard_positions_list[text_var_idx - 1]
            
            # Add is_checkpoint status for per-variation checkpoint control
            if is_leaf_list and text_var_idx <= len(is_leaf_list):
                new_p_entry['_is_leaf'] = is_leaf_list[text_var_idx - 1]
            
            new_expanded_prompts.append(new_p_entry)
            
        expanded_prompts.extend(new_expanded_prompts)
    
    # Process expanded prompts with LoRA permutation
    for p_entry in expanded_prompts:
        prompt_loras = p_entry.get('loras')
        
        if prompt_loras and isinstance(prompt_loras, list):
            for lora_str in prompt_loras:
                list_of_arrays = parse_lora_combination_string(lora_str, library, range_increment=range_increment)
                jobs_from_permutation = generate_job_permutations(p_entry, list_of_arrays)
                temp_jobs.extend(jobs_from_permutation)
        elif default_loras:
            for alias in default_loras:
                list_of_arrays = parse_lora_combination_string(alias, library, range_increment=range_increment)
                jobs_from_permutation = generate_job_permutations(p_entry, list_of_arrays)
                temp_jobs.extend(jobs_from_permutation)
        else:
            job_dict = {
                'prompt': p_entry,
                'loras': [],
                'filename_suffix': 'base'
            }
            
            if 'inputs' in p_entry:
                job_dict['inputs'] = p_entry['inputs']
            
            temp_jobs.append(job_dict)
    
    # =========================================================================
    # SAMPLER PERMUTATION PHASE
    # =========================================================================
    
    final_jobs_with_samplers = []
    
    if not samplers_config:
        active_samplers = [None]
    elif isinstance(samplers_config, str):
        active_samplers = [samplers_config]
    elif isinstance(samplers_config, list):
        active_samplers = samplers_config
    else:
        active_samplers = [None]
    
    suffix_config = global_conf.get('system', {}).get('suffixes', [])
    
    if default_params is None:
        default_params = {'width': 1024, 'height': 1024, 'steps': 9, 'cfg': 1.0}

    for job in temp_jobs:
        for s_entry in active_samplers:
            if isinstance(s_entry, dict) and s_entry.get('skip', False):
                continue
            
            # Handle None or string cases
            if s_entry is None or isinstance(s_entry, str):
                new_job = job.copy()
                current_params = default_params.copy()
                sampler_name = s_entry if isinstance(s_entry, str) else None
                scheduler_type = None
                s_params_override = {}
                
                if sampler_name:
                    sched_name = scheduler_type if scheduler_type else "simple"
                    suffix_part = f"_{sampler_name}_{sched_name}"
                    suffix_part += build_suffix_string(current_params, s_params_override, suffix_config)
                    new_job['filename_suffix'] += suffix_part
                
                new_job['sampler'] = sampler_name
                new_job['scheduler'] = scheduler_type
                new_job['params'] = current_params
                new_job['sampler_params'] = s_params_override
                final_jobs_with_samplers.append(new_job)
                continue
            
            # Handle dict case with potential list-valued parameters
            if isinstance(s_entry, dict):
                base_sampler_name = s_entry.get('sampler')
                
                permutable_params = {}
                fixed_params = {}
                standard_keys = ['sampler', 'scheduler', 'width', 'height', 'steps', 'cfg']
                
                for key, value in s_entry.items():
                    if key == 'sampler':
                        continue
                    elif isinstance(value, list):
                        permutable_params[key] = value
                    else:
                        fixed_params[key] = value
                
                if permutable_params:
                    perm_keys = list(permutable_params.keys())
                    perm_value_lists = [permutable_params[k] for k in perm_keys]
                    
                    for value_combination in product(*perm_value_lists):
                        new_job = job.copy()
                        current_params = default_params.copy()
                        
                        combined_config = fixed_params.copy()
                        for i, key in enumerate(perm_keys):
                            combined_config[key] = value_combination[i]
                        
                        sampler_name = base_sampler_name
                        scheduler_type = combined_config.get('scheduler')
                        
                        if 'width' in combined_config:
                            current_params['width'] = int(combined_config['width'])
                        if 'height' in combined_config:
                            current_params['height'] = int(combined_config['height'])
                        if 'steps' in combined_config:
                            current_params['steps'] = int(combined_config['steps'])
                        if 'cfg' in combined_config:
                            current_params['cfg'] = float(combined_config['cfg'])
                        
                        s_params_override = {}
                        for k, v in combined_config.items():
                            if k not in standard_keys:
                                s_params_override[k] = v
                        
                        if sampler_name:
                            sched_name = scheduler_type if scheduler_type else "simple"
                            suffix_part = f"_{sampler_name}_{sched_name}"
                            suffix_part += build_suffix_string(current_params, s_params_override, suffix_config)
                            new_job['filename_suffix'] += suffix_part
                        
                        new_job['sampler'] = sampler_name
                        new_job['scheduler'] = scheduler_type
                        new_job['params'] = current_params
                        new_job['sampler_params'] = s_params_override
                        final_jobs_with_samplers.append(new_job)
                else:
                    new_job = job.copy()
                    current_params = default_params.copy()
                    
                    sampler_name = base_sampler_name
                    scheduler_type = fixed_params.get('scheduler')
                    
                    if 'width' in fixed_params:
                        current_params['width'] = int(fixed_params['width'])
                    if 'height' in fixed_params:
                        current_params['height'] = int(fixed_params['height'])
                    if 'steps' in fixed_params:
                        current_params['steps'] = int(fixed_params['steps'])
                    if 'cfg' in fixed_params:
                        current_params['cfg'] = float(fixed_params['cfg'])
                    
                    s_params_override = {}
                    for k, v in fixed_params.items():
                        if k not in standard_keys:
                            s_params_override[k] = v
                    
                    if sampler_name:
                        sched_name = scheduler_type if scheduler_type else "simple"
                        suffix_part = f"_{sampler_name}_{sched_name}"
                        suffix_part += build_suffix_string(current_params, s_params_override, suffix_config)
                        new_job['filename_suffix'] += suffix_part
                    
                    new_job['sampler'] = sampler_name
                    new_job['scheduler'] = scheduler_type
                    new_job['params'] = current_params
                    new_job['sampler_params'] = s_params_override
                    final_jobs_with_samplers.append(new_job)

    # =========================================================================
    # FINALIZATION
    # =========================================================================
    
    # Assign sequential index 
    for i, job in enumerate(final_jobs_with_samplers):
        job['original_index'] = i + 1
        
    # Sort for optimized LoRA loading
    def sort_key(job):
        lora_sig = "_".join([f"{l['alias']}{l['strength']:.3g}" for l in job['loras']])
        sampler_sig = job.get('sampler') or ""
        return f"{lora_sig}_{sampler_sig}"
        
    final_jobs_with_samplers.sort(key=sort_key)
    
    # =========================================================================
    # RESOLUTION PERMUTATION PHASE
    # =========================================================================
    
    final_jobs_with_resolutions = []
    
    for job in final_jobs_with_samplers:
        prompt_entry = job['prompt']
        resolutions = prompt_entry.get('resolutions', [])
        
        if resolutions:
            for resolution in resolutions:
                if isinstance(resolution, list) and len(resolution) == 2:
                    resolution_job = copy.deepcopy(job)
                    resolution_job['resolution_expressions'] = resolution
                    final_jobs_with_resolutions.append(resolution_job)
        else:
            final_jobs_with_resolutions.append(job)
    
    return final_jobs_with_resolutions
