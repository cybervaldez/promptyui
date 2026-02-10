/**
 * PromptyUI - Wildcard Inline Expansion Popover
 *
 * Click a defined wildcard chip in the Quill editor → the chip expands
 * in-place as an absolutely-positioned overlay → type comma-separated
 * values → save. Keeps the editor-first workflow intact.
 */

PU.wildcardPopover = {
    _el: null,
    _open: false,
    _wildcardName: null,
    _chipEl: null,
    _quillInstance: null,
    _quillPath: null,
    _extValues: [],
    _localValues: [],
    _onClickOutside: null,
    _onKeyDown: null,
    _passive: false,

    /**
     * Open inline expansion for a defined wildcard chip
     */
    open(chipEl, wcName, quill, path, isFocusMode, passive = false) {
        // Close any existing expansion or autocomplete
        if (PU.wildcardPopover._open) {
            PU.wildcardPopover.close();
        }
        if (PU.quill._autocompleteOpen) {
            PU.quill.closeAutocomplete();
        }

        PU.wildcardPopover._chipEl = chipEl;
        PU.wildcardPopover._wildcardName = wcName;
        PU.wildcardPopover._quillInstance = quill;
        PU.wildcardPopover._quillPath = path;
        PU.wildcardPopover._open = true;
        PU.wildcardPopover._passive = passive;

        // Read local values from prompt.wildcards
        const prompt = PU.editor.getModifiedPrompt();
        const localWc = prompt ? (prompt.wildcards || []).find(w => w.name === wcName) : null;
        PU.wildcardPopover._localValues = localWc
            ? (Array.isArray(localWc.text) ? [...localWc.text] : [localWc.text])
            : [];

        // Create element if needed
        if (!PU.wildcardPopover._el) {
            PU.wildcardPopover._el = document.createElement('div');
            PU.wildcardPopover._el.className = 'pu-wc-inline';
            PU.wildcardPopover._el.setAttribute('data-testid', 'pu-wc-inline');
            document.body.appendChild(PU.wildcardPopover._el);
        }

        PU.wildcardPopover._el.style.display = 'flex';
        PU.wildcardPopover._extValues = [];
        PU.wildcardPopover.render();
        PU.wildcardPopover.position();

        // Load extension values async
        PU.helpers.getExtensionWildcardValues(wcName).then(extVals => {
            PU.wildcardPopover._extValues = extVals || [];
            if (PU.wildcardPopover._open && PU.wildcardPopover._wildcardName === wcName) {
                PU.wildcardPopover.render();
            }
        });

        // Focus input after render (skip in passive mode)
        if (!passive) {
            requestAnimationFrame(() => {
                const input = PU.wildcardPopover._el?.querySelector('.pu-wc-inline-input');
                if (input) input.focus();
            });
        }

        // Click-outside listener (deferred to avoid catching the opening click)
        PU.wildcardPopover._onClickOutside = (e) => {
            if (PU.wildcardPopover._el && !PU.wildcardPopover._el.contains(e.target) &&
                e.target !== chipEl && !chipEl.contains(e.target)) {
                PU.wildcardPopover.close();
            }
        };
        setTimeout(() => {
            document.addEventListener('mousedown', PU.wildcardPopover._onClickOutside);
        }, 0);

        // Escape / Tab key listener
        PU.wildcardPopover._onKeyDown = (e) => {
            if (e.key === 'Escape') {
                e.preventDefault();
                e.stopPropagation();
                PU.wildcardPopover.close();
            } else if (e.key === 'Tab' && PU.wildcardPopover._passive) {
                e.preventDefault();
                e.stopPropagation();
                PU.wildcardPopover.activate();
            }
        };
        document.addEventListener('keydown', PU.wildcardPopover._onKeyDown, true);
    },

    /**
     * Close inline expansion
     */
    close() {
        PU.wildcardPopover._open = false;
        PU.wildcardPopover._passive = false;
        if (PU.wildcardPopover._el) {
            PU.wildcardPopover._el.style.display = 'none';
        }
        if (PU.wildcardPopover._onClickOutside) {
            document.removeEventListener('mousedown', PU.wildcardPopover._onClickOutside);
            PU.wildcardPopover._onClickOutside = null;
        }
        if (PU.wildcardPopover._onKeyDown) {
            document.removeEventListener('keydown', PU.wildcardPopover._onKeyDown, true);
            PU.wildcardPopover._onKeyDown = null;
        }
        PU.wildcardPopover._chipEl = null;
        PU.wildcardPopover._quillInstance = null;
        PU.wildcardPopover._quillPath = null;
        PU.wildcardPopover._wildcardName = null;
        PU.wildcardPopover._extValues = [];
        PU.wildcardPopover._localValues = [];
    },

    /**
     * Activate a passive popover into active mode with input.
     */
    activate() {
        if (!PU.wildcardPopover._open || !PU.wildcardPopover._passive) return;
        PU.wildcardPopover._passive = false;
        PU.wildcardPopover.render();
        requestAnimationFrame(() => {
            const input = PU.wildcardPopover._el?.querySelector('.pu-wc-inline-input');
            if (input) input.focus();
        });
    },

    /**
     * Render the inline expansion content
     */
    render() {
        const el = PU.wildcardPopover._el;
        if (!el) return;

        const wcName = PU.wildcardPopover._wildcardName;
        const extValues = PU.wildcardPopover._extValues;
        const localValues = PU.wildcardPopover._localValues;
        const esc = PU.blocks.escapeHtml;

        let html = '';

        // Label
        html += `<span class="pu-wc-inline-label">${esc(wcName)}:</span>`;

        // Pills container
        html += '<span class="pu-wc-inline-pills">';

        // Extension value pills (read-only, muted)
        extValues.forEach((v, i) => {
            if (i > 0) html += '<span class="pu-wc-inline-separator">&middot;</span>';
            html += `<span class="pu-wc-inline-pill ext" title="From extension">${esc(v)}</span>`;
        });

        // Separator between ext and local if both exist
        if (extValues.length > 0 && localValues.length > 0) {
            html += '<span class="pu-wc-inline-separator">&middot;</span>';
        }

        // Local value pills (editable, with remove button)
        localValues.forEach((v, i) => {
            if (i > 0 && extValues.length === 0) {
                html += '<span class="pu-wc-inline-separator">&middot;</span>';
            } else if (i > 0) {
                html += '<span class="pu-wc-inline-separator">&middot;</span>';
            }
            html += `<span class="pu-wc-inline-pill local" data-testid="pu-wc-inline-pill-${i}">${esc(v)}<button class="remove" data-testid="pu-wc-inline-remove-${i}" data-idx="${i}" title="Remove value">&times;</button></span>`;
        });

        html += '</span>';

        // Input or passive hint
        if (PU.wildcardPopover._passive) {
            html += `<span class="pu-wc-inline-hint" data-testid="pu-wc-inline-hint">press tab to add values</span>`;
        } else {
            html += `<input type="text" class="pu-wc-inline-input" data-testid="pu-wc-inline-input" placeholder="add values..." />`;
        }

        // Variations preview (always visible when values exist)
        const allValues = [...extValues, ...localValues];
        if (allValues.length > 0) {
            const variationsHtml = PU.wildcardPopover._generateVariationsHtml();
            if (variationsHtml) {
                html += '<div class="pu-wc-inline-variations" data-testid="pu-wc-inline-variations">';
                html += variationsHtml;
                html += '</div>';
            }
        }

        el.innerHTML = html;

        // Wire remove clicks
        el.querySelectorAll('.remove').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                const idx = parseInt(btn.dataset.idx);
                PU.wildcardPopover.removeLocalValue(idx);
            });
        });

        // Wire input keydown
        const input = el.querySelector('.pu-wc-inline-input');
        if (input) {
            input.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    e.preventDefault();
                    if (input.value.trim()) {
                        PU.wildcardPopover.addValues(input.value);
                        input.value = '';
                    }
                } else if (e.key === 'Escape') {
                    e.preventDefault();
                    e.stopPropagation();
                    PU.wildcardPopover.close();
                }
            });

            // Commit on comma
            input.addEventListener('input', (e) => {
                const val = input.value;
                if (val.includes(',')) {
                    PU.wildcardPopover.addValues(val);
                    input.value = '';
                }
            });
        }
    },

    /**
     * Add comma-separated values to the wildcard
     */
    addValues(commaSeparatedText) {
        const newValues = commaSeparatedText
            .split(',')
            .map(v => v.trim())
            .filter(v => v.length > 0);

        if (newValues.length === 0) return;

        const wcName = PU.wildcardPopover._wildcardName;
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        // Ensure wildcards array
        if (!prompt.wildcards) {
            prompt.wildcards = [];
        }

        // Find or create wildcard entry
        let wc = prompt.wildcards.find(w => w.name === wcName);
        if (!wc) {
            wc = { name: wcName, text: [] };
            prompt.wildcards.push(wc);
        }
        if (!Array.isArray(wc.text)) {
            wc.text = [wc.text];
        }

        // Deduplicate against local + ext
        const existingLocal = new Set(wc.text.map(v => v.toLowerCase()));
        const existingExt = new Set(PU.wildcardPopover._extValues.map(v => v.toLowerCase()));
        const deduped = newValues.filter(v => {
            const lower = v.toLowerCase();
            return !existingLocal.has(lower) && !existingExt.has(lower);
        });

        if (deduped.length === 0) return;

        // Append
        wc.text.push(...deduped);
        PU.wildcardPopover._localValues = [...wc.text];

        // Re-render
        PU.wildcardPopover.render();

        // Refresh chip preview in editor
        PU.wildcardPopover.refreshChip(PU.wildcardPopover._quillInstance, wcName);

        // Refresh inspector
        PU.wildcardPopover._refreshInspector();

        // Re-focus input
        requestAnimationFrame(() => {
            const input = PU.wildcardPopover._el.querySelector('.pu-wc-inline-input');
            if (input) input.focus();
        });
    },

    /**
     * Remove a local value by index
     */
    removeLocalValue(index) {
        const wcName = PU.wildcardPopover._wildcardName;
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        const wc = (prompt.wildcards || []).find(w => w.name === wcName);
        if (!wc || !Array.isArray(wc.text)) return;

        wc.text.splice(index, 1);
        PU.wildcardPopover._localValues = [...wc.text];

        PU.wildcardPopover.render();
        PU.wildcardPopover.refreshChip(PU.wildcardPopover._quillInstance, wcName);
        PU.wildcardPopover._refreshInspector();

        // Re-focus input
        requestAnimationFrame(() => {
            const input = PU.wildcardPopover._el.querySelector('.pu-wc-inline-input');
            if (input) input.focus();
        });
    },

    /**
     * Update chip preview text in all matching chip DOMs
     */
    refreshChip(quill, wcName) {
        if (!quill) return;

        const wildcardLookup = PU.helpers.getWildcardLookup();
        const values = wildcardLookup[wcName] || [];
        const preview = values.length > 0
            ? values.slice(0, 3).join(', ') + (values.length > 3 ? ` +${values.length - 3}` : '')
            : '';

        // Update all chip DOMs in this quill instance
        const chips = quill.root.querySelectorAll(`.ql-wildcard-chip[data-wildcard-name="${wcName}"]`);
        chips.forEach(chip => {
            // Update preview text
            let previewEl = chip.querySelector('.ql-wc-preview');
            if (preview && !previewEl) {
                previewEl = document.createElement('span');
                previewEl.className = 'ql-wc-preview';
                chip.appendChild(previewEl);
            }
            if (previewEl) {
                previewEl.textContent = preview;
            }

            // Toggle undefined class
            if (values.length === 0) {
                chip.classList.add('ql-wc-undefined');
            } else {
                chip.classList.remove('ql-wc-undefined');
            }
        });

        // Also update chips in main editor instances
        for (const [, inst] of Object.entries(PU.quill.instances)) {
            if (inst === quill) continue;
            const otherChips = inst.root.querySelectorAll(`.ql-wildcard-chip[data-wildcard-name="${wcName}"]`);
            otherChips.forEach(chip => {
                let previewEl = chip.querySelector('.ql-wc-preview');
                if (preview && !previewEl) {
                    previewEl = document.createElement('span');
                    previewEl.className = 'ql-wc-preview';
                    chip.appendChild(previewEl);
                }
                if (previewEl) {
                    previewEl.textContent = preview;
                }
                if (values.length === 0) {
                    chip.classList.add('ql-wc-undefined');
                } else {
                    chip.classList.remove('ql-wc-undefined');
                }
            });
        }

        // Also update focus mode quill if active
        if (PU.state.focusMode.active && PU.state.focusMode.quillInstance &&
            PU.state.focusMode.quillInstance !== quill) {
            const focusChips = PU.state.focusMode.quillInstance.root.querySelectorAll(
                `.ql-wildcard-chip[data-wildcard-name="${wcName}"]`
            );
            focusChips.forEach(chip => {
                let previewEl = chip.querySelector('.ql-wc-preview');
                if (preview && !previewEl) {
                    previewEl = document.createElement('span');
                    previewEl.className = 'ql-wc-preview';
                    chip.appendChild(previewEl);
                }
                if (previewEl) previewEl.textContent = preview;
                if (values.length === 0) {
                    chip.classList.add('ql-wc-undefined');
                } else {
                    chip.classList.remove('ql-wc-undefined');
                }
            });
        }
    },

    /**
     * Position element flush with chip
     */
    position() {
        const el = PU.wildcardPopover._el;
        const chip = PU.wildcardPopover._chipEl;
        if (!el || !chip) return;

        const chipRect = chip.getBoundingClientRect();

        // Force layout reflow
        el.getBoundingClientRect();
        const elHeight = el.offsetHeight;
        const elWidth = el.offsetWidth;

        // Default: position below chip, aligned left
        let top = chipRect.bottom + 4;
        let left = chipRect.left;

        // Flip above if near viewport bottom
        if (top + elHeight > window.innerHeight - 10) {
            top = chipRect.top - elHeight - 4;
        }

        // Clamp right edge
        if (left + elWidth > window.innerWidth - 10) {
            left = window.innerWidth - elWidth - 10;
        }

        // Clamp left edge
        if (left < 10) left = 10;

        el.style.left = left + 'px';
        el.style.top = top + 'px';
    },

    /**
     * Generate variations preview HTML for the inline popover.
     */
    _generateVariationsHtml() {
        const wcName = PU.wildcardPopover._wildcardName;
        const path = PU.wildcardPopover._quillPath;
        if (!wcName || !path) return '';

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return '';

        const block = PU.blocks.findBlockByPath(prompt.text || [], path);
        if (!block || !block.content) return '';

        const variations = PU.focus.generateFocusedVariations(block.content, wcName);
        if (variations.length === 0) return '';

        const esc = PU.blocks.escapeHtml;
        let html = '';
        variations.forEach((v, idx) => {
            const escaped = PU.preview.escapeHtmlPreservingMarkers(v.markedText);
            let pillHtml = PU.preview.renderWildcardPills(escaped);
            // Mark the active wildcard's pills so CSS can differentiate
            pillHtml = pillHtml.replace(
                new RegExp(`data-wc-name="${esc(wcName)}"`, 'g'),
                `data-wc-name="${esc(wcName)}" data-wc-active`
            );
            html += `<div class="pu-wc-inline-variation-item">
                <span class="pu-wc-inline-variation-index">${idx + 1}.</span>
                <span class="pu-wc-inline-variation-text">${pillHtml}</span>
            </div>`;
        });
        return html;
    },

    /**
     * Refresh the inspector wildcards context
     */
    _refreshInspector() {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        const blockPath = PU.state.selectedBlockPath;
        if (!blockPath) return;
        const block = PU.blocks.findBlockByPath(prompt.text || [], blockPath);
        if (block && block.content) {
            const usedWildcards = PU.blocks.detectWildcards(block.content);
            PU.inspector.updateWildcardsContext(usedWildcards, prompt.wildcards || []);
        }
    }
};
