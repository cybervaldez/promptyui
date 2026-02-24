"""
src/segments.py - Multi-Platform Segmentation Utilities

Shared library for building minimal segments from extensions
and reconstructing prompts from segment references.

PLATFORMS SUPPORTED:
--------------------
- Generation (main.py) - Python
- API Server (server.py) - Python  
- WebUI (via API or JS port) - JavaScript
- Terminal UI (future) - Python
- PromptyUI (future) - Python

CORE CONCEPTS:
--------------
SegmentRegistry:
    In-memory lookup for extension texts and wildcards.
    Built either from global_conf (during generation) or from JSON (at runtime).

Composition:
    Minimal representation of a text variation:
    {
        "ext": [["ext_name", text_idx], ...],  # Extension text references
        "wc": {"wildcard_name": value_idx, ...}  # Wildcard value indices
    }

FUNCTIONS:
----------
build_ext_registry(global_conf) -> dict:
    Extract all extension text values into a lookup registry.

build_composition(ext_indices, wc_usage) -> dict:
    Convert ext_indices and wildcard usage to minimal composition format.

reconstruct_template(composition, registry) -> str:
    Rebuild template string from composition references.

resolve_prompt(composition, registry) -> str:
    Full prompt resolution (template + wildcard substitution).

AI ASSISTANT NOTES:
-------------------
- Registry stores text lists per extension ID
- Composition references use 0-based indices
- Wildcards are resolved at reconstruction time
"""

import re
from typing import Dict, List, Tuple, Optional, Any, Union


class SegmentRegistry:
    """
    Registry for extension texts and wildcards.
    
    Provides efficient lookup for prompt reconstruction across all platforms.
    Can be built from loaded extensions (during generation) or from JSON (at runtime).
    """
    
    def __init__(self, ext_registry: Dict[str, List[str]], wildcards: Dict[str, List[str]]):
        """
        Initialize registry with pre-built data.
        
        Args:
            ext_registry: Dict mapping ext_id -> list of text strings
            wildcards: Dict mapping wildcard_name -> list of values
        """
        self.ext_registry = ext_registry
        self.wildcards = wildcards
    
    @classmethod
    def from_global_conf(cls, global_conf: dict) -> 'SegmentRegistry':
        """
        Build registry from loaded extensions in global_conf.
        
        Extracts all extension text lists and wildcard definitions
        from the global configuration loaded during job processing.
        
        Args:
            global_conf: Global configuration dict with 'ext' key
            
        Returns:
            SegmentRegistry instance with all extension data
        """
        ext_registry = {}
        wildcards = {}
        
        for ext in global_conf.get('ext', []):
            ext_id = ext.get('id')
            if not ext_id:
                continue
            
            # Extract text lists (text, text2, text3, etc.)
            text_lists = []
            for key in sorted(ext.keys()):
                if key == 'text' or (key.startswith('text') and key[4:].isdigit()):
                    values = ext.get(key, [])
                    if isinstance(values, list):
                        text_lists.extend(values)
            
            if text_lists:
                ext_registry[ext_id] = text_lists
            
            # Extract wildcards from this extension
            for wc in ext.get('wildcards', []):
                wc_name = wc.get('name')
                wc_text = wc.get('text', [])
                if wc_name and wc_text:
                    if wc_name in wildcards:
                        # Merge with existing (preserve order, add new)
                        existing = set(wildcards[wc_name])
                        wildcards[wc_name].extend([v for v in wc_text if v not in existing])
                    else:
                        wildcards[wc_name] = list(wc_text)
        
        return cls(ext_registry, wildcards)
    
    @classmethod
    def from_json(cls, segments: dict) -> 'SegmentRegistry':
        """
        Load registry from seed.json segments section.
        
        Args:
            segments: The 'segments' dict from seed.json
            
        Returns:
            SegmentRegistry instance
        """
        return cls(
            ext_registry=segments.get('ext_registry', {}),
            wildcards=segments.get('wildcards', {})
        )
    
    def to_dict(self) -> dict:
        """
        Export registry to dict format for JSON serialization.
        
        Returns:
            Dict with 'ext_registry' and 'wildcards' keys
        """
        return {
            'ext_registry': self.ext_registry,
            'wildcards': self.wildcards
        }
    
    def get_ext_text(self, ext_id: str, index: int) -> str:
        """
        Get a specific text from an extension by index.
        
        Args:
            ext_id: Extension identifier
            index: 0-based index into the text list
            
        Returns:
            Text string or empty string if not found
        """
        texts = self.ext_registry.get(ext_id, [])
        if 0 <= index < len(texts):
            return texts[index]
        return ''
    
    def get_wildcard_value(self, wc_name: str, index: int) -> str:
        """
        Get a specific wildcard value by index.
        
        Args:
            wc_name: Wildcard name (without __ delimiters)
            index: 0-based index into the values list
            
        Returns:
            Value string or placeholder if not found
        """
        values = self.wildcards.get(wc_name, [])
        if 0 <= index < len(values):
            return values[index]
        return f'__{wc_name}__'  # Return placeholder if not found


def build_composition(ext_indices: Dict[str, int], wc_usage: Dict[str, Any], annotations: Optional[Dict[str, Any]] = None) -> dict:
    """
    Build minimal composition from ext_indices and wildcard usage.

    Converts the tracking data from job building into the minimal
    format stored in JSON for reconstruction.

    Args:
        ext_indices: Dict mapping ext_name -> 1-based index used
        wc_usage: Dict mapping wildcard_name -> {value, index} or index
        annotations: Optional dict of merged annotations for this variation

    Returns:
        Composition dict with 'ext', 'wc', and optionally 'ann' keys

    Example:
        ext_indices = {'mature-themes': 3, 'intimate-scenarios': 1}
        wc_usage = {'theme_type': {'value': 'boudoir', 'index': 1}}

        # Returns:
        {
            'ext': [['intimate-scenarios', 0], ['mature-themes', 2]],
            'wc': {'theme_type': {'index': 0, 'value': 'boudoir'}}
        }
    """
    # Convert ext_indices to sorted list of [ext_id, 0-based index]
    ext_refs = []
    for ext_name in sorted(ext_indices.keys()):
        idx = ext_indices[ext_name]
        # Convert from 1-based (filename) to 0-based (array index)
        ext_refs.append([ext_name, idx - 1])
    
    # Convert wc_usage to index+value dict for cross-variant matching
    wc_data = {}
    for wc_name, wc_input in wc_usage.items():
        if isinstance(wc_input, dict):
            # Format: {value: str, index: int} - index is 1-based
            wc_data[wc_name] = {
                'index': wc_input.get('index', 1) - 1,  # Convert to 0-based
                'value': wc_input.get('value', '')
            }
        elif isinstance(wc_input, int):
            # Legacy: only index (assume 1-based)
            # No value available, will need variant.json lookup for resolution
            wc_data[wc_name] = wc_input - 1
        else:
            wc_data[wc_name] = {'index': 0, 'value': ''}
    
    result = {
        'ext': ext_refs,
        'wc': wc_data
    }
    if annotations:
        result['ann'] = annotations
    return result


def reconstruct_template(composition: dict, registry: SegmentRegistry, delimiter: str = ', ') -> str:
    """
    Rebuild template string from composition references.
    
    Concatenates extension texts in order with delimiter, wildcards still as placeholders.
    
    Args:
        composition: Dict with 'ext' (list of [ext_id, idx]) and 'wc' keys
        registry: SegmentRegistry with ext_registry data
        delimiter: String to join extension texts (default: ', ')
        
    Returns:
        Template string with __wildcard__ placeholders
        
    Example:
        composition = {'ext': [['mature-themes', 2]], 'wc': {'theme_type': 0}}
        # If mature-themes[2] = "artistic maturity, __theme_type__, sophisticated"
        # Returns: "artistic maturity, __theme_type__, sophisticated"
    """
    ext_refs = composition.get('ext', [])
    
    if not ext_refs:
        return ''
    
    # Concatenate extension texts in order with delimiter
    parts = []
    for ext_id, idx in ext_refs:
        text = registry.get_ext_text(ext_id, idx)
        if text:
            parts.append(text)
    
    return delimiter.join(parts)


def resolve_wildcards_in_text(
    template: str,
    wc_indices: Dict[str, int],
    registry: SegmentRegistry
) -> str:
    """
    Replace __wildcard__ placeholders with resolved values.
    
    Args:
        template: Text with __wildcard__ placeholders
        wc_indices: Dict mapping wildcard_name -> 0-based index
        registry: SegmentRegistry with wildcards data
        
    Returns:
        Fully resolved text string
    """
    result = template
    
    # Find all placeholders
    wildcard_pattern = re.compile(r'__([a-zA-Z0-9_-]+)__')
    
    for match in wildcard_pattern.finditer(template):
        wc_name = match.group(1)
        idx = wc_indices.get(wc_name, 0)
        value = registry.get_wildcard_value(wc_name, idx)
        result = result.replace(f'__{wc_name}__', value)
    
    return result


def resolve_prompt(composition: dict, registry: SegmentRegistry) -> str:
    """
    Full prompt resolution from minimal segment data.
    
    Reconstructs the template from extension references,
    then resolves all wildcard placeholders.
    
    Args:
        composition: Dict with 'ext' and 'wc' keys
        registry: SegmentRegistry with all lookup data
        
    Returns:
        Fully resolved prompt string
        
    Example:
        composition = {
            'ext': [['mature-themes', 2]],
            'wc': {'theme_type': 0}
        }
        # Returns: "artistic maturity, boudoir photography style, sophisticated"
    """
    template = reconstruct_template(composition, registry)
    wc_indices = composition.get('wc', {})
    return resolve_wildcards_in_text(template, wc_indices, registry)


def get_image_prompt(
    image_data: dict,
    segments: dict,
    registry: Optional[SegmentRegistry] = None
) -> str:
    """
    Convenience function to resolve prompt for an image entry.
    
    Args:
        image_data: Image dict with 't' (text segment index)
        segments: Full segments dict from JSON
        registry: Optional pre-built registry (built from segments if None)
        
    Returns:
        Fully resolved prompt string
    """
    if registry is None:
        registry = SegmentRegistry.from_json(segments)
    
    t_idx = image_data.get('t', 0)
    composition_list = segments.get('composition', [])
    
    if 0 <= t_idx < len(composition_list):
        composition = composition_list[t_idx]
        return resolve_prompt(composition, registry)
    
    return ''
