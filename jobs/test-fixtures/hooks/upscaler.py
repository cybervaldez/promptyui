"""
Upscaler hook — demo of cross-block artifact consumption.

Reads upstream_artifacts from dependency blocks, processes them,
and produces new artifacts. This is the reference implementation
for the cross-block artifact flow pattern.

Usage in hooks.yaml:
  generate:
    - script: hooks/upscaler.py
"""


def execute(context, params=None):
    block_path = context.get('block_path', '?')
    comp_idx = context.get('composition_index', 0)

    # Read upstream artifacts from completed dependency blocks
    upstream = context.get('upstream_artifacts', {})
    block_states = context.get('block_states', {})

    # Collect all upstream image artifacts
    source_artifacts = []
    for bp, arts in upstream.items():
        for art in arts:
            source_artifacts.append(art)

    # Produce an upscaled artifact referencing what was consumed
    source_names = [a.get('name', '?') for a in source_artifacts]
    return {
        'status': 'success',
        'data': {
            'output': f'Upscaled {len(source_artifacts)} artifacts from upstream',
            'artifacts': [{
                'name': f'upscaled-{block_path}-{comp_idx}.txt',
                'type': 'text',
                'mod_id': 'upscaler',
                'preview': f'Upscaled: {", ".join(source_names[:4])}',
                'source_count': len(source_artifacts),
                'source_blocks': list(upstream.keys()),
            }]
        }
    }
