/**
 * PromptyUI - Focus Mode
 *
 * Zen editing overlay: clicking into a content block covers the background
 * with an overlay showing only the focused block's editor with a preview
 * panel below it in a vertical split.
 */

PU.focus = {
    // Debounce timer for preview updates inside focus mode
    _previewDebounceTimer: null,

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
        state.activeTab = 'variations';
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

        // Reset tab state
        PU.focus._resetTabs();

        // Create Quill editor in focus panel
        const content = block.content || '';
        PU.focus.createQuill(quillContainer, path, content);

        // Focus the Quill editor
        if (state.quillInstance) {
            state.quillInstance.focus();
        }

        // Load the Variations tab preview
        PU.focus.loadVariationsPreview();
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

        // Clear preview content
        const previewContent = document.querySelector('[data-testid="pu-focus-preview-content"]');
        if (previewContent) {
            previewContent.innerHTML = '';
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

        // Clear debounce timer
        if (PU.focus._previewDebounceTimer) {
            clearTimeout(PU.focus._previewDebounceTimer);
            PU.focus._previewDebounceTimer = null;
        }

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

        // Selection-change: track activeWildcard for pill highlighting
        quill.on('selection-change', (range, oldRange, source) => {
            if (!range) return;
            const wcName = PU.quill.getAdjacentWildcardName(quill);
            if (wcName !== PU.state.preview.activeWildcard) {
                PU.state.preview.activeWildcard = wcName;
                PU.focus.updateWildcardFocus();
            }
        });

        // Focus handler: does NOT call PU.focus.enter() again (prevents loop)
        // Blur handler: does NOT exit focus mode (only overlay click / Escape do)

        // Keyboard handler for autocomplete
        quill.root.addEventListener('keydown', (e) => {
            if (PU.quill._autocompleteOpen) {
                PU.quill.handleAutocompleteKey(e);
            }
        });

        // Store as transient instance (not in PU.quill.instances)
        PU.state.focusMode.quillInstance = quill;
        return quill;
    },

    /**
     * Handle text-change events from the focus Quill.
     * Serializes to plain text, updates block state, debounces preview reload.
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

        // Debounce preview reload
        PU.focus.debouncePreviewUpdate();
    },

    /**
     * Debounce preview update in focus mode.
     */
    debouncePreviewUpdate() {
        if (PU.focus._previewDebounceTimer) {
            clearTimeout(PU.focus._previewDebounceTimer);
        }

        PU.focus._previewDebounceTimer = setTimeout(() => {
            const state = PU.state.focusMode;
            if (!state.active) return;

            if (state.activeTab === 'variations') {
                PU.focus.loadVariationsPreview();
            } else {
                PU.focus.loadFullTextPreview();
            }
        }, 300);
    },

    /**
     * Switch between Variations and Full Text tabs.
     */
    switchTab(tabName) {
        const state = PU.state.focusMode;
        state.activeTab = tabName;

        // Toggle active class on tab buttons
        const tabBtns = document.querySelectorAll('.pu-focus-tab');
        tabBtns.forEach(btn => {
            btn.classList.toggle('active', btn.dataset.testid === `pu-focus-tab-${tabName}`);
        });

        // Load the appropriate preview
        if (tabName === 'variations') {
            PU.focus.loadVariationsPreview();
        } else {
            PU.focus.loadFullTextPreview();
        }
    },

    /**
     * Reset tab buttons to initial state (Variations active).
     */
    _resetTabs() {
        const tabBtns = document.querySelectorAll('.pu-focus-tab');
        tabBtns.forEach(btn => {
            btn.classList.toggle('active', btn.dataset.testid === 'pu-focus-tab-variations');
        });
    },

    /**
     * Load and render the Variations preview tab.
     * Uses the same pipeline as PU.preview.loadPreview() + PU.preview.render().
     */
    async loadVariationsPreview() {
        const state = PU.state.focusMode;
        if (!state.active) return;

        const path = state.blockPath;
        const contentEl = document.querySelector('[data-testid="pu-focus-preview-content"]');
        if (!contentEl) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            contentEl.innerHTML = '<div class="pu-preview-item" style="color: var(--pu-text-muted);">No prompt selected</div>';
            return;
        }

        const block = PU.blocks.findBlockByPath(prompt.text || [], path);
        if (!block) {
            contentEl.innerHTML = '<div class="pu-preview-item" style="color: var(--pu-text-muted);">Block not found</div>';
            return;
        }

        // Check if block has wildcards
        const blockContent = block.content || '';
        const wildcards = PU.blocks.detectWildcards(blockContent);

        if (wildcards.length === 0) {
            // No wildcards: show single static output
            contentEl.innerHTML = `
                <div class="pu-preview-item">
                    <span class="pu-preview-item-index">1.</span>
                    ${PU.blocks.escapeHtml(blockContent) || '<em style="color: var(--pu-text-muted);">Empty content</em>'}
                </div>
                <div style="padding: var(--pu-space-sm); color: var(--pu-text-muted); font-size: var(--pu-font-size-sm);">
                    Single static output (no wildcards)
                </div>`;
            return;
        }

        // Build API request
        const params = {
            job_id: PU.state.activeJobId,
            prompt_id: PU.state.activePromptId,
            wildcards: prompt.wildcards || [],
            include_nested: true,
            limit: 10
        };

        if ('content' in block) {
            params.text = [block];
        } else if ('ext_text' in block) {
            params.text = [block];
        }

        // Show loading state
        contentEl.innerHTML = '<div class="pu-loading">Loading preview...</div>';

        try {
            const data = await PU.api.previewVariations(params);
            const variations = data.variations || [];

            if (variations.length === 0) {
                contentEl.innerHTML = '<div class="pu-preview-item">No variations generated</div>';
                return;
            }

            contentEl.innerHTML = variations.map((v, idx) => {
                const marked = PU.preview.markWildcardValues(v.text, v.wildcard_values);
                const escaped = PU.preview.escapeHtmlPreservingMarkers(marked);
                const pillHtml = PU.preview.renderWildcardPills(escaped);
                return `
                    <div class="pu-preview-item" data-testid="pu-focus-preview-item-${idx}">
                        <span class="pu-preview-item-index">${idx + 1}.</span>
                        ${pillHtml}
                    </div>`;
            }).join('');

            // Apply wildcard focus highlighting
            PU.focus.updateWildcardFocus();

        } catch (e) {
            console.error('Focus mode: failed to load preview:', e);
            contentEl.innerHTML = `<div class="pu-preview-item" style="color: var(--pu-error);">Failed to load preview: ${PU.blocks.escapeHtml(e.message)}</div>`;
        }
    },

    /**
     * Load and render the Full Text preview tab.
     * Shows composed parent+block text with wildcard pills.
     */
    async loadFullTextPreview() {
        const state = PU.state.focusMode;
        if (!state.active) return;

        const path = state.blockPath;
        const contentEl = document.querySelector('[data-testid="pu-focus-preview-content"]');
        if (!contentEl) return;

        // Show loading state
        contentEl.innerHTML = '<div class="pu-loading">Building full text...</div>';

        try {
            // Build checkpoint data to get composed text
            const checkpoints = await PU.preview.buildCheckpointData();

            if (!checkpoints || checkpoints.length === 0) {
                contentEl.innerHTML = '<div class="pu-preview-item" style="color: var(--pu-text-muted);">No checkpoint data available</div>';
                return;
            }

            // Find the checkpoint that matches this block's path
            // Convert edit path (e.g. "0.1") to semantic path using generateNodeId
            const matchingCheckpoint = PU.focus.findCheckpointForEditPath(checkpoints, path);

            if (!matchingCheckpoint) {
                contentEl.innerHTML = '<div class="pu-preview-item" style="color: var(--pu-text-muted);">Could not find matching checkpoint for path: ' + PU.blocks.escapeHtml(path) + '</div>';
                return;
            }

            // Render base text (muted) + new text (primary/bold) with wildcard pills
            const baseText = matchingCheckpoint.baseText || '';
            const newText = matchingCheckpoint.newText || '';

            // Convert markers to pills
            const baseEscaped = PU.preview.escapeHtmlPreservingMarkers(baseText);
            const basePills = PU.preview.renderWildcardPills(baseEscaped);

            const newEscaped = PU.preview.escapeHtmlPreservingMarkers(newText);
            const newPills = PU.preview.renderWildcardPills(newEscaped);

            let html = '<div class="pu-focus-fulltext">';
            if (basePills) {
                html += `<span class="pu-text-base">${basePills} </span>`;
            }
            html += `<span class="pu-text-new">${newPills}</span>`;
            html += '</div>';

            // Show output path
            const outputPath = PU.preview.buildOutputPath(matchingCheckpoint);
            html += `<div style="margin-top: var(--pu-space-md); font-family: var(--pu-font-mono); font-size: var(--pu-font-size-xs); color: var(--pu-text-secondary); background: var(--pu-bg-primary); padding: 6px 10px; border-radius: var(--pu-radius); word-break: break-all;">Path: ${PU.blocks.escapeHtml(outputPath)}</div>`;

            contentEl.innerHTML = html;

        } catch (e) {
            console.error('Focus mode: failed to build full text:', e);
            contentEl.innerHTML = `<div class="pu-preview-item" style="color: var(--pu-error);">Failed to build full text: ${PU.blocks.escapeHtml(e.message)}</div>`;
        }
    },

    /**
     * Find the checkpoint matching an edit path (e.g. "0", "0.1").
     * Walks the prompt tree to map edit indices to semantic node IDs.
     */
    findCheckpointForEditPath(checkpoints, editPath) {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !prompt.text) return null;

        // Build semantic path by walking the tree using edit path indices
        const parts = editPath.split('.').map(p => parseInt(p, 10));
        let blocks = prompt.text;
        let semanticPath = '';

        for (let i = 0; i < parts.length; i++) {
            const idx = parts[i];
            if (!Array.isArray(blocks) || idx >= blocks.length) return null;

            const block = blocks[idx];
            const nodeId = PU.preview.generateNodeId(block, idx);
            semanticPath = semanticPath ? `${semanticPath}/${nodeId}` : nodeId;

            // Navigate into children for next iteration
            if (i < parts.length - 1) {
                blocks = block.after || [];
            }
        }

        // Find matching checkpoint
        return checkpoints.find(cp => cp.path === semanticPath) || null;
    },

    /**
     * Handle overlay click — exit if clicking the overlay background.
     */
    handleOverlayClick(event) {
        const overlay = document.querySelector('[data-testid="pu-focus-overlay"]');
        if (event.target === overlay) {
            PU.focus.exit();
        }
    },

    /**
     * Update wildcard focus highlighting in the focus preview panel.
     */
    updateWildcardFocus() {
        const contentEl = document.querySelector('[data-testid="pu-focus-preview-content"]');
        if (!contentEl) return;

        const activeWc = PU.state.preview.activeWildcard;

        if (activeWc) {
            contentEl.classList.add('pu-preview-wc-focus');
            contentEl.querySelectorAll('.pu-wc-pill').forEach(pill => {
                if (pill.getAttribute('data-wc-name') === activeWc) {
                    pill.classList.add('pu-wc-pill-active');
                } else {
                    pill.classList.remove('pu-wc-pill-active');
                }
            });
        } else {
            contentEl.classList.remove('pu-preview-wc-focus');
            contentEl.querySelectorAll('.pu-wc-pill').forEach(pill => {
                pill.classList.remove('pu-wc-pill-active');
            });
        }
    }
};
