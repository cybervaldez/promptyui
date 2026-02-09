#!/usr/bin/env python3
"""
Artifact Manager - Mod Output Storage System

Handles saving and retrieving mod-generated artifacts (text, images, data)
with support for both checkpoint-level and job-level storage.

SECURITY MODEL:
    - tmp/           = System only (execution logs, queue data) - MODS BLOCKED
    - _artifacts/    = Mod-safe zone (all mod outputs go here)

Storage Levels:
    1. JOB-LEVEL (scope='job'):
       jobs/{job}/_artifacts/{mod-id}/
       Use for: Cross-checkpoint data (favorites, stats, global config)

    2. CHECKPOINT-LEVEL (scope='checkpoint', default):
       jobs/{job}/outputs/c99/{prompt}/{checkpoint}/_artifacts/{mod-id}/
       Use for: Per-image artifacts (captions, masks, processed images)

Storage structure:
    jobs/{job}/
    ├── tmp/                              # 🔒 SYSTEM ONLY
    │   ├── execution_*.log
    │   └── generate_list.json
    │
    ├── _artifacts/                       # 🔓 JOB-LEVEL (scope='job')
    │   ├── favorites/
    │   │   └── favorites.txt
    │   └── test-config/
    │       └── logs.json
    │
    └── outputs/c99/prompt/path/
        └── _artifacts/                   # 🔓 CHECKPOINT-LEVEL (default)
            └── caption-generator/
                └── 0001_c0_caption.txt

Usage in mods:
    from src.artifact_manager import ArtifactManager

    # Checkpoint-level (default) - for per-image artifacts
    am = ArtifactManager(context, mod_id='caption-generator')
    am.save('caption.txt', text_content)  # Saves as {stem}_caption.txt

    # Job-level - for cross-checkpoint data
    am = ArtifactManager(context, mod_id='favorites', scope='job')
    am.append('favorites.txt', new_entry)  # Appends to job-level file

    # With alias (for workflows)
    am = ArtifactManager(context, mod_id='segmentation', alias='segment-person')
    am.save('mask.png', image_bytes, binary=True)
"""

from pathlib import Path
from typing import Optional, List, Dict, Any, Union
import json


# Type mapping for artifact filtering
TYPE_EXTENSIONS = {
    'text': ['.txt', '.md', '.log'],
    'data': ['.json', '.yaml', '.yml', '.csv'],
    'image': ['.png', '.jpg', '.jpeg', '.gif', '.webp'],
    'video': ['.mp4', '.webm', '.mov'],
}


def get_file_type(path: Path) -> str:
    """Determine file type from extension."""
    ext = path.suffix.lower()
    for type_name, extensions in TYPE_EXTENSIONS.items():
        if ext in extensions:
            return type_name
    return 'file'


class ArtifactManager:
    """Manages artifact storage for a specific mod execution.

    Storage Scopes:
        - 'checkpoint' (default): Per-checkpoint artifacts in outputs/.../checkpoint/_artifacts/
        - 'job': Job-wide artifacts in job_dir/_artifacts/

    Artifact Folder Priority (highest to lowest):
        1. artifact_path - Explicit custom path (most flexible)
        2. alias         - Dynamic folder name (shared across mods)
        3. mod_id        - Constant folder name (default, never changes)
    """

    def __init__(self, context: Dict[str, Any], mod_id: str = None,
                 alias: str = None, artifact_path: str = None,
                 scope: str = 'checkpoint'):
        """
        Initialize artifact manager for a mod.

        Args:
            context: Execution context with image_path, checkpoint_dir, job_dir, etc.
            mod_id: Mod identifier - constant folder name (uses context['mod_id'] if not provided)
            alias: Dynamic folder name - overrides mod_id, can be shared by multiple mods
            artifact_path: Explicit custom path - highest priority, most flexible
            scope: Storage scope - 'checkpoint' (default) or 'job'
                   - checkpoint: saves to checkpoint/_artifacts/{mod-id}/
                   - job: saves to job_dir/_artifacts/{mod-id}/

        Priority: artifact_path > alias > mod_id

        Examples:
            # Checkpoint-level (default): for per-image artifacts
            am = ArtifactManager(context, mod_id='caption-generator')
            # Result: checkpoint/_artifacts/caption-generator/

            # Job-level: for cross-checkpoint data
            am = ArtifactManager(context, mod_id='favorites', scope='job')
            # Result: job_dir/_artifacts/favorites/

            # With alias: shared folder for multiple mods
            am = ArtifactManager(context, mod_id='caption-en', alias='captions')
            # Result: _artifacts/captions/

            # With custom path: full control
            am = ArtifactManager(context, mod_id='upscaler', artifact_path='upscaled/2x')
            # Result: _artifacts/upscaled/2x/
        """
        self.context = context
        self.mod_id = mod_id or context.get('mod_id', 'unknown-mod')
        self.alias = alias or context.get('alias')  # From mods.yaml
        self.artifact_path = artifact_path or context.get('artifact_path')
        self.scope = scope

        # Determine folder name with priority: artifact_path > alias > mod_id
        if self.artifact_path:
            self.source = self.artifact_path
        elif self.alias:
            self.source = self.alias
        else:
            self.source = self.mod_id

        # Get job directory (for job-level scope)
        job_dir = context.get('job_dir')
        self.job_dir = Path(job_dir) if job_dir else None

        # Get checkpoint directory and image stem (for checkpoint-level scope)
        self.checkpoint_dir = None
        self.image_stem = None
        self.artifacts_dir = None
        self.image_path = None

        # Try to get from context
        image_path = context.get('image_path') or context.get('output_path')
        checkpoint_dir = context.get('checkpoint_dir')

        if image_path:
            self.image_path = Path(image_path)
            self.image_stem = self.image_path.stem
            self.checkpoint_dir = self.image_path.parent
        elif checkpoint_dir:
            self.checkpoint_dir = Path(checkpoint_dir)
            self.image_stem = None  # Bulk mode - no specific image

        # Set artifacts directory based on scope
        if self.scope == 'job' and self.job_dir:
            # Job-level: job_dir/_artifacts/{mod-id}/
            self.artifacts_dir = self.job_dir / '_artifacts' / self.source
        elif self.checkpoint_dir:
            # Checkpoint-level (default): checkpoint/_artifacts/{mod-id}/
            self.artifacts_dir = self.checkpoint_dir / '_artifacts' / self.source
    
    @property
    def is_available(self) -> bool:
        """Check if artifact storage is available."""
        return self.artifacts_dir is not None
    
    def save(self, filename: str, content: Union[str, bytes], 
             binary: bool = False, prefix_stem: bool = True) -> Optional[Path]:
        """
        Save an artifact file.
        
        Args:
            filename: Base name of the file to save
            content: File content (string or bytes)
            binary: If True, write as binary; else write as text
            prefix_stem: If True and image_stem exists, prefix filename with stem
            
        Returns:
            Path to saved file, or None if failed
        """
        if not self.is_available:
            return None
        
        self.artifacts_dir.mkdir(parents=True, exist_ok=True)
        
        # Build final filename
        if prefix_stem and self.image_stem:
            # Split filename to insert stem before extension
            name_parts = filename.rsplit('.', 1)
            if len(name_parts) == 2:
                final_name = f"{self.image_stem}_{name_parts[0]}.{name_parts[1]}"
            else:
                final_name = f"{self.image_stem}_{filename}"
        else:
            final_name = filename
        
        target_path = self.artifacts_dir / final_name
        
        try:
            if binary:
                target_path.write_bytes(content)
            else:
                target_path.write_text(content, encoding='utf-8')
            return target_path
        except Exception as e:
            print(f"ArtifactManager: Failed to save {final_name}: {e}")
            return None
    
    def save_json(self, filename: str, data: Any, prefix_stem: bool = True) -> Optional[Path]:
        """Save data as JSON file."""
        return self.save(filename, json.dumps(data, indent=2), prefix_stem=prefix_stem)
    
    # Track artifacts created during bulk operations
    _bulk_artifacts: List[Dict[str, Any]] = []
    
    def register_artifact(self, name: str, file_type: str = None, metadata: Dict = None) -> None:
        """
        Register an artifact for inclusion in bulk manifest.
        Call this after save() to track what was created.
        
        Args:
            name: Artifact filename (as saved)
            file_type: Override type ('image', 'text', 'data')
            metadata: Additional metadata to include
        """
        if not hasattr(self, '_bulk_artifacts') or self._bulk_artifacts is None:
            self._bulk_artifacts = []
        
        file_path = self.artifacts_dir / name if self.artifacts_dir else None
        
        artifact_info = {
            'name': name,
            'stem': self.image_stem,
            'type': file_type or (get_file_type(file_path) if file_path else 'file'),
        }
        if metadata:
            artifact_info['metadata'] = metadata
        
        self._bulk_artifacts.append(artifact_info)
    
    def generate_manifest(self, 
                         extra_metadata: Dict = None,
                         include_stats: bool = True) -> Dict[str, Any]:
        """
        Generate a complete manifest for bulk operations.
        
        Args:
            extra_metadata: Additional metadata to include
            include_stats: Whether to include file count statistics
            
        Returns:
            Manifest dictionary ready to be saved
        """
        import datetime
        
        # Scan actual files if no artifacts registered
        if not hasattr(self, '_bulk_artifacts') or not self._bulk_artifacts:
            files = self.list_files()
        else:
            files = self._bulk_artifacts
        
        manifest = {
            'mod': self.mod_id,
            'source': self.source,  # alias if set, else mod_id
            'created_at': datetime.datetime.now().isoformat(),
            'artifacts': files,
        }
        
        if self.alias:
            manifest['alias'] = self.alias
        
        if include_stats:
            manifest['stats'] = {
                'total_files': len(files),
                'types': {},
            }
            for f in files:
                t = f.get('type', 'file')
                manifest['stats']['types'][t] = manifest['stats']['types'].get(t, 0) + 1
        
        if extra_metadata:
            manifest['metadata'] = extra_metadata
        
        return manifest
    
    def save_bulk_manifest(self, extra_metadata: Dict = None) -> Optional[Path]:
        """
        Generate and save a manifest.json for bulk operations.
        
        Returns:
            Path to saved manifest, or None if failed
        """
        manifest = self.generate_manifest(extra_metadata=extra_metadata)
        return self.save('manifest.json', json.dumps(manifest, indent=2), prefix_stem=False)
    
    def save_manifest(self, manifest_data: Dict[str, Any]) -> Optional[Path]:
        """Save a custom manifest.json (no stem prefix)."""
        return self.save('manifest.json', json.dumps(manifest_data, indent=2), prefix_stem=False)
    
    def list_files(self, stem_filter: str = None) -> List[Dict[str, Any]]:
        """
        List artifacts for this mod/alias.
        
        Args:
            stem_filter: Optional image stem to filter by
            
        Returns:
            List of dicts with 'name', 'path', 'type', 'size', 'stem', 'mod'
        """
        if not self.is_available or not self.artifacts_dir.exists():
            return []
        
        files = []
        for f in self.artifacts_dir.rglob('*'):
            if f.is_file():
                rel_path = f.relative_to(self.artifacts_dir)
                
                # Extract stem from filename if prefixed
                file_stem = self._extract_stem(f.name)
                
                # Apply stem filter if provided
                if stem_filter and file_stem != stem_filter:
                    continue
                
                files.append({
                    'name': f.name,
                    'path': str(rel_path),
                    'full_path': str(f),
                    'type': get_file_type(f),
                    'size': f.stat().st_size,
                    'stem': file_stem,
                    'mod': self.mod_id,
                    'alias': self.alias,
                })
        return files
    
    def _extract_stem(self, filename: str) -> Optional[str]:
        """Extract image stem from artifact filename (e.g., '0001_c0_caption.txt' -> '0001_c0')."""
        # Pattern: NNNN_cN_... or NNNN_cN_lora_sampler_...
        parts = filename.split('_')
        if len(parts) >= 2 and parts[0].isdigit() and parts[1].startswith('c'):
            return f"{parts[0]}_{parts[1]}"
        return None
    
    def read(self, filename: str, binary: bool = False, use_stem: bool = True) -> Optional[Union[str, bytes]]:
        """Read an artifact file."""
        if not self.is_available:
            return None

        # Build full filename with stem if needed
        if use_stem and self.image_stem:
            name_parts = filename.rsplit('.', 1)
            if len(name_parts) == 2:
                full_name = f"{self.image_stem}_{name_parts[0]}.{name_parts[1]}"
            else:
                full_name = f"{self.image_stem}_{filename}"
        else:
            full_name = filename

        target_path = self.artifacts_dir / full_name
        if not target_path.exists():
            return None

        try:
            if binary:
                return target_path.read_bytes()
            return target_path.read_text(encoding='utf-8')
        except Exception:
            return None

    def append(self, filename: str, content: str, prefix_stem: bool = False) -> Optional[Path]:
        """
        Append content to an artifact file. Creates file if it doesn't exist.

        Useful for log files, favorites lists, or any accumulating data.

        Args:
            filename: Base name of the file
            content: Content to append
            prefix_stem: If True and image_stem exists, prefix filename with stem

        Returns:
            Path to saved file, or None if failed

        Example:
            am = ArtifactManager(context, mod_id='favorites', scope='job')
            am.append('favorites.txt', f"[{timestamp}] {entry}\\n")
        """
        existing = self.read(filename, use_stem=prefix_stem) or ''
        return self.save(filename, existing + content, prefix_stem=prefix_stem)

    def append_json(self, filename: str, entry: Any, prefix_stem: bool = False) -> Optional[Path]:
        """
        Append an entry to a JSON array file. Creates file if it doesn't exist.

        Useful for structured logs where each entry is a dict/object.

        Args:
            filename: Base name of the JSON file
            entry: Object to append to the array
            prefix_stem: If True and image_stem exists, prefix filename with stem

        Returns:
            Path to saved file, or None if failed

        Example:
            am = ArtifactManager(context, mod_id='test-config', scope='job')
            am.append_json('logs.json', {'timestamp': '...', 'event': 'test'})
        """
        existing = self.read(filename, use_stem=prefix_stem) or '[]'
        try:
            data = json.loads(existing)
            if not isinstance(data, list):
                data = [data]
        except json.JSONDecodeError:
            data = []
        data.append(entry)
        return self.save_json(filename, data, prefix_stem=prefix_stem)


def list_checkpoint_artifacts(checkpoint_dir: Path, 
                              type_filter: str = None,
                              mod_filter: str = None,
                              alias_filter: str = None,
                              stem_filter: str = None) -> Dict[str, List[Dict]]:
    """
    List all artifacts in a checkpoint's _artifacts/ folder.
    
    Args:
        checkpoint_dir: Path to checkpoint directory
        type_filter: Optional filter by file type ('image', 'text', 'data')
        mod_filter: Optional filter by mod ID
        alias_filter: Optional filter by alias name
        stem_filter: Optional filter by image stem
        
    Returns:
        Dict of source (mod_id or alias) -> list of artifact files
    """
    artifacts_dir = checkpoint_dir / '_artifacts'
    
    if not artifacts_dir.exists():
        return {}
    
    result = {}
    for source_dir in artifacts_dir.iterdir():
        if source_dir.is_dir():
            source = source_dir.name
            
            # Apply mod/alias filter
            if mod_filter and source != mod_filter:
                continue
            if alias_filter and source != alias_filter:
                continue
            
            am = ArtifactManager({'checkpoint_dir': str(checkpoint_dir)}, mod_id=source)
            files = am.list_files(stem_filter=stem_filter)
            
            # Apply type filter
            if type_filter:
                files = [f for f in files if f['type'] == type_filter]
            
            if files:
                result[source] = files
    
    return result


def query_artifacts(checkpoint_dir: Path, filters: Dict[str, str] = None) -> List[Dict[str, Any]]:
    """
    Query artifacts with flexible filters.
    
    Args:
        checkpoint_dir: Path to checkpoint directory
        filters: Dict with optional keys: 'type', 'mod', 'alias', 'stem'
        
    Returns:
        Flat list of matching artifacts
    """
    filters = filters or {}
    
    artifacts_by_source = list_checkpoint_artifacts(
        checkpoint_dir,
        type_filter=filters.get('type'),
        mod_filter=filters.get('mod'),
        alias_filter=filters.get('alias'),
        stem_filter=filters.get('stem'),
    )
    
    # Flatten to list
    result = []
    for source, files in artifacts_by_source.items():
        for f in files:
            f['source'] = source
            result.append(f)

    return result


def list_job_artifacts(job_dir: Path,
                       type_filter: str = None,
                       mod_filter: str = None) -> Dict[str, List[Dict]]:
    """
    List all job-level artifacts in job_dir/_artifacts/ folder.

    Args:
        job_dir: Path to job directory
        type_filter: Optional filter by file type ('image', 'text', 'data')
        mod_filter: Optional filter by mod ID

    Returns:
        Dict of source (mod_id) -> list of artifact files
    """
    artifacts_dir = job_dir / '_artifacts'

    if not artifacts_dir.exists():
        return {}

    result = {}
    for source_dir in artifacts_dir.iterdir():
        if source_dir.is_dir():
            source = source_dir.name

            # Apply mod filter
            if mod_filter and source != mod_filter:
                continue

            am = ArtifactManager({'job_dir': str(job_dir)}, mod_id=source, scope='job')
            files = am.list_files()

            # Apply type filter
            if type_filter:
                files = [f for f in files if f['type'] == type_filter]

            if files:
                result[source] = files

    return result
