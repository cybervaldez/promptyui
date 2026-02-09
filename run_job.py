#!/usr/bin/env python3
"""
Run Job CLI - Execute job with hooks-based pipeline.

This is a stub for the prompt-only version. Image generation has been removed.
The hook pipeline for mods can still be executed if needed.

Usage:
    ./run_job.py andrea-fashion -c 99 --max 10
"""

import sys
import argparse
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="Run job with hooks pipeline (prompt-only mode)")
    parser.add_argument("job", type=str, help="Name of the job folder")
    parser.add_argument("--composition", "-c", type=int, required=True,
                        help="Composition ID")
    parser.add_argument("--max", type=int, default=10,
                        help="Maximum images to process")
    parser.add_argument("--prompt-id", "-p", dest="prompt_id", type=str, default=None,
                        help="Filter to specific prompt ID")
    parser.add_argument("--path", type=str, default=None,
                        help="Filter to specific path")
    args = parser.parse_args()

    root_dir = Path.cwd()
    job_dir = root_dir / "jobs" / args.job

    if not job_dir.exists():
        sys.exit(f"❌ Job not found: {job_dir}")

    print(f"\n⚠️  Image generation has been removed from this codebase.")
    print(f"   This is now a prompt-only system.")
    print(f"")
    print(f"   To work with prompts, use:")
    print(f"     python build-job.py {args.job}")
    print(f"")
    print(f"   Or use the WebUI:")
    print(f"     ./start-jm.sh")


if __name__ == "__main__":
    main()
