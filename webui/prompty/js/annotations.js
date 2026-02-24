/**
 * PromptyUI - Annotations
 *
 * Inline annotation editor for block metadata.
 * Provides key-value CRUD, badge updates, and an annotation event system.
 */

PU.annotations = {
    // Track which editors are open (Set of paths)
    _openEditors: new Set(),

    // Registered annotation event handlers: name -> { event, handler }
    _hooks: {},

    // =========================================================================
    // EDITOR TOGGLE
    // =========================================================================

    toggleEditor(path) {
        if (PU.annotations._openEditors.has(path)) {
            PU.annotations.closeEditor(path);
        } else {
            PU.annotations.openEditor(path);
        }
    },

    openEditor(path) {
        const pathId = path.replace(/\./g, '-');
        const blockEl = document.querySelector(`[data-testid="pu-block-${pathId}"]`);
        if (!blockEl) return;

        const body = blockEl.querySelector(':scope > .pu-block-body');
        if (!body) return;

        // Don't double-insert
        if (body.querySelector('.pu-annotation-editor')) return;

        PU.annotations._openEditors.add(path);

        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        const annotations = block.annotations || {};
        const editorHtml = PU.annotations._buildEditorHtml(path, pathId, annotations);

        const editorDiv = document.createElement('div');
        editorDiv.className = 'pu-annotation-editor';
        editorDiv.dataset.testid = `pu-ann-editor-${pathId}`;
        editorDiv.innerHTML = editorHtml;
        body.appendChild(editorDiv);

        // Trigger open animation
        requestAnimationFrame(() => {
            editorDiv.classList.add('open');
        });

        PU.annotations.fire('render', { block, path, annotations, containerEl: editorDiv });
    },

    closeEditor(path) {
        const pathId = path.replace(/\./g, '-');
        const editorEl = document.querySelector(`[data-testid="pu-ann-editor-${pathId}"]`);
        if (editorEl) {
            editorEl.classList.remove('open');
            editorEl.addEventListener('transitionend', () => editorEl.remove(), { once: true });
            // Fallback removal if transition doesn't fire
            setTimeout(() => { if (editorEl.parentNode) editorEl.remove(); }, 350);
        }
        PU.annotations._openEditors.delete(path);
    },

    // =========================================================================
    // EDITOR HTML
    // =========================================================================

    _buildEditorHtml(path, pathId, annotations) {
        const entries = Object.entries(annotations);
        let rowsHtml = '';

        entries.forEach(([key, value], idx) => {
            rowsHtml += PU.annotations._buildRowHtml(path, pathId, idx, key, String(value));
        });

        return `
            <div class="pu-annotation-header">
                <span class="pu-annotation-title">Annotations</span>
                <button class="pu-annotation-close" data-testid="pu-ann-close-${pathId}"
                        onclick="event.stopPropagation(); PU.annotations.closeEditor('${path}')">&times;</button>
            </div>
            <div class="pu-annotation-rows" data-testid="pu-ann-rows-${pathId}">
                ${rowsHtml}
            </div>
            <button class="pu-annotation-add" data-testid="pu-ann-add-${pathId}"
                    onclick="event.stopPropagation(); PU.annotations._addRow('${path}', '${pathId}')">+ Add annotation</button>
        `;
    },

    _buildRowHtml(path, pathId, idx, key, value) {
        const eKey = PU.blocks.escapeAttr(key);
        const eValue = PU.blocks.escapeAttr(value);
        return `
            <div class="pu-annotation-row" data-testid="pu-ann-row-${pathId}-${idx}">
                <input type="text" class="pu-ann-key" value="${eKey}" placeholder="key"
                       data-testid="pu-ann-key-${pathId}-${idx}"
                       onchange="PU.annotations._handleKeyChange('${path}', ${idx}, this)"
                       onclick="event.stopPropagation()">
                <input type="text" class="pu-ann-value" value="${eValue}" placeholder="value"
                       data-testid="pu-ann-value-${pathId}-${idx}"
                       onchange="PU.annotations._handleValueChange('${path}', ${idx}, this)"
                       onclick="event.stopPropagation()">
                <button class="pu-ann-remove" data-testid="pu-ann-remove-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._removeRow('${path}', '${PU.blocks.escapeAttr(key)}')"
                        title="Remove annotation">&times;</button>
            </div>
        `;
    },

    // =========================================================================
    // ROW HANDLERS
    // =========================================================================

    _handleKeyChange(path, rowIdx, inputEl) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        const oldAnnotations = block.annotations || {};
        const entries = Object.entries(oldAnnotations);

        if (rowIdx >= entries.length) return;

        const oldKey = entries[rowIdx][0];
        const value = entries[rowIdx][1];
        const newKey = inputEl.value.trim();

        if (!newKey || newKey === oldKey) return;

        // Rebuild annotations preserving order but with new key
        const newAnnotations = {};
        for (const [k, v] of entries) {
            if (k === oldKey) {
                newAnnotations[newKey] = value;
            } else {
                newAnnotations[k] = v;
            }
        }

        block.annotations = newAnnotations;
        PU.annotations._refreshBadge(path);
        PU.annotations.fire('change', { block, path, annotations: newAnnotations });
    },

    _handleValueChange(path, rowIdx, inputEl) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        const entries = Object.entries(block.annotations || {});
        if (rowIdx >= entries.length) return;

        const key = entries[rowIdx][0];
        let newValue = inputEl.value;

        // Auto-detect types
        if (newValue === 'true') newValue = true;
        else if (newValue === 'false') newValue = false;
        else if (newValue !== '' && !isNaN(Number(newValue))) newValue = Number(newValue);

        if (!block.annotations) block.annotations = {};
        block.annotations[key] = newValue;

        PU.annotations.fire('change', { block, path, annotations: block.annotations });
    },

    _addRow(path, pathId) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        if (!block.annotations) block.annotations = {};

        // Find unique key name
        let keyName = 'key';
        let counter = 1;
        while (block.annotations.hasOwnProperty(keyName)) {
            keyName = `key${counter++}`;
        }
        block.annotations[keyName] = '';

        // Re-render the rows section
        const rowsEl = document.querySelector(`[data-testid="pu-ann-rows-${pathId}"]`);
        if (rowsEl) {
            const entries = Object.entries(block.annotations);
            let html = '';
            entries.forEach(([k, v], idx) => {
                html += PU.annotations._buildRowHtml(path, pathId, idx, k, String(v));
            });
            rowsEl.innerHTML = html;
        }

        PU.annotations._refreshBadge(path);
        PU.annotations.fire('change', { block, path, annotations: block.annotations });
    },

    _removeRow(path, key) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        PU.blocks.removeAnnotation(prompt.text, path, key);

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        const annotations = (block && block.annotations) || {};

        // Re-render the rows section
        const pathId = path.replace(/\./g, '-');
        const rowsEl = document.querySelector(`[data-testid="pu-ann-rows-${pathId}"]`);
        if (rowsEl) {
            const entries = Object.entries(annotations);
            let html = '';
            entries.forEach(([k, v], idx) => {
                html += PU.annotations._buildRowHtml(path, pathId, idx, k, String(v));
            });
            rowsEl.innerHTML = html;
        }

        PU.annotations._refreshBadge(path);
        PU.annotations.fire('change', { block, path, annotations });

        // Close editor if no annotations left
        if (Object.keys(annotations).length === 0) {
            PU.annotations.closeEditor(path);
        }
    },

    // =========================================================================
    // BADGE REFRESH (without full re-render)
    // =========================================================================

    _refreshBadge(path) {
        const pathId = path.replace(/\./g, '-');
        const badgeEl = document.querySelector(`[data-testid="pu-ann-badge-${pathId}"]`);
        const annotateBtn = document.querySelector(`[data-testid="pu-block-annotate-btn-${pathId}"]`);

        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        const ann = (block && block.annotations) || {};
        const count = Object.keys(ann).length;

        // Update badge
        if (count > 0) {
            if (badgeEl) {
                const countEl = badgeEl.querySelector('.pu-ann-count');
                if (countEl) countEl.textContent = count;
            } else {
                // Badge doesn't exist yet; insert it. Requires locating resolved-text div.
                const blockEl = document.querySelector(`[data-testid="pu-block-${pathId}"]`);
                if (blockEl) {
                    const resolvedEl = blockEl.querySelector('.pu-resolved-text');
                    if (resolvedEl) {
                        const temp = document.createElement('span');
                        temp.innerHTML = PU.blocks._renderAnnotationBadge(block, path, pathId);
                        if (temp.firstElementChild) {
                            // Insert before first inline-actions or at end
                            const inlineActions = resolvedEl.querySelector('.pu-inline-actions');
                            if (inlineActions) {
                                resolvedEl.insertBefore(temp.firstElementChild, inlineActions);
                            } else {
                                resolvedEl.appendChild(temp.firstElementChild);
                            }
                        }
                    }
                }
            }
        } else {
            // Remove badge
            if (badgeEl) badgeEl.remove();
        }

        // Update annotate button tint
        if (annotateBtn) {
            if (count > 0) {
                annotateBtn.classList.add('has-annotations');
            } else {
                annotateBtn.classList.remove('has-annotations');
            }
        }
    },

    // =========================================================================
    // ANNOTATION EVENT SYSTEM
    // =========================================================================

    /**
     * Register an annotation event handler
     * @param {string} name - Unique handler name
     * @param {string} event - 'render' | 'select' | 'change' | 'export'
     * @param {Function} handler - (context) => void
     */
    register(name, event, handler) {
        PU.annotations._hooks[name] = { event, handler };
    },

    /**
     * Unregister an annotation event handler
     */
    unregister(name) {
        delete PU.annotations._hooks[name];
    },

    /**
     * Fire an event to all registered annotation handlers
     * @param {string} event - Event name
     * @param {Object} context - { block, path, annotations, containerEl }
     */
    fire(event, context) {
        for (const [name, hook] of Object.entries(PU.annotations._hooks)) {
            if (hook.event === event) {
                try {
                    hook.handler(context);
                } catch (e) {
                    console.warn(`Annotation handler '${name}' error:`, e);
                }
            }
        }
    },

    // =========================================================================
    // RESTORE OPEN EDITORS (after DOM rebuild)
    // =========================================================================

    restoreOpenEditors() {
        for (const path of PU.annotations._openEditors) {
            // Re-open editors that were open before re-render
            // Use a microtask to ensure DOM is ready
            setTimeout(() => {
                PU.annotations._openEditors.delete(path); // Remove first so openEditor doesn't skip
                PU.annotations.openEditor(path);
            }, 0);
        }
    }
};
