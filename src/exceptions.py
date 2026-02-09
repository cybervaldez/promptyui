"""
src/exceptions.py - Custom Exceptions for Prompt Generator

This module defines custom exception classes used throughout the Prompt Generator
batch generation system. These exceptions provide clear error categorization
for extension resolution and wildcard substitution failures.

EXCEPTIONS:
-----------
ExtensionError:
    Raised when extension resolution fails. This includes:
    - Extension ID not found in global config
    - Invalid extension path syntax (e.g., "id.key.extra.invalid")
    - Attempting to resolve structured data (wildcards/loras) into text

WildcardError:
    Raised when wildcard substitution fails. This includes:
    - Wildcard placeholder not defined in wildcards section
    - Empty wildcard text list

USAGE:
------
    from src.exceptions import ExtensionError, WildcardError
    
    # In extension resolution
    if ext_id not in extensions:
        raise ExtensionError(f"Extension ID '{ext_id}' not found")
    
    # In wildcard resolution
    if wildcard_name not in wildcard_lookup:
        raise WildcardError(f"Wildcard '__{wildcard_name}__' not defined")

AI ASSISTANT NOTES:
-------------------
- ExtensionError is caught in build_jobs() to provide user-friendly error messages
- WildcardError causes immediate job failure with detailed context
- Both exceptions inherit from Python's built-in Exception class
"""


class ExtensionError(Exception):
    """
    Custom exception for errors during extension resolution.
    
    Raised when:
    - Extension ID is not found in global config 'ext' section
    - Extension path syntax is invalid (expected: id, id.key, id.one, id.key.one)
    - Attempting to merge structured data (wildcards, loras) into text list
    
    Attributes:
        message (str): Detailed error description including the problematic path
    
    Example:
        raise ExtensionError("Extension ID 'sexy-pose' not found in global config")
    """
    pass


class WildcardError(Exception):
    """
    Custom exception for errors during wildcard resolution.
    
    Raised when:
    - A __wildcard__ placeholder is used but not defined in wildcards section
    - A wildcard exists but has an empty text list
    
    Attributes:
        message (str): Error description with the missing wildcard name
    
    Example:
        raise WildcardError("Wildcard '___pose___' referenced but not defined")
    """
    pass
