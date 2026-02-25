"""Log hook stage for test verification."""


def execute(context, params=None):
    hook = context.get('hook', 'unknown')
    path = context.get('block_path', '?')
    idx = context.get('composition_index', '?')
    print(f"[HOOK] {hook} block={path} comp={idx}")
    return {'status': 'success', 'data': {'hook': hook, 'block_path': path}}
