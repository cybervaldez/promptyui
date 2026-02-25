"""Echo resolved text as the 'generated' output."""


def execute(context, params=None):
    text = context.get('resolved_text', '')
    return {'status': 'success', 'data': {'output': text[:100]}}
