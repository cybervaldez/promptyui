"""Generate hook that produces text artifacts with full content.

Demonstrates the complete value chain:
  wildcards + annotations → hook context → generated text → artifact with content → JSONL on disk

Unlike echo_generate (which returns a short preview), text_writer returns
a `content` field with the full generated text. The JSONL consolidation
writes `content` to disk (falling back to `preview` if absent).

Hook context used:
  resolved_text    — the prompt text with wildcards substituted
  annotations      — user intent (e.g., tone, format, audience)
  block_path       — block position in the tree
  composition_index — which composition within the block
"""


def execute(context, params=None):
    block_path = context.get('block_path', '?')
    comp_idx = context.get('composition_index', 0)
    resolved_text = context.get('resolved_text', '')
    annotations = context.get('annotations', {}) or {}

    # Build the "generated" content from context
    tone = annotations.get('tone', 'professional')
    audience = annotations.get('audience', 'general')
    subject = resolved_text.strip()

    content = (
        f"Subject: {subject}\n"
        f"Tone: {tone}\n"
        f"Audience: {audience}\n"
        f"\n"
        f"Dear {audience},\n"
        f"\n"
        f"{subject}\n"
        f"\n"
        f"This is a {tone} message generated for composition {comp_idx} "
        f"of block {block_path}.\n"
        f"\n"
        f"Best regards,\n"
        f"Text Writer Hook"
    )

    return {
        'status': 'success',
        'data': {
            'output': content,
            'artifacts': [{
                'name': f'email-{block_path}-{comp_idx}.txt',
                'type': 'text',
                'mod_id': 'text_writer',
                'preview': subject[:80],
                'content': content,
            }]
        }
    }
