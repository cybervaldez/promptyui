"""
src/cli/main.py - Entry Point & Routing

Main entry point for the CLI. Contains:
- Argument parser setup
- Mode routing (--build, --stage, --mode batch, etc.)
- Environment setup (DEBUG_MODE, trace ID)
- Exit codes

Debug relevance: When CLI args aren't parsed correctly
"""

import os
import sys
import json
import argparse
import hashlib
import signal
import threading
from pathlib import Path
from datetime import datetime

from .utils import _debug_log
from .webui_bridge import detect_webui_port, auto_detect_webui_server
from .queue_manager import add_to_queue, process_queue_items
from .tester import PipelineCLITester


# Thread-safe shutdown event for signal handling
#
# SHUTDOWN COORDINATION:
# - This pattern handles in-process graceful shutdown
# - When SIGTERM received (from bake-cli, WebUI stop, or Ctrl+C), _shutdown_event is set
# - All loops check _shutdown_event.is_set() and exit gracefully
# - For cross-process coordination, signal handlers can be used
_shutdown_event = threading.Event()


def _signal_handler(signum, frame):
    """Handle SIGTERM and SIGINT for graceful shutdown."""
    signame = 'SIGTERM' if signum == signal.SIGTERM else 'SIGINT'
    print(f"\nReceived {signame}, shutting down gracefully...")
    _shutdown_event.set()


# Register signal handlers
signal.signal(signal.SIGTERM, _signal_handler)
signal.signal(signal.SIGINT, _signal_handler)


def _show_build_summary(build_type: str, existing: int, missing: int) -> int:
    """Display build summary in terminal.

    Args:
        build_type: Type of build (covers, configs, etc.)
        existing: Count of already generated images
        missing: Count of missing images

    Returns:
        Total count
    """
    total = existing + missing
    print(f"\n{build_type.capitalize()} Summary:")
    print(f"   Already generated: {existing}")
    print(f"   Missing: {missing}")
    print(f"   Total: {total}")
    return total


def _prompt_build_action(existing: int, missing: int) -> str:
    """Interactive prompt for build action.

    Args:
        existing: Count of already generated images
        missing: Count of missing images

    Returns:
        'overwrite', 'resume', or 'cancel'
    """
    total = existing + missing
    print(f"\nOptions:")
    print(f"   [O] Overwrite all ({total} images)")
    if missing > 0:
        print(f"   [R] Resume ({missing} missing only)")
    else:
        print(f"   [R] Resume (nothing to generate)")
    print(f"   [C] Cancel")

    while True:
        try:
            choice = input("\nChoice [O/R/C]: ").strip().upper()
        except (KeyboardInterrupt, EOFError):
            print("\nCancelled.")
            return 'cancel'

        if choice == 'O':
            return 'overwrite'
        elif choice == 'R':
            return 'resume'
        elif choice == 'C':
            return 'cancel'
        print("Invalid choice. Enter O, R, or C.")


def main() -> int:
    """Main entry point for the CLI.

    Returns:
        Exit code (0 for success, 1 for failure)
    """
    parser = argparse.ArgumentParser(
        description="Unified Image Generation CLI - Full WebUI Parity",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Generate single image with full hooks pipeline
    python generate-cli.py pixel-fantasy -c 99 --prompt-id pixel-wildcards

    # Generate with wildcard operation
    python generate-cli.py pixel-fantasy -c 99 --operation medieval

    # Debug mode (generate placeholder images for testing)
    python generate-cli.py pixel-fantasy -c 99 --debug-images

    # Batch: process all pending images
    python generate-cli.py pixel-fantasy -c 99 --mode batch --max 10

    # Build covers (like WebUI "Generate Covers" button)
    python generate-cli.py pixel-fantasy -c 99 --build covers

    # Build all (like WebUI "Build All" button)
    python generate-cli.py pixel-fantasy -c 99 --build all

    # WebUI mode (enables SSE events and toast notifications)
    python generate-cli.py pixel-fantasy -c 99 --webui
        """
    )
    # Required arguments
    parser.add_argument("job", type=str, help="Job name")
    parser.add_argument("-c", "--composition", type=int, required=True, help="Composition ID")

    # Mode selection
    parser.add_argument("-o", "--operation", type=str, default=None,
                        help="Apply wildcard operation before generation")
    parser.add_argument("-m", "--mode", type=str, default=None,
                        choices=['batch'],
                        help="Execution mode (batch: process pending images from data.json)")

    # Build actions (WebUI parity)
    parser.add_argument("--build", type=str, default=None,
                        choices=['covers', 'configs', 'variations', 'all', 'variants'],
                        help="Build action (matches WebUI buttons)")

    # Filtering
    parser.add_argument("-a", "--address", type=int, default=1, help="Address index (default: 1, first image)")
    parser.add_argument("-p", "--prompt-id", type=str, default=None, help="Filter to specific prompt ID")
    parser.add_argument("--path", type=str, default=None, help="Path string for configs/variations")
    parser.add_argument("--config-index", type=int, default=0,
                        help="Config index (default: 0). Use with --build covers to specify which config to generate covers for")

    # Execution flags
    parser.add_argument("--debug-images", nargs='?', const=0, type=int, default=None,
                        help="Generate placeholder images with optional delay seconds (default: 1-3s random, e.g. --debug-images 5 for 5s fixed delay)")
    parser.add_argument("--trace-id", type=str, default=None,
                        help="Override auto-generated trace ID for log correlation")
    parser.add_argument("--rebuild", action="store_true", help="Force regeneration even if image exists")
    parser.add_argument("--check", action="store_true",
                        help="Show existing/missing counts without building")
    parser.add_argument("--resume", action="store_true",
                        help="Only generate missing images (default behavior, explicit)")
    parser.add_argument("--yes", "-y", action="store_true",
                        help="Skip confirmation prompt (for scripted use)")
    parser.add_argument("--max", type=int, default=None, help="Maximum images to process in batch mode")

    # WebUI integration
    parser.add_argument("--webui", action="store_true",
                        help="Force WebUI integration (auto-detected when server is running)")
    parser.add_argument("--port", type=int, default=None,
                        help="WebUI server port (default: auto-detect from config or 8084)")
    parser.add_argument("--no-interactive", action="store_true",
                        help="Don't prompt on WebUI connection failure (for automation)")
    parser.add_argument("--queue", action="store_true",
                        help="Add to generate-list queue instead of generating directly")
    parser.add_argument("--start-worker", action="store_true",
                        help="Start worker after queuing (uses smart start-or-queue by default)")
    parser.add_argument("--promote", action="store_true",
                        help="Promote batch to top priority (stops current batch and starts this one immediately)")
    parser.add_argument("--force", action="store_true",
                        help="Stop running task and start this one (use when worker is busy)")
    parser.add_argument("--process-queue", action="store_true",
                        help="Process items from existing generate-list queue (used by WebUI resume)")


    # Utility
    parser.add_argument("--list-operations", action="store_true", help="List available wildcard operations and exit")
    parser.add_argument("--list-artifacts", action="store_true",
                        help="List artifacts for prompt/path (requires --prompt-id and --path)")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")

    # Build stages (declarative stage-based generation)
    parser.add_argument("--list-stages", action="store_true",
                        help="List available build stages and exit")
    parser.add_argument("--stage", type=str, metavar="STAGE_ID",
                        help="Build items matching a stage query (e.g., 'checkpoints', 'pending')")

    args = parser.parse_args()

    # Fix #5: Validate --resume + --rebuild conflict early
    if args.resume and args.rebuild:
        print("\nError: --resume and --rebuild are mutually exclusive.")
        return 1

    # Auto-detect WebUI server if --webui not explicitly set
    if not args.webui:
        server_running, detected_port = auto_detect_webui_server(
            args.job, args.composition, args.port
        )
        if server_running:
            print(f"   Auto-detected WebUI server on port {detected_port}")
            args.webui = True
            args.port = detected_port
    else:
        # --webui flag explicitly set, detect port
        args.port = detect_webui_port(args.job, args.composition, args.port)

    # Set JOB_DIR environment variable for debug logging
    job_dir = Path.cwd() / 'jobs' / args.job
    os.environ['JOB_DIR'] = str(job_dir)

    # Always generate trace-id from params hash + timestamp (deterministic for same params)
    hash_parts = [
        args.job,
        str(args.composition),
        args.operation or 'default',
        args.prompt_id or 'all',
        args.path or 'none',
        args.build or 'none',
        str(args.config_index),
        str(args.max or 'all'),
        'rebuild' if args.rebuild else 'build',
        'queue' if args.queue else 'direct',
        'debug' if args.debug_images else 'real'
    ]
    params_key = ':'.join(hash_parts)
    params_hash = hashlib.md5(params_key.encode()).hexdigest()[:6]
    timestamp = datetime.now().strftime('%H%M%S')

    # Format: {hash}_{timestamp} - hash is deterministic, timestamp makes it unique per run
    auto_trace_id = f"{params_hash}_{timestamp}"

    # Allow --trace-id to override auto-generated ID
    trace_id = args.trace_id if args.trace_id else auto_trace_id

    # Set DEBUG_ID environment variable (always set now)
    os.environ['DEBUG_ID'] = trace_id

    # Calculate debug log path
    debug_log_path = job_dir / 'tmp' / 'debug' / f"{trace_id}.log"

    # Write initial debug log entry with full command
    cmd_parts = [f"generate-cli.py {args.job} -c {args.composition}"]
    if args.prompt_id:
        cmd_parts.append(f"--prompt {args.prompt_id}")
    if args.build:
        cmd_parts.append(f"--build {args.build}")
    if args.config_index:
        cmd_parts.append(f"--config-index {args.config_index}")
    if args.operation:
        cmd_parts.append(f"--operation {args.operation}")
    if args.debug_images:
        cmd_parts.append("--debug-images")
    if args.rebuild:
        cmd_parts.append("--rebuild")
    if args.check:
        cmd_parts.append("--check")
    if args.yes:
        cmd_parts.append("--yes")
    if args.resume:
        cmd_parts.append("--resume")
    if args.max:
        cmd_parts.append(f"--max {args.max}")
    if args.webui:
        cmd_parts.append(f"--webui --port {args.port}")
    if args.queue:
        cmd_parts.append("--queue")
    _debug_log('CLI', 'START', ' '.join(cmd_parts))

    # Set WebUI environment variables if --webui flag is set
    is_connected = False
    if args.webui:
        os.environ['WEBUI_PORT'] = str(args.port)
        os.environ['WEBUI_ENABLED'] = '1'

        # Test connection to WebUI server
        from src.webui_events import test_webui_connection

        is_connected, message = test_webui_connection(args.port)

        if is_connected:
            print(f"   {message}")
        else:
            print(f"\nWARNING: WebUI Integration Disabled")
            print(f"   {message}")
            print(f"   Events will not be pushed to WebUI.")
            print(f"\n   To fix:")
            print(f"   1. Start WebUI server: ./start-prompty.sh")
            print(f"   2. Or remove --webui flag to run CLI-only mode\n")

            if not args.no_interactive:
                # Ask user if they want to continue
                try:
                    response = input("   Continue anyway? [y/N]: ").strip().lower()
                    if response not in ['y', 'yes']:
                        print("   Aborted.")
                        return 0
                except (KeyboardInterrupt, EOFError):
                    print("\n   Aborted.")
                    return 0
            else:
                # Non-interactive: continue silently
                print("   Continuing in CLI-only mode (--no-interactive).\n")

    # Determine effective mode
    if args.build:
        effective_mode = f"build-{args.build}"
    elif args.mode:
        effective_mode = args.mode
    else:
        effective_mode = "e2e"  # Default: single image E2E test

    print("\n" + "=" * 70)
    print("GENERATE-CLI - Unified Image Generation")
    print("=" * 70)
    print(f"   Job:         {args.job}")
    print(f"   Composition: c{args.composition}")
    if args.operation:
        print(f"   Operation:   {args.operation}")
    else:
        print(f"   Operation:   (none)")
    print(f"   Mode:        {effective_mode}")
    if args.webui:
        status = "Connected" if is_connected else "Unreachable"
        print(f"   WebUI:       {status} (port {args.port})")
    if args.debug_images is not None:
        delay_info = f"{args.debug_images}s fixed" if args.debug_images > 0 else "1-3s random"
        print(f"   Debug:       Placeholder images ({delay_info} delay)")
    if args.max:
        print(f"   Max images:  {args.max}")
    # Always show trace ID and log path for debugging context
    print(f"   Trace ID:    {trace_id}")
    print(f"   📋 Debug log: file://{debug_log_path}")

    try:
        tester = PipelineCLITester(
            args.job, args.composition,
            args.prompt_id, args.debug_images, args.rebuild,
            _shutdown_event, args.operation
        )
        # Store webui flag for use in generation
        tester.webui_mode = args.webui
        tester.webui_port = args.port
    except ValueError as e:
        print(f"\nError: {e}")
        return 1

    if args.prompt_id:
        print(f"   Prompt ID:   {args.prompt_id}")

    if args.list_operations:
        print("\nAvailable wildcard operations:")
        for op in tester.get_available_operations():
            marker = " <- selected" if op == args.operation else ""
            print(f"   {op}{marker}")
        return 0

    if args.list_artifacts:
        if not args.prompt_id or not args.path:
            print("\nError: --list-artifacts requires --prompt-id and --path")
            return 1

        from src.artifact_manager import list_checkpoint_artifacts

        checkpoint_dir = (
            tester.comp_dir /
            args.prompt_id / args.path
        )

        if not checkpoint_dir.exists():
            print(f"\nCheckpoint not found: {checkpoint_dir}")
            return 1

        artifacts = list_checkpoint_artifacts(checkpoint_dir)

        if not artifacts:
            print(f"\nARTIFACTS: {args.path}")
            print("  No artifacts found.")
            return 0

        print(f"\nARTIFACTS: {args.path}")
        print(f"  {'Alias/Mod':<24} {'Type':<8} {'Files':<6}")
        print(f"  {'-'*24} {'-'*8} {'-'*6}")

        total_files = 0
        for source, files in sorted(artifacts.items()):
            # Determine predominant type
            type_counts = {}
            for f in files:
                t = f.get('type', 'file')
                type_counts[t] = type_counts.get(t, 0) + 1

            main_type = max(type_counts, key=type_counts.get) if type_counts else '-'
            file_count = len(files)
            total_files += file_count

            print(f"  {source:<24} {main_type:<8} {file_count:<6}")

        print(f"\n  Total: {total_files} files in {len(artifacts)} sources")
        return 0

    # Handle --list-stages flag
    if args.list_stages:
        from src.build_stages import StageBuilder

        builder = StageBuilder(tester.job_dir, args.composition, args.variant)
        groups = builder.get_groups_with_stages()

        print(f"\nBuild Stages for {args.job} (c{args.composition}, variant={args.variant}):\n")

        for group in groups:
            mode_icon = ">>>" if group['mode'] == 'sequential' else "+++"
            print(f"  {mode_icon} {group['label']} ({group['mode']})")
            for stage in group['stages']:
                status = "x" if stage['remaining'] == 0 else "o"
                active = ">" if stage['id'] == group.get('current_stage_id') else " "
                print(f"    {active}{status} {stage['id']}: {stage['done']}/{stage['total']} (remaining: {stage['remaining']})")
            print()

        return 0

    # Handle --stage flag (build items matching a stage query)
    if args.stage:
        from src.build_stages import StageBuilder

        builder = StageBuilder(tester.job_dir, args.composition, args.variant)
        stage = builder.get_stage(args.stage)

        if not stage:
            print(f"\nStage '{args.stage}' not found")
            print("   Use --list-stages to see available stages")
            return 1

        # Get items matching the stage query
        items = builder.get_items_for_stage(args.stage, max_count=args.max)

        if not items:
            print(f"\nStage '{args.stage}' has no pending items")
            return 0

        print(f"\nStage: {args.stage}")
        print(f"   Total matching: {stage.remaining}")
        print(f"   Processing: {len(items)} items" + (f" (limited by --max {args.max})" if args.max else ""))

        if args.debug_images:
            print(f"\nDEBUG MODE: Generating AI-readable placeholder images:\n")
            for i, item in enumerate(items[:5]):
                print(f"   {i+1}. {item['prompt_id']}/{item['path']} i{item['address_index']} c{item['config_index']}")
            if len(items) > 5:
                print(f"   ... and {len(items) - 5} more")
            # Continue to generation (don't exit) - DEBUG_MODE env var triggers placeholders

        # Execute the items using the existing pipeline
        print(f"\nGenerating {len(items)} images from stage '{args.stage}'...\n")

        # Use the tester's existing generation infrastructure
        success_count = 0
        error_count = 0

        for i, item in enumerate(items):
            # Check for shutdown signal
            if _shutdown_event.is_set():
                print(f"\nShutdown requested, stopping after {success_count} images")
                break

            print(f"[{i+1}/{len(items)}] {item['prompt_id']}/{item['path']} i{item['address_index']} c{item['config_index']}")

            try:
                result = tester._generate_single_image(
                    prompt_id=item['prompt_id'],
                    path_string=item['path'],
                    address_index=item['address_index'],
                    config_index=item['config_index'],
                    wc_indices={},
                    rebuild=args.rebuild
                )

                if result:
                    success_count += 1
                    print(f"   Generated")
                else:
                    error_count += 1
                    print(f"   Failed")

            except Exception as e:
                error_count += 1
                print(f"   Error: {e}")

        print(f"\nStage '{args.stage}' complete:")
        print(f"   Success: {success_count}")
        if error_count:
            print(f"   Errors: {error_count}")

        return 0 if error_count == 0 else 1

    # Check if worker is busy (WebUI parity)
    if args.webui and not args.queue and not args.process_queue:
        try:
            import requests
            status_res = requests.get(f'http://localhost:{args.port}/api/worker/status', timeout=2)
            if status_res.ok:
                status_data = status_res.json()
                if status_data.get('running'):
                    ongoing = status_data.get('ongoing') or {}
                    progress = ongoing.get('progress', {})

                    if args.force:
                        # Stop current task and proceed
                        print(f"\n   Stopping current task: {ongoing.get('title', 'Unknown')}")
                        pause_res = requests.post(f'http://localhost:{args.port}/api/generate-list/pause', timeout=5)
                        if pause_res.ok:
                            print("   Current task paused (can be resumed later)")
                        else:
                            print("   Warning: Could not pause current task")
                    else:
                        # Show verbose error and exit
                        print("\n" + "=" * 70)
                        print("WORKER BUSY")
                        print("=" * 70)
                        print(f"\n   Current task: {ongoing.get('title', 'Unknown')}")
                        if progress.get('total', 0) > 0:
                            print(f"   Progress:     {progress.get('current', 0)}/{progress.get('total', 0)} ({progress.get('percent', 0)}%)")
                        print(f"   Source:       {ongoing.get('source', 'unknown')}")
                        print(f"\n   Options:")
                        print(f"      --queue    Add to queue (runs after current completes)")
                        print(f"      --force    Stop current task and start this one")
                        print()
                        return 1
        except Exception as e:
            # Connection error - proceed anyway (server might not be running)
            _debug_log('CLI', 'WARN', f'Could not check worker status: {e}')

    # Push worker start event for WebUI
    if args.webui:
        try:
            from src.webui_events import push_event
            import time as time_module
            push_event('worker', {
                'running': True,
                'start_time': time_module.time()
            })
        except ImportError:
            pass

    # Run tests based on mode
    results = []

    # Handle --process-queue flag (WebUI resume)
    if args.process_queue:
        sys.path.insert(0, str(Path.cwd() / 'webui' / 'v4'))
        from server.generate_list import GenerateList

        job_dir = Path.cwd() / 'jobs' / args.job
        generate_list = GenerateList(job_dir)

        if not generate_list.ongoing_id:
            print("\nNo ongoing batch to process")
            return 1

        batch = generate_list.get_batch(generate_list.ongoing_id)
        if not batch:
            print(f"\nBatch {generate_list.ongoing_id} not found")
            return 1

        # Get remaining items (from current_index to end)
        items = batch.get('items', [])
        current_index = batch.get('current_index', 0)
        remaining_items = items[current_index:]

        if not remaining_items:
            print("\nAll items already processed")
            generate_list.stop_ongoing()
            return 0

        print(f"\nProcessing queue: {len(remaining_items)} remaining items")
        print(f"   Batch: {batch.get('title', 'Untitled')}")
        print(f"   Progress: {current_index}/{len(items)}")

        process_queue_items(tester, generate_list, batch, remaining_items, args, _shutdown_event)
        return 0

    # Handle --build flag (WebUI parity)
    if args.build:
        # Fix #2: Validate required args BEFORE confirmation
        if args.build in ['configs', 'variations', 'variants']:
            if not args.prompt_id or not args.path:
                print(f"\nError: --prompt-id and --path required for --build {args.build}")
                return 1

        # === Build Confirmation Logic (WebUI parity) ===
        # Get ALL items for this build type to calculate counts
        all_items = []
        if args.build == 'covers':
            all_items = tester.build_module.build_covers(args.prompt_id, args.config_index, rebuild=True)
        elif args.build == 'configs':
            if args.prompt_id and args.path:
                all_items = tester.build_module.build_configs(args.prompt_id, args.path, args.config_index, rebuild=True)
        elif args.build == 'variations':
            if args.prompt_id and args.path:
                all_items = tester.build_module.build_variations(args.prompt_id, args.path, args.address, rebuild=True)
        elif args.build == 'all':
            all_items = tester.build_module.build_all(args.config_index, rebuild=True)
        elif args.build == 'variants':
            if args.prompt_id and args.path:
                all_items = tester.build_module.build_variants(args.prompt_id, args.path, args.config_index, args.address, rebuild=True)

        # Calculate existing/missing counts
        pending_items = tester.build_module._filter_pending_items(all_items)
        existing_count = len(all_items) - len(pending_items)
        missing_count = len(pending_items)
        total_count = len(all_items)

        # Fix #1: Zero items warning
        if total_count == 0:
            print(f"\n{args.build.capitalize()}: No items found to build.")
            if args.build in ['configs', 'variations', 'variants']:
                print("   Check that --prompt-id and --path are correct.")
            return 0

        # --check: Just show summary and exit
        if args.check:
            _show_build_summary(args.build, existing_count, missing_count)
            print("\nUse --rebuild to regenerate all, or run without flags to generate missing only.")
            return 0

        # Interactive confirmation (unless --yes or --queue is passed)
        if not args.yes and not args.queue and total_count > 0:
            _show_build_summary(args.build, existing_count, missing_count)

            choice = _prompt_build_action(existing_count, missing_count)
            if choice == 'cancel':
                print("Cancelled.")
                return 0
            elif choice == 'overwrite':
                args.rebuild = True
            # 'resume' keeps args.rebuild as-is (False by default)

        # === End Build Confirmation Logic ===

        if args.build == 'covers':
            # Build cover images (address_index=1) for all checkpoints
            results = tester.run_build_covers_test(args.prompt_id, args.config_index)

            # Handle --queue flag: add to generate-list instead of generating
            if args.queue:
                items = tester.build_module.build_covers(args.prompt_id, args.config_index, args.rebuild)
                # Filter pending items FIRST (unless rebuilding), then apply max limit
                if not args.rebuild:
                    items = tester.build_module._filter_pending_items(items)
                if args.max:
                    items = items[:args.max]
                # Fix #4: Empty queue guard
                if not items:
                    print(f"\n{args.build.capitalize()}: No items to queue.")
                    return 0
                queue_result = add_to_queue(args, items, f"Build Covers - c{args.config_index}", _shutdown_event)

                # If --start-worker, process items ourselves (CLI is the worker)
                if queue_result:
                    generate_list, batch, queued_items = queue_result
                    process_queue_items(tester, generate_list, batch, queued_items, args, _shutdown_event)

                return 0

            # Execute build (now runs in debug mode too, generating placeholder images)
            build_results = tester.execute_build_covers(args.prompt_id, args.config_index, args.max)
            results.extend(build_results)
        elif args.build == 'configs':
            # Validation moved to Fix #2 (early validation block above)
            results = tester.run_build_configs_test(args.prompt_id, args.path, args.config_index)

            if args.queue:
                items = tester.build_module.build_configs(args.prompt_id, args.path, args.config_index, args.rebuild)
                # Filter pending items FIRST (unless rebuilding), then apply max limit
                if not args.rebuild:
                    items = tester.build_module._filter_pending_items(items)
                if args.max:
                    items = items[:args.max]
                # Fix #4: Empty queue guard
                if not items:
                    print(f"\n{args.build.capitalize()}: No items to queue.")
                    return 0
                queue_result = add_to_queue(args, items, f"Build Configs - {args.prompt_id}/{args.path}", _shutdown_event)

                # If --start-worker, process items ourselves
                if queue_result:
                    generate_list, batch, queued_items = queue_result
                    process_queue_items(tester, generate_list, batch, queued_items, args, _shutdown_event)

                return 0

            # Execute build (now runs in debug mode too, generating placeholder images)
            build_results = tester.execute_build_configs(args.prompt_id, args.path, args.address, args.max)
            results.extend(build_results)
        elif args.build == 'variations':
            # Validation moved to Fix #2 (early validation block above)
            results = tester.run_build_variations_test(args.prompt_id, args.path, args.address)

            if args.queue:
                items = tester.build_module.build_variations(args.prompt_id, args.path, args.address, args.rebuild)
                # Filter pending items FIRST (unless rebuilding), then apply max limit
                if not args.rebuild:
                    items = tester.build_module._filter_pending_items(items)
                if args.max:
                    items = items[:args.max]
                # Fix #4: Empty queue guard
                if not items:
                    print(f"\n{args.build.capitalize()}: No items to queue.")
                    return 0
                queue_result = add_to_queue(args, items, f"Build Variations - {args.prompt_id}/{args.path} img:{args.address}", _shutdown_event)

                # If --start-worker, process items ourselves
                if queue_result:
                    generate_list, batch, queued_items = queue_result
                    process_queue_items(tester, generate_list, batch, queued_items, args, _shutdown_event)

                return 0

            # Execute build (now runs in debug mode too, generating placeholder images)
            build_results = tester.execute_build_variations(args.prompt_id, args.path, args.address, args.max)
            results.extend(build_results)
        elif args.build == 'all':
            # Build all: covers for all checkpoints x all base configs
            # Only run test validation in debug mode
            if args.debug_images:
                results = tester.run_build_covers_test(args.prompt_id, args.config_index)

            if args.queue:
                items = tester.build_module.build_all(args.config_index, args.rebuild)
                # Filter pending items FIRST (unless rebuilding), then apply max limit
                if not args.rebuild:
                    items = tester.build_module._filter_pending_items(items)
                if args.max:
                    items = items[:args.max]
                # Fix #4: Empty queue guard
                if not items:
                    print(f"\n{args.build.capitalize()}: No items to queue.")
                    return 0
                queue_result = add_to_queue(args, items, f"Build All - c{args.config_index}", _shutdown_event)

                # If --start-worker, process items ourselves
                if queue_result:
                    generate_list, batch, queued_items = queue_result
                    process_queue_items(tester, generate_list, batch, queued_items, args, _shutdown_event)

                return 0

            # Execute build (now runs in debug mode too, generating placeholder images)
            build_results = tester.execute_build_all(args.max)
            results.extend(build_results)
        elif args.build == 'variants':
            # Build variants: cover images for all variants affecting this checkpoint
            # Validation moved to Fix #2 (early validation block above)

            # Only run test in debug mode
            if args.debug_images:
                results = tester.run_build_variants_test(
                    args.prompt_id, args.path, args.config_index, args.address
                )

            if args.queue:
                items = tester.build_module.build_variants(
                    args.prompt_id, args.path, args.config_index, args.address, args.rebuild
                )
                # Filter pending items FIRST (unless rebuilding), then apply max limit
                if not args.rebuild:
                    items = tester.build_module._filter_pending_items(items)
                if args.max:
                    items = items[:args.max]
                # Fix #4: Empty queue guard
                if not items:
                    print(f"\n{args.build.capitalize()}: No items to queue.")
                    return 0

                queue_result = add_to_queue(
                    args, items,
                    f"Build Variants - {args.prompt_id}/{args.path}",
                    _shutdown_event
                )

                # If --start-worker, process items ourselves
                if queue_result:
                    generate_list, batch, queued_items = queue_result
                    process_queue_items(tester, generate_list, batch, queued_items, args, _shutdown_event)

                return 0

            # Execute build (now runs in debug mode too, generating placeholder images)
            build_results = tester.execute_build_variants(
                args.prompt_id, args.path, args.config_index, args.address, args.max
            )
            results.extend(build_results)
    # Handle batch mode
    elif args.mode == 'batch':
        # Batch mode: process pending images from data.json
        results = tester.run_batch_processing(args.max)

    # Run single image generation by default (E2E test)
    # Debug mode generates placeholder images for fast validation
    if not args.build and args.mode != 'batch':
        gen_result = tester.generate_test_image(args.address)
        results.append(gen_result)

    # Summary
    print("\n" + "=" * 70)
    print("TEST SUMMARY")
    print("=" * 70)

    passed_count = sum(1 for _, passed in results if passed)
    total_count = len(results)

    for name, passed in results:
        status = "PASS" if passed else "FAIL"
        print(f"{'PASS' if passed else 'FAIL'}: {name}")

    print(f"\nTotal: {passed_count}/{total_count} tests passed")

    # Push worker_complete and worker stop events for WebUI mode
    if args.webui:
        try:
            from src.webui_events import push_event
            push_event('worker_complete', {
                'total': total_count,
                'passed': passed_count,
                'failed': total_count - passed_count,
                'build_action': args.build
            })
            # Also push job_end for frontend compatibility
            push_event('job_end', {
                'success': passed_count == total_count,
                'total': total_count,
                'passed': passed_count,
                'failed': total_count - passed_count
            })
            # Push worker stop event to hide "GENERATING..." indicator
            push_event('worker', {
                'running': False,
                'start_time': None
            })
        except ImportError:
            pass

    if passed_count == total_count:
        print("\nALL TESTS PASSED!")

        # Output JSON completion signal if --json flag is set
        if args.json:
            completion_signal = json.dumps({
                "event": "job_complete",
                "status": "success",
                "total": total_count,
                "passed": passed_count,
                "failed": total_count - passed_count,
                "job": args.job,
                "composition": args.composition,
                "operation": args.operation,
                "build_action": args.build
            })
            print(f"__JSON_COMPLETION__: {completion_signal}")

        return 0
    else:
        print("\nSOME TESTS FAILED")

        # Output JSON completion signal if --json flag is set
        if args.json:
            completion_signal = json.dumps({
                "event": "job_complete",
                "status": "failed",
                "total": total_count,
                "passed": passed_count,
                "failed": total_count - passed_count,
                "job": args.job,
                "composition": args.composition,
                "operation": args.operation,
                "build_action": args.build
            })
            print(f"__JSON_COMPLETION__: {completion_signal}")

        return 1
