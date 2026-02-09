"""
src/cli/queue_manager.py - Queue Operations

Generate-list queue management including:
- Adding items to queue (_add_to_queue)
- Processing queue items (_process_queue_items)

Debug relevance: When queue/WebUI integration breaks
"""

import os
import sys
import time
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Any

from .utils import _debug_log


def add_to_queue(args, items: list, title: str, shutdown_event=None) -> Optional[Tuple[Any, Dict, List]]:
    """Add items to generate-list queue and optionally start processing.

    Args:
        args: Parsed arguments
        items: List of generation items
        title: Batch title
        shutdown_event: Optional threading.Event for shutdown signaling

    Returns:
        tuple: (generate_list, batch, items) if --start-worker is set, None otherwise
    """
    # Import GenerateList
    sys.path.insert(0, str(Path.cwd() / 'webui' / 'v4'))
    try:
        from server.generate_list import GenerateList
    except ImportError as e:
        print(f"\nError: Could not import GenerateList: {e}")
        print("   Make sure WebUI server files are present.")
        sys.exit(1)

    job_dir = Path.cwd() / 'jobs' / args.job

    # Create GenerateList instance
    generate_list = GenerateList(job_dir)

    # Capture CLI flags for WebUI resume (same pattern as WebUI build buttons)
    cli_payload = {
        'type': 'cli',
        'composition': args.composition,
        'variant': args.variant,
        'build_action': args.build,
        'rebuild': args.rebuild,
    }

    # Add optional flags if specified
    if args.prompt_id:
        cli_payload['prompt_id'] = args.prompt_id
    if args.path:
        cli_payload['path'] = args.path
    if args.address:
        cli_payload['address_index'] = args.address
    if args.config_index:
        cli_payload['config_index'] = args.config_index

    # Change "Build" to "Rebuild" in title if batch contains rebuilds
    has_rebuilds = args.rebuild or any(item.get('rebuild', False) for item in items)
    if has_rebuilds:
        title = title.replace('Build', 'Rebuild')
        # Also ensure all items have rebuild flag set
        for item in items:
            item['rebuild'] = True

    # Create batch
    batch = generate_list.create_batch(
        title=title,
        items=items,
        source='cli',
        source_page=cli_payload
    )

    # Register CLI process ID for WebUI stop functionality
    pid = os.getpid()
    generate_list.register_batch_pid(batch['id'], pid)

    # Log batch creation to debug log for tracing
    _debug_log('CLI', 'BATCH', f"Created {batch['id']} \"{title}\" with {len(items)} items (queue mode)")

    print(f"\nAdded {len(items)} items to queue")
    print(f"   Batch ID: {batch['id']}")
    print(f"   Registered PID {pid} for WebUI stop support")
    print(f"   Title: {title}")
    if has_rebuilds:
        print(f"   Mode: REBUILD (force regenerate existing images)")
        print(f"   rebuild_count: {len(items)}")

    # Start batch and return items for CLI to process
    if args.start_worker:
        # Check if we should promote (force to top priority)
        if args.promote:
            # Use promote_to_top which stops current and starts this one immediately
            result = generate_list.promote_to_top(batch['id'], stop_current=True)
            if result:
                print(f"   Status: ⚡ PROMOTED to top priority (stopped ongoing batch)")
                print(f"   Processing: CLI will generate {len(items)} items...")
            else:
                print(f"   Error: Failed to promote batch")
                return None
        else:
            # Default: Use smart start-or-queue logic (WebUI parity)
            result = generate_list.start_or_queue(batch['id'])
            
            # Verbose logging for queue state tracking
            if result.get('action') == 'started':
                print(f"   Status: ✅ Started immediately (no ongoing batch)")
                print(f"   Processing: CLI will generate {len(items)} items...")
            elif result.get('action') == 'queued':
                position = result.get('position', '?')
                ongoing_id = result.get('ongoing_id')
                ongoing_batch = generate_list.get_batch(ongoing_id) if ongoing_id else None
                
                print(f"   Status: 📋 Queued (position {position} in next-up)")
                if ongoing_batch:
                    ongoing_title = ongoing_batch.get('title', 'Unknown')[:40]
                    ongoing_progress = f"{ongoing_batch.get('generated', 0)}/{ongoing_batch.get('total', 0)}"
                    print(f"   Ongoing: '{ongoing_title}...' ({ongoing_progress} images)")
                print(f"   → Batch will auto-start when current batch completes")
                print(f"   → Use --promote flag to override and start immediately")
                
                # Don't process items - they're queued for WebUI/later processing
                return None
            elif result.get('action') == 'already_ongoing':
                print(f"   Status: ▶️  Already ongoing (resuming)")
                print(f"   Processing: CLI will continue generating {len(items)} items...")
            else:
                print(f"   Error: Unexpected result from start_or_queue: {result}")
                return None
        
        return (generate_list, batch, items)
    else:
        print(f"   Status: Queued (use --start-worker to auto-start)")
        print(f"   → Start from WebUI or run with --start-worker")
        return None


def process_queue_items(tester, generate_list, batch: dict, items: list, args, shutdown_event=None) -> None:
    """Process queue items directly from CLI.

    Args:
        tester: PipelineCLITester instance
        generate_list: GenerateList instance
        batch: Batch dict
        items: List of items to process
        args: Parsed arguments
        shutdown_event: Optional threading.Event for shutdown signaling
    """
    from src.webui_events import push_event

    job_dir = Path(tester.job_dir) if hasattr(tester, 'job_dir') else Path.cwd() / 'jobs' / args.job

    print(f"\n{'='*70}")
    print(f"PROCESSING QUEUE: {len(items)} items")
    print(f"{'='*70}\n")

    # Push worker start event
    if args.webui:
        push_event('worker', {'running': True, 'start_time': time.time()})

    completed = 0
    failed = 0

    for i, item in enumerate(items, 1):
        # Check for shutdown signal (WebUI stop or Ctrl+C)
        if shutdown_event and shutdown_event.is_set():
            print("\n   Shutdown requested, stopping queue processing...")
            break

        prompt_id = item['prompt_id']
        path = item['path']
        address_index = item.get('address_index', 1)
        config_index = item.get('config_index', item.get('config_idx', 0))
        rebuild_flag = item.get('rebuild', False)
        operation = item.get('operation', None)  # Wildcard operation to apply

        rebuild_indicator = " [REBUILD]" if rebuild_flag else ""
        operation_indicator = f" [op:{operation}]" if operation else ""
        print(f"[{i}/{len(items)}] {prompt_id}/{path} img:{address_index} cfg:{config_index}{rebuild_indicator}{operation_indicator}")

        try:
            # Generate the image (wc_indices is empty for queue-based generation)
            wc_indices = item.get('wc', {})  # Use wc from item if available

            # Set operation for this item (generator handles _ops/ path)
            original_operation = tester.operation
            if operation:
                tester.operation = operation

            result = tester._generate_single_image(prompt_id, path, address_index, config_index, wc_indices, rebuild_flag)

            # Restore original operation
            tester.operation = original_operation
            if result:
                completed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"   Error: {e}")
            failed += 1

        # Update queue progress (this may auto-advance to next batch when exhausted)
        generate_list.pop_next_item()

    # Only stop if this batch is still ongoing (pop_next_item may have auto-advanced)
    if generate_list.ongoing_id == batch['id']:
        generate_list.stop_ongoing()

    # Force reload to pick up any batches added while we were processing
    # This is critical for WebUI-spawned workers where the API may have queued
    # additional batches during generation (e.g., user clicks "Build Variations"
    # while "Build Covers" is running)
    generate_list._reload_if_modified()

    # Continue processing queued batches until empty (CLI-WebUI parity)
    # This ensures CLI behaves like WebUI: processes all queued batches, not just one
    while generate_list.ongoing_id:
        next_batch = generate_list.get_batch(generate_list.ongoing_id)
        if not next_batch:
            break
        if not next_batch.get('items'):
            break

        # Re-register PID for WebUI stop support
        generate_list.register_batch_pid(next_batch['id'], os.getpid())

        remaining_items = next_batch['items'][next_batch.get('current_index', 0):]
        if not remaining_items:
            generate_list.stop_ongoing()
            continue
        
        print(f"\n▶️  Auto-starting next batch: {next_batch['title'][:40]}...")
        print(f"   Items: {len(remaining_items)}")
        
        # Recursive call - same hooks/mods/SIGINT handling applies
        process_queue_items(tester, generate_list, next_batch, remaining_items, args, shutdown_event)

    print(f"\n{'='*70}")
    print(f"ALL QUEUES COMPLETE")
    print(f"{'='*70}")

    # Push worker stop event
    if args.webui:
        push_event('worker', {'running': False, 'start_time': None})
    
