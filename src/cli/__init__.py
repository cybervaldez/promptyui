"""
src/cli - Modular CLI for prompt generation.

This package provides the unified CLI for image generation with full WebUI parity.
The CLI uses HookPipeline (mods_pre → image_generation → mods_post) to match
WebUI behavior exactly.

Usage:
    from src.cli import main
    sys.exit(main())

Or directly:
    python generate-cli.py pixel-fantasy -c 99 --build covers
"""

from .main import main

__all__ = ['main']
