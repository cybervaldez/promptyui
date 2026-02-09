"""
src/wildcards.py - Wildcard Resolution and Text Processing

This module handles wildcard substitution in text templates and text consumption modes.
Wildcards are placeholders like __pose__ that get replaced with random values from
a defined list during prompt generation.

CORE CONCEPTS:
--------------
Wildcards:
    Placeholders in text using double underscore syntax: __wildcard_name__
    Each wildcard maps to a list of possible values in the extension wildcards section.
    During generation, placeholders are replaced with random selections.

Wildcard Consumption Modes:
    0 (Iterate): Use ALL values from wildcard list (Cartesian product)
    1 (Random 1): Pick ONE random value
    N (Random N): Pick N random unique values

Text Variants:
    Prompts can have structured text entries with per-entry consumption rules:
    - content: "Template with __wildcard__"
    - wildcards: 0|1|N (consumption mode)

FUNCTIONS:
----------
resolve_wildcards(text_list, wildcard_map, track_usage=False):
    Perform random wildcard substitution in a list of text templates.
    Optionally tracks which values were chosen for each text.
    Returns resolved texts (and usage data if track_usage=True).

process_text_variant(variant, wildcard_lookup, default_mode=0):
    Expand a single text variant (string or structured dict) into a list 
    of strings based on wildcard consumption rules.
    Used during prompt expansion to handle mixed text/dict entries.

apply_text_consumption_mode(text_items, text_mode):
    Apply text consumption mode to extended text items.
    Similar to wildcard consumption but for text lists from extensions.
    Returns filtered list based on mode (0=all, 1=random, N=sample).

WILDCARD SYNTAX:
----------------
    Text template: "A __pose__ woman wearing __outfit__"
    
    Wildcards section:
      - name: pose
        text:
          - standing
          - sitting
          - walking
      - name: outfit
        text:
          - red dress
          - blue jeans

    Each __pose__ is replaced with a random selection from the pose list.

CONSUMPTION MODES:
------------------
    Mode 0 (Iterate):
        Creates Cartesian product of all wildcard values.
        3 poses × 3 outfits = 9 combinations
        
    Mode 1 (Random 1):
        Picks one random value, placeholder stays for runtime resolution.
        Returns single template with wildcards intact.
        
    Mode N (Random N):
        Pre-samples N unique values from each wildcard.
        N poses × N outfits combinations generated.

AI ASSISTANT NOTES:
-------------------
- Wildcard names may contain: letters, numbers, underscores, hyphens
- Regex pattern: r"__([a-zA-Z0-9_-]+)__"
- WildcardError is raised if wildcard not defined or empty
- Usage tracking returns dict mapping wildcard names to chosen values
- process_text_variant handles both string and dict text entries
"""

import re
import random
from itertools import product

from src.exceptions import WildcardError


def resolve_wildcards(text_list, wildcard_map, track_usage=False):
    """
    Perform random wildcard substitution in a list of text templates.
    
    Finds all __wildcard__ placeholders in each text template and replaces
    them with random selections from the corresponding wildcard definitions.
    
    Args:
        text_list: List of text templates containing __wildcard__ placeholders
        wildcard_map: List of wildcard definition dicts with 'name' and 'text' keys
        track_usage: If True, track which values were chosen for each text
        
    Returns:
        If track_usage=False: List of resolved text strings
        If track_usage=True: Tuple of (resolved_texts, usage_data)
            where usage_data is a list of dicts mapping wildcard names to chosen values
            
    Raises:
        WildcardError: If a placeholder references an undefined or empty wildcard
        
    Example:
        texts = ["A __pose__ woman"]
        wildcards = [{"name": "pose", "text": ["standing", "sitting"]}]
        
        resolved = resolve_wildcards(texts, wildcards)
        # -> ["A standing woman"] or ["A sitting woman"]
        
        resolved, usage = resolve_wildcards(texts, wildcards, track_usage=True)
        # -> (["A standing woman"], [{"pose": "standing"}])
    """
    # Build lookup dict from wildcard definitions
    wildcard_lookup = {wc.get('name'): wc.get('text', []) for wc in wildcard_map if wc.get('name')}
    
    resolved_texts = []
    usage_tracking = []
    
    # Regex to find __WILDNAME__ placeholders (includes hyphens)
    wildcard_pattern = re.compile(r"__([a-zA-Z0-9_-]+)__")

    for text_template in text_list:
        resolved_text = text_template
        wildcards_used = {}
        
        # Find all wildcards in the current template
        placeholders = wildcard_pattern.findall(text_template)
        
        if not placeholders:
            resolved_texts.append(text_template)
            if track_usage:
                usage_tracking.append(wildcards_used)
            continue
            
        # Perform substitution for all unique placeholders found
        # Sort them to ensure deterministic order of random number consumption
        for name in sorted(list(set(placeholders))):
            if name not in wildcard_lookup:
                raise WildcardError(f"Wildcard '___{name}___' referenced in prompt but not defined in the 'wildcards' section.")
            
            choices = wildcard_lookup[name]
            if not choices:
                raise WildcardError(f"Wildcard '___{name}___' found but has an empty text list.")
            
            # Pick random choice and track its index (1-based for filename)
            choice_idx = random.randint(0, len(choices) - 1)
            random_choice = choices[choice_idx]
            
            # Track which value and index was chosen
            if track_usage:
                wildcards_used[name] = {
                    'value': random_choice,
                    'index': choice_idx + 1
                }
            
            # Substitute ALL instances of the placeholder in the template
            placeholder_token = f"__{name}__"
            resolved_text = resolved_text.replace(placeholder_token, random_choice)

        resolved_texts.append(resolved_text)
        if track_usage:
            usage_tracking.append(wildcards_used)
        
    if track_usage:
        return resolved_texts, usage_tracking
    return resolved_texts


def process_text_variant(variant, wildcard_lookup, default_mode=0):
    """
    Expand a single text variant into a list of strings based on consumption rules.
    
    Text variants can be either simple strings or structured dicts with
    content and optional wildcard consumption configuration.
    
    Args:
        variant: Either a string or dict with 'content' and optional 'wildcards' keys
        wildcard_lookup: Dict mapping wildcard names to their text lists
        default_mode: Default consumption mode if not specified (0=iterate)
        
    Returns:
        List of expanded text strings
        
    Consumption Modes:
        0 (Iterate): Generate Cartesian product of all wildcard values
        1 (Random 1): Keep wildcard placeholders for runtime resolution
        N (Random N): Pre-sample N values from each wildcard
        
    Example (simple string):
        process_text_variant("A __pose__ woman", lookup)
        # Returns: ["A __pose__ woman"]  (no expansion, raw template)
        
    Example (structured with mode 0):
        process_text_variant({
            "content": "A __pose__ woman",
            "wildcards": 0
        }, {"pose": ["standing", "sitting"]})
        # Returns: ["A standing woman", "A sitting woman"]
        
    Example (structured with mode 1):
        process_text_variant({
            "content": "A __pose__ woman", 
            "wildcards": 1
        }, lookup)
        # Returns: ["A __pose__ woman"]  (placeholder kept for runtime)
    """
    if isinstance(variant, str):
        return [variant]
    
    if not isinstance(variant, dict) or 'content' not in variant:
        print(f"   ⚠️  Warning: Invalid text structure found, skipping. Expected string or dict with 'content'.")
        return []

    template = variant['content']
    config = variant.get('wildcards')
    
    # Apply default mode if config is missing
    if config is None:
        count = default_mode
    elif isinstance(config, int):
        count = config
    else:
        print(f"   ⚠️  Warning: Invalid wildcards config type (expected int), using default mode")
        count = default_mode
    
    # Regex to find wildcards
    wildcard_pattern = re.compile(r"__([a-zA-Z0-9_-]+)__")
    placeholders = wildcard_pattern.findall(template)
    
    if not placeholders:
        return [template]

    # Organize values for Cartesian product based on count
    unique_placeholders = sorted(list(set(placeholders)))
    
    # Build a map of {placeholder_name: list_of_strings_to_use}
    values_map = {}
    
    for name in unique_placeholders:
        if name not in wildcard_lookup:
            raise WildcardError(f"Wildcard '___{name}___' referenced in structured prompt but not defined.")
        
        definitions = wildcard_lookup[name]
        
        if count == 0:
            # Iterate through ALL definitions
            values_map[name] = definitions
        elif count == 1:
            # Random 1: Keep placeholder for runtime resolution
            values_map[name] = [f"__{name}__"]
        else:
            # Random N: Pre-sample distinct values
            if len(definitions) < count:
                print(f"   ⚠️  Warning: Wildcard '{name}' requested {count} unique items but only has {len(definitions)}. Using all.")
                values_map[name] = definitions
            else:
                values_map[name] = random.sample(definitions, count)

    # Generate Cartesian product of all placeholder values
    lists_to_product = [values_map[name] for name in unique_placeholders]
    
    expanded_strings = []
    
    for combo in product(*lists_to_product):
        current_text = template
        for i, name in enumerate(unique_placeholders):
            val = combo[i]
            current_text = current_text.replace(f"__{name}__", val)
        expanded_strings.append(current_text)

    return expanded_strings


def apply_text_consumption_mode(text_items, text_mode):
    """
    Apply text consumption mode to extended text items.
    
    Similar to wildcard consumption but for text lists from extensions.
    Filters the text list based on the specified consumption mode.
    
    Args:
        text_items: List of text strings from extension resolution
        text_mode: int controlling consumption (0=all, 1=random, N=sample N)
        
    Returns:
        Filtered list of text items based on mode
        
    Modes:
        0: Return all items (iterate through all)
        1: Pick 1 random item
        N: Pick N random unique items (or all if list smaller than N)
        
    Example:
        items = ["text1", "text2", "text3", "text4", "text5"]
        
        apply_text_consumption_mode(items, 0)
        # -> ["text1", "text2", "text3", "text4", "text5"]
        
        apply_text_consumption_mode(items, 1)
        # -> ["text3"]  (random single item)
        
        apply_text_consumption_mode(items, 3)
        # -> ["text2", "text5", "text1"]  (3 random unique items)
    """
    if not text_items:
        return text_items
    
    # Determine count
    if isinstance(text_mode, int):
        count = text_mode
    else:
        count = 0  # Default to all if not int
    
    if count == 0:
        # Return all items
        return text_items
    elif count == 1:
        # Pick one random
        return [random.choice(text_items)]
    else:
        # Pick N random unique items
        if len(text_items) < count:
            print(f"   ⚠️  Warning: text mode requested {count} items but only {len(text_items)} available. Using all.")
            return text_items
        return random.sample(text_items, count)
