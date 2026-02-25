/**
 * PromptyUI - Focus Mode
 *
 * Zen editing overlay: clicking into a content block covers the background
 * with an overlay showing the focused block's Quill editor.
 * Supports draft mode: block isn't created until the user types content.
 */

PU.focus = {
    /**
     * Enter focus mode for a block at the given path.
     * @param {string} path - Block path (e.g. "0", "0.1")
     * @param {Object} [opts] - Optional: { draft: true, parentPath: string|null }
     */
    enter(path, opts) {
        const state = PU.state.focusMode;

        // Guard: already active
        if (state.active) return;

        // Guard: debounce rapid entry (300ms)
        if (Date.now() - state.enterTimestamp < 300) return;

        // Guard: must have a prompt
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return;

        const isDraft = opts && opts.draft;

        if (!isDraft) {
            // Guard: block must exist and be a content block (not ext_text)
            const block = PU.blocks.findBlockByPath(prompt.text || [], path);
            if (!block || !('content' in block)) return;
        }

        // Set state
        state.active = true;
        state.blockPath = path;
        state.enterTimestamp = Date.now();
        state.draft = !!isDraft;
        state.draftParentPath = isDraft ? (opts.parentPath || null) : null;
        state.draftMaterialized = false;

        PU.actions.updateUrl();

        // Get overlay elements
        const overlay = document.querySelector('[data-testid="pu-focus-overlay"]');
        const titleEl = document.querySelector('[data-testid="pu-focus-title"]');
        const quillContainer = document.querySelector('[data-testid="pu-focus-quill"]');

        if (!overlay || !quillContainer) return;

        // Update title with block path
        if (titleEl) {
            titleEl.textContent = 'Block: ' + path;
        }

        // Show overlay with transition choreography
        overlay.style.display = 'flex';
        requestAnimationFrame(() => {
            overlay.classList.add('pu-focus-visible');
        });

        // Prevent background scroll
        document.body.classList.add('pu-focus-active');

        // Create Quill editor in focus panel
        const content = isDraft ? '' : (PU.blocks.findBlockByPath(prompt.text || [], path).content || '');
        PU.focus.createQuill(quillContainer, path, content);

        // Insert parent context as inline Quill blot at position 0
        const contextHtml = PU.focus._buildContextHtml(path);
        if (contextHtml && state.quillInstance) {
            state.quillInstance.insertEmbed(0, 'parentContext', { html: contextHtml }, Quill.sources.SILENT);
            state._hasParentContext = true;

            // Wire up wildcard click-to-cycle inside the blot
            const blotEl = quillContainer.querySelector('.ql-parent-context');
            if (blotEl) {
                blotEl.querySelectorAll('.pu-wc-text-value').forEach(el => {
                    el.addEventListener('click', (e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        const wcName = el.dataset.wc;
                        const values = JSON.parse(el.dataset.values || '[]');
                        const currentValue = el.dataset.value;
                        if (!wcName || values.length === 0) return;
                        const others = values.filter(v => v !== currentValue);
                        const newValue = others.length > 0
                            ? others[Math.floor(Math.random() * others.length)]
                            : values[Math.floor(Math.random() * values.length)];
                        el.dataset.value = newValue;
                        el.textContent = newValue;
                        // Refocus Quill editor after click on non-editable blot
                        requestAnimationFrame(() => {
                            if (state.quillInstance) {
                                const pos = state._hasParentContext ? 1 : 0;
                                state.quillInstance.focus();
                                state.quillInstance.setSelection(pos, 0);
                            }
                        });
                    });
                });
            }
        } else {
            state._hasParentContext = false;
        }

        // Initial output render — show counter or empty state (never expanded on entry)
        PU.focus._outputExpanded = false;
        PU.focus._syncIncludeCheckboxes(path);
        PU.focus._updateFocusOutputState(isDraft ? '' : content, path);

        // Focus the Quill editor and position cursor after the blot
        if (state.quillInstance) {
            const startPos = state._hasParentContext ? 1 : 0;
            requestAnimationFrame(() => {
                if (state.quillInstance) {
                    state.quillInstance.focus();
                    state.quillInstance.setSelection(startPos, 0);
                }
            });
        }
    },

    /**
     * Exit focus mode, syncing content back to the block.
     */
    exit() {
        const state = PU.state.focusMode;

        // Guard: not active
        if (!state.active) return;

        const path = state.blockPath;
        const wasDraft = state.draft;
        const materialized = state.draftMaterialized;

        // Serialize focus Quill to plain text and sync back
        if (state.quillInstance) {
            const text = PU.quill.serialize(state.quillInstance);

            if (wasDraft && !materialized) {
                // Draft was never materialized — nothing to save
            } else if (wasDraft && materialized && !text.trim()) {
                // Materialized but user cleared all content — delete the block
                const prompt = PU.editor.getModifiedPrompt();
                if (prompt && Array.isArray(prompt.text)) {
                    PU.blocks.deleteBlockAtPath(prompt.text, path);
                }
            } else {
                // Normal path: update block content
                const prompt = PU.editor.getModifiedPrompt();
                if (prompt) {
                    const block = PU.blocks.findBlockByPath(prompt.text || [], path);
                    if (block && 'content' in block) {
                        block.content = text;
                    }
                }
            }

            // Destroy focus Quill
            state.quillInstance.disable();
            state.quillInstance = null;
        }

        // Clear container
        const quillContainer = document.querySelector('[data-testid="pu-focus-quill"]');
        if (quillContainer) {
            quillContainer.innerHTML = '';
        }

        // Clear resolved output (overlay itself hides, so this is cleanup)
        const focusOutput = document.querySelector('[data-testid="pu-focus-output"]');
        if (focusOutput) {
            focusOutput.style.display = 'none';
            focusOutput.classList.remove('collapsed', 'label-none', 'label-hybrid', 'label-inline', 'pu-focus-output-state-empty', 'pu-focus-output-state-counter');
            const list = focusOutput.querySelector('[data-testid="pu-focus-output-list"]');
            if (list) list.innerHTML = '';
        }
        PU.focus._outputFilters = {};
        PU.focus._outputCurrentOutputs = null;
        PU.focus._outputCollapsed = false;
        PU.focus._outputExpanded = false;

        // Transition out: remove visible class, then hide after transition
        const overlay = document.querySelector('[data-testid="pu-focus-overlay"]');
        if (overlay) {
            overlay.classList.remove('pu-focus-visible');
            setTimeout(() => {
                overlay.style.display = 'none';
            }, 200);
        }

        // Restore background scroll
        document.body.classList.remove('pu-focus-active');

        // Reset state
        state.active = false;
        state.blockPath = null;
        state.quillInstance = null;
        state.draft = false;
        state.draftParentPath = null;
        state.draftMaterialized = false;
        state._hasParentContext = false;

        PU.actions.updateUrl();

        // Re-render blocks to refresh original Quills
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
    },

    /**
     * Materialize a draft block into the prompt data model.
     * Called on first text-change when in draft mode.
     */
    _materializeDraft(path) {
        const state = PU.state.focusMode;
        if (!state.draft || state.draftMaterialized) return;

        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        // Actually create the block
        PU.blocks.addNestedBlockAtPath(prompt.text, state.draftParentPath, 'content');
        state.draftMaterialized = true;
    },

    /**
     * Create a Quill instance for the focus mode editor.
     * Similar to PU.quill.create() but NOT stored in PU.quill.instances.
     */
    createQuill(containerEl, path, content) {
        // Clear container
        containerEl.innerHTML = '';

        // Bail if Quill not available
        if (typeof Quill === 'undefined') return;

        const quill = new Quill(containerEl, {
            theme: 'snow',
            modules: {
                toolbar: false
            },
            placeholder: ''
        });

        // Inject hint inside the Quill container (containerEl becomes .ql-container)
        const hint = document.createElement('div');
        hint.className = 'pu-focus-hint';
        hint.setAttribute('data-testid', 'pu-focus-hint');
        hint.textContent = 'hint: type __ to search or create wildcards';
        containerEl.appendChild(hint);

        // Parse initial content into Delta with wildcard embeds
        const wildcardLookup = PU.helpers.getWildcardLookup();
        const ops = PU.quill.parseContentToOps(content || '', wildcardLookup);
        quill.setContents({ ops: ops }, Quill.sources.SILENT);

        // Text-change: update state + debounce preview reload
        quill.on('text-change', (delta, oldDelta, source) => {
            if (source === Quill.sources.SILENT) return;
            PU.focus.handleTextChange(path, quill);
        });

        // Selection-change: track activeWildcard + passive popover
        quill.on('selection-change', (range, oldRange, source) => {
            if (!range) return;

            // Prevent cursor/selection from landing before parent context blot
            if (PU.state.focusMode._hasParentContext && range.index === 0) {
                quill.setSelection(1, Math.max(0, range.length - 1), Quill.sources.SILENT);
                return;
            }

            const wcName = PU.quill.getAdjacentWildcardName(quill);
            if (wcName !== PU.state.preview.activeWildcard) {
                PU.state.preview.activeWildcard = wcName;
            }

            // Passive popover: show when cursor is adjacent to a wildcard chip
            if (PU.wildcardPopover?._suppressReopen) return;
            if (wcName && PU.wildcardPopover) {
                if (!PU.wildcardPopover._open || PU.wildcardPopover._wildcardName !== wcName) {
                    const chipEl = PU.quill.getAdjacentWildcardChipEl(quill);
                    if (chipEl) {
                        PU.wildcardPopover.open(chipEl, wcName, quill, path, true, true);
                    }
                }
            } else if (PU.wildcardPopover?._open && PU.wildcardPopover._passive) {
                // Cursor moved away — close only if still passive
                PU.wildcardPopover.close();
            }
        });

        // Focus handler: does NOT call PU.focus.enter() again (prevents loop)
        // Blur handler: does NOT exit focus mode (only overlay click / Escape do)

        // Keyboard handler — CAPTURE phase so we fire before Quill's Keyboard module
        quill.root.addEventListener('keydown', (e) => {
            // Protect parent context blot from deletion
            if (PU.state.focusMode._hasParentContext) {
                const sel = quill.getSelection();
                if (sel) {
                    // Backspace at pos 1 (or 0) with no selection — would delete the blot
                    if (e.key === 'Backspace' && sel.length === 0 && sel.index <= 1) {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        return;
                    }
                    // Delete key at pos 0 with no selection
                    if (e.key === 'Delete' && sel.length === 0 && sel.index === 0) {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        return;
                    }
                    // Ctrl/Cmd+A — select child content only (skip blot at pos 0)
                    if ((e.ctrlKey || e.metaKey) && e.key === 'a') {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        quill.setSelection(1, quill.getLength() - 2);
                        return;
                    }
                }
            }

            // Autocomplete takes priority (only consume if actually handled)
            if (PU.quill._autocompleteOpen) {
                const handled = PU.quill.handleAutocompleteKey(e);
                if (handled) return;
            }
            // Tab activates passive popover
            if (e.key === 'Tab' && PU.wildcardPopover?._open && PU.wildcardPopover._passive) {
                e.preventDefault();
                e.stopPropagation();
                PU.wildcardPopover.activate();
                return;
            }
        }, true);

        // beforeinput guard — catches deletions that bypass keydown (mobile, IME)
        quill.root.addEventListener('beforeinput', (e) => {
            if (!PU.state.focusMode._hasParentContext) return;
            const sel = quill.getSelection();
            if (!sel) return;
            // Block backward deletion at blot boundary
            if (e.inputType === 'deleteContentBackward' && sel.length === 0 && sel.index <= 1) {
                e.preventDefault();
                return;
            }
            // Block forward deletion at position 0
            if (e.inputType === 'deleteContentForward' && sel.length === 0 && sel.index === 0) {
                e.preventDefault();
                return;
            }
            // Block any input that would replace content starting at position 0
            if (sel.index === 0 && sel.length > 0) {
                e.preventDefault();
                quill.setSelection(1, Math.max(0, sel.length - 1), Quill.sources.SILENT);
                return;
            }
        });

        // Blur guard — prevent editor from losing focus when deleting last text
        quill.root.addEventListener('blur', () => {
            setTimeout(() => {
                if (!PU.state.focusMode.active) return;
                if (PU.state.focusMode.quillInstance !== quill) return;
                if (PU.wildcardPopover?._open) return;
                if (PU.quill._autocompleteOpen) return;
                quill.focus();
            }, 50);
        });

        // Store as transient instance (not in PU.quill.instances)
        PU.state.focusMode.quillInstance = quill;
        return quill;
    },

    /**
     * Handle text-change events from the focus Quill.
     * Serializes to plain text, updates block state.
     */
    handleTextChange(path, quillInstance) {
        const plainText = PU.quill.serialize(quillInstance);
        const state = PU.state.focusMode;

        // Draft mode: materialize on first real content
        if (state.draft && !state.draftMaterialized && plainText.trim()) {
            PU.focus._materializeDraft(path);
        }

        // Update block state (without re-rendering blocks)
        if (!state.draft || state.draftMaterialized) {
            const prompt = PU.editor.getModifiedPrompt();
            if (prompt) {
                const block = PU.blocks.findBlockByPath(prompt.text || [], path);
                if (block && 'content' in block) {
                    block.content = plainText;
                }
            }
        }

        // Update token counter chip (live template count while editing)
        PU.blocks.updateTokenCounter(path, plainText);

        // Update resolved output section
        PU.focus._debouncedPopulateFocusOutput(plainText, path);

        // Check for autocomplete trigger
        const sel = quillInstance.getSelection();
        if (sel) {
            const textBefore = quillInstance.getText(0, sel.index);

            // Complete wildcard pattern typed — skip autocomplete, convert directly
            if (textBefore.match(/__([a-zA-Z0-9][a-zA-Z0-9_-]*)__$/)) {
                if (PU.quill._autocompleteOpen) PU.quill.closeAutocomplete();
                // Suppress passive popover during conversion (setSelection triggers selection-change)
                if (PU.wildcardPopover) PU.wildcardPopover._suppressReopen = true;
                PU.quill.convertWildcardsInline(quillInstance);

                // Auto-open popover for new (undefined) wildcards
                requestAnimationFrame(() => {
                    const undefinedChip = quillInstance.root.querySelector('.ql-wc-undefined');
                    if (undefinedChip && PU.wildcardPopover) {
                        PU.wildcardPopover._suppressReopen = false;
                        const wcName = undefinedChip.getAttribute('data-wildcard-name');
                        PU.wildcardPopover.open(undefinedChip, wcName, quillInstance, path, PU.state.focusMode.active);
                        PU.wildcardPopover._forceValues = true;
                    } else {
                        if (PU.wildcardPopover) PU.wildcardPopover._suppressReopen = false;
                    }
                });
                return;
            }

            // Colon shortcut: __name: → create chip + open popover
            if (PU.quill.handleColonShortcut(quillInstance, path, sel, textBefore)) {
                // Update block state
                const text = PU.quill.serialize(quillInstance);
                const prompt2 = PU.editor.getModifiedPrompt();
                if (prompt2) {
                    const block2 = PU.blocks.findBlockByPath(prompt2.text || [], path);
                    if (block2 && 'content' in block2) block2.content = text;
                }
                return;
            }

            const triggerMatch = textBefore.match(/__([a-zA-Z0-9_-]*)$/);

            if (triggerMatch) {
                const textAfter = quillInstance.getText(sel.index, 10);
                const isClosed = textAfter.startsWith('__');

                if (!isClosed) {
                    const triggerIndex = sel.index - triggerMatch[0].length;
                    const query = triggerMatch[1];
                    PU.quill.showAutocomplete(quillInstance, path, triggerIndex, query);
                    return;
                }
            }
        }

        // Close autocomplete if no trigger found
        if (PU.quill._autocompleteOpen) {
            PU.quill.closeAutocomplete();
        }

        // Convert any newly typed wildcards to inline chips
        PU.quill.convertWildcardsInline(quillInstance);
    },



    /**
     * Generate focused variations for a single active wildcard.
     * Returns one entry per value of the active wildcard, with non-active
     * wildcards using random distinct values per variation.
     * Output uses {{name:value}} markers directly for the pill pipeline.
     */
    generateFocusedVariations(blockContent, activeWildcard) {
        const wcLookup = PU.helpers.getWildcardLookup();
        const activeValues = wcLookup[activeWildcard] || [];
        if (activeValues.length === 0) return [];

        // Collect inactive wildcard names used in this content
        const inactiveWcNames = [];
        blockContent.replace(/__([a-zA-Z0-9_-]+)__/g, (match, wcName) => {
            if (wcName !== activeWildcard && !inactiveWcNames.includes(wcName)) {
                inactiveWcNames.push(wcName);
            }
            return match;
        });

        // Pre-shuffle each inactive wildcard's values to ensure distinct picks per variation
        const inactiveShuffled = {};
        for (const wcName of inactiveWcNames) {
            const values = wcLookup[wcName];
            if (values && values.length > 0) {
                // Fisher-Yates shuffle a copy
                const shuffled = [...values];
                for (let j = shuffled.length - 1; j > 0; j--) {
                    const k = Math.floor(Math.random() * (j + 1));
                    [shuffled[j], shuffled[k]] = [shuffled[k], shuffled[j]];
                }
                inactiveShuffled[wcName] = shuffled;
            }
        }

        return activeValues.map((activeVal, i) => {
            const markedText = blockContent.replace(/__([a-zA-Z0-9_-]+)__/g, (match, wcName) => {
                if (wcName === activeWildcard) {
                    return `{{${wcName}:${activeVal}}}`;
                }
                const shuffled = inactiveShuffled[wcName];
                if (shuffled && shuffled.length > 0) {
                    return `{{${wcName}:${shuffled[i % shuffled.length]}}}`;
                }
                return match;
            });
            return { markedText, activeValue: activeVal };
        });
    },

    /**
     * Build inline parent hierarchy context HTML for a given block path.
     * Renders ancestors as flowing text with standard wildcard dropdowns.
     * Returns empty string for root blocks (depth 0).
     */
    _buildContextHtml(path) {
        const resolutions = PU.editor._lastResolutions;
        if (!resolutions) return '';

        // Build ancestor paths: "0.1.2" → ["0", "0.1"]
        const parts = path.split('.');
        if (parts.length <= 1) return ''; // Root block — no ancestors

        const ancestors = [];
        for (let i = 1; i < parts.length; i++) {
            ancestors.push(parts.slice(0, i).join('.'));
        }

        // Cap visible ancestors: show first, "... N more", last
        const MAX_VISIBLE = 3;
        let visible = ancestors;
        let collapsed = 0;
        if (ancestors.length > MAX_VISIBLE) {
            visible = [ancestors[0], ...ancestors.slice(-(MAX_VISIBLE - 1))];
            collapsed = ancestors.length - MAX_VISIBLE;
        }

        // Re-render ancestor resolved HTML in compact mode so we always
        // get simple .pu-wc-text-value spans regardless of current visualizer.
        const savedViz = PU.state.previewMode.visualizer;
        PU.state.previewMode.visualizer = 'compact';

        let html = '';
        visible.forEach((ancestorPath, i) => {
            // Insert collapsed indicator after first ancestor
            if (i === 1 && collapsed > 0) {
                html += `<span class="pu-ctx-collapsed">\u22EF ${collapsed} more \u22EF</span> `;
            }

            const res = resolutions.get(ancestorPath);
            if (!res) return;

            // Re-render from marker text in compact mode, then convert to context pills
            const compactHtml = res.resolvedMarkerText
                ? PU.blocks.renderResolvedTextWithDropdowns(res.resolvedMarkerText, res.wildcardDropdowns, ancestorPath)
                : res.resolvedHtml;

            html += PU.focus._renderContextBlock(compactHtml);

            // Separator between ancestors (space for sentence flow)
            if (i < visible.length - 1) {
                html += ' ';
            }
        });

        PU.state.previewMode.visualizer = savedViz;

        return html;
    },

    /**
     * Render a single ancestor block's compact HTML as an inline context block.
     * Keeps standard .pu-wc-text-value dropdown spans as-is.
     */
    _renderContextBlock(compactHtml) {
        if (!compactHtml) return '';
        return `<span class="pu-ctx-block">${compactHtml}</span>`;
    },

    // --- Focus Output Footer (multi-variation resolved output) ---

    _outputTimer: null,
    _outputCurrentOutputs: null,
    _outputFilters: {},      // Focus-specific filter state {dim: Set(values)}
    _outputCollapsed: false,
    _outputExpanded: false,
    _outputLabelMode: null,  // null = inherit from main editor

    // Session-global Include toggle (persist across block switches)
    _includeChildren: true,

    /**
     * Toggle Include Children checkbox. Session-global.
     */
    toggleIncludeChildren(checked) {
        PU.focus._includeChildren = checked;
        PU.focus._refreshAfterIncludeChange();
    },

    /**
     * Re-compute and re-render output after an Include toggle change.
     */
    _refreshAfterIncludeChange() {
        const state = PU.state.focusMode;
        if (!state.active || !state.quillInstance) return;
        const plainText = PU.quill.serialize(state.quillInstance);
        if (PU.focus._outputExpanded) {
            PU.focus._populateFocusOutput(plainText, state.blockPath);
        } else {
            const counters = PU.focus._computeFocusCounters(plainText, state.blockPath);
            PU.focus._renderFocusCounter(counters);
        }
    },

    /**
     * Sync Include checkbox DOM state with JS state.
     * Called on enter() and when rendering output.
     */
    _syncIncludeCheckboxes(path) {
        const childrenCb = document.querySelector('[data-testid="pu-focus-include-children"]');

        if (childrenCb) {
            const prompt = PU.helpers.getActivePrompt();
            const block = prompt ? PU.blocks.findBlockByPath(prompt.text || [], path) : null;
            const hasChildren = block && block.after && block.after.length > 0;

            if (hasChildren) {
                childrenCb.disabled = false;
                childrenCb.checked = PU.focus._includeChildren;
            } else {
                childrenCb.disabled = true;
                childrenCb.checked = false;
            }
        }
    },

    /**
     * Collect leaf paths from a subtree rooted at the given block.
     * Mirrors preview.js:collectLeaves — recursively walks .after arrays.
     * @param {Object} block - Block object with optional .after array
     * @param {string} path - Path string for this block (e.g. "0.0")
     * @returns {string[]} Array of leaf path strings
     */
    _collectSubtreeLeaves(block, path) {
        const leaves = [];
        if (block.after && block.after.length > 0) {
            block.after.forEach((child, idx) => {
                const childPath = `${path}.${idx}`;
                leaves.push(...PU.focus._collectSubtreeLeaves(child, childPath));
            });
        } else {
            leaves.push(path);
        }
        return leaves;
    },

    /**
     * Build accumulated raw content from root ancestors down to the focused block.
     * Returns concatenated text with __wildcard__ notation preserved.
     */
    _buildAccumulatedRaw(currentContent, path) {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text)) return currentContent || '';

        const parts = path.split('.');
        let accumulated = '';

        // Walk from root to parent, collecting ancestor content
        for (let depth = 0; depth < parts.length; depth++) {
            const subPath = parts.slice(0, depth + 1).join('.');
            const block = PU.blocks.findBlockByPath(prompt.text, subPath);
            if (!block) continue;

            let blockContent = '';
            if (subPath === path) {
                blockContent = currentContent || '';
            } else if ('content' in block) {
                blockContent = block.content || '';
            }
            // Skip ext_text ancestors (we only accumulate content blocks)

            if (blockContent) {
                accumulated = PU.focus._smartJoin(accumulated, blockContent);
            }
        }

        return accumulated;
    },

    /**
     * Build accumulated raw text from root ancestors through the focused block
     * and then continuing down to a specific leaf path below the focused block.
     * @param {string} currentContent - Live editor content for the focused block
     * @param {string} focusPath - Path of the focused block (e.g. "0.0")
     * @param {string} leafPath - Path of a leaf descendant (e.g. "0.0.1.0")
     * @returns {string} Full accumulated raw text with __wildcard__ notation
     */
    _buildLeafAccumulatedRaw(currentContent, focusPath, leafPath) {
        // Part 1: ancestors + focused block
        let accumulated = PU.focus._buildAccumulatedRaw(currentContent, focusPath);

        // Part 2: walk from focusPath down to leafPath
        if (leafPath === focusPath) return accumulated;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text)) return accumulated;

        const focusParts = focusPath.split('.');
        const leafParts = leafPath.split('.');

        // Walk each depth level below the focused block
        for (let depth = focusParts.length + 1; depth <= leafParts.length; depth++) {
            const subPath = leafParts.slice(0, depth).join('.');
            const block = PU.blocks.findBlockByPath(prompt.text, subPath);
            if (!block) continue;

            let blockContent = '';
            if ('content' in block) {
                blockContent = block.content || '';
            }

            if (blockContent) {
                accumulated = PU.focus._smartJoin(accumulated, blockContent);
            }
        }

        return accumulated;
    },

    /**
     * Intelligently join two text segments (mirrors preview.js smartJoin).
     */
    _smartJoin(parent, child) {
        if (!parent) return child;
        if (!child) return parent;
        const seps = [',', ' ', '\n', '\t'];
        if (seps.some(s => parent.trimEnd().endsWith(s)) || seps.some(s => child.trimStart().startsWith(s)))
            return parent + child;
        return parent.trimEnd() + ' ' + child.trimStart();
    },

    /**
     * Lightweight counter computation — only counts, never resolves text.
     * Returns { leafCount, totalCompositions, wildcardCount, wcNames }.
     */
    _computeFocusCounters(currentContent, path) {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text)) return { leafCount: 0, totalCompositions: 0, wildcardCount: 0, wcNames: [] };

        const focusBlock = PU.blocks.findBlockByPath(prompt.text, path);

        // Get leaf paths — respect Include Children toggle
        let leafPaths;
        if (!PU.focus._includeChildren || !focusBlock || !focusBlock.after || focusBlock.after.length === 0) {
            leafPaths = [path];
        } else {
            leafPaths = PU.focus._collectSubtreeLeaves(focusBlock, path);
        }

        // Build accumulated raw text for each leaf to scan for wildcards
        const wildcardLookup = PU.helpers.getWildcardLookup();
        const seenWc = new Set();
        const wcNames = [];

        let nonEmptyLeafCount = 0;
        for (const lp of leafPaths) {
            const raw = PU.focus._buildLeafAccumulatedRaw(currentContent, path, lp);
            if (!raw.trim()) continue; // Skip empty leaves
            nonEmptyLeafCount++;
            const matches = raw.match(/__([a-zA-Z0-9_-]+)__/g) || [];
            for (const m of matches) {
                const name = m.replace(/__/g, '');
                if (!seenWc.has(name) && wildcardLookup[name] && wildcardLookup[name].length > 0) {
                    seenWc.add(name);
                    wcNames.push(name);
                }
            }
        }

        const wildcardCounts = {};
        for (const name of wcNames) {
            wildcardCounts[name] = wildcardLookup[name].length;
        }

        const totalCompositions = wcNames.length > 0
            ? PU.preview.computeTotalCompositions(1, wildcardCounts) * nonEmptyLeafCount
            : nonEmptyLeafCount;

        return {
            leafCount: nonEmptyLeafCount,
            totalCompositions,
            wildcardCount: wcNames.length,
            wcNames
        };
    },

    /**
     * Render the counter summary line into the output list.
     * Hides header controls and shows a clickable expand link.
     */
    _renderFocusCounter(counters) {
        const footer = document.querySelector('[data-testid="pu-focus-output"]');
        if (!footer) return;

        footer.style.display = '';
        footer.classList.remove('pu-focus-output-state-empty', 'collapsed');
        footer.classList.add('pu-focus-output-state-counter');

        // Keep Include checkboxes in sync
        const state = PU.state.focusMode;
        if (state.active && state.blockPath) PU.focus._syncIncludeCheckboxes(state.blockPath);

        const outputList = footer.querySelector('[data-testid="pu-focus-output-list"]');
        const countEl = footer.querySelector('[data-testid="pu-focus-output-count"]');
        const filterBadge = footer.querySelector('[data-testid="pu-focus-filter-badge"]');
        const labelToggle = footer.querySelector('[data-testid="pu-focus-label-toggle"]');
        const copyBtn = footer.querySelector('[data-testid="pu-focus-output-copy"]');
        const chevron = footer.querySelector('[data-testid="pu-focus-output-chevron"]');

        // Hide header controls in counter mode
        if (countEl) countEl.textContent = '';
        if (filterBadge) filterBadge.style.display = 'none';
        if (labelToggle) labelToggle.style.display = 'none';
        if (copyBtn) copyBtn.style.display = 'none';
        if (chevron) chevron.style.display = 'none';
        PU.focus._renderFocusFilterTree([]);

        // Build summary text
        const parts = [];
        parts.push(`${counters.totalCompositions} resolved prompt${counters.totalCompositions !== 1 ? 's' : ''}`);
        if (counters.wildcardCount > 0) {
            parts.push(`${counters.wildcardCount} wildcard${counters.wildcardCount !== 1 ? 's' : ''}`);
        }

        if (outputList) {
            const link = counters.totalCompositions > 0
                ? `<a class="pu-focus-counter-link" onclick="PU.focus.expandOutput()">See resolved prompts \u25B6</a>`
                : '';
            outputList.innerHTML = `<div class="pu-focus-output-counter"><span class="pu-focus-counter-text">${parts.join(' \u00B7 ')}</span>${link}</div>`;
        }

        PU.focus._outputCurrentOutputs = null;
    },

    /**
     * Expand from counter to full resolved output.
     * Click handler for "See resolved prompts" link.
     */
    expandOutput() {
        PU.focus._outputExpanded = true;
        const state = PU.state.focusMode;
        if (!state.active || !state.quillInstance) return;
        const plainText = PU.quill.serialize(state.quillInstance);
        PU.focus._populateFocusOutput(plainText, state.blockPath);
    },

    /**
     * Router that determines which output state to render.
     * Replaces direct _populateFocusOutput calls in the debounce path.
     */
    _updateFocusOutputState(content, path) {
        if (PU.focus._outputExpanded) {
            PU.focus._populateFocusOutput(content || '', path);
            return;
        }
        // Counter state — always compute real counts (works for empty content too)
        const counters = PU.focus._computeFocusCounters(content || '', path);
        PU.focus._renderFocusCounter(counters);
    },

    /**
     * Compute multi-variation outputs for the focused block's subtree.
     * Collects leaf paths under the focused block, builds accumulated text
     * for each leaf path, and resolves wildcards for sampled compositions.
     */
    _computeFocusOutputs(currentContent, path, maxSamples = 20) {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text)) return { outputs: [], total: 0 };

        const focusBlock = PU.blocks.findBlockByPath(prompt.text, path);

        // Get leaf paths — respect Include Children toggle
        let leafPaths;
        if (!PU.focus._includeChildren || !focusBlock || !focusBlock.after || focusBlock.after.length === 0) {
            leafPaths = [path];
        } else {
            leafPaths = PU.focus._collectSubtreeLeaves(focusBlock, path);
        }

        // Build accumulated raw text for each leaf path (always includes parent)
        const leafTexts = [];

        for (const lp of leafPaths) {
            const raw = PU.focus._buildLeafAccumulatedRaw(currentContent, path, lp);
            if (raw.trim()) {
                leafTexts.push({ leafPath: lp, raw });
            }
        }

        if (leafTexts.length === 0) return { outputs: [], total: 0 };

        // Ancestor-only raw text (focused block contributes nothing)
        const parentRaw = PU.focus._buildAccumulatedRaw('', path);
        // Ancestors + focused block (no children) — for 3-zone segment rendering
        const selfRaw = PU.focus._buildAccumulatedRaw(currentContent, path);

        const wildcardLookup = PU.helpers.getWildcardLookup();

        // Collect wildcard names across ALL leaf accumulated texts (union)
        const seenWc = new Set();
        const wcNames = [];
        for (const lt of leafTexts) {
            const matches = lt.raw.match(/__([a-zA-Z0-9_-]+)__/g) || [];
            for (const m of matches) {
                const name = m.replace(/__/g, '');
                if (!seenWc.has(name) && wildcardLookup[name] && wildcardLookup[name].length > 0) {
                    seenWc.add(name);
                    wcNames.push(name);
                }
            }
        }

        const wildcardCounts = {};
        for (const name of wcNames) {
            wildcardCounts[name] = wildcardLookup[name].length;
        }

        const total = PU.preview.computeTotalCompositions(1, wildcardCounts);

        if (total <= 0 || wcNames.length === 0) {
            // No wildcards — one output per leaf path with plain text
            return {
                outputs: leafTexts.map((lt, i) => ({
                    label: String(i),
                    wcDetails: null,
                    text: lt.raw,
                    parentText: parentRaw || '',
                    selfText: selfRaw || ''
                })),
                total: leafTexts.length
            };
        }

        const currentId = PU.state.previewMode.compositionId || 0;
        const sampleIds = PU.preview.sampleCompositionIds(total, maxSamples, currentId);

        // Sort wildcard names alphabetically for consistent label ordering
        const orderedWcNames = [...wcNames].sort();

        const allOutputTexts = new Set();
        const allOutputs = [];
        const MAX_UNIQUE = 50;

        for (const compId of sampleIds) {
            if (allOutputs.length >= MAX_UNIQUE) break;

            const [, compWcIndices] = PU.preview.compositionToIndices(compId, 1, wildcardCounts);

            for (const lt of leafTexts) {
                if (allOutputs.length >= MAX_UNIQUE) break;

                // Build label and wcDetails
                const idxParts = orderedWcNames.map(n => compWcIndices[n]);
                const leafSuffix = leafTexts.length > 1 ? `:${lt.leafPath}` : '';
                const versionLabel = idxParts.join('.') + leafSuffix;
                const wcDetails = orderedWcNames.map(n => ({
                    name: n,
                    value: wildcardLookup[n][compWcIndices[n] % wildcardLookup[n].length]
                }));

                // Resolve wildcards in this leaf's accumulated text
                const resolveWc = (raw) => raw.replace(/__([a-zA-Z0-9_-]+)__/g, (match, wcName) => {
                    const values = wildcardLookup[wcName];
                    if (values && values.length > 0) {
                        const idx = compWcIndices[wcName] !== undefined ? compWcIndices[wcName] : 0;
                        return values[idx % values.length];
                    }
                    return match;
                });
                const resolved = resolveWc(lt.raw);
                const resolvedParent = parentRaw ? resolveWc(parentRaw) : '';
                const resolvedSelf = selfRaw ? resolveWc(selfRaw) : '';

                if (!allOutputTexts.has(resolved)) {
                    allOutputTexts.add(resolved);
                    allOutputs.push({
                        label: versionLabel,
                        wcDetails: wcDetails,
                        text: resolved,
                        parentText: resolvedParent,
                        selfText: resolvedSelf
                    });
                }
            }
        }

        return { outputs: allOutputs, total: total * leafTexts.length };
    },

    /**
     * Populate the focus output footer with multi-variation resolved outputs.
     * Three visual states:
     *   Empty: no content → instructional text, no header controls
     *   Single: content but no wildcards → one output item, minimal header
     *   Multi: content with wildcards → full output list + filter tree + all controls
     */
    _populateFocusOutput(content, path) {
        const footer = document.querySelector('[data-testid="pu-focus-output"]');
        if (!footer) return;

        // Always visible — never display:none
        footer.style.display = '';

        // Keep Include checkboxes in sync
        PU.focus._syncIncludeCheckboxes(path);

        const outputList = footer.querySelector('[data-testid="pu-focus-output-list"]');
        const countEl = footer.querySelector('[data-testid="pu-focus-output-count"]');
        const filterBadge = footer.querySelector('[data-testid="pu-focus-filter-badge"]');
        const labelToggle = footer.querySelector('[data-testid="pu-focus-label-toggle"]');
        const copyBtn = footer.querySelector('[data-testid="pu-focus-output-copy"]');
        const chevron = footer.querySelector('[data-testid="pu-focus-output-chevron"]');

        // --- Expanded mode ---
        footer.classList.remove('pu-focus-output-state-empty', 'pu-focus-output-state-counter');
        if (labelToggle) labelToggle.style.display = '';
        if (copyBtn) copyBtn.style.display = '';
        if (chevron) chevron.style.display = '';

        const { outputs, total } = PU.focus._computeFocusOutputs(content || '', path);
        if (outputs.length === 0) {
            PU.focus._outputCurrentOutputs = null;
            if (countEl) countEl.textContent = '(0 total)';
            if (filterBadge) filterBadge.style.display = 'none';
            PU.focus._renderFocusFilterTree([]);
            if (outputList) outputList.innerHTML = '<div class="pu-focus-output-empty-msg">No resolved prompts for the current selection.</div>';
            PU.focus._applyFocusLabelMode();
            if (PU.focus._outputCollapsed) footer.classList.add('collapsed');
            else footer.classList.remove('collapsed');
            return;
        }

        PU.focus._outputCurrentOutputs = outputs;

        // Render filter tree
        PU.focus._renderFocusFilterTree(outputs);

        // Apply filters
        const af = PU.focus._outputFilters;
        const hasFilters = Object.values(af).some(s => s && s.size > 0);
        let visibleOutputs = outputs;
        if (hasFilters) {
            visibleOutputs = outputs.filter(o => PU.focus._isFocusOutputVisible(o));
        }

        // Update count badge
        if (countEl) {
            if (outputs.length > 0) {
                countEl.textContent = hasFilters
                    ? `(${visibleOutputs.length} / ${outputs.length} of ${total})`
                    : `(${outputs.length} of ${total} total)`;
            } else {
                countEl.textContent = '';
            }
        }

        // Update filter badge
        if (filterBadge) {
            if (hasFilters) {
                const n = Object.values(af).reduce((s, set) => s + (set ? set.size : 0), 0);
                filterBadge.textContent = `${n} filter${n > 1 ? 's' : ''}`;
                filterBadge.style.display = '';
            } else {
                filterBadge.style.display = 'none';
            }
        }

        // Render output list (with parent text prefix in gray)
        if (outputList) {
            outputList.innerHTML = visibleOutputs.map((out, idx) =>
                PU.focus._renderFocusOutputItem(out, idx)
            ).join('');
        }

        // Apply label mode
        PU.focus._applyFocusLabelMode();

        // Restore collapse state
        if (PU.focus._outputCollapsed) {
            footer.classList.add('collapsed');
        } else {
            footer.classList.remove('collapsed');
        }
    },

    /**
     * Render focus filter tree (mirrors editor._renderFilterTree).
     */
    _renderFocusFilterTree(outputs) {
        const treeScroll = document.querySelector('[data-testid="pu-focus-filter-scroll"]');
        const treePanel = document.querySelector('[data-testid="pu-focus-filter-tree"]');
        const resetBtn = document.querySelector('[data-testid="pu-focus-filter-reset"]');
        if (!treeScroll || !treePanel) return;

        // Get free wildcard names (all of them in focus — no pins)
        const freeNames = PU.focus._getFocusFreeWcNames(outputs);
        if (outputs.length <= 1 || freeNames.length === 0) {
            treePanel.style.display = 'none';
            return;
        }

        treePanel.style.display = 'flex';
        const af = PU.focus._outputFilters;
        const dimValues = PU.editor._buildDimValues(outputs);

        let html = '';
        for (const dim of freeNames) {
            const values = dimValues[dim] || [];
            if (values.length === 0) continue;
            const normalizedDim = PU.preview.normalizeWildcardName(dim);
            const dimAttr = PU.blocks.escapeAttr(dim);

            html += `<div class="pu-filter-dim"><div class="pu-filter-dim-header" onclick="PU.focus.toggleFilterDim('${dimAttr}')"><span class="pu-filter-dim-chevron">&#9654;</span>${PU.blocks.escapeHtml(normalizedDim)}</div><div class="pu-filter-dim-values" style="max-height:300px">`;

            const counts = values.map(v => PU.focus._countFocusFilterMatches(outputs, dim, v));
            const mx = Math.max(...counts, 1);

            values.forEach((val, i) => {
                const dimSet = af[dim];
                const act = dimSet && dimSet.has(val);
                const c = counts[i];
                const pct = Math.round((c / mx) * 100);
                const valAttr = PU.blocks.escapeAttr(val);

                html += `<div class="pu-filter-value ${act ? 'active' : ''}" onclick="PU.focus.toggleFilter('${dimAttr}','${valAttr}')"><span class="pu-filter-dot"></span><span class="pu-filter-value-name">${PU.blocks.escapeHtml(val)}</span><span class="pu-filter-value-bar-track"><span class="pu-filter-value-bar-dash"></span><span class="pu-filter-value-bar-fill ${c === 0 ? 'zero' : ''}" style="width:${pct}%"></span></span><span class="pu-filter-value-count">${c}</span></div>`;
            });
            html += '</div></div>';
        }
        treeScroll.innerHTML = html;

        const hasFilters = Object.values(af).some(s => s && s.size > 0);
        if (resetBtn) {
            resetBtn.style.display = hasFilters ? 'flex' : 'none';
            resetBtn.closest('.pu-filter-tree-footer')?.classList.toggle('pu-hidden', !hasFilters);
        }
    },

    _getFocusFreeWcNames(outputs) {
        if (!outputs || outputs.length === 0) return [];
        const first = outputs[0];
        if (!first.wcDetails || first.wcDetails.length === 0) return [];
        return first.wcDetails.map(d => d.name);
    },

    _isFocusOutputVisible(out) {
        const af = PU.focus._outputFilters;
        if (!out.wcDetails) return true;
        for (const d of Object.keys(af)) {
            const set = af[d];
            if (!set || set.size === 0) continue;
            const detail = out.wcDetails.find(wd => wd.name === d);
            const val = detail ? detail.value : null;
            if (!set.has(val)) return false;
        }
        return true;
    },

    _countFocusFilterMatches(outputs, dim, val) {
        const af = PU.focus._outputFilters;
        return outputs.filter(o => {
            if (!o.wcDetails) return false;
            for (const d of Object.keys(af)) {
                const set = af[d];
                if (!set || set.size === 0) continue;
                const detail = o.wcDetails.find(wd => wd.name === d);
                const ov = detail ? detail.value : null;
                if (d === dim) {
                    if (ov !== val) return false;
                } else {
                    if (!set.has(ov)) return false;
                }
            }
            const detail = o.wcDetails.find(wd => wd.name === dim);
            return detail && detail.value === val;
        }).length;
    },

    /**
     * Apply label mode to focus output footer.
     */
    _applyFocusLabelMode() {
        const footer = document.querySelector('[data-testid="pu-focus-output"]');
        if (!footer) return;
        const mode = PU.focus._outputLabelMode || PU.state.ui.outputLabelMode || 'none';
        footer.classList.remove('label-none', 'label-hybrid', 'label-inline');
        footer.classList.add('label-' + mode);
        const btn = footer.querySelector('[data-testid="pu-focus-label-toggle"]');
        if (btn) {
            const icons = { none: '\u2012', hybrid: '#', inline: 'Aa' };
            btn.textContent = icons[mode] || '\u2012';
            btn.title = 'Label mode: ' + mode;
        }
    },

    /**
     * Render a focus output item with 3-zone segment tints:
     * parent (gray), self/this-block (warm tint), children (cool tint).
     */
    _renderFocusOutputItem(out, idx) {
        // Build label HTML (same as editor._renderOutputItem)
        let labelHtml;
        if (out.wcDetails && out.wcDetails.length > 0) {
            const expandedParts = out.wcDetails.map(d =>
                `<span class="pu-label-wc-name">${PU.blocks.escapeHtml(d.name)}</span><span class="pu-label-wc-eq">=</span><span class="pu-label-wc-val">${PU.blocks.escapeHtml(d.value)}</span>`
            ).join('<span class="pu-label-wc-sep">\u00B7</span>');
            const inlineValues = out.wcDetails.map(d =>
                `<span class="pu-label-value">${PU.blocks.escapeHtml(d.value)}</span>`
            ).join('<span class="pu-label-sep">\u00B7</span>');
            const tooltipText = out.wcDetails.map(d => `${d.name}=${d.value}`).join(', ');
            labelHtml = `<span class="pu-label-compact">${PU.blocks.escapeHtml(out.label)}</span><span class="pu-label-expanded">${expandedParts}</span><span class="pu-label-inline">${inlineValues}<span class="pu-output-item-help" title="${PU.blocks.escapeHtml(tooltipText)}">?</span></span>`;
        } else {
            labelHtml = PU.blocks.escapeHtml(out.label);
        }

        // Split text into 3 segments: parent (ancestors), self (focused block), child (descendants)
        let textHtml;
        const parentText = out.parentText || '';
        const selfText = out.selfText || '';
        const fullText = out.text || '';

        // Find parent boundary in fullText
        let parentEnd = 0;
        if (parentText) {
            if (fullText.startsWith(parentText)) {
                parentEnd = parentText.length;
            } else {
                // smartJoin may have trimmed — try trimmed match
                const trimmed = parentText.trimEnd();
                if (trimmed && fullText.startsWith(trimmed)) {
                    parentEnd = trimmed.length;
                }
            }
        }

        // Find self boundary in fullText
        let selfEnd = parentEnd;
        if (selfText) {
            if (fullText.startsWith(selfText)) {
                selfEnd = selfText.length;
            } else {
                const trimmed = selfText.trimEnd();
                if (trimmed && fullText.startsWith(trimmed)) {
                    selfEnd = trimmed.length;
                }
            }
        }

        const parentSegment = fullText.slice(0, parentEnd);
        const selfSegment = fullText.slice(parentEnd, selfEnd);
        const childSegment = fullText.slice(selfEnd);

        let parts = '';
        if (parentSegment) parts += `<span class="pu-seg-parent">${PU.blocks.escapeHtml(parentSegment)}</span>`;
        if (selfSegment) parts += `<span class="pu-seg-self">${PU.blocks.escapeHtml(selfSegment)}</span>`;
        if (childSegment) parts += `<span class="pu-seg-child">${PU.blocks.escapeHtml(childSegment)}</span>`;
        textHtml = parts || PU.blocks.escapeHtml(fullText);

        return `<div class="pu-output-item" data-testid="pu-output-item-${idx}">
            <span class="pu-output-item-label">${labelHtml}</span>
            <div class="pu-output-item-text">${textHtml}</div>
        </div>`;
    },

    // --- Focus Output Actions (called from HTML onclick) ---

    toggleOutput() {
        const footer = document.querySelector('[data-testid="pu-focus-output"]');
        if (!footer) return;
        // In counter mode, clicking header expands to full output
        if (footer.classList.contains('pu-focus-output-state-counter')) {
            PU.focus.expandOutput();
            return;
        }
        PU.focus._outputCollapsed = !PU.focus._outputCollapsed;
        footer.classList.toggle('collapsed');
    },

    cycleLabelMode() {
        const modes = ['none', 'hybrid', 'inline'];
        const current = PU.focus._outputLabelMode || PU.state.ui.outputLabelMode || 'none';
        const idx = modes.indexOf(current);
        PU.focus._outputLabelMode = modes[(idx + 1) % modes.length];
        PU.focus._applyFocusLabelMode();
    },

    copyOutput() {
        const btn = document.querySelector('[data-testid="pu-focus-output-copy"]');
        const footer = document.querySelector('[data-testid="pu-focus-output"]');
        if (!footer) return;
        const items = footer.querySelectorAll('.pu-output-item-text');
        const texts = [...items].map(el => el.textContent.trim()).filter(Boolean);
        if (texts.length === 0) return;
        try { navigator.clipboard.writeText(texts.join('\n\n---\n\n')); } catch (e) { /* */ }
        PU.actions._showCopiedFeedback(btn);
    },

    toggleFilter(dim, val) {
        const af = PU.focus._outputFilters;
        if (!af[dim]) af[dim] = new Set();
        if (af[dim].has(val)) {
            af[dim].delete(val);
            if (af[dim].size === 0) delete af[dim];
        } else {
            af[dim].add(val);
        }
        // Re-render with current cached content
        PU.focus._refreshFocusOutput();
    },

    toggleFilterDim(dim) {
        // Toggle collapse of a filter dimension group
        const panel = document.querySelector(`[data-testid="pu-focus-filter-scroll"]`);
        if (!panel) return;
        const headers = panel.querySelectorAll('.pu-filter-dim-header');
        for (const h of headers) {
            if (h.textContent.includes(PU.preview.normalizeWildcardName(dim))) {
                const valuesEl = h.nextElementSibling;
                const chevron = h.querySelector('.pu-filter-dim-chevron');
                if (valuesEl) valuesEl.classList.toggle('collapsed');
                if (chevron) chevron.classList.toggle('collapsed');
            }
        }
    },

    resetFilters() {
        PU.focus._outputFilters = {};
        PU.focus._refreshFocusOutput();
    },

    /**
     * Refresh focus output using current quill content (for filter changes).
     */
    _refreshFocusOutput() {
        const state = PU.state.focusMode;
        if (!state.active || !state.quillInstance) return;
        if (!PU.focus._outputExpanded) return;  // Filters only apply in expanded mode
        const plainText = PU.quill.serialize(state.quillInstance);
        PU.focus._populateFocusOutput(plainText, state.blockPath);
    },

    /**
     * Debounced version of _populateFocusOutput for text-change events.
     */
    _debouncedPopulateFocusOutput(content, path) {
        clearTimeout(PU.focus._outputTimer);
        PU.focus._outputTimer = setTimeout(() => {
            if (PU.focus._outputExpanded) {
                PU.focus._outputExpanded = false;  // Content changed → stale
            }
            PU.focus._updateFocusOutputState(content, path);
        }, 250);
    },

    /**
     * Handle overlay click — refocus editor instead of closing.
     * Overlay can only be closed via the X button or Escape key.
     */
    handleOverlayClick(event) {
        const state = PU.state.focusMode;
        if (state.active && state.quillInstance) {
            state.quillInstance.focus();
        }
    }
};

// Register focus mode as a modal overlay
PU.overlay.registerModal('focus', () => PU.focus.exit());
