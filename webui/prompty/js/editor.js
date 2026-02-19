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
        const noPrompts = document.querySelector('[data-testid="pu-editor-no-prompts"]');

        if (emptyState) emptyState.style.display = 'none';
        if (noPrompts) noPrompts.style.display = 'none';
        if (content) content.style.display = 'flex';

        // Update prompt title
        const titleEl = document.querySelector('[data-testid="pu-editor-title"]');
        if (titleEl) titleEl.textContent = promptId;

        // Update defaults toolbar
        PU.editor.updateDefaultsToolbar(jobId);

        // Update visualizer selector
        PU.editor.updateVisualizerSelector();

        // Render blocks with resolved content
        await PU.editor.renderBlocks(jobId, promptId);

        // Sync right panel
        PU.rightPanel.render();
    },

    /**
     * Show empty state (no job selected)
     */
    showEmptyState() {
        const emptyState = document.querySelector('[data-testid="pu-editor-empty"]');
        const content = document.querySelector('[data-testid="pu-editor-content"]');
        const noPrompts = document.querySelector('[data-testid="pu-editor-no-prompts"]');

        if (emptyState) emptyState.style.display = 'flex';
        if (content) content.style.display = 'none';
        if (noPrompts) noPrompts.style.display = 'none';
    },

    /**
     * Show no-prompts state (job selected but 0 prompts)
     */
    showNoPromptsState() {
        const emptyState = document.querySelector('[data-testid="pu-editor-empty"]');
        const content = document.querySelector('[data-testid="pu-editor-content"]');
        const noPrompts = document.querySelector('[data-testid="pu-editor-no-prompts"]');

        if (emptyState) emptyState.style.display = 'none';
        if (content) content.style.display = 'none';
        if (noPrompts) noPrompts.style.display = 'flex';
    },

    /**
     * Update defaults toolbar
     */
    updateDefaultsToolbar(jobId) {
        const job = PU.helpers.getActiveJob();
        if (!job) return;

        const defaults = job.defaults || {};

        // Check if extensions exist
        const tree = PU.state.globalExtensions.tree;
        const hasExtensions = tree && Object.keys(tree).filter(k => k !== '_files').length > 0;

        // Toggle ext row vs "no extensions" message
        const extRow = document.querySelector('[data-testid="pu-defaults-ext-row"]');
        const noExtMsg = document.querySelector('[data-testid="pu-defaults-no-ext"]');
        if (extRow) extRow.style.display = hasExtensions ? '' : 'none';
        if (noExtMsg) noExtMsg.style.display = hasExtensions ? 'none' : '';

        // Update ext dropdown only when extensions exist
        if (hasExtensions) {
            const extSelect = document.querySelector('[data-testid="pu-defaults-ext"]');
            if (extSelect) {
                PU.editor.populateExtDropdown(extSelect, defaults.ext || 'defaults');
            }
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
     * Update visualizer selector from state
     */
    updateVisualizerSelector() {
        const vizSelect = document.querySelector('[data-testid="pu-editor-visualizer"]');
        if (vizSelect) vizSelect.value = PU.state.previewMode.visualizer;
    },

    /**
     * Handle visualizer dropdown change
     */
    async handleVisualizerChange(value) {
        const valid = ['compact', 'typewriter', 'reel', 'stack', 'ticker'];
        if (!valid.includes(value)) return;
        PU.state.previewMode.visualizer = value;
        PU.editor.updateVisualizerSelector();
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.actions.updateUrl();
    },

    /**
     * Render blocks for a prompt (async - resolves content)
     */
    async renderBlocks(jobId, promptId) {
        const container = document.querySelector('[data-testid="pu-blocks-container"]');
        if (!container) return;

        // Set viz mode on container so CSS can scope compact vs animated styles
        container.dataset.viz = PU.state.previewMode.visualizer;

        PU.blocks.cleanupVisualizerAnimations();

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
            PU.editor._lastResolutions = resolutions;
            container.innerHTML = PU.blocks.renderBlock({ content: textItems }, '0', 0, resolutions);

            PU.editor.attachBlockInteractions();
            PU.blocks.initVisualizerAnimations();
            PU.editor._buildWildcardBlockMap();
            return;
        }

        // Handle legacy string array format
        if (Array.isArray(textItems) && textItems.length > 0 && typeof textItems[0] === 'string') {
            const items = textItems.map(t => ({ content: t }));
            const resolutions = await PU.preview.buildBlockResolutions(items);
            PU.editor._lastResolutions = resolutions;
            container.innerHTML = items.map((item, idx) =>
                PU.blocks.renderBlock(item, String(idx), 0, resolutions)
            ).join('');

            PU.editor.attachBlockInteractions();
            PU.blocks.initVisualizerAnimations();
            PU.editor._buildWildcardBlockMap();
            return;
        }

        // Handle new nested format
        if (Array.isArray(textItems)) {
            if (textItems.length === 0) {
                container.innerHTML = '<div class="pu-rp-wc-empty">No content blocks. Click "+ Add Root Block" to start.</div>';
                return;
            }

            const resolutions = await PU.preview.buildBlockResolutions(textItems);
            PU.editor._lastResolutions = resolutions;
            container.innerHTML = textItems.map((item, idx) =>
                PU.blocks.renderBlock(item, String(idx), 0, resolutions)
            ).join('');

            PU.editor.attachBlockInteractions();
            PU.blocks.initVisualizerAnimations();
            PU.editor._buildWildcardBlockMap();
            return;
        }

        container.innerHTML = '<div class="pu-loading">Unknown text format</div>';
    },

    // Last computed resolutions (for focus mode context strip)
    _lastResolutions: null,

    // Wildcard-to-blocks map: wcName -> Set of block paths (built after renderBlocks)
    _wildcardToBlocks: {},

    /**
     * Build a map of wildcard name → Set of block paths that contain it.
     * Queries [data-wc] spans in the rendered blocks and maps each to its
     * closest .pu-block parent. Then augments with theme wildcards from
     * ext_text cache (maps theme wildcard → ext_text block path).
     * Called after renderBlocks() completes.
     */
    _buildWildcardBlockMap() {
        const map = {};
        const container = document.querySelector('[data-testid="pu-blocks-container"]');
        if (!container) { PU.editor._wildcardToBlocks = map; return; }

        // Phase 1: Scan data-wc spans in rendered blocks (covers wildcards in content)
        container.querySelectorAll('[data-wc]').forEach(span => {
            const block = span.closest('.pu-block');
            if (block && block.dataset.path !== undefined) {
                const wcName = span.dataset.wc;
                if (!map[wcName]) map[wcName] = new Set();
                map[wcName].add(block.dataset.path);
            }
        });

        // Phase 2: Map theme wildcards to their ext_text block paths.
        // Theme wildcards may not appear as __name__ in any content block,
        // but they're still associated with the ext_text block that sources them.
        const prompt = PU.helpers.getActivePrompt();
        if (prompt && Array.isArray(prompt.text)) {
            const cache = PU.state.previewMode._extTextCache || {};
            const walkBlocks = (items, pathPrefix) => {
                items.forEach((item, idx) => {
                    const path = pathPrefix ? `${pathPrefix}.${idx}` : String(idx);
                    if (item && 'ext_text' in item && item.ext_text) {
                        // Find cached data for this ext_text
                        const extName = item.ext_text;
                        const job = PU.helpers.getActiveJob();
                        const extPrefix = (prompt.ext) || (job && job.defaults && job.defaults.ext) || '';
                        const needsPrefix = extPrefix && !extName.startsWith(extPrefix + '/');
                        const cacheKey = needsPrefix ? `${extPrefix}/${extName}` : extName;
                        const data = cache[cacheKey];
                        if (data && data.wildcards) {
                            for (const wc of data.wildcards) {
                                if (wc.name) {
                                    if (!map[wc.name]) map[wc.name] = new Set();
                                    map[wc.name].add(path);
                                }
                            }
                        }
                    }
                    if (item && item.after) walkBlocks(item.after, path);
                });
            };
            walkBlocks(prompt.text, '');
        }

        PU.editor._wildcardToBlocks = map;
    },

    /**
     * Build unique values per dimension from outputs (used by focus.js filter tree)
     */
    _buildDimValues(outputs) {
        const dims = {};
        if (!outputs || outputs.length === 0) return dims;
        for (const out of outputs) {
            if (!out.wcDetails) continue;
            for (const d of out.wcDetails) {
                if (!dims[d.name]) dims[d.name] = [];
                if (!dims[d.name].includes(d.value)) dims[d.name].push(d.value);
            }
        }
        return dims;
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

        // Update right panel with wildcards
        PU.rightPanel.render();
    },

    /**
     * Add block at root level
     */
    async addBlock(type) {
        // For ext_text, show picker instead of creating empty block
        if (type === 'ext_text') {
            PU.rightPanel.showExtensionPicker((extId) => {
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

        // Compute draft path without creating the block yet
        const draftPath = String(prompt.text.length);

        // Hide add menu
        PU.actions.toggleAddMenu(false);

        // Open focus in draft mode — block is created on first keystroke
        PU.focus.enter(draftPath, { draft: true, parentPath: null });
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

        // Compute draft path without creating the block yet
        const parent = PU.blocks.findBlockByPath(prompt.text, parentPath);
        if (!parent) return;
        const afterLen = (parent.after && parent.after.length) || 0;
        const draftPath = `${parentPath}.${afterLen}`;

        // Open focus in draft mode — block is created on first keystroke
        PU.focus.enter(draftPath, { draft: true, parentPath: parentPath });
    },

    // Track pending delete confirmations
    _pendingDelete: null,
    _deleteRevertTimer: null,

    /**
     * Revert delete confirmation state for a button
     */
    _revertDeleteConfirm(deleteBtn, path) {
        if (PU.editor._pendingDelete === path) {
            PU.editor._pendingDelete = null;
            PU.editor._deleteRevertTimer = null;
            deleteBtn.classList.remove('pu-delete-confirm');
            deleteBtn.innerHTML = deleteBtn._originalHTML || '&#128465;';
            deleteBtn.removeEventListener('mouseenter', deleteBtn._onConfirmEnter);
            deleteBtn.removeEventListener('mouseleave', deleteBtn._onConfirmLeave);
        }
    },

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
            if (PU.editor._deleteRevertTimer) {
                clearTimeout(PU.editor._deleteRevertTimer);
                PU.editor._deleteRevertTimer = null;
            }

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
            deleteBtn._originalHTML = deleteBtn.innerHTML;
            deleteBtn.classList.add('pu-delete-confirm');
            deleteBtn.innerHTML = '<span class="pu-confirm-label">CONFIRM?</span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';

            // Hover-aware auto-revert: close on mouseleave, cancel on mouseenter
            deleteBtn._onConfirmEnter = () => {
                if (PU.editor._deleteRevertTimer) {
                    clearTimeout(PU.editor._deleteRevertTimer);
                    PU.editor._deleteRevertTimer = null;
                }
            };
            deleteBtn._onConfirmLeave = () => {
                PU.editor._deleteRevertTimer = setTimeout(() => {
                    PU.editor._revertDeleteConfirm(deleteBtn, path);
                }, 1000);
            };
            deleteBtn.addEventListener('mouseenter', deleteBtn._onConfirmEnter);
            deleteBtn.addEventListener('mouseleave', deleteBtn._onConfirmLeave);
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
        if (['ext_text_max', 'wildcards_max', 'seed', 'batch_total', 'width', 'height'].includes(key)) {
            value = parseInt(value, 10) || 0;
        }

        job.defaults[key] = value;
    }
};
