/**
 * PromptyUI - Quill Wildcard Integration
 *
 * Custom WildcardBlot for inline wildcard chips in Quill editor.
 * Manages Quill instance lifecycle and plain-text serialization.
 * Includes inline autocomplete dropdown for wildcard discovery.
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
            nameSpan.textContent = value.name;
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
                node.setAttribute('data-testid', 'pu-wc-chip-undefined');
            } else {
                node.setAttribute('data-testid', 'pu-wc-chip-defined');
            }

            // Click: position cursor at chip → triggers selection-change → passive popover
            node.style.cursor = 'pointer';
            node.setAttribute('title', value.undefined ? 'Click to add values' : 'Click to edit values');
            node.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                const editorEl = node.closest('.ql-editor');
                if (!editorEl) return;
                const containerEl = editorEl.closest('.pu-focus-quill');
                if (!containerEl) return;
                const path = containerEl.dataset.path;

                if (PU.state.focusMode.active && PU.state.focusMode.quillInstance) {
                    // Already in focus mode — position cursor in focus quill
                    PU.quill.positionCursorAtWildcard(PU.state.focusMode.quillInstance, value.name);
                } else {
                    // Enter focus mode, then position cursor at chip
                    PU.focus.enter(path);
                    requestAnimationFrame(() => {
                        if (PU.state.focusMode.quillInstance) {
                            PU.quill.positionCursorAtWildcard(PU.state.focusMode.quillInstance, value.name);
                        }
                    });
                }
            });

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
        _updatingFromQuill: null,

        // Autocomplete state
        _autocompleteOpen: false,
        _autocompleteEl: null,
        _autocompleteQuill: null,
        _autocompletePath: null,
        _autocompleteTriggerIndex: null,
        _autocompleteSelectedIdx: 0,
        _autocompleteQuery: '',
        _autocompleteItems: [],

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
        },

        // ============================================
        // Autocomplete Methods
        // ============================================

        /**
         * Show autocomplete dropdown for a partial wildcard
         */
        showAutocomplete(quill, path, triggerIndex, query) {
            const wasOpen = PU.quill._autocompleteOpen;
            PU.quill._autocompleteOpen = true;
            PU.quill._autocompleteQuill = quill;
            PU.quill._autocompletePath = path;
            PU.quill._autocompleteTriggerIndex = triggerIndex;
            PU.quill._autocompleteQuery = query;
            // Only reset selection when first opening, not on re-renders from text-change
            if (!wasOpen) {
                PU.quill._autocompleteSelectedIdx = 0;
            }

            // Create dropdown element if not exists
            if (!PU.quill._autocompleteEl) {
                PU.quill._autocompleteEl = document.createElement('div');
                PU.quill._autocompleteEl.className = 'pu-autocomplete-menu';
                PU.quill._autocompleteEl.setAttribute('data-testid', 'pu-autocomplete-menu');
                document.body.appendChild(PU.quill._autocompleteEl);
            }

            PU.quill._autocompleteEl.style.display = 'block';
            PU.quill.renderAutocompleteItems(query);
            PU.quill.positionAutocomplete(quill, triggerIndex);
        },

        /**
         * Render autocomplete items into the dropdown
         */
        renderAutocompleteItems(query) {
            const el = PU.quill._autocompleteEl;
            if (!el) return;

            const items = PU.helpers.getAutocompleteItems();
            const q = (query || '').toLowerCase();

            // Filter by query
            const filtered = q
                ? items.filter(item => item.name.toLowerCase().includes(q))
                : items;

            // Separate into sections
            const localItems = filtered.filter(i => i.source === 'local');
            const extItems = filtered.filter(i => i.source !== 'local');

            // Build all visible items for index tracking
            const allItems = [...localItems, ...extItems];
            PU.quill._autocompleteItems = allItems;

            // Clamp selected index to valid range when filtered list shrinks
            const hasNewOption = q && !allItems.some(item => item.name.toLowerCase() === q);
            const totalSelectable = allItems.length + (hasNewOption ? 1 : 0);
            if (totalSelectable > 0 && PU.quill._autocompleteSelectedIdx >= totalSelectable) {
                PU.quill._autocompleteSelectedIdx = totalSelectable - 1;
            }

            let html = '';

            if (allItems.length === 0 && !q) {
                html = '<div class="pu-autocomplete-empty">No wildcards found</div>';
            } else {
                // Local section
                if (localItems.length > 0) {
                    html += '<div class="pu-autocomplete-section">This Prompt</div>';
                    localItems.forEach((item, i) => {
                        const idx = i;
                        const selected = idx === PU.quill._autocompleteSelectedIdx ? ' selected' : '';
                        html += `<div class="pu-autocomplete-item${selected}" data-testid="pu-autocomplete-item" data-idx="${idx}" data-name="${PU.quill._escHtml(item.name)}">`;
                        html += `<span class="pu-autocomplete-item-name">__${PU.quill._escHtml(item.name)}__</span>`;
                        if (item.preview) {
                            html += `<span class="pu-autocomplete-item-preview">${PU.quill._escHtml(item.preview)}</span>`;
                        }
                        html += '</div>';
                    });
                }

                // Extension section
                if (extItems.length > 0) {
                    html += '<div class="pu-autocomplete-section">Extensions</div>';
                    extItems.forEach((item, i) => {
                        const idx = localItems.length + i;
                        const selected = idx === PU.quill._autocompleteSelectedIdx ? ' selected' : '';
                        const sourceName = item.source.split('/').pop();
                        html += `<div class="pu-autocomplete-item${selected}" data-testid="pu-autocomplete-item" data-idx="${idx}" data-name="${PU.quill._escHtml(item.name)}">`;
                        html += `<span class="pu-autocomplete-item-name">__${PU.quill._escHtml(item.name)}__</span>`;
                        html += `<span class="pu-autocomplete-item-source">${PU.quill._escHtml(sourceName)}</span>`;
                        html += '</div>';
                    });
                }
            }

            // "+ New wildcard" option when query has content and no exact match
            if (hasNewOption) {
                const newIdx = allItems.length;
                const selected = newIdx === PU.quill._autocompleteSelectedIdx ? ' selected' : '';
                html += `<div class="pu-autocomplete-new${selected}" data-testid="pu-autocomplete-new" data-idx="${newIdx}" data-name="${PU.quill._escHtml(query)}">`;
                html += `+ New wildcard: <span class="pu-autocomplete-new-name">__${PU.quill._escHtml(query)}__</span>`;
                html += '</div>';
            }

            el.innerHTML = html;

            // Click delegation
            el.onclick = (e) => {
                const itemEl = e.target.closest('[data-name]');
                if (itemEl) {
                    const name = itemEl.dataset.name;
                    PU.quill.selectAutocompleteItem(name);
                }
            };
        },

        /**
         * Refresh autocomplete after async data loads
         */
        refreshAutocomplete() {
            if (PU.quill._autocompleteOpen) {
                PU.quill.renderAutocompleteItems(PU.quill._autocompleteQuery);
            }
        },

        /**
         * Position autocomplete dropdown relative to cursor
         */
        positionAutocomplete(quill, triggerIndex) {
            const el = PU.quill._autocompleteEl;
            if (!el) return;

            let rect;
            const nativeSel = window.getSelection();
            if (nativeSel && nativeSel.rangeCount > 0) {
                const range = nativeSel.getRangeAt(0);
                rect = range.getBoundingClientRect();
            }

            if (!rect || (rect.x === 0 && rect.y === 0)) {
                // Fallback: use the editor container position
                const editorEl = quill.root.closest('.pu-focus-quill');
                if (editorEl) {
                    rect = editorEl.getBoundingClientRect();
                }
            }

            if (!rect) return;

            // Force layout reflow so offsetHeight/Width are accurate
            // (element was just set to display:block and populated)
            el.getBoundingClientRect();
            const menuHeight = el.offsetHeight;
            const menuWidth = el.offsetWidth;

            let top = rect.bottom + 4;
            let left = rect.left;

            // Flip above if near bottom
            if (top + menuHeight > window.innerHeight - 10) {
                top = rect.top - menuHeight - 4;
            }

            // Clamp right edge
            if (left + menuWidth > window.innerWidth - 10) {
                left = window.innerWidth - menuWidth - 10;
            }

            // Clamp left edge
            if (left < 10) left = 10;

            el.style.left = left + 'px';
            el.style.top = top + 'px';
        },

        /**
         * Select an autocomplete item and insert as chip
         */
        selectAutocompleteItem(name) {
            const quill = PU.quill._autocompleteQuill;
            const path = PU.quill._autocompletePath;
            const triggerIndex = PU.quill._autocompleteTriggerIndex;

            if (!quill || triggerIndex == null) return;

            // Calculate length of text to delete: from triggerIndex to current cursor
            const sel = quill.getSelection();
            const cursorPos = sel ? sel.index : triggerIndex + 2 + PU.quill._autocompleteQuery.length;
            const deleteLength = cursorPos - triggerIndex;

            // Delete __partial text
            quill.deleteText(triggerIndex, deleteLength, Quill.sources.SILENT);

            // Insert wildcard chip
            const wildcardLookup = PU.helpers.getWildcardLookup();
            const values = wildcardLookup[name] || [];
            const preview = values.length > 0
                ? values.slice(0, 3).join(', ') + (values.length > 3 ? ` +${values.length - 3}` : '')
                : '';

            quill.insertEmbed(triggerIndex, 'wildcard', {
                name: name,
                preview: preview,
                undefined: values.length === 0
            }, Quill.sources.SILENT);

            // Set cursor after chip
            quill.setSelection(triggerIndex + 1, 0, Quill.sources.SILENT);

            // Update block content state
            PU.quill._updatingFromQuill = path;
            const plainText = PU.quill.serialize(quill);
            PU.actions.updateBlockContent(path, plainText);
            PU.quill._updatingFromQuill = null;

            // Close autocomplete
            PU.quill.closeAutocomplete();

            // Re-focus editor
            quill.focus();

            // Auto-open popover for new (undefined) wildcards so user can add values
            if (values.length === 0) {
                requestAnimationFrame(() => {
                    const chipEl = quill.root.querySelector(
                        `.ql-wildcard-chip[data-wildcard-name="${name}"]`
                    );
                    if (chipEl && PU.wildcardPopover) {
                        PU.wildcardPopover.open(
                            chipEl, name, quill,
                            path, PU.state.focusMode.active
                        );
                    }
                });
            }
        },

        /**
         * Close autocomplete dropdown
         */
        closeAutocomplete() {
            PU.quill._autocompleteOpen = false;
            if (PU.quill._autocompleteEl) {
                PU.quill._autocompleteEl.style.display = 'none';
            }
            PU.quill._autocompleteQuill = null;
            PU.quill._autocompletePath = null;
            PU.quill._autocompleteTriggerIndex = null;
            PU.quill._autocompleteSelectedIdx = 0;
            PU.quill._autocompleteQuery = '';
            PU.quill._autocompleteItems = [];
        },

        /**
         * Handle keyboard events for autocomplete navigation
         * Returns true if the key was consumed
         */
        handleAutocompleteKey(e) {
            if (!PU.quill._autocompleteOpen) return false;

            const el = PU.quill._autocompleteEl;
            if (!el) return false;

            // Count total selectable items (including "+ New wildcard")
            const selectableItems = el.querySelectorAll('[data-name]');
            const totalItems = selectableItems.length;
            if (totalItems === 0 && e.key !== 'Escape') return false;

            if (e.key === 'ArrowDown') {
                e.preventDefault();
                e.stopPropagation();
                PU.quill._autocompleteSelectedIdx = Math.min(PU.quill._autocompleteSelectedIdx + 1, totalItems - 1);
                PU.quill.renderAutocompleteItems(PU.quill._autocompleteQuery);
                // Scroll selected into view
                const selectedEl = el.querySelector('.selected');
                if (selectedEl) selectedEl.scrollIntoView({ block: 'nearest' });
                return true;
            }

            if (e.key === 'ArrowUp') {
                e.preventDefault();
                e.stopPropagation();
                PU.quill._autocompleteSelectedIdx = Math.max(PU.quill._autocompleteSelectedIdx - 1, 0);
                PU.quill.renderAutocompleteItems(PU.quill._autocompleteQuery);
                const selectedEl = el.querySelector('.selected');
                if (selectedEl) selectedEl.scrollIntoView({ block: 'nearest' });
                return true;
            }

            if (e.key === 'Enter' || e.key === 'Tab') {
                e.preventDefault();
                e.stopPropagation();
                const selectedEl = el.querySelector('.selected[data-name]');
                if (selectedEl) {
                    PU.quill.selectAutocompleteItem(selectedEl.dataset.name);
                }
                return true;
            }

            if (e.key === 'Escape') {
                e.preventDefault();
                e.stopPropagation();
                PU.quill.closeAutocomplete();
                return true;
            }

            return false;
        },

        /**
         * Get the wildcard name adjacent to the cursor position.
         * Checks the leaf at the cursor index and the one before it.
         * Returns the wildcard name string or null.
         */
        getAdjacentWildcardName(quill) {
            const sel = quill.getSelection();
            if (!sel) return null;

            // Check leaf at cursor position
            try {
                const [leafAt] = quill.getLeaf(sel.index);
                if (leafAt && leafAt.domNode && leafAt.domNode.getAttribute &&
                    leafAt.domNode.getAttribute('data-wildcard-name')) {
                    return leafAt.domNode.getAttribute('data-wildcard-name');
                }
            } catch (e) { /* ignore */ }

            // Check leaf before cursor
            if (sel.index > 0) {
                try {
                    const [leafBefore] = quill.getLeaf(sel.index - 1);
                    if (leafBefore && leafBefore.domNode && leafBefore.domNode.getAttribute &&
                        leafBefore.domNode.getAttribute('data-wildcard-name')) {
                        return leafBefore.domNode.getAttribute('data-wildcard-name');
                    }
                } catch (e) { /* ignore */ }
            }

            // Check leaf after cursor (cursor is positioned before a chip)
            try {
                const [leafAfter] = quill.getLeaf(sel.index + 1);
                if (leafAfter && leafAfter.domNode && leafAfter.domNode.getAttribute &&
                    leafAfter.domNode.getAttribute('data-wildcard-name')) {
                    return leafAfter.domNode.getAttribute('data-wildcard-name');
                }
            } catch (e) { /* ignore */ }

            return null;
        },

        /**
         * Get the wildcard chip DOM element adjacent to the cursor.
         * Checks offsets 0, -1, +1 from the selection index.
         */
        getAdjacentWildcardChipEl(quill) {
            const sel = quill.getSelection();
            if (!sel) return null;
            for (const offset of [0, -1, 1]) {
                const idx = sel.index + offset;
                if (idx < 0) continue;
                try {
                    const [leaf] = quill.getLeaf(idx);
                    if (leaf?.domNode?.classList?.contains('ql-wildcard-chip')) {
                        return leaf.domNode;
                    }
                } catch (e) { /* ignore */ }
            }
            return null;
        },

        /**
         * Position cursor adjacent to the first chip matching wcName.
         * Triggers selection-change which opens the passive popover.
         */
        positionCursorAtWildcard(quill, wcName) {
            const chip = quill.root.querySelector(
                `.ql-wildcard-chip[data-wildcard-name="${wcName}"]`
            );
            if (!chip) return;
            try {
                const blot = Quill.find(chip);
                if (blot) {
                    const index = quill.getIndex(blot);
                    quill.setSelection(index + 1, 0, Quill.sources.USER);
                }
            } catch (e) { /* ignore */ }
        },

        /**
         * Handle colon shortcut: __name: → create chip and open popover.
         * Returns true if handled.
         */
        handleColonShortcut(quillInstance, path, sel, textBefore) {
            const colonMatch = textBefore.match(/__([a-zA-Z0-9_-]+):$/);
            if (!colonMatch) return false;

            const wcName = colonMatch[1];
            const triggerIdx = sel.index - colonMatch[0].length;

            // Close autocomplete if open
            if (PU.quill._autocompleteOpen) PU.quill.closeAutocomplete();

            // Delete __name: text and insert chip
            quillInstance.deleteText(triggerIdx, colonMatch[0].length, Quill.sources.SILENT);
            const wildcardLookup = PU.helpers.getWildcardLookup();
            const values = wildcardLookup[wcName] || [];
            const preview = values.length > 0
                ? values.slice(0, 3).join(', ') + (values.length > 3 ? ` +${values.length - 3}` : '')
                : '';
            quillInstance.insertEmbed(triggerIdx, 'wildcard', {
                name: wcName, preview, undefined: values.length === 0
            }, Quill.sources.SILENT);
            quillInstance.setSelection(triggerIdx + 1, 0, Quill.sources.SILENT);

            // Open popover on the chip
            requestAnimationFrame(() => {
                const chipEl = quillInstance.root.querySelector(
                    `.ql-wildcard-chip[data-wildcard-name="${wcName}"]`
                );
                if (chipEl && PU.wildcardPopover) {
                    PU.wildcardPopover.open(
                        chipEl, wcName, quillInstance,
                        path, PU.state.focusMode.active
                    );
                }
            });
            return true;
        },

        /**
         * HTML-escape helper
         */
        _escHtml(str) {
            const div = document.createElement('div');
            div.textContent = str;
            return div.innerHTML;
        }
    };

} else {
    // Quill CDN failed to load - provide stub namespace
    PU.quill = {
        _updatingFromQuill: null,
        _autocompleteOpen: false,
        serialize() { return ''; },
        parseContentToOps() { return []; },
        convertWildcardsInline() {},
        closeAutocomplete() {},
        handleAutocompleteKey() { return false; },
        refreshAutocomplete() {},
        _fallback: true
    };
    console.warn('Quill CDN not loaded - falling back to plain textarea mode');
}
