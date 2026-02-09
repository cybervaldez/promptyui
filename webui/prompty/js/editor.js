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

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            container.innerHTML = '<div class="pu-loading">No prompt data</div>';
            return;
        }

        const textItems = prompt.text || [];

        // Handle legacy string format
        if (typeof textItems === 'string') {
            container.innerHTML = PU.blocks.renderBlock({ content: textItems }, '0');
            return;
        }

        // Handle legacy string array format
        if (Array.isArray(textItems) && textItems.length > 0 && typeof textItems[0] === 'string') {
            container.innerHTML = textItems.map((text, idx) =>
                PU.blocks.renderBlock({ content: text }, String(idx))
            ).join('');
            return;
        }

        // Handle new nested format
        if (Array.isArray(textItems)) {
            container.innerHTML = textItems.map((item, idx) =>
                PU.blocks.renderBlock(item, String(idx))
            ).join('');

            if (textItems.length === 0) {
                container.innerHTML = '<div class="pu-inspector-empty">No content blocks. Click "+ Add Root Block" to start.</div>';
            }
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

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (block && 'content' in block) {
            block.content = content;
        }

        // Update inspector with wildcards
        const wildcards = PU.blocks.detectWildcards(content);
        PU.inspector.updateWildcardsContext(wildcards, prompt.wildcards || []);

        // Live update: toggle textarea accent class and refresh wildcard chips
        const pathId = path.replace(/\./g, '-');
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
                // Create container if it doesn't exist yet
                const newContainer = document.createElement('div');
                newContainer.className = 'pu-content-wildcards';
                newContainer.dataset.testid = `pu-content-wildcards-${pathId}`;
                newContainer.innerHTML = chipsHtml;
                if (textarea) textarea.insertAdjacentElement('afterend', newContainer);
            }
        } else if (wcContainer) {
            wcContainer.remove();
        }

        // Debounce preview update
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

        // Add new block
        const newPath = PU.blocks.addNestedBlockAtPath(prompt.text, null, type);

        // Re-render
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);

        // Select new block
        if (newPath) {
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

        // Add nested block
        const newPath = PU.blocks.addNestedBlockAtPath(prompt.text, parentPath, 'content');

        // Re-render
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);

        // Select new block
        if (newPath) {
            PU.actions.selectBlock(newPath);
        }
    },

    /**
     * Delete block
     */
    deleteBlock(path) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        if (!Array.isArray(prompt.text)) return;

        // Confirm deletion
        if (!confirm('Delete this block?')) return;

        // Delete block
        PU.blocks.deleteBlockAtPath(prompt.text, path);

        // Re-render
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);

        // Clear selection
        PU.state.selectedBlockPath = null;
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
