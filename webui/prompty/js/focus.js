/**
 * PromptyUI - Focus Mode
 *
 * Zen editing overlay: clicking into a content block covers the background
 * with an overlay showing the focused block's Quill editor.
 */

PU.focus = {
    /**
     * Enter focus mode for a block at the given path.
     */
    enter(path) {
        const state = PU.state.focusMode;

        // Guard: already active
        if (state.active) return;

        // Guard: debounce rapid entry (300ms)
        if (Date.now() - state.enterTimestamp < 300) return;

        // Guard: preview mode active
        if (PU.state.previewMode.active) return;

        // Guard: must have a prompt
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return;

        // Guard: block must exist and be a content block (not ext_text)
        const block = PU.blocks.findBlockByPath(prompt.text || [], path);
        if (!block || !('content' in block)) return;

        // Set state
        state.active = true;
        state.blockPath = path;
        state.enterTimestamp = Date.now();

        // Hide floating preview
        PU.preview.hide();

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
        const content = block.content || '';
        PU.focus.createQuill(quillContainer, path, content);

        // Focus the Quill editor
        if (state.quillInstance) {
            state.quillInstance.focus();
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

        // Serialize focus Quill to plain text and sync back
        if (state.quillInstance) {
            const text = PU.quill.serialize(state.quillInstance);
            PU.editor.updateBlockContent(path, text);

            // Destroy focus Quill
            state.quillInstance.disable();
            state.quillInstance = null;
        }

        // Clear container
        const quillContainer = document.querySelector('[data-testid="pu-focus-quill"]');
        if (quillContainer) {
            quillContainer.innerHTML = '';
        }

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

        // Re-render blocks to refresh original Quills
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
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
            placeholder: 'Enter content... Use __name__ for wildcards'
        });

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
            const wcName = PU.quill.getAdjacentWildcardName(quill);
            if (wcName !== PU.state.preview.activeWildcard) {
                PU.state.preview.activeWildcard = wcName;
            }

            // Passive popover: show when cursor is adjacent to a wildcard chip
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

        // Keyboard handler for autocomplete + passive popover activation
        quill.root.addEventListener('keydown', (e) => {
            // Autocomplete takes priority
            if (PU.quill._autocompleteOpen) {
                PU.quill.handleAutocompleteKey(e);
                return;
            }
            // Tab activates passive popover
            if (e.key === 'Tab' && PU.wildcardPopover?._open && PU.wildcardPopover._passive) {
                e.preventDefault();
                e.stopPropagation();
                PU.wildcardPopover.activate();
                return;
            }
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

        // Update block state (without re-rendering blocks)
        const prompt = PU.editor.getModifiedPrompt();
        if (prompt) {
            const block = PU.blocks.findBlockByPath(prompt.text || [], path);
            if (block && 'content' in block) {
                block.content = plainText;
            }
        }

        // Check for autocomplete trigger
        const sel = quillInstance.getSelection();
        if (sel) {
            const textBefore = quillInstance.getText(0, sel.index);

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
     * wildcards using deterministic cycling seeded by compositionId.
     * Output uses {{name:value}} markers directly for the pill pipeline.
     */
    generateFocusedVariations(blockContent, activeWildcard) {
        const wcLookup = PU.helpers.getWildcardLookup();
        const activeValues = wcLookup[activeWildcard] || [];
        if (activeValues.length === 0) return [];

        const seed = PU.state.previewMode.compositionId || 99;

        return activeValues.map((activeVal, i) => {
            const markedText = blockContent.replace(/__([a-zA-Z0-9_-]+)__/g, (match, wcName) => {
                if (wcName === activeWildcard) {
                    return `{{${wcName}:${activeVal}}}`;
                }
                const values = wcLookup[wcName];
                if (values && values.length > 0) {
                    return `{{${wcName}:${values[(seed + i) % values.length]}}}`;
                }
                return match;
            });
            return { markedText, activeValue: activeVal };
        });
    },

    /**
     * Handle overlay click — exit if clicking the overlay background.
     */
    handleOverlayClick(event) {
        const overlay = document.querySelector('[data-testid="pu-focus-overlay"]');
        if (event.target === overlay) {
            PU.focus.exit();
        }
    }
};
