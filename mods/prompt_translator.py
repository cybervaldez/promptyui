#!/usr/bin/env python3
"""
Prompt Translator Mod - Stage: [build, pre]

Pre-computes translations at build time, applies them at generation time.
Demonstrates the build+pre pattern for expensive computations.

Use Cases:
- Language translation
- Prompt variations
- Template substitution
"""

from pathlib import Path


# Simple mock translations (replace with actual API in production)
MOCK_TRANSLATIONS = {
    'ja': {
        'beautiful': '美しい',
        'woman': '女性',
        'fashion': 'ファッション',
        'portrait': 'ポートレート',
        'elegant': 'エレガント'
    },
    'es': {
        'beautiful': 'hermosa',
        'woman': 'mujer',
        'fashion': 'moda',
        'portrait': 'retrato',
        'elegant': 'elegante'
    }
}


def simple_translate(text: str, target_lang: str) -> str:
    """Simple word-by-word translation for demo purposes."""
    if target_lang not in MOCK_TRANSLATIONS:
        return text
    
    translations = MOCK_TRANSLATIONS[target_lang]
    result = text.lower()
    for en_word, translated in translations.items():
        result = result.replace(en_word, translated)
    return result


def execute(context):
    """
    BUILD: Pre-compute translations for all checkpoints.
    PRE: Apply translation based on UI selection.
    """
    hook = context.get('hook', '')
    
    if hook == 'mods_build':
        # BUILD STAGE: Pre-compute all translations
        prompt_data = context.get('prompt_data', {})
        prompt_id = context.get('prompt_id', 'unknown')
        
        translations = {}
        checkpoints = prompt_data.get('checkpoints', [])
        
        for checkpoint in checkpoints:
            path_string = checkpoint.get('path_string', '')
            raw_text = checkpoint.get('raw_text', '')
            
            if raw_text:
                translations[path_string] = {
                    'original': raw_text,
                    'ja': simple_translate(raw_text, 'ja'),
                    'es': simple_translate(raw_text, 'es')
                }
        
        # Store in prompt metadata
        if 'mods' not in prompt_data:
            prompt_data['mods'] = {}
        
        prompt_data['mods']['translator'] = {
            'translations': translations,
            'available_languages': ['en', 'ja', 'es']
        }
        
        return {
            'status': 'success',
            'modify_context': {'prompt_data': prompt_data},
            'data': {'translated_paths': len(translations)}
        }
    
    elif hook == 'pre':
        # PRE STAGE: Apply translation before generation
        ui_params = context.get('ui_params', {})
        target_lang = ui_params.get('language', 'en')
        
        if target_lang == 'en':
            # No translation needed for English
            return {'status': 'success', 'data': {'language': 'en', 'action': 'no_change'}}
        
        path = context.get('path', '')
        
        # Get pre-computed translations from context
        # (Would be loaded from prompt.json in real usage)
        translations = context.get('translations', {})
        
        if path in translations and target_lang in translations[path]:
            translated_prompt = translations[path][target_lang]
            context['resolved_prompt'] = translated_prompt
            
            return {
                'status': 'success',
                'modify_context': {'resolved_prompt': translated_prompt},
                'data': {'language': target_lang, 'action': 'translated'}
            }
        
        return {'status': 'success', 'data': {'language': target_lang, 'action': 'not_found'}}
    
    return {'status': 'skip', 'reason': f'Unknown hook: {hook}'}
