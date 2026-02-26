"""Generate hook that echoes resolved text and produces a test artifact.

When upstream_artifacts are present (cross-block dependency), includes
upstream info in the artifact for verification in E2E tests.
"""


def execute(context, params=None):
    block_path = context.get('block_path', '?')
    comp_idx = context.get('composition_index', 0)
    upstream = context.get('upstream_artifacts', {})

    # Support conditional failure for testing failure cascade
    annotations = context.get('annotations', {}) or {}
    if annotations.get('_force_fail'):
        return {
            'status': 'error',
            'error': {
                'code': 'FORCE_FAIL',
                'message': f'Forced failure on block {block_path} (composition {comp_idx})',
            }
        }

    artifact = {
        'name': f'output-{block_path}-{comp_idx}.txt',
        'type': 'text',
        'mod_id': 'echo_generate',
        'preview': context.get('resolved_text', '')[:80],
    }

    # When upstream artifacts exist, include cross-block metadata
    if upstream:
        source_count = sum(len(arts) for arts in upstream.values())
        artifact['upstream_source_count'] = source_count
        artifact['upstream_blocks'] = sorted(upstream.keys())

    return {
        'status': 'success',
        'data': {
            'output': context.get('resolved_text', ''),
            'artifacts': [artifact]
        }
    }
