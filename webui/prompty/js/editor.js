/**
 * PromptyUI - Editor
 *
 * Main editor panel for editing prompts and defaults.
 * Renders resolved tree view with inline wildcard dropdowns.
 */

PU.editor = {
    /**
     * Show editor for a prompt
     */
    async showPrompt(jobId, promptId) {
        const emptyState = document.querySelector('[data-testid="pu-editor-empty"]');
        const content = document.querySelector('[data-testid="pu-editor-content"]');

        if (emptyState) emptyState.style.display = 'none';
        if (content) content.style.display = 'flex';

        // Update prompt title
        const titleEl = document.querySelector('[data-testid="pu-editor-title"]');
        if (titleEl) titleEl.textContent = promptId;

        // Update defaults toolbar
        PU.editor.updateDefaultsToolbar(jobId);

        // Update odometer toolbar
        PU.editor.updateOdometerToolbar();

        // Render blocks with resolved content
        await PU.editor.renderBlocks(jobId, promptId);
    },

    /**
     * Show empty state
     */
    showEmptyState() {
        const emptyState = document.querySelector('[data-testid="pu-editor-empty"]');
        const content = document.querySelector('[data-testid="pu-editor-content"]');

        if (emptyState) emptyState.style.display = 'flex';
        if (content) content.style.display = 'none';
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
     * Update odometer toolbar inputs from state
     */
    updateOdometerToolbar() {
        const compInput = document.querySelector('[data-testid="pu-odometer-composition"]');
        if (compInput) compInput.value = PU.state.previewMode.compositionId;

        const extTextInput = document.querySelector('[data-testid="pu-odometer-ext-text"]');
        if (extTextInput) extTextInput.value = PU.state.previewMode.extTextMax;

        const wcMaxInput = document.querySelector('[data-testid="pu-odometer-wc-max"]');
        if (wcMaxInput) wcMaxInput.value = PU.state.previewMode.extWildcardsMax;
    },

    /**
     * Handle odometer input changes
     */
    async handleOdometerChange(field, value) {
        const val = parseInt(value, 10);
        if (isNaN(val)) return;

        if (field === 'composition') {
            if (val < 0) return;
            PU.state.previewMode.compositionId = val;
        } else if (field === 'ext_text') {
            if (val < 1) return;
            PU.state.previewMode.extTextMax = val;
        } else if (field === 'wc_max') {
            if (val < 0) return;
            PU.state.previewMode.extWildcardsMax = val;
        }

        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.actions.updateUrl();
    },

    /**
     * Randomize composition ID
     */
    async randomizeComposition() {
        const randomId = Math.floor(Math.random() * 10000);
        PU.state.previewMode.compositionId = randomId;

        const compInput = document.querySelector('[data-testid="pu-odometer-composition"]');
        if (compInput) compInput.value = randomId;

        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.actions.updateUrl();
    },

    /**
     * Render blocks for a prompt (async - resolves content)
     */
    async renderBlocks(jobId, promptId) {
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
            const items = [{ content: textItems }];
            const resolutions = await PU.preview.buildBlockResolutions(items);
            container.innerHTML = PU.blocks.renderBlock({ content: textItems }, '0', 0, resolutions);
            PU.preview.renderHeaderWildcardDropdowns(resolutions);
            await PU.editor.populateOutputFooter(items, resolutions);
            PU.editor.attachBlockInteractions();
            return;
        }

        // Handle legacy string array format
        if (Array.isArray(textItems) && textItems.length > 0 && typeof textItems[0] === 'string') {
            const items = textItems.map(t => ({ content: t }));
            const resolutions = await PU.preview.buildBlockResolutions(items);
            container.innerHTML = items.map((item, idx) =>
                PU.blocks.renderBlock(item, String(idx), 0, resolutions)
            ).join('');
            PU.preview.renderHeaderWildcardDropdowns(resolutions);
            await PU.editor.populateOutputFooter(items, resolutions);
            PU.editor.attachBlockInteractions();
            return;
        }

        // Handle new nested format
        if (Array.isArray(textItems)) {
            if (textItems.length === 0) {
                container.innerHTML = '<div class="pu-inspector-empty">No content blocks. Click "+ Add Root Block" to start.</div>';
                PU.preview.renderHeaderWildcardDropdowns(null);
                return;
            }

            const resolutions = await PU.preview.buildBlockResolutions(textItems);
            container.innerHTML = textItems.map((item, idx) =>
                PU.blocks.renderBlock(item, String(idx), 0, resolutions)
            ).join('');
            PU.preview.renderHeaderWildcardDropdowns(resolutions);
            await PU.editor.populateOutputFooter(textItems, resolutions);
            PU.editor.attachBlockInteractions();
            return;
        }

        container.innerHTML = '<div class="pu-loading">Unknown text format</div>';
    },

    // Generation counter for stale async guard
    _footerGeneration: 0,

    /**
     * Populate the output footer with terminal outputs from multiple compositions
     */
    async populateOutputFooter(textItems, resolutions) {
        const footer = document.querySelector('[data-testid="pu-output-footer"]');
        if (!footer) return;

        const gen = ++PU.editor._footerGeneration;
        const { outputs, total } = await PU.preview.buildMultiCompositionOutputs(textItems, resolutions, 20);
        if (gen !== PU.editor._footerGeneration) return; // stale guard

        const body = footer.querySelector('[data-testid="pu-output-footer-body"]');
        const countEl = footer.querySelector('[data-testid="pu-output-footer-count"]');

        if (countEl) {
            if (outputs.length > 0) {
                countEl.textContent = `(${outputs.length} of ${total} total)`;
            } else {
                countEl.textContent = '';
            }
        }

        if (body) {
            if (outputs.length === 0) {
                body.innerHTML = '<div class="pu-output-empty">No terminal outputs</div>';
            } else {
                body.innerHTML = outputs.map((out, idx) =>
                    `<div class="pu-output-item" data-testid="pu-output-item-${idx}">
                        <span class="pu-output-item-label">${PU.blocks.escapeHtml(out.label)}</span>
                        <div class="pu-output-item-text">${PU.blocks.escapeHtml(out.text)}</div>
                    </div>`
                ).join('');
            }
        }

        // Restore collapse state
        if (PU.state.ui.outputFooterCollapsed) {
            footer.classList.add('collapsed');
        } else {
            footer.classList.remove('collapsed');
        }
    },

    /**
     * Attach click handlers for block interactions
     */
    attachBlockInteractions() {
        // Click handler on clickable blocks → open focus mode
        document.querySelectorAll('.pu-block-clickable').forEach(el => {
            el.addEventListener('click', (e) => {
                const path = el.dataset.path;
                if (path) {
                    PU.actions.selectBlock(path);
                    PU.focus.enter(path);
                }
            });
        });
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
     * Update block content — updates state then re-renders
     */
    updateBlockContent(path, content) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

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
    },

    /**
     * Add block at root level
     */
    async addBlock(type) {
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
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);

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
    async addNestedBlock(parentPath) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        // Ensure text is an array
        if (!Array.isArray(prompt.text)) {
            prompt.text = [];
        }

        // Add nested block
        const newPath = PU.blocks.addNestedBlockAtPath(prompt.text, parentPath, 'content');

        // Re-render
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);

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

            const performDelete = () => {
                PU.blocks.deleteBlockAtPath(prompt.text, path);
                PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
                PU.state.selectedBlockPath = null;
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
