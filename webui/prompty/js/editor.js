/**
 * PromptyUI - Editor
 *
 * Main editor panel for editing prompts and defaults.
 */

PU.editor = {
    // Debounce timer for preview updates
    previewDebounceTimer: null,

    /**
     * Show editor for a prompt
     */
    async showPrompt(jobId, promptId) {
        const emptyState = document.querySelector('[data-testid="pu-editor-empty"]');
        const content = document.querySelector('[data-testid="pu-editor-content"]');
        const previewMode = document.querySelector('[data-testid="pu-preview-mode"]');

        if (emptyState) emptyState.style.display = 'none';

        // Show editor or preview mode depending on state
        if (PU.state.previewMode.active) {
            if (content) content.style.display = 'none';
            if (previewMode) previewMode.style.display = 'flex';
        } else {
            if (content) content.style.display = 'flex';
            if (previewMode) previewMode.style.display = 'none';
        }

        // Update prompt title
        const titleEl = document.querySelector('[data-testid="pu-editor-title"]');
        if (titleEl) titleEl.textContent = promptId;

        // Update defaults toolbar
        PU.editor.updateDefaultsToolbar(jobId);

        // Render blocks
        PU.editor.renderBlocks(jobId, promptId);

        // If in preview mode, rebuild checkpoints for the new prompt
        if (PU.state.previewMode.active) {
            const checkpoints = await PU.preview.buildCheckpointData();
            PU.state.previewMode.checkpoints = checkpoints;
            PU.preview.renderCheckpointRows(checkpoints);
        }

        // Check for pending preview mode activation (from URL)
        if (PU.state.previewMode.pendingActivation) {
            PU.state.previewMode.pendingActivation = false;
            // enterPreviewMode is now async but we don't need to await here
            PU.preview.enterPreviewMode();
        }

        // Update preview mode button visibility
        PU.preview.updateModeButton();
    },

    /**
     * Show empty state
     */
    showEmptyState() {
        const emptyState = document.querySelector('[data-testid="pu-editor-empty"]');
        const content = document.querySelector('[data-testid="pu-editor-content"]');
        const previewMode = document.querySelector('[data-testid="pu-preview-mode"]');

        if (emptyState) emptyState.style.display = 'flex';
        if (content) content.style.display = 'none';
        if (previewMode) previewMode.style.display = 'none';

        // Exit preview mode if active and hide button
        PU.state.previewMode.active = false;
        PU.preview.updateModeButton();
    },

    /**
     * Update defaults toolbar
     */
    updateDefaultsToolbar(jobId) {
        const job = PU.helpers.getActiveJob();
        if (!job) return;

        const defaults = job.defaults || {};

        // Update ext dropdown
        const extSelect = document.querySelector('[data-testid="pu-defaults-ext"]');
        if (extSelect) {
            PU.editor.populateExtDropdown(extSelect, defaults.ext || 'defaults');
        }

        // Update ext_text_max
        const extTextMaxInput = document.querySelector('[data-testid="pu-defaults-ext-text-max"]');
        if (extTextMaxInput) {
            extTextMaxInput.value = defaults.ext_text_max || 0;
        }

        // Update ext_wildcards_max
        const extWildcardsMaxInput = document.querySelector('[data-testid="pu-defaults-ext-wildcards-max"]');
        if (extWildcardsMaxInput) {
            extWildcardsMaxInput.value = defaults.ext_wildcards_max || 0;
        }
    },

    /**
     * Populate ext dropdown with available extensions
     */
    populateExtDropdown(select, currentValue) {
        const tree = PU.state.globalExtensions.tree;

        // Get all folder paths from extension tree
        const folders = [];

        function collectFolders(node, path) {
            for (const [key, value] of Object.entries(node)) {
                if (key === '_files') continue;
                const folderPath = path ? `${path}/${key}` : key;
                folders.push(folderPath);
                collectFolders(value, folderPath);
            }
        }

        collectFolders(tree, '');

        // Build options
        select.innerHTML = folders.map(folder =>
            `<option value="${folder}" ${folder === currentValue ? 'selected' : ''}>${folder}</option>`
        ).join('') || '<option value="">No extensions found</option>';
    },

    /**
     * Render blocks for a prompt
     */
    renderBlocks(jobId, promptId) {
        const container = document.querySelector('[data-testid="pu-blocks-container"]');
        if (!container) return;

        // Destroy all Quill instances BEFORE innerHTML replacement
        if (PU.quill) PU.quill.destroyAll();

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            container.innerHTML = '<div class="pu-loading">No prompt data</div>';
            return;
        }

        const textItems = prompt.text || [];

        // Show fallback notice if Quill failed to load
        const fallbackNotice = (PU.quill && PU.quill._fallback)
            ? '<div class="pu-fallback-notice" data-testid="pu-fallback-notice">Rich editing unavailable &mdash; using basic editor</div>'
            : '';

        // Handle legacy string format
        if (typeof textItems === 'string') {
            container.innerHTML = fallbackNotice + PU.blocks.renderBlock({ content: textItems }, '0');
            if (PU.quill) PU.quill.initAll();
            return;
        }

        // Handle legacy string array format
        if (Array.isArray(textItems) && textItems.length > 0 && typeof textItems[0] === 'string') {
            container.innerHTML = fallbackNotice + textItems.map((text, idx) =>
                PU.blocks.renderBlock({ content: text }, String(idx))
            ).join('');
            if (PU.quill) PU.quill.initAll();
            return;
        }

        // Handle new nested format
        if (Array.isArray(textItems)) {
            container.innerHTML = fallbackNotice + textItems.map((item, idx) =>
                PU.blocks.renderBlock(item, String(idx))
            ).join('');

            if (textItems.length === 0) {
                container.innerHTML = '<div class="pu-inspector-empty">No content blocks. Click "+ Add Root Block" to start.</div>';
            }

            // Initialize all Quill editors AFTER rendering
            if (PU.quill) PU.quill.initAll();
            return;
        }

        container.innerHTML = '<div class="pu-loading">Unknown text format</div>';
    },

    /**
     * Get or create modified prompt
     */
    getModifiedPrompt() {
        const jobId = PU.state.activeJobId;
        const promptId = PU.state.activePromptId;

        if (!jobId || !promptId) return null;

        // Get or create modified job
        if (!PU.state.modifiedJobs[jobId]) {
            PU.state.modifiedJobs[jobId] = PU.helpers.deepClone(PU.state.jobs[jobId]);
        }

        const job = PU.state.modifiedJobs[jobId];
        const promptIndex = job.prompts.findIndex(p => p.id === promptId);

        if (promptIndex === -1) return null;

        return job.prompts[promptIndex];
    },

    /**
     * Update block content
     */
    updateBlockContent(path, content) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        // Ensure text is an array
        if (!Array.isArray(prompt.text)) {
            prompt.text = [];
        }

        // Always update block state (needed for preview API to read current content)
        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (block && 'content' in block) {
            block.content = content;
        }

        // Skip DOM updates if this update came from Quill's text-change
        // (Quill already manages its own editor DOM; only state + preview need updating)
        const fromQuill = PU.quill && PU.quill._updatingFromQuill === path;

        if (!fromQuill) {
            // Update inspector with wildcards
            const wildcards = PU.blocks.detectWildcards(content);
            PU.inspector.updateWildcardsContext(wildcards, prompt.wildcards || []);

            // Live update: refresh wildcard summary or chips depending on mode
            const pathId = path.replace(/\./g, '-');

            if (PU.quill && !PU.quill._fallback) {
                // Quill mode: update wildcard summary (conditionally render)
                let summaryEl = document.querySelector(`[data-testid="pu-content-wc-summary-${pathId}"]`);
                if (wildcards.length > 0) {
                    if (!summaryEl) {
                        // Create summary div next to the Quill editor
                        summaryEl = document.createElement('div');
                        summaryEl.className = 'pu-wc-summary';
                        summaryEl.dataset.testid = `pu-content-wc-summary-${pathId}`;
                        const quillEl = document.querySelector(`[data-testid="pu-block-input-${pathId}"]`);
                        if (quillEl) quillEl.insertAdjacentElement('afterend', summaryEl);
                    }
                    summaryEl.innerHTML = PU.blocks.renderWildcardSummary(wildcards);
                } else if (summaryEl) {
                    summaryEl.remove();
                }
            } else {
                // Fallback textarea mode: toggle accent class and refresh chips
                const textarea = document.querySelector(`[data-testid="pu-block-input-${pathId}"]`);
                if (textarea) {
                    textarea.classList.toggle('pu-content-has-wildcards', wildcards.length > 0);
                }

                const wcContainer = document.querySelector(`[data-testid="pu-content-wildcards-${pathId}"]`);
                if (wildcards.length > 0) {
                    const wildcardLookup = PU.helpers.getWildcardLookup();
                    const chipsHtml = PU.blocks.renderWildcardChips(wildcards, wildcardLookup);
                    if (wcContainer) {
                        wcContainer.innerHTML = chipsHtml;
                    } else {
                        const newContainer = document.createElement('div');
                        newContainer.className = 'pu-content-wildcards';
                        newContainer.dataset.testid = `pu-content-wildcards-${pathId}`;
                        newContainer.innerHTML = chipsHtml;
                        if (textarea) textarea.insertAdjacentElement('afterend', newContainer);
                    }
                } else if (wcContainer) {
                    wcContainer.remove();
                }
            }
        }

        // Always debounce preview update (even from Quill changes)
        PU.editor.debouncePreviewUpdate(path);
    },

    /**
     * Debounce preview update
     */
    debouncePreviewUpdate(path) {
        if (PU.editor.previewDebounceTimer) {
            clearTimeout(PU.editor.previewDebounceTimer);
        }

        PU.editor.previewDebounceTimer = setTimeout(() => {
            if (PU.state.preview.visible && PU.state.preview.targetPath === path) {
                PU.preview.loadPreview(path);
            }
        }, 300);
    },

    /**
     * Save focused Quill editor state before re-render
     */
    _saveFocusedQuillState() {
        if (!PU.quill || PU.quill._fallback) return null;

        for (const [path, instance] of Object.entries(PU.quill.instances)) {
            if (instance.hasFocus()) {
                return {
                    path: path,
                    selection: instance.getSelection()
                };
            }
        }
        return null;
    },

    /**
     * Restore Quill editor focus/selection after re-render
     */
    _restoreQuillState(saved) {
        if (!saved || !PU.quill || PU.quill._fallback) return;

        const instance = PU.quill.instances[saved.path];
        if (instance) {
            instance.focus();
            if (saved.selection) {
                instance.setSelection(saved.selection.index, saved.selection.length, Quill.sources.SILENT);
            }
        }
    },

    /**
     * Compute adjusted path after a sibling deletion.
     * If the deleted path is a sibling before this path at the same level,
     * decrement this path's last segment.
     */
    _adjustPathAfterDelete(focusedPath, deletedPath) {
        const fp = focusedPath.split('.').map(Number);
        const dp = deletedPath.split('.').map(Number);

        // Only adjust if at the same nesting depth and same parent
        if (fp.length !== dp.length) return focusedPath;

        // Check same parent (all segments except last must match)
        for (let i = 0; i < fp.length - 1; i++) {
            if (fp[i] !== dp[i]) return focusedPath;
        }

        // Same parent — if deleted index is before focused, decrement
        if (dp[fp.length - 1] < fp[fp.length - 1]) {
            fp[fp.length - 1]--;
            return fp.join('.');
        }

        return focusedPath;
    },

    /**
     * Add block at root level
     */
    addBlock(type) {
        // For ext_text, show picker instead of creating empty block
        if (type === 'ext_text') {
            PU.inspector.showExtensionPicker((extId) => {
                PU.actions.insertExtText(extId);
            });
            // Hide add menu
            PU.actions.toggleAddMenu(false);
            return;
        }

        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        // Ensure text is an array
        if (!Array.isArray(prompt.text)) {
            prompt.text = [];
        }

        // Save focused editor state before re-render
        const savedState = PU.editor._saveFocusedQuillState();

        // Add new block
        const newPath = PU.blocks.addNestedBlockAtPath(prompt.text, null, type);

        // Re-render
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);

        // Restore previous editor focus if it wasn't the new block
        if (savedState && savedState.path !== newPath) {
            PU.editor._restoreQuillState(savedState);
        }

        // Animate new block entry
        if (newPath) {
            const pathId = newPath.replace(/\./g, '-');
            const newBlockEl = document.querySelector(`[data-testid="pu-block-${pathId}"]`);
            if (newBlockEl) {
                newBlockEl.classList.add('pu-block-entering');
                newBlockEl.addEventListener('animationend', () => {
                    newBlockEl.classList.remove('pu-block-entering');
                }, { once: true });
            }
            PU.actions.selectBlock(newPath);
        }

        // Hide add menu
        PU.actions.toggleAddMenu(false);
    },

    /**
     * Add nested block
     */
    addNestedBlock(parentPath) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        // Ensure text is an array
        if (!Array.isArray(prompt.text)) {
            prompt.text = [];
        }

        // Save focused editor state before re-render
        const savedState = PU.editor._saveFocusedQuillState();

        // Add nested block
        const newPath = PU.blocks.addNestedBlockAtPath(prompt.text, parentPath, 'content');

        // Re-render
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);

        // Restore previous editor focus if it wasn't the new block
        if (savedState && savedState.path !== newPath) {
            PU.editor._restoreQuillState(savedState);
        }

        // Animate new block entry and select
        if (newPath) {
            const pathId = newPath.replace(/\./g, '-');
            const newBlockEl = document.querySelector(`[data-testid="pu-block-${pathId}"]`);
            if (newBlockEl) {
                newBlockEl.classList.add('pu-block-entering');
                newBlockEl.addEventListener('animationend', () => {
                    newBlockEl.classList.remove('pu-block-entering');
                }, { once: true });
            }
            PU.actions.selectBlock(newPath);
        }
    },

    // Track pending delete confirmations
    _pendingDelete: null,

    /**
     * Delete block (inline confirmation)
     */
    deleteBlock(path) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        if (!Array.isArray(prompt.text)) return;

        const pathId = path.replace(/\./g, '-');
        const deleteBtn = document.querySelector(`[data-testid="pu-block-delete-btn-${pathId}"]`);

        // If already in confirm state for this path, perform the deletion
        if (PU.editor._pendingDelete === path) {
            PU.editor._pendingDelete = null;

            // Save focused editor state (if editing a different block)
            const savedState = PU.editor._saveFocusedQuillState();
            if (savedState && savedState.path !== path) {
                savedState.path = PU.editor._adjustPathAfterDelete(savedState.path, path);
            }

            const performDelete = () => {
                PU.blocks.deleteBlockAtPath(prompt.text, path);
                PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
                PU.state.selectedBlockPath = null;

                // Restore previous editor focus
                if (savedState && savedState.path !== path) {
                    PU.editor._restoreQuillState(savedState);
                }
            };

            // Animate exit before removing
            const blockEl = document.querySelector(`[data-testid="pu-block-${pathId}"]`);
            if (blockEl) {
                blockEl.classList.add('pu-block-exiting');
                blockEl.addEventListener('animationend', performDelete, { once: true });
            } else {
                performDelete();
            }
            return;
        }

        // First click: enter confirm state
        PU.editor._pendingDelete = path;
        if (deleteBtn) {
            deleteBtn.classList.add('pu-delete-confirm');
            deleteBtn.textContent = 'Confirm?';

            // Auto-revert after 3 seconds
            setTimeout(() => {
                if (PU.editor._pendingDelete === path) {
                    PU.editor._pendingDelete = null;
                    deleteBtn.classList.remove('pu-delete-confirm');
                    deleteBtn.innerHTML = '&#128465;';
                }
            }, 3000);
        }
    },

    /**
     * Update ext_text_max for a block
     */
    updateExtTextMax(path, value) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (block && 'ext_text' in block) {
            const numValue = parseInt(value, 10);
            if (numValue === 0) {
                delete block.ext_text_max;
            } else {
                block.ext_text_max = numValue;
            }
        }
    },

    /**
     * Update defaults value
     */
    updateDefaults(key, value) {
        const jobId = PU.state.activeJobId;
        if (!jobId) return;

        // Get or create modified job
        if (!PU.state.modifiedJobs[jobId]) {
            PU.state.modifiedJobs[jobId] = PU.helpers.deepClone(PU.state.jobs[jobId]);
        }

        const job = PU.state.modifiedJobs[jobId];
        if (!job.defaults) {
            job.defaults = {};
        }

        // Convert numeric values
        if (['ext_text_max', 'ext_wildcards_max', 'seed', 'batch_total', 'width', 'height'].includes(key)) {
            value = parseInt(value, 10) || 0;
        }

        job.defaults[key] = value;
    }
};
