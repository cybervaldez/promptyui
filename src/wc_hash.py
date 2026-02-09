"""
wc_hash.py - Content-Addressable Wildcard Hash Utility

Provides deterministic hash computation for wildcard and ext_text combinations.
This enables content-addressable filenames where:
- Same wildcard/ext_text combination = same filename (no duplicates)
- Different combination = different filename (no conflicts)

Hash Input Structure:
    {
        'wc': {'mood': 0, 'pose': 1},      # 0-based wildcard indices
        'ext': {'mature_themes': 1}         # 1-based ext_text indices
    }

Usage:
    from src.wc_hash import compute_wc_hash, build_content_filename

    # Compute hash from indices
    wc_hash = compute_wc_hash({'mood': 0, 'pose': 2})  # → "7a2c1f"

    # Build full filename
    filename = build_content_filename(wc_hash, 0, 'base', 'euler', 'simple')
    # → "wc_7a2c1f_cfg0_base_euler_simple.png"
"""

import hashlib
import json
from typing import Dict, Optional


def compute_wc_hash(wc_dict: Optional[Dict[str, int]] = None,
                   ext_indices: Optional[Dict[str, int]] = None) -> str:
    """
    Compute 6-char hash from wildcard and ext_text indices.

    The hash is deterministic - same input always produces same hash.
    This enables content-addressable filenames that are:
    - Unique per wildcard/ext_text combination
    - Consistent across compositions (same content = same hash)

    Args:
        wc_dict: Wildcard indices {name: 0-based-index} from data.json 'wc' field
        ext_indices: Ext_text indices {name: 1-based-index} from data.json 'ext' field

    Returns:
        6-character hex hash (e.g., "7a2c1f")

    Examples:
        compute_wc_hash({'mood': 0, 'pose': 2})                    # → "abc123"
        compute_wc_hash({}, {'boss_fight': 1})                     # → "def456"
        compute_wc_hash({'theme': 0}, {'mature_themes': 1})        # → "ghi789"
        compute_wc_hash(None, None)                                # → "d41d8c" (null)
        compute_wc_hash({}, {})                                    # → "d41d8c" (empty = null)
    """
    content = {
        'wc': wc_dict or {},
        'ext': ext_indices or {}
    }
    # sort_keys ensures deterministic serialization
    data = json.dumps(content, sort_keys=True)
    return hashlib.md5(data.encode()).hexdigest()[:6]


def build_content_filename(wc_hash: str, config_index: int, suffix: str,
                          sampler: str, scheduler: str) -> str:
    """
    Build content-addressable filename from hash.

    New filename format replaces address-based naming:
    - Old: {index:04d}_c{config_index}_{suffix}_{sampler}_{scheduler}.png
    - New: wc_{hash}_cfg{config_index}_{suffix}_{sampler}_{scheduler}.png

    Args:
        wc_hash: 6-character hash from compute_wc_hash()
        config_index: Config index (0-based)
        suffix: LoRA suffix (e.g., 'base', 'pixel_art-0.8')
        sampler: Sampler name (e.g., 'euler')
        scheduler: Scheduler name (e.g., 'simple')

    Returns:
        Filename string like "wc_7a2c1f_cfg0_base_euler_simple.png"
    """
    return f"wc_{wc_hash}_cfg{config_index}_{suffix}_{sampler}_{scheduler}.png"


def build_operation_filename(wc_hash: str, config_index: int) -> str:
    """
    Build content-addressable filename for operation outputs.

    Operations use a simpler format without sampler/scheduler.

    Args:
        wc_hash: 6-character hash from compute_wc_hash()
        config_index: Config index (0-based)

    Returns:
        Filename string like "wc_7a2c1f_cfg0.png"
    """
    return f"wc_{wc_hash}_cfg{config_index}.png"


def parse_wc_hash_from_filename(filename: str) -> Optional[str]:
    """
    Extract wc_hash from a content-addressable filename.

    Args:
        filename: Filename like "wc_7a2c1f_cfg0_base_euler_simple.png"

    Returns:
        Hash string like "7a2c1f", or None if not a hash-based filename
    """
    import re
    # Match wc_{6-char-hash}_cfg{digit}...
    match = re.match(r'^wc_([a-f0-9]{6})_cfg\d+', filename)
    if match:
        return match.group(1)
    return None


def is_hash_based_filename(filename: str) -> bool:
    """
    Check if a filename uses the new hash-based format.

    Args:
        filename: Filename to check

    Returns:
        True if filename starts with "wc_" and has valid hash format
    """
    return parse_wc_hash_from_filename(filename) is not None
