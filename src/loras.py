"""
src/loras.py - LoRA Handling and Strength Generation

This module handles LoRA (Low-Rank Adaptation) configuration parsing, strength range
generation, and filename suffix building for the batch generation system.

CORE CONCEPTS:
--------------
LoRA Library:
    Defined in jobs.yaml 'loras' section. Each entry has:
    - alias: Short name for referencing (e.g., "lora1")
    - name: Actual filename (e.g., "model.safetensors")
    - strength: Default strength value
    - triggers: List of trigger phrases to inject into prompts

Strength Ranges:
    LoRAs can be specified with strength ranges using ~~ syntax:
    - "lora1:0.5" - Fixed strength 0.5
    - "lora1:0.5~~1.0" - Range from 0.5 to 1.0 (generates multiple jobs)
    - "lora1:off" - Disable LoRA and remove triggers

Combinations:
    Multiple LoRAs combined with + operator:
    - "lora1:0.8+lora2:0.5" - Both LoRAs at specified strengths
    
    Combined with ranges:
    - "lora1:0.5~~1.0+lora2:0.8" - Permutes all lora1 strengths with fixed lora2

FUNCTIONS:
----------
generate_range_values(start_str, end_str=None, increment=0.1):
    Generate list of strength values from start to end with given increment.
    Returns [start] if end_str is None.

get_precision_from_increment(increment):
    Calculate decimal places needed for display based on increment.
    Used for clean filename formatting (e.g., 0.05 -> 2 decimals).

parse_lora_combination_string(lora_str, library, range_increment=0.1):
    Parse a LoRA combination string into a list of strength/trigger arrays.
    Handles +, :, ~~, and 'off' syntax.
    Returns list of arrays suitable for Cartesian product.

build_suffix_string(params, sampler_params, suffix_config):
    Build filename suffix from generation parameters.
    Uses suffix_config from config.yaml for customization.
    Returns string like "_cfg[1.0]_s[9]_w[1024]_h[1024]".

generate_job_permutations(prompt_entry, list_of_strength_arrays):
    Generate Cartesian product of all LoRA strength combinations.
    Returns list of job dicts with loras and filename_suffix.

LORA COMBINATION SYNTAX:
------------------------
    "lora1"              - Default strength from library
    "lora1:0.8"          - Fixed strength 0.8
    "lora1:0.5~~1.0"     - Range from 0.5 to 1.0
    "lora1:off"          - Disable LoRA, remove triggers from prompt
    "lora1:0.0"          - Strength 0 but keep triggers
    "lora1:0.8+lora2:0.5" - Multiple LoRAs combined

FILENAME SUFFIX FORMAT:
-----------------------
    Default: _lora1[0.80]_lora2[0.50]_cfg[1.0]_s[9]_w[1024]_h[1024]
    
    Configurable via suffix_config in config.yaml:
    - name: Parameter name
    - alias: Short name for filename (optional)
    - show: Whether to include in suffix (optional)

AI ASSISTANT NOTES:
-------------------
- Triggers can be a list of strings for multi-trigger LoRAs
- "off" removes triggers entirely, "0.0" keeps triggers with zero weight
- Filename precision matches range_increment (0.05 -> 2 decimal places)
- parse_lora_combination_string returns nested lists for product()
"""

from itertools import product

from src.config import resolve_path


def generate_range_values(start_str, end_str=None, increment=0.1):
    """
    Generate a list of strength values from start to end (inclusive).
    
    Uses torch.linspace for accurate floating point stepping, avoiding
    cumulative rounding errors from repeated addition.
    
    Args:
        start_str: Starting value as string or number
        end_str: Ending value as string or number (None for single value)
        increment: Step size between values (default 0.1)
        
    Returns:
        List of float values, rounded to 3 decimal places
        Returns [start] if end_str is None or start == end
        Returns [] on ValueError
        
    Example:
        generate_range_values("0.5")
        # -> [0.5]
        
        generate_range_values("0.5", "1.0", 0.1)
        # -> [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        
        generate_range_values("0.0", "1.0", 0.25)
        # -> [0.0, 0.25, 0.5, 0.75, 1.0]
    """
    try:
        start = float(start_str)
        
        if end_str is None:
            return [start]

        end = float(end_str)
        
        if start == end:
            return [start]
            
        increment = max(0.001, float(increment))
            
        diff = end - start
        
        if abs(diff) < increment:
            num_steps = 2
        else:
            num_steps = round(abs(diff) / increment) + 1
        
        if num_steps == 1:
            values = [start]
        else:
            values = [start + i * (end - start) / (num_steps - 1) for i in range(num_steps)]
        
        # Round values to 3 decimal places for clean storage/comparison
        return [round(v, 3) for v in values]
        
    except ValueError:
        return []


def get_precision_from_increment(increment):
    """
    Calculate the number of decimal places needed for display based on increment.
    
    Used to format strength values in filenames with appropriate precision.
    Trailing zeros in the increment's decimal part are ignored.
    
    Args:
        increment: Numeric increment value
        
    Returns:
        Integer number of decimal places (minimum 1)
        
    Example:
        get_precision_from_increment(0.1)   # -> 1
        get_precision_from_increment(0.05)  # -> 2
        get_precision_from_increment(0.25)  # -> 2
        get_precision_from_increment(1.0)   # -> 1
    """
    s = str(increment).split('.')
    if len(s) > 1:
        return len(s[1].rstrip('0'))
    return 1


def parse_lora_combination_string(lora_combination_str, library, range_increment=0.1):
    """
    Parse a LoRA combination string into arrays for permutation.
    
    Handles the full LoRA combination syntax including multiple LoRAs,
    strength ranges, and special 'off' mode.
    
    Args:
        lora_combination_str: String like "lora1:0.5~~1.0+lora2:0.8"
        library: Dict mapping aliases to LoRA definitions
        range_increment: Step size for strength ranges
        
    Returns:
        List of arrays, where each array contains config dicts for one LoRA.
        Each config dict has: path, strength, alias, triggers, suffix_part, remove_trigger
        
        The returned structure is designed for itertools.product() to generate
        all permutations.
        
    Config Dict Fields:
        path: Resolved path to LoRA file
        strength: Float strength value
        alias: LoRA alias for identification
        triggers: List of trigger phrases (empty if 'off')
        suffix_part: Filename suffix string like "lora1[0.80]"
        remove_trigger: Boolean, True if 'off' was specified
        
    Example:
        library = {"lora1": {"path": "/loras/model.safetensors", "strength": 1.0, "triggers": ["trigger phrase"]}}
        
        result = parse_lora_combination_string("lora1:0.5~~0.7", library, 0.1)
        # Returns: [[
        #   {"alias": "lora1", "strength": 0.5, "suffix_part": "lora1[0.5]", ...},
        #   {"alias": "lora1", "strength": 0.6, "suffix_part": "lora1[0.6]", ...},
        #   {"alias": "lora1", "strength": 0.7, "suffix_part": "lora1[0.7]", ...}
        # ]]
    """
    # Determine dynamic precision
    precision = get_precision_from_increment(range_increment)
    format_spec = f".{precision}f"
    
    parts = lora_combination_str.split('+')
    list_of_strength_arrays = []
    
    for part in parts:
        part = part.strip()
        if not part:
            continue
        
        alias = part.split(':', 1)[0]
        
        if alias not in library:
            print(f"   ⚠️  Warning: LoRA alias '{alias}' not found in config!")
            continue

        lib_entry = library[alias]
        
        strength_range_str = part.split(':', 1)[1].lower().strip() if ':' in part else None
        
        config_array_for_this_lora = [] 
        
        # Resolve strength values (list of 1 or more for ranges)
        strength_values = []
        
        if strength_range_str and '~~' in strength_range_str:
            start_str, end_str = strength_range_str.split('~~', 1)
            strength_values = generate_range_values(start_str.strip(), end_str.strip(), increment=range_increment)
        elif strength_range_str == "off":
            strength_values = [0.0]
        elif strength_range_str in ["0", "0.0"]:
            strength_values = [0.0]
        elif strength_range_str is not None:
            try:
                strength_values = [float(strength_range_str)]
            except ValueError:
                strength_values = [lib_entry.get('strength', 1.0)]
        else: 
            # Default strength (no colon provided)
            strength_values = [lib_entry.get('strength', 1.0)]

        # Resolve triggers (list of strings)
        base_triggers = lib_entry.get('triggers', [])
        if not base_triggers:
            base_triggers = ['']
        
        # Permutation loop: iterate through all strengths and triggers
        for strength_val in strength_values:
            
            current_remove_trigger = False
            
            if strength_range_str == "off":
                base_suffix = f"lora_{alias}[off]"
                current_remove_trigger = True
            elif strength_val == 0.0:
                base_suffix = f"lora_{alias}[{0.0:{format_spec}}]"
            else:
                base_suffix = f"lora_{alias}[{strength_val:{format_spec}}]"
                
            # If 'off', skip trigger multiplication
            if current_remove_trigger:
                config_array_for_this_lora.append({
                    'path': lib_entry['path'],
                    'strength': strength_val,
                    'alias': alias,
                    'triggers': [],
                    'suffix_part': base_suffix,
                    'remove_trigger': True,
                    'trigger_idx': 0
                })
            else:
                # Iterate over base triggers with index tracking
                for trigger_idx, single_trigger_phrase in enumerate(base_triggers):
                    # Always add trigger index to suffix (1-indexed)
                    suffix_with_idx = f"{base_suffix}[{trigger_idx + 1}]"
                    
                    config_array_for_this_lora.append({
                        'path': lib_entry['path'],
                        'strength': strength_val,
                        'alias': alias,
                        'triggers': [single_trigger_phrase],
                        'suffix_part': suffix_with_idx,
                        'remove_trigger': False,
                        'trigger_idx': trigger_idx + 1
                    })

        if config_array_for_this_lora:
            list_of_strength_arrays.append(config_array_for_this_lora)

    return list_of_strength_arrays


def build_suffix_string(params, sampler_params, suffix_config):
    """
    Build filename suffix string based on global suffix configuration.
    
    Constructs a standardized suffix for generated image filenames that
    includes generation parameters for traceability.
    
    Args:
        params: Dict with standard params (cfg, steps, width, height)
        sampler_params: Dict with additional sampler params (shift, etc.)
        suffix_config: List of suffix config dicts from config.yaml
        
    Returns:
        Formatted suffix string starting with underscore
        
    Suffix Config Format (in config.yaml):
        suffix:
          - name: cfg
            alias: c
            show: true
          - name: steps
            alias: s
            show: true
          - name: width
            alias: w
            show: false  # Hidden from filename
            
    Example:
        params = {"cfg": 1.0, "steps": 9, "width": 1024, "height": 1024}
        sampler_params = {"shift": 1.5}
        suffix_config = [
            {"name": "cfg", "alias": "c"},
            {"name": "steps", "alias": "s"},
            {"name": "shift", "alias": "sh"}
        ]
        
        result = build_suffix_string(params, sampler_params, suffix_config)
        # -> "_c[1.0]_s[9]_sh[1.5]"
    """
    if not suffix_config:
        # Fallback to default format if no config
        suffix = f"_cfg[{params['cfg']}]_steps[{params['steps']}]_width[{params['width']}]_height[{params['height']}]"
        if 'shift' in sampler_params:
            suffix += f"_shift[{sampler_params['shift']}]"
        return suffix
    
    # Build suffix from configuration
    suffix_parts = []
    
    # Create lookup dict for suffix config
    suffix_lookup = {}
    for s_conf in suffix_config:
        name = s_conf.get('name')
        alias = s_conf.get('alias', name)
        show = s_conf.get('show', True)
        suffix_lookup[name] = {'alias': alias, 'show': show}
    
    # Standard params
    standard_params = ['cfg', 'steps', 'width', 'height']
    for param_name in standard_params:
        if param_name in suffix_lookup:
            conf = suffix_lookup[param_name]
            if conf['show'] and param_name in params:
                alias = conf['alias']
                value = params[param_name]
                suffix_parts.append(f"{alias}[{value}]")
        else:
            # If not in config, include by default with full name
            if param_name in params:
                suffix_parts.append(f"{param_name}[{params[param_name]}]")
    
    # Additional sampler params (like shift)
    for param_name, value in sampler_params.items():
        if param_name in suffix_lookup:
            conf = suffix_lookup[param_name]
            if conf['show']:
                alias = conf['alias']
                suffix_parts.append(f"{alias}[{value}]")
        else:
            suffix_parts.append(f"{param_name}[{value}]")
    
    return '_' + '_'.join(suffix_parts) if suffix_parts else ""


def generate_job_permutations(prompt_entry, list_of_strength_arrays):
    """
    Generate Cartesian product of all LoRA strength combinations.
    
    Takes the nested list structure from parse_lora_combination_string()
    and generates all possible combinations as job dictionaries.
    
    Args:
        prompt_entry: Prompt definition dict from jobs.yaml
        list_of_strength_arrays: Nested list of LoRA config dicts
        
    Returns:
        List of job dicts, each containing:
        - prompt: Reference to prompt_entry
        - loras: List of LoRA config dicts for this combination
        - filename_suffix: Combined suffix string
        - inputs: (if present in prompt_entry)
        
    Example:
        prompt = {"id": "test", "text": "A woman"}
        lora_arrays = [
            [{"alias": "lora1", "strength": 0.5, "suffix_part": "lora1[0.5]", ...}],
            [{"alias": "lora2", "strength": 0.8, "suffix_part": "lora2[0.8]", ...}]
        ]
        
        jobs = generate_job_permutations(prompt, lora_arrays)
        # Returns: [{
        #   "prompt": prompt,
        #   "loras": [lora1_config, lora2_config],
        #   "filename_suffix": "lora1[0.5]_lora2[0.8]"
        # }]
    """
    final_jobs = []
    
    for combination_tuple in product(*list_of_strength_arrays):
        loras_config = list(combination_tuple)
        
        # Build final suffix string from the suffixes of all parts
        suffix = "_".join([l['suffix_part'] for l in loras_config])
        
        job_dict = {
            'prompt': prompt_entry,
            'loras': loras_config,
            'filename_suffix': suffix
        }
        
        # Copy inputs field if present (needed for edit models)
        if 'inputs' in prompt_entry:
            job_dict['inputs'] = prompt_entry['inputs']
        
        final_jobs.append(job_dict)
    
    return final_jobs
