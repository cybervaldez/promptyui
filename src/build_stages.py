#!/usr/bin/env python3
"""
Build Stages System

Provides a declarative, YAML-based system for defining generation stages.
Each stage specifies a query that filters images and defines a button
for the WebUI.

Usage:
    from src.build_stages import StageBuilder

    builder = StageBuilder(job_dir, composition, variant)
    stages = builder.get_all_stages()  # For multi-button UI
    current = builder.get_current_stage()  # For sequential mode
    queued = builder.queue_stage('checkpoints')  # Queue items for a stage
"""

import json
import fnmatch
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field


@dataclass
class StageQuery:
    """Filter criteria for matching images."""
    status: Optional[List[int]] = None  # [0], [0, 2], etc.
    address_index: Optional[int] = None  # 1-based
    address_index_range: Optional[tuple] = None  # (min, max)
    config: Optional[List[int]] = None  # [0], [1, 2, 3], etc.
    config_range: Optional[tuple] = None  # (min, max) or (min, None) for "min+"
    prompt_id: Optional[List[str]] = None
    path_pattern: Optional[str] = None  # Glob pattern
    wildcards: Optional[Dict[str, Any]] = None  # wildcard_name: value or pattern
    lora: Optional[Dict[str, Any]] = None  # suffix, strength, etc.
    variant_mode: str = "single"  # "single" | "all_affected" | "missing_only"


@dataclass
class Stage:
    """A generation stage definition."""
    id: str
    label: str
    icon: str = "▶"
    mode: str = "button"  # "button" (always visible) or "sequential"
    priority: int = 100
    query: StageQuery = field(default_factory=StageQuery)
    script: Optional[str] = None
    depends_on: List[str] = field(default_factory=list)
    is_default: bool = False
    group_id: Optional[str] = None  # Which group this stage belongs to

    # Runtime counts (populated by StageBuilder)
    total: int = 0
    remaining: int = 0
    done: int = 0


def parse_range(value: Any) -> tuple:
    """Parse range syntax like '1-5', '1+', or single int."""
    if isinstance(value, int):
        return ([value], None)  # Single value

    if isinstance(value, list):
        return (value, None)  # List of values

    if isinstance(value, str):
        value = value.strip()

        # "1+" means 1 and above
        if value.endswith('+'):
            min_val = int(value[:-1])
            return (None, (min_val, None))

        # "!0" means not 0
        if value.startswith('!'):
            exclude = int(value[1:])
            return (None, ('exclude', exclude))

        # "1-5" means range
        if '-' in value:
            parts = value.split('-')
            return (None, (int(parts[0]), int(parts[1])))

        # Single number as string
        return ([int(value)], None)

    return (None, None)


def parse_query(query_dict: dict) -> StageQuery:
    """Parse query dictionary into StageQuery object."""
    q = StageQuery()

    # Status
    if 'status' in query_dict:
        val = query_dict['status']
        if isinstance(val, int):
            q.status = [val]
        elif isinstance(val, list):
            q.status = val

    # Address index
    if 'address_index' in query_dict:
        val = query_dict['address_index']
        if isinstance(val, int):
            q.address_index = val
        else:
            vals, rng = parse_range(val)
            if vals:
                q.address_index = vals[0]
            else:
                q.address_index_range = rng

    # Config
    if 'config' in query_dict:
        vals, rng = parse_range(query_dict['config'])
        if vals:
            q.config = vals
        else:
            q.config_range = rng

    # Prompt ID
    if 'prompt_id' in query_dict:
        val = query_dict['prompt_id']
        q.prompt_id = val if isinstance(val, list) else [val]

    # Path pattern
    if 'path' in query_dict:
        q.path_pattern = query_dict['path']

    # Wildcards
    if 'wildcards' in query_dict:
        q.wildcards = query_dict['wildcards']

    # LoRA filters
    if 'lora' in query_dict:
        q.lora = query_dict['lora']

    # Variant mode
    if 'variant_mode' in query_dict:
        q.variant_mode = query_dict['variant_mode']

    return q


def parse_stage(stage_dict: dict) -> Stage:
    """Parse stage dictionary into Stage object."""
    query = parse_query(stage_dict.get('query', {'status': 0}))

    return Stage(
        id=stage_dict['id'],
        label=stage_dict.get('label', stage_dict['id']),
        icon=stage_dict.get('icon', '▶'),
        mode=stage_dict.get('mode', 'button'),
        priority=stage_dict.get('priority', 100),
        query=query,
        script=stage_dict.get('script'),
        depends_on=stage_dict.get('depends_on', []),
        is_default=stage_dict.get('is_default', False)
    )


class StageBuilder:
    """Manages build stages for a job."""

    DEFAULT_STAGE = {
        'id': 'pending',
        'label': 'Generate ({remaining} pending)',
        'icon': '▶',
        'is_default': True,
        'query': {'status': 0}
    }

    def __init__(self, job_dir: Path, composition: int, variant: str = None):
        self.job_dir = Path(job_dir)
        self.composition = composition
        self.variant = variant  # Deprecated: kept for API compatibility
        self.comp_dir = self.job_dir / 'outputs'

        self.stages: List[Stage] = []
        self._load_stages()

    def _load_stages(self):
        """Load stages from build_stages.yaml or use defaults.

        Supports two formats:
        1. Top-level 'stages' list (legacy/simple)
        2. 'groups' list with nested stages (new format)
        """
        stages_file = self.job_dir / 'build_stages.yaml'
        self.groups = []  # Store parsed groups

        if stages_file.exists():
            try:
                import yaml
                with open(stages_file, 'r') as f:
                    config = yaml.safe_load(f)

                if config:
                    # New format: groups
                    if 'groups' in config:
                        for group_dict in config['groups']:
                            group = {
                                'id': group_dict['id'],
                                'label': group_dict.get('label', group_dict['id']),
                                'icon': group_dict.get('icon', '▶'),
                                'mode': group_dict.get('mode', 'button'),
                                'stages': []
                            }
                            for stage_dict in group_dict.get('stages', []):
                                stage = parse_stage(stage_dict)
                                stage.group_id = group['id']
                                self.stages.append(stage)
                                group['stages'].append(stage.id)
                            self.groups.append(group)

                    # Legacy format: top-level stages
                    elif 'stages' in config:
                        default_group = {
                            'id': 'default',
                            'label': 'Generate',
                            'icon': '▶',
                            'mode': 'button',
                            'stages': []
                        }
                        for stage_dict in config['stages']:
                            stage = parse_stage(stage_dict)
                            stage.group_id = 'default'
                            self.stages.append(stage)
                            default_group['stages'].append(stage.id)
                        self.groups.append(default_group)

            except Exception as e:
                print(f"   Warning: Error loading build_stages.yaml: {e}")

        # Add default stage if none defined
        if not self.stages:
            default_stage = parse_stage(self.DEFAULT_STAGE)
            default_stage.group_id = 'default'
            self.stages.append(default_stage)
            self.groups.append({
                'id': 'default',
                'label': 'Generate',
                'icon': '▶',
                'mode': 'button',
                'stages': ['pending']
            })

        # Sort stages by priority
        self.stages.sort(key=lambda s: s.priority)

    def _image_matches_query(self, img: dict, data: dict, query: StageQuery) -> bool:
        """Check if an image matches a stage query."""
        # Status check happens at config level, handled separately

        # Address index
        if query.address_index is not None:
            if img.get('i') != query.address_index:
                return False

        if query.address_index_range is not None:
            idx = img.get('i', 0)
            min_val, max_val = query.address_index_range
            if max_val is None:  # "min+"
                if idx < min_val:
                    return False
            else:
                if not (min_val <= idx <= max_val):
                    return False

        # Prompt ID
        if query.prompt_id is not None:
            if data.get('prompt_id') not in query.prompt_id:
                return False

        # Path pattern
        if query.path_pattern is not None:
            if not fnmatch.fnmatch(data.get('path_string', ''), query.path_pattern):
                return False

        # Wildcards
        if query.wildcards is not None:
            img_wc = img.get('wc', {})
            for wc_name, wc_filter in query.wildcards.items():
                img_val = str(img_wc.get(wc_name, ''))
                if isinstance(wc_filter, str) and '*' in wc_filter:
                    # Glob pattern
                    if not fnmatch.fnmatch(img_val, wc_filter):
                        return False
                elif isinstance(wc_filter, list):
                    # Value must be in list
                    if img_val not in [str(v) for v in wc_filter]:
                        return False
                else:
                    # Exact match
                    if img_val != str(wc_filter):
                        return False

        return True

    def _config_matches_query(self, cfg_idx: int, query: StageQuery) -> bool:
        """Check if a config index matches query."""
        if query.config is not None:
            return cfg_idx in query.config

        if query.config_range is not None:
            # config_range can be:
            # - ('exclude', N) for !N
            # - (min, max) for min-max range
            # - (min, None) for min+ (min and above)
            first, second = query.config_range

            if first == 'exclude':
                return cfg_idx != second
            else:
                # It's a (min, max) tuple
                min_val = first
                max_val = second
                if max_val is None:  # "min+"
                    return cfg_idx >= min_val
                else:
                    return min_val <= cfg_idx <= max_val

        return True  # No config filter means all configs

    def _count_for_stage(self, stage: Stage) -> dict:
        """Count matching images for a stage."""
        total = 0
        remaining = 0  # Status 0 (pending) + status 2 (queued)
        done = 0       # Status 1 (generated)
        queued = 0     # Status 2 only

        if not self.comp_dir.exists():
            return {'total': 0, 'remaining': 0, 'done': 0, 'queued': 0}

        q = stage.query

        for data_file in self.comp_dir.rglob('data.json'):
            try:
                with open(data_file, 'r') as f:
                    data = json.load(f)

                # Load composition-specific status from separate file
                status_file = data_file.parent / 'status' / f'c{self.composition}.json'
                status_data = {}
                if status_file.exists():
                    with open(status_file, 'r') as f:
                        status_data = json.load(f)
                status_matrix = status_data.get('status', [])

                for img_idx, img in enumerate(data.get('images', [])):
                    if not self._image_matches_query(img, data, q):
                        continue

                    # Get status from status matrix (rows=images, cols=configs)
                    status_row = status_matrix[img_idx] if img_idx < len(status_matrix) else []

                    for cfg_idx in range(data.get('num_configs', 0)):
                        if not self._config_matches_query(cfg_idx, q):
                            continue

                        status = status_row[cfg_idx] if cfg_idx < len(status_row) else 0
                        total += 1
                        if status == 1:
                            done += 1
                        elif status == 2:
                            queued += 1
                            remaining += 1  # Queued counts as remaining work
                        elif status == 0:
                            remaining += 1
            except Exception:
                continue

        return {'total': total, 'remaining': remaining, 'done': done, 'queued': queued}

    def get_all_stages(self, include_counts: bool = True) -> List[Stage]:
        """Get all stages with optional counts."""
        if include_counts:
            for stage in self.stages:
                counts = self._count_for_stage(stage)
                stage.total = counts['total']
                stage.remaining = counts['remaining']
                stage.done = counts['done']

        return self.stages

    def get_stage(self, stage_id: str) -> Optional[Stage]:
        """Get a specific stage by ID."""
        for stage in self.stages:
            if stage.id == stage_id:
                counts = self._count_for_stage(stage)
                stage.total = counts['total']
                stage.remaining = counts['remaining']
                stage.done = counts['done']
                return stage
        return None

    def get_current_stage(self) -> Optional[Stage]:
        """Get the first incomplete stage (for sequential mode)."""
        stages = self.get_all_stages(include_counts=True)

        completed_ids = {s.id for s in stages if s.remaining == 0}

        for stage in stages:
            # Check dependencies
            if stage.depends_on:
                if not all(dep in completed_ids for dep in stage.depends_on):
                    continue

            if stage.remaining > 0:
                return stage

        return None  # All done

    def get_items_for_stage(self, stage_id: str, max_count: int = None) -> list:
        """Get items matching a stage query without modifying status.

        This method is used by the WebUI/CLI to get items for generation
        without changing the data.json files.

        Args:
            stage_id: The stage ID to query
            max_count: Optional limit on number of items to return

        Returns:
            List of item dicts with prompt_id, path, address_index, config_index
        """
        stage = self.get_stage(stage_id)
        if not stage:
            return []

        items = []
        q = stage.query
        target_statuses = q.status if q.status else [0]

        for data_file in self.comp_dir.rglob('data.json'):
            try:
                with open(data_file, 'r') as f:
                    data = json.load(f)

                # Load composition-specific status from separate file
                status_file = data_file.parent / 'status' / f'c{self.composition}.json'
                status_data = {}
                if status_file.exists():
                    with open(status_file, 'r') as f:
                        status_data = json.load(f)
                status_matrix = status_data.get('status', [])

                for img_idx, img in enumerate(data.get('images', [])):
                    if not self._image_matches_query(img, data, q):
                        continue

                    # Get status from status matrix (rows=images, cols=configs)
                    status_row = status_matrix[img_idx] if img_idx < len(status_matrix) else []

                    for cfg_idx in range(data.get('num_configs', 0)):
                        if not self._config_matches_query(cfg_idx, q):
                            continue

                        status = status_row[cfg_idx] if cfg_idx < len(status_row) else 0
                        if status in target_statuses:
                            items.append({
                                'prompt_id': data.get('prompt_id', ''),
                                'path': data.get('path_string', ''),
                                'address_index': img.get('i', 0),
                                'config_index': cfg_idx,
                                'variant': self.variant,
                                'rebuild': False
                            })

                            # Check limit
                            if max_count and len(items) >= max_count:
                                return items
            except Exception:
                continue

        return items

    def queue_stage(self, stage_id: str, max_count: int = None) -> dict:
        """Queue all matching pending items for a stage.

        If stage has a script defined, execute it for custom selection logic.
        Otherwise, queue all items matching the query.

        Args:
            stage_id: The stage ID to queue
            max_count: Optional limit on number of items to queue
        """
        stage = self.get_stage(stage_id)
        if not stage:
            return {'success': False, 'error': f'Stage not found: {stage_id}'}

        # If stage has a script, use custom logic
        if stage.script:
            return self._queue_with_script(stage, max_count)

        # Default: queue all matching items
        return self._queue_matching_items(stage, max_count)

    def _queue_with_script(self, stage: Stage, max_count: int = None) -> dict:
        """Execute custom script hook for queueing logic."""
        import subprocess
        import sys

        script_path = self.job_dir / stage.script
        if not script_path.exists():
            return {'success': False, 'error': f'Script not found: {stage.script}'}

        # Collect query results to pass to script
        query_results = self._collect_query_results(stage)

        # Build context for script
        context = {
            'job_dir': str(self.job_dir),
            'composition': self.composition,
            'variant': self.variant,
            'stage_id': stage.id,
            'max_count': max_count,
            'query_results': query_results
        }

        try:
            # Execute script and pass context via stdin
            result = subprocess.run(
                [sys.executable, str(script_path)],
                input=json.dumps(context),
                capture_output=True,
                text=True,
                cwd=str(self.job_dir),
                timeout=30
            )

            if result.returncode != 0:
                return {
                    'success': False,
                    'error': f'Script failed: {result.stderr}'
                }

            # Parse script output
            output = json.loads(result.stdout)
            items_to_queue = output.get('queue', [])
            custom_label = output.get('label')

            # Apply max_count limit
            if max_count and len(items_to_queue) > max_count:
                items_to_queue = items_to_queue[:max_count]

            # Queue the items returned by script
            queued = 0
            status_files_to_save = {}

            for item in items_to_queue:
                data_file = Path(item['data_file'])
                status_file = data_file.parent / 'status' / f'c{self.composition}.json'

                # Load data.json for image indexing
                with open(data_file, 'r') as f:
                    data = json.load(f)

                # Load or create status file
                if status_file not in status_files_to_save:
                    if status_file.exists():
                        with open(status_file, 'r') as f:
                            status_files_to_save[status_file] = json.load(f)
                    else:
                        status_files_to_save[status_file] = {'status': []}

                status_data = status_files_to_save[status_file]
                status_matrix = status_data.get('status', [])

                # Find image index and update status
                for img_idx, img in enumerate(data.get('images', [])):
                    if img['i'] == item['address_index']:
                        cfg_idx = item['config_index']

                        # Ensure status matrix has enough rows
                        while len(status_matrix) <= img_idx:
                            status_matrix.append([])
                        status_row = status_matrix[img_idx]

                        # Ensure status row has enough columns
                        while len(status_row) <= cfg_idx:
                            status_row.append(0)

                        if status_row[cfg_idx] == 0:
                            status_row[cfg_idx] = 2
                            queued += 1
                        break

                status_data['status'] = status_matrix

            # Write modified status files
            files_updated = 0
            for status_file, status_data in status_files_to_save.items():
                status_file.parent.mkdir(parents=True, exist_ok=True)
                with open(status_file, 'w') as f:
                    json.dump(status_data, f, indent=2)
                files_updated += 1

            return {
                'success': True,
                'stage_id': stage.id,
                'queued': queued,
                'files_updated': files_updated,
                'script_used': True,
                'custom_label': custom_label
            }

        except subprocess.TimeoutExpired:
            return {'success': False, 'error': 'Script timed out (30s limit)'}
        except json.JSONDecodeError as e:
            return {'success': False, 'error': f'Invalid script output: {e}'}
        except Exception as e:
            return {'success': False, 'error': f'Script error: {e}'}

    def _collect_query_results(self, stage: Stage) -> list:
        """Collect all items matching stage query for script input."""
        results = []
        q = stage.query
        target_statuses = q.status if q.status else [0]

        for data_file in self.comp_dir.rglob('data.json'):
            try:
                with open(data_file, 'r') as f:
                    data = json.load(f)

                # Load composition-specific status from separate file
                status_file = data_file.parent / 'status' / f'c{self.composition}.json'
                status_data = {}
                if status_file.exists():
                    with open(status_file, 'r') as f:
                        status_data = json.load(f)
                status_matrix = status_data.get('status', [])

                for img_idx, img in enumerate(data.get('images', [])):
                    if not self._image_matches_query(img, data, q):
                        continue

                    # Get status from status matrix (rows=images, cols=configs)
                    status_row = status_matrix[img_idx] if img_idx < len(status_matrix) else []

                    for cfg_idx in range(data.get('num_configs', 0)):
                        if not self._config_matches_query(cfg_idx, q):
                            continue

                        status = status_row[cfg_idx] if cfg_idx < len(status_row) else 0
                        if status in target_statuses:
                            results.append({
                                'data_file': str(data_file),
                                'prompt_id': data.get('prompt_id', ''),
                                'path_string': data.get('path_string', ''),
                                'address_index': img.get('i', 0),
                                'config_index': cfg_idx,
                                'status': status,
                                'wildcards': img.get('wc', {})
                            })
            except Exception:
                continue

        return results

    def _queue_matching_items(self, stage: Stage, max_count: int = None) -> dict:
        """Queue all items matching stage query (default behavior)."""
        queued = 0
        files_updated = 0
        q = stage.query
        items_queued = []

        status_files_to_save = {}

        for data_file in self.comp_dir.rglob('data.json'):
            try:
                with open(data_file, 'r') as f:
                    data = json.load(f)

                # Load composition-specific status from separate file
                status_file = data_file.parent / 'status' / f'c{self.composition}.json'
                status_data = {}
                if status_file.exists():
                    with open(status_file, 'r') as f:
                        status_data = json.load(f)
                status_matrix = status_data.get('status', [])

                file_modified = False

                for img_idx, img in enumerate(data.get('images', [])):
                    if not self._image_matches_query(img, data, q):
                        continue

                    # Get or create status row for this image
                    while len(status_matrix) <= img_idx:
                        status_matrix.append([])
                    status_row = status_matrix[img_idx]

                    for cfg_idx in range(data.get('num_configs', 0)):
                        if not self._config_matches_query(cfg_idx, q):
                            continue

                        # Check max_count limit
                        if max_count and queued >= max_count:
                            break

                        # Ensure status_row has enough entries
                        while len(status_row) <= cfg_idx:
                            status_row.append(0)

                        # Queue pending items (status 0) or re-queue stale items (status 2)
                        if status_row[cfg_idx] in (0, 2):
                            status_row[cfg_idx] = 2  # Queue
                            queued += 1
                            file_modified = True
                            items_queued.append({
                                'prompt_id': data.get('prompt_id', ''),
                                'path': data.get('path_string', ''),
                                'address_index': img.get('i', 0),
                                'config_index': cfg_idx,
                                'queued_at': datetime.now().isoformat()
                            })

                    # Break outer loop if limit reached
                    if max_count and queued >= max_count:
                        break

                if file_modified:
                    status_data['status'] = status_matrix
                    status_files_to_save[status_file] = status_data

                # Break file loop if limit reached
                if max_count and queued >= max_count:
                    break

            except Exception:
                continue

        # Write modified status files
        for status_file, status_data in status_files_to_save.items():
            status_file.parent.mkdir(parents=True, exist_ok=True)
            with open(status_file, 'w') as f:
                json.dump(status_data, f, indent=2)
            files_updated += 1

        return {
            'success': True,
            'stage_id': stage.id,
            'queued': queued,
            'files_updated': files_updated,
            'items': items_queued  # Return the actual items for the in-memory queue
        }

    def format_label(self, stage: Stage) -> str:
        """Format stage label with variable substitution."""
        label = stage.label
        label = label.replace('{remaining}', str(stage.remaining))
        label = label.replace('{total}', str(stage.total))
        label = label.replace('{done}', str(stage.done))
        return label

    def to_json(self, stage: Stage) -> dict:
        """Convert stage to JSON-serializable dict."""
        return {
            'id': stage.id,
            'label': self.format_label(stage),
            'icon': stage.icon,
            'mode': stage.mode,
            'priority': stage.priority,
            'is_default': stage.is_default,
            'remaining': stage.remaining,
            'total': stage.total,
            'done': stage.done,
            'has_script': stage.script is not None,
            'depends_on': stage.depends_on,
            'group_id': stage.group_id
        }

    def get_groups_with_stages(self) -> list:
        """Get groups with their stages and counts."""
        # Ensure stages have counts
        self.get_all_stages(include_counts=True)

        result = []
        for group in self.groups:
            group_stages = [
                self.to_json(s) for s in self.stages
                if s.group_id == group['id']
            ]

            # Determine current stage (for sequential groups)
            current_stage_id = None
            if group['mode'] == 'sequential':
                completed_ids = {s['id'] for s in group_stages if s['remaining'] == 0}
                for s in group_stages:
                    deps = s.get('depends_on', [])
                    if s['remaining'] > 0 and all(d in completed_ids for d in deps):
                        current_stage_id = s['id']
                        break

            result.append({
                'id': group['id'],
                'label': group['label'],
                'icon': group['icon'],
                'mode': group['mode'],
                'stages': group_stages,
                'current_stage_id': current_stage_id
            })

        return result

    # Alias used by WebUI API
    def get_stage_groups(self) -> list:
        """Alias for get_groups_with_stages() used by WebUI API."""
        return self.get_groups_with_stages()


# CLI for testing
if __name__ == '__main__':
    import sys

    if len(sys.argv) < 2:
        print("Usage: python build_stages.py <job_dir> [composition]")
        sys.exit(1)

    job_dir = Path(sys.argv[1])
    composition = int(sys.argv[2]) if len(sys.argv) > 2 else 99

    builder = StageBuilder(job_dir, composition)
    groups = builder.get_groups_with_stages()

    print(f"\n📋 Build Stage Groups for {job_dir.name} (c{composition}):\n")
    for group in groups:
        mode_icon = "🔗" if group['mode'] == 'sequential' else "⊕"
        print(f"  {mode_icon} {group['label']} ({group['mode']})")
        for stage in group['stages']:
            status = "✓" if stage['remaining'] == 0 else "○"
            active = "→" if stage['id'] == group.get('current_stage_id') else " "
            print(f"    {active}{status} {stage['id']}: {stage['done']}/{stage['total']}")
        print()
