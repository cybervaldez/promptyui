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

        const vizSelect = document.querySelector('[data-testid="pu-odometer-visualizer"]');
        if (vizSelect) vizSelect.value = PU.state.previewMode.visualizer;
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
     * Handle visualizer dropdown change
     */
    async handleVisualizerChange(value) {
        const valid = ['compact', 'typewriter', 'reel', 'stack', 'ticker'];
        if (!valid.includes(value)) return;
        PU.state.previewMode.visualizer = value;
        PU.editor.updateOdometerToolbar();
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
            await PU.editor.populateOutputFooter(items, resolutions);
            PU.editor.attachBlockInteractions();
            PU.blocks.initVisualizerAnimations();
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
            await PU.editor.populateOutputFooter(items, resolutions);
            PU.editor.attachBlockInteractions();
            PU.blocks.initVisualizerAnimations();
            return;
        }

        // Handle new nested format
        if (Array.isArray(textItems)) {
            if (textItems.length === 0) {
                container.innerHTML = '<div class="pu-inspector-empty">No content blocks. Click "+ Add Root Block" to start.</div>';
                return;
            }

            const resolutions = await PU.preview.buildBlockResolutions(textItems);
            PU.editor._lastResolutions = resolutions;
            container.innerHTML = textItems.map((item, idx) =>
                PU.blocks.renderBlock(item, String(idx), 0, resolutions)
            ).join('');
            await PU.editor.populateOutputFooter(textItems, resolutions);
            PU.editor.attachBlockInteractions();
            PU.blocks.initVisualizerAnimations();
            return;
        }

        container.innerHTML = '<div class="pu-loading">Unknown text format</div>';
    },

    // Last computed resolutions (for focus mode context strip)
    _lastResolutions: null,

    // Generation counter for stale async guard
    _footerGeneration: 0,
    _footerTextItems: null,
    _footerResolutions: null,
    _footerCurrentOutputs: null,
    _footerCurrentTotal: 0,

    /**
     * Populate the output footer with terminal outputs from multiple compositions
     */
    async populateOutputFooter(textItems, resolutions) {
        const footer = document.querySelector('[data-testid="pu-output-footer"]');
        if (!footer) return;

        PU.editor._footerTextItems = textItems;
        PU.editor._footerResolutions = resolutions;

        const gen = ++PU.editor._footerGeneration;
        const { outputs, total } = await PU.preview.buildMultiCompositionOutputs(textItems, resolutions, 20);
        if (gen !== PU.editor._footerGeneration) return; // stale guard

        PU.editor._renderFooterBody(outputs, total);
        PU.editor.applyOutputLabelMode();
    },

    /**
     * Apply the current output label display mode to the footer
     */
    applyOutputLabelMode() {
        const footer = document.querySelector('[data-testid="pu-output-footer"]');
        if (!footer) return;
        const mode = PU.state.ui.outputLabelMode || 'none';
        footer.classList.remove('label-none', 'label-hybrid', 'label-inline');
        footer.classList.add('label-' + mode);
        const btn = footer.querySelector('[data-testid="pu-output-label-toggle"]');
        if (btn) {
            const icons = { none: '\u2012', hybrid: '#', inline: 'Aa' };
            btn.textContent = icons[mode];
            btn.title = 'Label mode: ' + mode;
        }
    },

    /**
     * Render a single output item HTML (shared by flat and grouped paths)
     */
    _renderOutputItem(out, idx) {
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
        return `<div class="pu-output-item" data-testid="pu-output-item-${idx}">
            <span class="pu-output-item-label">${labelHtml}</span>
            <div class="pu-output-item-text">${PU.blocks.escapeHtml(out.text)}</div>
        </div>`;
    },

    /**
     * Get free (non-pinned) wildcard names from outputs
     */
    _getFreeWcNames(outputs) {
        if (!outputs || outputs.length === 0) return [];
        const first = outputs[0];
        if (!first.wcDetails || first.wcDetails.length === 0) return [];
        return first.wcDetails.map(d => d.name);
    },

    /**
     * Count outputs matching a specific filter value, considering other active filters
     */
    _countFilterMatches(outputs, dim, val) {
        const af = PU.state.ui.outputFilters;
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
            // Check the target dim/val specifically
            const detail = o.wcDetails.find(wd => wd.name === dim);
            return detail && detail.value === val;
        }).length;
    },

    /**
     * Check if an output is visible given active filters
     */
    _isOutputVisible(out) {
        const af = PU.state.ui.outputFilters;
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

    /**
     * Build unique values per dimension from outputs
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
     * Render the filter tree panel HTML
     */
    _renderFilterTree(outputs) {
        const treeScroll = document.querySelector('[data-testid="pu-filter-tree-scroll"]');
        const treePanel = document.querySelector('[data-testid="pu-filter-tree"]');
        const resetBtn = document.querySelector('[data-testid="pu-filter-reset-btn"]');
        if (!treeScroll || !treePanel) return;

        const freeNames = PU.editor._getFreeWcNames(outputs);
        if (outputs.length <= 1 || freeNames.length === 0) {
            treePanel.style.display = 'none';
            return;
        }

        treePanel.style.display = 'flex';
        const af = PU.state.ui.outputFilters;
        const collapsed = PU.state.ui.outputFilterCollapsed;
        const dimValues = PU.editor._buildDimValues(outputs);

        let html = '';
        for (const dim of freeNames) {
            const values = dimValues[dim] || [];
            if (values.length === 0) continue;
            const ic = collapsed[dim] || false;
            const normalizedDim = PU.preview.normalizeWildcardName(dim);
            const dimAttr = PU.blocks.escapeAttr(dim);

            html += `<div class="pu-filter-dim"><div class="pu-filter-dim-header" onclick="PU.actions.toggleFilterDim('${dimAttr}')"><span class="pu-filter-dim-chevron ${ic ? 'collapsed' : ''}">&#9654;</span>${PU.blocks.escapeHtml(normalizedDim)}</div><div class="pu-filter-dim-values ${ic ? 'collapsed' : ''}" style="max-height:300px">`;

            const counts = values.map(v => PU.editor._countFilterMatches(outputs, dim, v));
            const mx = Math.max(...counts, 1);

            values.forEach((val, i) => {
                const dimSet = af[dim];
                const act = dimSet && dimSet.has(val);
                const c = counts[i];
                const pct = Math.round((c / mx) * 100);
                const valAttr = PU.blocks.escapeAttr(val);

                html += `<div class="pu-filter-value ${act ? 'active' : ''}" data-testid="pu-filter-value-${dimAttr}-${valAttr}" onclick="PU.actions.toggleOutputFilter('${dimAttr}','${valAttr}')"><span class="pu-filter-dot"></span><span class="pu-filter-value-name">${PU.blocks.escapeHtml(val)}</span><span class="pu-filter-value-bar-track"><span class="pu-filter-value-bar-dash"></span><span class="pu-filter-value-bar-fill ${c === 0 ? 'zero' : ''}" style="width:${pct}%"></span></span><span class="pu-filter-value-count">${c}</span></div>`;
            });
            html += '</div></div>';
        }
        treeScroll.innerHTML = html;

        // Show/hide reset button
        const hasFilters = Object.values(af).some(s => s && s.size > 0);
        if (resetBtn) {
            resetBtn.style.display = hasFilters ? 'flex' : 'none';
            resetBtn.closest('.pu-filter-tree-footer')?.classList.toggle('pu-hidden', !hasFilters);
        }
    },

    /**
     * Render output footer body content (filter tree + filtered output list)
     */
    _renderFooterBody(outputs, total) {
        const footer = document.querySelector('[data-testid="pu-output-footer"]');
        if (!footer) return;

        // Cache for re-renders
        PU.editor._footerCurrentOutputs = outputs;
        PU.editor._footerCurrentTotal = total;

        const countEl = footer.querySelector('[data-testid="pu-output-footer-count"]');
        const outputList = footer.querySelector('[data-testid="pu-output-list"]');

        // Auto-reset: if filtered dimensions are no longer free, clear them
        const freeNames = PU.editor._getFreeWcNames(outputs);
        const af = PU.state.ui.outputFilters;
        for (const d of Object.keys(af)) {
            if (!freeNames.includes(d)) {
                delete af[d];
            }
        }

        // Render filter tree
        PU.editor._renderFilterTree(outputs);

        // Filter outputs
        const hasFilters = Object.values(af).some(s => s && s.size > 0);
        let visibleOutputs = outputs;
        if (hasFilters) {
            visibleOutputs = outputs.filter(o => PU.editor._isOutputVisible(o));
        }

        // Update count badge
        if (countEl) {
            if (outputs.length > 0) {
                if (hasFilters) {
                    countEl.textContent = `(${visibleOutputs.length} / ${outputs.length} of ${total})`;
                } else {
                    countEl.textContent = `(${outputs.length} of ${total} total)`;
                }
            } else {
                countEl.textContent = '';
            }
        }

        // Update filter badge in header
        const filterBadge = footer.querySelector('[data-testid="pu-output-filter-badge"]');
        if (filterBadge) {
            if (hasFilters) {
                const n = Object.values(af).reduce((s, set) => s + (set ? set.size : 0), 0);
                filterBadge.textContent = `${n} filter${n > 1 ? 's' : ''}`;
                filterBadge.style.display = '';
            } else {
                filterBadge.style.display = 'none';
            }
        }

        // Render output list
        if (outputList) {
            if (outputs.length === 0) {
                outputList.innerHTML = '<div class="pu-output-empty">No terminal outputs</div>';
            } else {
                let html = visibleOutputs.map((out, idx) =>
                    PU.editor._renderOutputItem(out, idx)
                ).join('');

                if (outputs.length < total) {
                    html += `<button class="pu-btn-sm pu-output-load-more"
                        data-testid="pu-output-load-more"
                        onclick="PU.actions.loadMoreOutputs()">Load all (up to 50)</button>`;
                }
                outputList.innerHTML = html;
            }
        }

        // Restore collapse state
        if (PU.state.ui.outputFooterCollapsed) {
            footer.classList.add('collapsed');
        } else {
            footer.classList.remove('collapsed');
        }

        PU.editor.applyOutputLabelMode();
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
        if (['ext_text_max', 'ext_wildcards_max', 'seed', 'batch_total', 'width', 'height'].includes(key)) {
            value = parseInt(value, 10) || 0;
        }

        job.defaults[key] = value;
    }
};
