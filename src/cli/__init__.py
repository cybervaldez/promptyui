"""
src/cli - Modular CLI for prompt generation.

This package provides the unified CLI for image generation with full WebUI parity.
The CLI uses HookPipeline to run the generation-time lifecycle:
  JOB_START → NODE_START → ANNOTATIONS_RESOLVE →
  MODS_PRE → IMAGE_GENERATION → MODS_POST →
  NODE_END → JOB_END

Hooks (hooks.yaml) fire at specific stages. Mods (mods.yaml) fire at
MODS_PRE/MODS_POST with stage/scope/filter guards. Both use the same
execution mechanism (_execute_single_hook → execute(context, params)).

Usage:
    from src.cli import main
    sys.exit(main())

Or directly:
    python generate-cli.py pixel-fantasy -c 99 --build covers
"""

from .main import main

__all__ = ['main']
