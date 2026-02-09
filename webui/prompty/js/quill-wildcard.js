/**
 * PromptyUI - Quill Wildcard Integration
 *
 * Custom WildcardBlot for inline wildcard chips in Quill editor.
 * Manages Quill instance lifecycle and plain-text serialization.
 */

// CDN fallback guard - skip if Quill not loaded
if (typeof Quill !== 'undefined') {

    // ============================================
    // WildcardBlot - Custom Embed Blot
    // ============================================
    const Embed = Quill.import('blots/embed');

    class WildcardBlot extends Embed {
        static blotName = 'wildcard';
        static tagName = 'span';
        static className = 'ql-wildcard-chip';

        static create(value) {
            const node = super.create();
            node.setAttribute('data-wildcard-name', value.name || '');
            node.setAttribute('contenteditable', 'false');

            const nameSpan = document.createElement('span');
            nameSpan.className = 'ql-wc-name';
            nameSpan.textContent = `__${value.name}__`;
            node.appendChild(nameSpan);

            if (value.preview) {
                const previewSpan = document.createElement('span');
                previewSpan.className = 'ql-wc-preview';
                previewSpan.textContent = value.preview;
                node.appendChild(previewSpan);
            }

            // Mark undefined wildcards
            if (value.undefined) {
                node.classList.add('ql-wc-undefined');
            }

            return node;
        }

        static value(node) {
            return {
                name: node.getAttribute('data-wildcard-name') || '',
                preview: node.querySelector('.ql-wc-preview')?.textContent || '',
                undefined: node.classList.contains('ql-wc-undefined')
            };
        }
    }

    Quill.register(WildcardBlot);

    // ============================================
    // PU.quill Namespace
    // ============================================
    PU.quill = {
        instances: {},
        _updatingFromQuill: null,

        /**
         * Create a Quill instance for a content block
         */
        create(containerEl, path, initialContent) {
            // Destroy existing instance for this path
            PU.quill.destroy(path);

            const quill = new Quill(containerEl, {
                theme: 'snow',
                modules: {
                    toolbar: false
                },
                placeholder: 'Enter content... Use __name__ for template wildcards (replaced at build time)'
            });

            // Parse initial content into Delta with wildcard embeds
            const wildcardLookup = PU.helpers.getWildcardLookup();
            const ops = PU.quill.parseContentToOps(initialContent || '', wildcardLookup);
            quill.setContents({ ops: ops }, Quill.sources.SILENT);

            // Attach text-change listener
            quill.on('text-change', (delta, oldDelta, source) => {
                if (source === Quill.sources.SILENT) return;
                PU.quill.handleTextChange(path, quill);
            });

            // Attach focus handlers
            quill.root.addEventListener('focus', () => {
                PU.actions.selectBlock(path);
                PU.actions.showPreviewForBlock(path);
            });

            quill.root.addEventListener('blur', () => {
                PU.actions.onBlockBlur(path);
            });

            PU.quill.instances[path] = quill;
            return quill;
        },

        /**
         * Destroy a Quill instance by path
         */
        destroy(path) {
            const instance = PU.quill.instances[path];
            if (instance) {
                instance.disable();
                delete PU.quill.instances[path];
            }
        },

        /**
         * Destroy all Quill instances
         */
        destroyAll() {
            for (const path of Object.keys(PU.quill.instances)) {
                PU.quill.destroy(path);
            }
        },

        /**
         * Initialize all Quill editors from rendered containers
         */
        initAll() {
            const containers = document.querySelectorAll('.pu-content-quill');
            containers.forEach(container => {
                const path = container.dataset.path;
                const initialContent = container.dataset.initial || '';
                if (path) {
                    PU.quill.create(container, path, initialContent);
                }
            });
        },

        /**
         * Serialize a Quill instance back to plain text
         */
        serialize(quillInstance) {
            const delta = quillInstance.getContents();
            let text = '';

            for (const op of delta.ops) {
                if (typeof op.insert === 'string') {
                    text += op.insert;
                } else if (op.insert && op.insert.wildcard) {
                    text += `__${op.insert.wildcard.name}__`;
                }
            }

            // Remove trailing newline that Quill always adds
            if (text.endsWith('\n')) {
                text = text.slice(0, -1);
            }

            return text;
        },

        /**
         * Parse plain text content into Quill Delta ops
         * Converts __name__ patterns to wildcard embed ops
         */
        parseContentToOps(plainText, wildcardLookup) {
            const ops = [];
            const regex = /__([a-zA-Z0-9_-]+)__/g;
            let lastIndex = 0;
            let match;

            while ((match = regex.exec(plainText)) !== null) {
                // Add text before the wildcard
                if (match.index > lastIndex) {
                    ops.push({ insert: plainText.slice(lastIndex, match.index) });
                }

                // Add wildcard embed
                const name = match[1];
                const values = wildcardLookup[name] || [];
                const preview = values.length > 0
                    ? values.slice(0, 3).join(', ') + (values.length > 3 ? ` +${values.length - 3}` : '')
                    : '';

                ops.push({
                    insert: {
                        wildcard: {
                            name: name,
                            preview: preview,
                            undefined: values.length === 0
                        }
                    }
                });

                lastIndex = match.index + match[0].length;
            }

            // Add remaining text
            if (lastIndex < plainText.length) {
                ops.push({ insert: plainText.slice(lastIndex) });
            }

            // Quill requires a trailing newline
            ops.push({ insert: '\n' });

            return ops;
        },

        /**
         * Handle text-change events from Quill
         * Serializes to plain text and updates state
         */
        handleTextChange(path, quillInstance) {
            // Set re-entrancy guard
            PU.quill._updatingFromQuill = path;

            const plainText = PU.quill.serialize(quillInstance);
            PU.actions.updateBlockContent(path, plainText);

            // Convert any newly typed wildcards to inline chips
            PU.quill.convertWildcardsInline(quillInstance);

            PU.quill._updatingFromQuill = null;
        },

        /**
         * Scan Quill content for unblotted __name__ patterns and convert to embeds
         */
        convertWildcardsInline(quillInstance) {
            const text = quillInstance.getText();
            const regex = /__([a-zA-Z0-9_-]+)__/g;
            let match;
            const replacements = [];

            while ((match = regex.exec(text)) !== null) {
                replacements.push({
                    index: match.index,
                    length: match[0].length,
                    name: match[1]
                });
            }

            if (replacements.length === 0) return;

            // Get current selection before modifications
            const selection = quillInstance.getSelection();

            // Process replacements in reverse order to preserve indices
            const wildcardLookup = PU.helpers.getWildcardLookup();

            for (let i = replacements.length - 1; i >= 0; i--) {
                const r = replacements[i];
                const values = wildcardLookup[r.name] || [];
                const preview = values.length > 0
                    ? values.slice(0, 3).join(', ') + (values.length > 3 ? ` +${values.length - 3}` : '')
                    : '';

                quillInstance.deleteText(r.index, r.length, Quill.sources.SILENT);
                quillInstance.insertEmbed(r.index, 'wildcard', {
                    name: r.name,
                    preview: preview,
                    undefined: values.length === 0
                }, Quill.sources.SILENT);
            }

            // Fix cursor position - place after last replacement
            if (selection && replacements.length > 0) {
                const firstReplacement = replacements[0];
                // Each replacement replaces N chars with 1 embed
                // Calculate new cursor position
                let newIndex = selection.index;
                for (const r of replacements) {
                    if (r.index + r.length <= selection.index) {
                        // This replacement was before cursor, adjust
                        newIndex -= (r.length - 1);
                    }
                }
                quillInstance.setSelection(newIndex, 0, Quill.sources.SILENT);
            }
        }
    };

} else {
    // Quill CDN failed to load - provide stub namespace
    PU.quill = {
        instances: {},
        _updatingFromQuill: null,
        create() {},
        destroy() {},
        destroyAll() {},
        initAll() {},
        serialize() { return ''; },
        parseContentToOps() { return []; },
        handleTextChange() {},
        convertWildcardsInline() {},
        _fallback: true
    };
    console.warn('Quill CDN not loaded - falling back to plain textarea mode');
}
