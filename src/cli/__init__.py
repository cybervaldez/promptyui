"""
src/cli - Modular CLI for prompt generation.

This package provides the unified CLI for generation with full WebUI parity.
The CLI uses HookPipeline — a pure hook-based engine where
execute_hook(name, ctx) runs whatever scripts are configured in hooks.yaml.

Hook lifecycle (conventions, not engine code):
  Block-level:       node_start → resolve (cached)
  Per-composition:   pre → generate → post
  Block-level:       node_end

Stage names are caller conventions. The engine doesn't special-case any name.
Mods (mods.yaml) are hooks with guards (stage, scope, filters).

Usage:
    from src.cli import main
    sys.exit(main())

Or directly:
    python generate-cli.py pixel-fantasy -c 99 --build covers
"""

from .main import main

__all__ = ['main']
