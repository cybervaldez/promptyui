#!/usr/bin/env python3
"""
Run Job CLI - DEPRECATED stub.

This entry point has been replaced by generate-cli.py (src/cli/main.py)
which uses HookPipeline for the full generation-time lifecycle.

Usage (new):
    python generate-cli.py andrea-fashion -c 99 --prompt-id pixel-wildcards
"""

import sys
import argparse
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="DEPRECATED - use generate-cli.py instead")
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

    print(f"\n⚠️  run_job.py is deprecated. Use generate-cli.py instead:")
    print(f"")
    print(f"   Generation (full HookPipeline lifecycle):")
    print(f"     python generate-cli.py {args.job} -c {args.composition}")
    print(f"")
    print(f"   Build prompts only:")
    print(f"     python build-job.py {args.job}")
    print(f"")
    print(f"   Or use the WebUI:")
    print(f"     ./start-prompty.sh")


if __name__ == "__main__":
    main()
