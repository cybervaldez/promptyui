/**
 * PromptyUI - Right Panel
 *
 * Unified right sidebar with preview-matching design.
 * Top: "Wildcards N" header + wildcard entries grouped by source
 * Bottom: compositions section (variation nav + dims + export)
 */

PU.rightPanel = {
    /**
     * Initialize the right panel (load extensions, initial render)
     */
    async init() {
        await PU.rightPanel.loadExtensions();

        // Restore persisted tab selection
        const savedTab = PU.state.ui.rightPanelTab;
        if (savedTab && savedTab !== 'wildcards') {
            PU.rightPanel.switchTab(savedTab);
        }

        PU.rightPanel.render();

        // Close popover/dropdown on outside click
        document.addEventListener('click', (e) => {
            // Close operation dropdown
            if (!e.target.closest('.pu-rp-op-selector') && !e.target.closest('.pu-rp-op-dropdown')) {
                PU.rightPanel.hideOpDropdown();
            }
            // Close replacement popover
            if (!e.target.closest('.pu-rp-replace-popover') && !e.target.closest('.pu-rp-wc-v')) {
                PU.rightPanel.hideReplacePopover();
            }
            // Close push-to-theme popover
            if (!e.target.closest('.pu-rp-push-popover') && !e.target.closest('.pu-rp-push-trigger')) {
                PU.rightPanel.hidePushPopover();
            }
            // Close defaults popover
            if (!e.target.closest('.pu-defaults-popover') && !e.target.closest('.pu-header-defaults-btn')) {
                PU.rightPanel.hideDefaultsPopover();
            }
        });

        // Escape key: close popovers first, then clear focus, then locks
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && !(e.target && e.target.closest && e.target.closest('input, textarea, [contenteditable]'))) {
                // Priority 0: close push popover if visible
                if (PU.state.themes.pushToThemePopover.visible) {
                    PU.rightPanel.hidePushPopover();
                    return;
                }
                // Priority 1: clear wildcard focus
                if (PU.state.previewMode.focusedWildcards.length > 0) {
                    PU.rightPanel.clearFocus();
                    return;
                }
                // Priority 2: clear all locks
                const locked = PU.state.previewMode.lockedValues;
                if (Object.keys(locked).length > 0) {
                    PU.state.previewMode.lockedValues = {};
                    const sw = PU.state.previewMode.selectedWildcards;
                    if (sw['*']) delete sw['*'];
                    PU.rightPanel.render();
                    PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
                }
            }
        });
    },

    /**
     * Load extensions from API
     */
    async loadExtensions() {
        try {
            await PU.api.loadExtensions();
        } catch (e) {
            console.error('Failed to load extensions:', e);
        }
    },

    // ============================================
    // Build Hooks: Operations (value replacement)
    // ============================================

    /**
     * Load available operations for the active job.
     * Called when job/prompt changes.
     */
    async loadOperations() {
        const jobId = PU.state.activeJobId;
        if (!jobId) {
            PU.state.buildComposition.operations = [];
            PU.state.buildComposition.activeOperation = null;
            PU.state.buildComposition.activeOperationData = null;
            return;
        }
        try {
            const ops = await PU.api.loadOperations(jobId);
            PU.state.buildComposition.operations = ops;
            // If previously selected operation is no longer available, deselect
            if (PU.state.buildComposition.activeOperation &&
                !ops.includes(PU.state.buildComposition.activeOperation)) {
                PU.state.buildComposition.activeOperation = null;
                PU.state.buildComposition.activeOperationData = null;
            }
        } catch (e) {
            console.warn('Failed to load operations:', e);
            PU.state.buildComposition.operations = [];
        }
    },

    /**
     * Select an operation by name (or null to deselect).
     * Loads the operation data from API and re-renders.
     */
    async selectOperation(opName) {
        if (!opName || opName === '__none__') {
            PU.state.buildComposition.activeOperation = null;
            PU.state.buildComposition.activeOperationData = null;
        } else {
            const jobId = PU.state.activeJobId;
            if (!jobId) return;
            try {
                const data = await PU.api.loadOperation(jobId, opName);
                PU.state.buildComposition.activeOperation = opName;
                PU.state.buildComposition.activeOperationData = data;
            } catch (e) {
                console.warn('Failed to load operation:', opName, e);
                PU.actions.showToast(`Failed to load operation: ${opName}`, 'error');
                return;
            }
        }
        PU.rightPanel.hideOpDropdown();
        PU.rightPanel.render();
    },

    /**
     * Toggle the operation dropdown below the top bar.
     */
    toggleOpDropdown() {
        const dropdown = document.querySelector('[data-testid="pu-rp-op-dropdown"]');
        if (!dropdown) return;

        if (dropdown.style.display !== 'none') {
            PU.rightPanel.hideOpDropdown();
            return;
        }

        PU.overlay.dismissPopovers();

        const ops = PU.state.buildComposition.operations;
        const activeOp = PU.state.buildComposition.activeOperation;
        const esc = PU.blocks.escapeHtml;

        let html = `<div class="pu-rp-op-dropdown-item none-item${!activeOp ? ' active' : ''}"
                         data-testid="pu-rp-op-item-none"
                         onclick="PU.rightPanel.selectOperation('__none__')">None</div>`;

        for (const op of ops) {
            const isActive = op === activeOp;
            html += `<div class="pu-rp-op-dropdown-item${isActive ? ' active' : ''}"
                          data-testid="pu-rp-op-item-${esc(op)}"
                          onclick="PU.rightPanel.selectOperation('${esc(op)}')">${esc(op)}</div>`;
        }

        dropdown.innerHTML = html;
        dropdown.style.display = 'block';
        PU.overlay.showOverlay();
    },

    /**
     * Hide the operation dropdown.
     */
    hideOpDropdown() {
        const dropdown = document.querySelector('[data-testid="pu-rp-op-dropdown"]');
        if (dropdown) dropdown.style.display = 'none';
    },

    /**
     * Get the active operation's mappings for a given wildcard name.
     * Returns { originalValue: replacementValue } or null.
     */
    _getOpMappings(wcName) {
        const opData = PU.state.buildComposition.activeOperationData;
        if (!opData || !opData.mappings) return null;
        return opData.mappings[wcName] || null;
    },

    /**
     * Full render of all panel sections
     */
    render() {
        PU.rightPanel.renderDefaultsPopover();
        PU.rightPanel.renderPromptAnnotations();
        PU.rightPanel.renderWildcardStream();
        PU.rightPanel.renderOpsSection();
        PU.rightPanel.renderAnnotationsTab();
    },

    // ============================================
    // Tab Switching
    // ============================================

    /**
     * Switch the active right panel tab.
     * @param {'wildcards'|'annotations'} tabName
     */
    switchTab(tabName) {
        PU.state.ui.rightPanelTab = tabName;

        // Update tab strip active state
        document.querySelectorAll('.pu-rp-tab').forEach(tab => {
            tab.classList.toggle('active', tab.dataset.tab === tabName);
        });

        // Update pane visibility
        document.querySelectorAll('.pu-rp-tab-pane').forEach(pane => {
            pane.classList.toggle('active', pane.dataset.pane === tabName);
        });

        // Render the newly active tab's content if needed
        if (tabName === 'annotations') {
            PU.rightPanel.renderAnnotationsTab();
        }

        PU.helpers.saveUIState();
    },

    // ============================================
    // Annotations Tab (full hierarchy overview)
    // ============================================

    /**
     * Render the annotations overview tab showing the full inheritance hierarchy:
     * Defaults → Prompt → Per-block sections with resolved annotations and source labels.
     */
    renderAnnotationsTab() {
        const container = document.querySelector('[data-testid="pu-rp-ann-overview"]');
        if (!container) return;

        const job = PU.helpers.getActiveJob();
        const prompt = PU.helpers.getActivePrompt();

        // Always update tab label count (even when pane is hidden)
        PU.rightPanel._updateAnnotationsTabCount(job, prompt);

        // Only render body if tab is active (avoid unnecessary work)
        const pane = document.querySelector('[data-testid="pu-rp-tab-pane-annotations"]');
        if (!pane || !pane.classList.contains('active')) return;

        if (!prompt) {
            container.innerHTML = '<div class="pu-rp-note">Select a prompt to see annotations</div>';
            return;
        }

        const esc = PU.blocks.escapeHtml;
        const escAttr = PU.blocks.escapeAttr;
        let html = '';

        // 1. Defaults section
        const defaultsAnn = (job && job.defaults && job.defaults.annotations) || {};
        const defaultsKeys = Object.keys(defaultsAnn);
        html += PU.rightPanel._renderAnnSection('defaults', 'Defaults', defaultsKeys.length, () => {
            if (defaultsKeys.length === 0) return '<div class="pu-rp-ann-section-empty">No default annotations</div>';
            return defaultsKeys.map(k => PU.rightPanel._renderAnnEntry(k, defaultsAnn[k], 'defaults')).join('');
        });

        // 2. Prompt section
        const promptAnn = (prompt.annotations) || {};
        const promptKeys = Object.keys(promptAnn);
        html += PU.rightPanel._renderAnnSection('prompt', 'Prompt', promptKeys.length, () => {
            if (promptKeys.length === 0) return '<div class="pu-rp-ann-section-empty">No prompt annotations</div>';
            return promptKeys.map(k => PU.rightPanel._renderAnnEntry(k, promptAnn[k], 'prompt')).join('');
        });

        // 3. Per-block sections
        const textItems = prompt.text || [];
        const blockSections = [];
        PU.rightPanel._walkBlocks(textItems, '', (block, path) => {
            const blockAnn = block.annotations || {};
            const blockKeys = Object.keys(blockAnn);
            if (blockKeys.length === 0) return; // skip blocks with no annotations

            const { computed, sources, removed } = PU.annotations.resolve(path);
            blockSections.push({ block, path, blockAnn, computed, sources, removed });
        });

        for (const sec of blockSections) {
            const pathId = sec.path.replace(/\./g, '-');
            const contentPreview = (sec.block.content || '').substring(0, 30);
            const label = contentPreview ? `Block ${sec.path}: ${esc(contentPreview)}${sec.block.content && sec.block.content.length > 30 ? '...' : ''}` : `Block ${sec.path}`;
            const annCount = Object.keys(sec.computed).length + Object.keys(sec.removed).length;

            html += PU.rightPanel._renderAnnSection(`block-${pathId}`, label, annCount, () => {
                let entries = '';
                // Computed annotations with sources
                for (const [k, v] of Object.entries(sec.computed)) {
                    entries += PU.rightPanel._renderAnnEntry(k, v, sec.sources[k] || 'block');
                }
                // Removed annotations
                for (const [k, origSource] of Object.entries(sec.removed)) {
                    entries += `<div class="pu-rp-ann-entry removed" data-testid="pu-rp-ann-entry-removed-${escAttr(k)}">
                        <span class="pu-rp-ann-entry-key">${esc(k)}:</span>
                        <span class="pu-rp-ann-entry-value">(removed)</span>
                        <span class="pu-rp-ann-entry-source">${esc(origSource)}</span>
                    </div>`;
                }
                if (!entries) return '<div class="pu-rp-ann-section-empty">No annotations</div>';
                return entries;
            }, sec.path, `pu-rp-ann-title-block`);
        }

        if (!html) {
            html = '<div class="pu-rp-note">No annotations in this prompt</div>';
        }

        container.innerHTML = html;

        // Attach click-to-scroll handlers for block sections
        container.querySelectorAll('[data-scroll-to-block]').forEach(el => {
            el.addEventListener('click', (e) => {
                e.stopPropagation();
                const path = el.dataset.scrollToBlock;
                PU.rightPanel._scrollToBlock(path);
            });
        });

        // Attach click-to-edit handlers for annotation entries
        container.querySelectorAll('[data-edit-block]').forEach(el => {
            el.addEventListener('click', (e) => {
                e.stopPropagation();
                const path = el.dataset.editBlock;
                PU.rightPanel._scrollToBlock(path);
                // Open annotation editor on that block
                setTimeout(() => PU.annotations.openEditor(path), 150);
            });
        });

        // Attach section toggle handlers
        container.querySelectorAll('.pu-rp-ann-section-header').forEach(header => {
            header.addEventListener('click', () => {
                const section = header.closest('.pu-rp-ann-section');
                if (section) section.classList.toggle('collapsed');
            });
        });
    },

    /**
     * Render a collapsible annotation section.
     */
    _renderAnnSection(id, title, count, renderBody, blockPath, titleClass) {
        const cls = titleClass || `pu-rp-ann-title-${id}`;
        const bodyHtml = renderBody();
        const blockPathEl = blockPath
            ? ` <span class="pu-rp-ann-block-path" data-scroll-to-block="${PU.blocks.escapeAttr(blockPath)}" title="Scroll to block">${PU.blocks.escapeHtml(blockPath)}</span>`
            : '';

        return `<div class="pu-rp-ann-section" data-testid="pu-rp-ann-section-${PU.blocks.escapeAttr(id)}">
            <div class="pu-rp-ann-section-header">
                <span class="pu-rp-ann-section-chevron">&#9660;</span>
                <span class="pu-rp-ann-section-title ${cls}">${title}</span>
                <span class="pu-rp-ann-section-count">${count > 0 ? `(${count})` : ''}</span>
                ${blockPathEl}
            </div>
            <div class="pu-rp-ann-section-body" data-testid="pu-rp-ann-body-${PU.blocks.escapeAttr(id)}">
                ${bodyHtml}
            </div>
        </div>`;
    },

    /**
     * Render a single annotation entry row.
     */
    _renderAnnEntry(key, value, source) {
        const esc = PU.blocks.escapeHtml;
        const displayValue = value === null ? '(null)' : String(value);
        return `<div class="pu-rp-ann-entry" data-testid="pu-rp-ann-entry-${esc(key)}">
            <span class="pu-rp-ann-entry-key">${esc(key)}:</span>
            <span class="pu-rp-ann-entry-value" title="${PU.blocks.escapeAttr(displayValue)}">${esc(displayValue)}</span>
            <span class="pu-rp-ann-entry-source">${esc(source)}</span>
        </div>`;
    },

    /**
     * Walk all blocks in the text tree, calling fn(block, path) for each.
     */
    _walkBlocks(textItems, prefix, fn) {
        if (!Array.isArray(textItems)) return;
        for (let i = 0; i < textItems.length; i++) {
            const item = textItems[i];
            const path = prefix ? `${prefix}.${i}` : String(i);
            fn(item, path);
            if (item.after && Array.isArray(item.after)) {
                PU.rightPanel._walkBlocks(item.after, path, fn);
            }
        }
    },

    /**
     * Scroll the editor canvas to a specific block and briefly highlight it.
     */
    _scrollToBlock(path) {
        const pathId = path.replace(/\./g, '-');
        const blockEl = document.querySelector(`[data-testid="pu-block-${pathId}"]`);
        if (!blockEl) return;

        blockEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
        blockEl.classList.add('pu-highlight-match');
        setTimeout(() => blockEl.classList.remove('pu-highlight-match'), 1500);
    },

    /**
     * Update the Annotations tab button label with total annotation count.
     */
    _updateAnnotationsTabCount(job, prompt) {
        const tabBtn = document.querySelector('[data-testid="pu-rp-tab-annotations"]');
        if (!tabBtn) return;

        if (!prompt) {
            tabBtn.textContent = 'Annotations';
            return;
        }

        const defaultsCount = Object.keys((job && job.defaults && job.defaults.annotations) || {}).length;
        const promptCount = Object.keys((prompt.annotations) || {}).length;

        let blockCount = 0;
        PU.rightPanel._walkBlocks(prompt.text || [], '', (block) => {
            blockCount += Object.keys(block.annotations || {}).length;
        });

        const total = defaultsCount + promptCount + blockCount;
        tabBtn.textContent = total > 0 ? `Annotations (${total})` : 'Annotations';
    },

    // ============================================
    // Job Defaults Popover (header gear icon)
    // ============================================

    toggleDefaultsPopover() {
        const popover = document.querySelector('[data-testid="pu-defaults-popover"]');
        if (!popover) return;
        if (popover.style.display !== 'none') {
            PU.rightPanel.hideDefaultsPopover();
        } else {
            PU.rightPanel.renderDefaultsPopover();
            popover.style.display = 'block';
        }
    },

    hideDefaultsPopover() {
        const popover = document.querySelector('[data-testid="pu-defaults-popover"]');
        if (popover) popover.style.display = 'none';
    },

    renderDefaultsPopover() {
        const popover = document.querySelector('[data-testid="pu-defaults-popover"]');
        if (!popover) return;

        const job = PU.helpers.getActiveJob();
        if (!job) {
            popover.innerHTML = '<div class="pu-defaults-popover-empty">No job selected</div>';
            return;
        }

        const defaults = job.defaults || {};
        const annotations = defaults.annotations || {};
        const esc = PU.blocks.escapeHtml;
        const escAttr = PU.blocks.escapeAttr;

        // Ext theme dropdown
        const tree = PU.state.globalExtensions.tree;
        const hasExtensions = tree && Object.keys(tree).filter(k => k !== '_files').length > 0;
        let extHtml = '';
        if (hasExtensions) {
            extHtml = `<div class="pu-defaults-popover-row">
                <label>ext</label>
                <select data-testid="pu-defaults-popover-ext"
                        onchange="PU.actions.updateDefaults('ext', this.value); PU.rightPanel.renderDefaultsPopover()">
                    <option value="">Loading...</option>
                </select>
            </div>`;
        }

        // Numeric defaults (read-only display)
        let infoHtml = '';
        const infoKeys = ['wildcards_max', 'ext_text_max', 'composition'];
        for (const key of infoKeys) {
            if (defaults[key] !== undefined) {
                infoHtml += `<div class="pu-defaults-popover-row">
                    <label>${esc(key)}</label>
                    <span class="pu-defaults-popover-val">${esc(String(defaults[key]))}</span>
                </div>`;
            }
        }

        // Annotations (editable)
        let annRows = '';
        for (const [key, value] of Object.entries(annotations)) {
            annRows += `<div class="pu-defaults-popover-ann-row" data-testid="pu-defaults-ann-row-${escAttr(key)}">
                <input type="text" class="pu-ann-key" value="${escAttr(key)}" placeholder="key"
                       onchange="PU.rightPanel._handleDefaultsAnnKeyChange('${escAttr(key)}', this)"
                       onclick="event.stopPropagation()">
                <input type="text" class="pu-ann-value" value="${escAttr(String(value))}" placeholder="value"
                       onchange="PU.rightPanel._handleDefaultsAnnValueChange('${escAttr(key)}', this)"
                       onclick="event.stopPropagation()">
                <button class="pu-ann-remove"
                        onclick="event.stopPropagation(); PU.rightPanel._removeDefaultsAnn('${escAttr(key)}')">&times;</button>
            </div>`;
        }

        popover.innerHTML = `
            <div class="pu-defaults-popover-header">
                <span>Job Defaults</span>
                <button class="pu-annotation-close" onclick="PU.rightPanel.hideDefaultsPopover()">&times;</button>
            </div>
            ${extHtml}
            ${infoHtml}
            <div class="pu-defaults-popover-divider">Annotations</div>
            <div class="pu-defaults-popover-ann" data-testid="pu-defaults-popover-ann">
                ${annRows || '<div class="pu-defaults-popover-empty-ann">No default annotations</div>'}
            </div>
            <button class="pu-annotation-add" data-testid="pu-defaults-ann-add"
                    onclick="event.stopPropagation(); PU.rightPanel._addDefaultsAnn()">+ Add annotation</button>
        `;

        // Populate ext dropdown after rendering
        if (hasExtensions) {
            const extSelect = popover.querySelector('[data-testid="pu-defaults-popover-ext"]');
            if (extSelect) {
                PU.editor.populateExtDropdown(extSelect, defaults.ext || 'defaults');
            }
        }
    },

    /** Get the modifiable job object (creates clone if needed) */
    _ensureModifiedJob() {
        const jobId = PU.state.activeJobId;
        if (!jobId) return null;
        if (!PU.state.modifiedJobs[jobId]) {
            PU.state.modifiedJobs[jobId] = PU.helpers.deepClone(PU.state.jobs[jobId]);
        }
        return PU.state.modifiedJobs[jobId];
    },

    _handleDefaultsAnnKeyChange(oldKey, inputEl) {
        const job = PU.rightPanel._ensureModifiedJob();
        if (!job) return;
        if (!job.defaults) job.defaults = {};
        if (!job.defaults.annotations) job.defaults.annotations = {};

        const newKey = inputEl.value.trim();
        if (!newKey || newKey === oldKey) return;

        const value = job.defaults.annotations[oldKey];
        const newAnn = {};
        for (const [k, v] of Object.entries(job.defaults.annotations)) {
            newAnn[k === oldKey ? newKey : k] = k === oldKey ? value : v;
        }
        job.defaults.annotations = newAnn;

        PU.rightPanel.renderDefaultsPopover();
        PU.annotations.propagateFromParent();
    },

    _handleDefaultsAnnValueChange(key, inputEl) {
        const job = PU.rightPanel._ensureModifiedJob();
        if (!job) return;
        if (!job.defaults) job.defaults = {};
        if (!job.defaults.annotations) job.defaults.annotations = {};

        let value = inputEl.value;
        if (value === 'true') value = true;
        else if (value === 'false') value = false;
        else if (value !== '' && !isNaN(Number(value))) value = Number(value);

        job.defaults.annotations[key] = value;
        PU.annotations.propagateFromParent();
    },

    _addDefaultsAnn() {
        const job = PU.rightPanel._ensureModifiedJob();
        if (!job) return;
        if (!job.defaults) job.defaults = {};
        if (!job.defaults.annotations) job.defaults.annotations = {};

        let keyName = 'key';
        let counter = 1;
        while (job.defaults.annotations.hasOwnProperty(keyName)) {
            keyName = `key${counter++}`;
        }
        job.defaults.annotations[keyName] = '';

        PU.rightPanel.renderDefaultsPopover();
        PU.annotations.propagateFromParent();
    },

    _removeDefaultsAnn(key) {
        const job = PU.rightPanel._ensureModifiedJob();
        if (!job || !job.defaults || !job.defaults.annotations) return;

        delete job.defaults.annotations[key];
        if (Object.keys(job.defaults.annotations).length === 0) {
            delete job.defaults.annotations;
        }

        PU.rightPanel.renderDefaultsPopover();
        PU.annotations.propagateFromParent();
    },

    // ============================================
    // Prompt Annotations Bar (right panel top)
    // ============================================

    togglePromptAnnotations() {
        const section = document.querySelector('[data-testid="pu-rp-prompt-ann"]');
        if (section) section.classList.toggle('collapsed');
        PU.state.ui.sectionsCollapsed.promptAnn = section?.classList.contains('collapsed') ?? false;
        PU.helpers.saveUIState();
    },

    renderPromptAnnotations() {
        const bar = document.querySelector('[data-testid="pu-rp-prompt-ann"]');
        if (!bar) return;

        const prompt = PU.helpers.getActivePrompt();
        const annotations = (prompt && prompt.annotations) || {};
        const count = Object.keys(annotations).length;

        // Update count badge
        const countEl = bar.querySelector('[data-testid="pu-rp-prompt-ann-count"]');
        if (countEl) {
            countEl.textContent = count > 0 ? `(${count})` : '';
        }

        // Hide bar when no prompt selected
        bar.style.display = prompt ? '' : 'none';

        // Apply persisted collapse state (collapsed by default)
        const isCollapsed = PU.state.ui.sectionsCollapsed.promptAnn !== false;
        bar.classList.toggle('collapsed', isCollapsed);

        // Render body
        const body = bar.querySelector('[data-testid="pu-rp-prompt-ann-body"]');
        if (!body) return;

        const escAttr = PU.blocks.escapeAttr;
        let rowsHtml = '';
        for (const [key, value] of Object.entries(annotations)) {
            rowsHtml += `<div class="pu-defaults-popover-ann-row" data-testid="pu-prompt-ann-row-${escAttr(key)}">
                <input type="text" class="pu-ann-key" value="${escAttr(key)}" placeholder="key"
                       onchange="PU.rightPanel._handlePromptAnnKeyChange('${escAttr(key)}', this)"
                       onclick="event.stopPropagation()">
                <input type="text" class="pu-ann-value" value="${escAttr(String(value))}" placeholder="value"
                       onchange="PU.rightPanel._handlePromptAnnValueChange('${escAttr(key)}', this)"
                       onclick="event.stopPropagation()">
                <button class="pu-ann-remove"
                        onclick="event.stopPropagation(); PU.rightPanel._removePromptAnn('${escAttr(key)}')">&times;</button>
            </div>`;
        }

        body.innerHTML = `
            <div class="pu-rp-prompt-ann-rows" data-testid="pu-rp-prompt-ann-rows">
                ${rowsHtml || '<div class="pu-defaults-popover-empty-ann">No prompt annotations</div>'}
            </div>
            <button class="pu-annotation-add" data-testid="pu-prompt-ann-add"
                    onclick="event.stopPropagation(); PU.rightPanel._addPromptAnn()">+ Add annotation</button>
        `;
    },

    _handlePromptAnnKeyChange(oldKey, inputEl) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;
        if (!prompt.annotations) prompt.annotations = {};

        const newKey = inputEl.value.trim();
        if (!newKey || newKey === oldKey) return;

        const value = prompt.annotations[oldKey];
        const newAnn = {};
        for (const [k, v] of Object.entries(prompt.annotations)) {
            newAnn[k === oldKey ? newKey : k] = k === oldKey ? value : v;
        }
        prompt.annotations = newAnn;

        PU.rightPanel.renderPromptAnnotations();
        PU.annotations.propagateFromParent();
    },

    _handlePromptAnnValueChange(key, inputEl) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;
        if (!prompt.annotations) prompt.annotations = {};

        let value = inputEl.value;
        if (value === 'true') value = true;
        else if (value === 'false') value = false;
        else if (value !== '' && !isNaN(Number(value))) value = Number(value);

        prompt.annotations[key] = value;
        PU.annotations.propagateFromParent();
    },

    _addPromptAnn() {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;
        if (!prompt.annotations) prompt.annotations = {};

        let keyName = 'key';
        let counter = 1;
        while (prompt.annotations.hasOwnProperty(keyName)) {
            keyName = `key${counter++}`;
        }
        prompt.annotations[keyName] = '';

        PU.rightPanel.renderPromptAnnotations();
        PU.annotations.propagateFromParent();
    },

    _removePromptAnn(key) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !prompt.annotations) return;

        delete prompt.annotations[key];
        if (Object.keys(prompt.annotations).length === 0) {
            delete prompt.annotations;
        }

        PU.rightPanel.renderPromptAnnotations();
        PU.annotations.propagateFromParent();
    },

    // ============================================
    // Wildcard Stream
    // ============================================

    /**
     * Render the wildcard stream: header + entries grouped by source.
     * Two sections: "shared" (ext + theme wildcards merged) and "local" (prompt-defined).
     */
    renderWildcardStream() {
        const container = document.querySelector('[data-testid="pu-rp-wc-stream"]');
        if (!container) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            container.innerHTML = '<div class="pu-rp-note">Select a prompt to see wildcards</div>';
            PU.rightPanel._updateTopBar(null, 0);
            return;
        }

        // Get local wildcards (from prompt definition)
        const localLookup = PU.helpers.getWildcardLookup();
        const localNames = new Set(Object.keys(localLookup));

        // Get full lookup (local + ext)
        const fullLookup = PU.preview.getFullWildcardLookup();
        const allNames = Object.keys(fullLookup).sort();

        if (allNames.length === 0) {
            container.innerHTML = '<div class="pu-rp-note">No wildcards or themes yet. The panel shows the composition navigator once wildcards are added.</div>';
            PU.rightPanel._updateTopBar(prompt, 0);
            return;
        }

        // Classify wildcards into "shared" (ext + theme) and "local"
        const sharedWildcards = [];
        const localWildcards = [];
        const themeSourceMap = PU.shared.buildThemeSourceMap();

        for (const name of allNames) {
            const isLocal = localNames.has(name);
            const isExt = !isLocal || PU.shared.isExtWildcard(name);
            const themeSrc = themeSourceMap[name];

            if (isLocal && isExt) {
                localWildcards.push({ name, source: 'override' });
            } else if (isLocal) {
                localWildcards.push({ name, source: 'local' });
            } else if (themeSrc) {
                sharedWildcards.push({ name, source: 'theme', path: themeSrc });
            } else {
                sharedWildcards.push({ name, source: 'ext', path: PU.shared.getExtWildcardPath(name) });
            }
        }

        // Get current composition indices for active chip highlighting
        const wildcardCounts = {};
        for (const name of allNames) {
            wildcardCounts[name] = fullLookup[name].length;
        }
        const extTextCount = PU.state.previewMode.extTextCount || 1;
        const compositionId = PU.state.previewMode.compositionId;

        let odometerIndices;
        [, odometerIndices] = PU.preview.compositionToIndices(compositionId, extTextCount, wildcardCounts);

        // Resolve active indices: prefer selectedWildcards['*'] overrides over odometer
        const globalOverrides = (PU.state.previewMode.selectedWildcards || {})['*'] || {};
        const resolvedIndices = {};
        for (const name of allNames) {
            let idx = odometerIndices[name] || 0;
            if (globalOverrides[name] !== undefined) {
                const overrideIdx = fullLookup[name].indexOf(globalOverrides[name]);
                if (overrideIdx >= 0) idx = overrideIdx;
            }
            resolvedIndices[name] = idx;
        }

        // Collect locked values and block-level pins
        const lockedValues = PU.state.previewMode.lockedValues || {};
        const allOverrides = PU.state.previewMode.selectedWildcards || {};
        const blockPins = {};
        for (const [bPath, overrides] of Object.entries(allOverrides)) {
            if (bPath === '*') continue;
            for (const [wcName, val] of Object.entries(overrides)) {
                if (!blockPins[wcName]) blockPins[wcName] = new Set();
                blockPins[wcName].add(val);
            }
        }

        let html = '';

        // Shared wildcards section (ext + theme merged)
        if (sharedWildcards.length > 0) {
            html += PU.rightPanel._renderDivider('shared');
            html += '<div class="pu-rp-wc-section">';
            for (const wc of sharedWildcards) {
                html += PU.rightPanel._renderWcEntry(wc, fullLookup[wc.name], resolvedIndices[wc.name] || 0, blockPins, lockedValues);
            }
            html += '</div>';
        }

        // Local wildcards section
        if (localWildcards.length > 0) {
            html += PU.rightPanel._renderDivider('local');
            html += '<div class="pu-rp-wc-section">';
            for (const wc of localWildcards) {
                html += PU.rightPanel._renderWcEntry(wc, fullLookup[wc.name], resolvedIndices[wc.name] || 0, blockPins, lockedValues);
            }
            html += '</div>';
        }

        container.innerHTML = html;

        // Update top bar
        PU.rightPanel._updateTopBar(prompt, allNames.length);

        // Attach chip click handlers
        // Click = preview (update selectedWildcards['*'] + re-render)
        // Ctrl+Click = toggle lock (add/remove from lockedValues)
        container.querySelectorAll('.pu-rp-wc-v').forEach(chip => {
            chip.addEventListener('click', (e) => {
                const wcName = chip.dataset.wcName;
                const val = chip.dataset.value;
                const idx = parseInt(chip.dataset.idx, 10);
                if (wcName && val !== undefined) {
                    if (e.ctrlKey || e.metaKey) {
                        PU.rightPanel.toggleLock(wcName, val);
                    } else {
                        PU.rightPanel.previewValue(wcName, val, idx);
                    }
                }
            });

            // Right-click: show replacement popover (operation value replacement)
            chip.addEventListener('contextmenu', (e) => {
                if (!PU.state.buildComposition.activeOperation) return;
                e.preventDefault();
                PU.rightPanel.showReplacePopover(chip, e);
            });

            // Hover: show footer tip
            chip.addEventListener('mouseenter', () => {
                PU.rightPanel._showFooterTip('<kbd>Ctrl</kbd>+Click lock wildcard');
            });
            chip.addEventListener('mouseleave', () => {
                PU.rightPanel._hideFooterTip();
            });
        });

        // Hover wildcard entry → highlight associated blocks in editor
        // (skip transient hover highlight when a focus is already pinned)
        container.querySelectorAll('.pu-rp-wc-entry').forEach(entry => {
            entry.addEventListener('mouseenter', () => {
                if (PU.state.previewMode.focusedWildcards.length > 0) return;
                const wcName = entry.dataset.wcName;
                if (wcName) PU.rightPanel._highlightBlocksForWildcard(wcName);
            });
            entry.addEventListener('mouseleave', () => {
                if (PU.state.previewMode.focusedWildcards.length > 0) return;
                PU.rightPanel._clearBlockHighlights();
            });
        });

        // Bulb icon click → toggle persistent focus mode for wildcard (multi-focus OR)
        container.querySelectorAll('.pu-wc-focus-icon').forEach(icon => {
            icon.addEventListener('click', (e) => {
                e.stopPropagation();
                const wcName = icon.dataset.wcName;
                if (wcName) PU.rightPanel.toggleFocus(wcName);
            });
        });

        // Push-to-theme trigger click → show push popover
        container.querySelectorAll('.pu-rp-push-trigger').forEach(icon => {
            icon.addEventListener('click', (e) => {
                e.stopPropagation();
                const wcName = icon.dataset.wcName;
                if (wcName) PU.rightPanel.showPushPopover(icon, wcName);
            });
        });

        // Re-apply persistent focus if active
        if (PU.state.previewMode.focusedWildcards.length > 0) {
            PU.rightPanel._applyFocusMulti();
        }
    },

    // ============================================
    // Wildcard ↔ Block Highlight (hover mapping)
    // ============================================

    /**
     * Highlight editor blocks that use the given wildcard.
     * Matching blocks get .pu-highlight-match, their ancestors get .pu-highlight-parent,
     * all others dim via the .pu-wc-highlighting container class.
     */
    _highlightBlocksForWildcard(wcName) {
        const blocksContainer = document.querySelector('[data-testid="pu-blocks-container"]');
        if (!blocksContainer) return;

        const map = PU.editor._wildcardToBlocks;
        if (!map) return;

        const matchingPaths = map[wcName] || new Set();

        // Compute parent paths for all matching blocks
        const parentPaths = new Set();
        for (const path of matchingPaths) {
            const parts = path.split('.');
            for (let i = 1; i < parts.length; i++) {
                parentPaths.add(parts.slice(0, i).join('.'));
            }
        }
        // Match takes priority over parent
        for (const path of matchingPaths) {
            parentPaths.delete(path);
        }

        // Add container-level class (drives default dimming via CSS)
        blocksContainer.classList.add('pu-wc-highlighting');

        // Apply per-block classes
        blocksContainer.querySelectorAll('.pu-block').forEach(block => {
            const path = block.dataset.path;
            block.classList.remove('pu-highlight-match', 'pu-highlight-parent');
            if (matchingPaths.has(path)) {
                block.classList.add('pu-highlight-match');
            } else if (parentPaths.has(path)) {
                block.classList.add('pu-highlight-parent');
            }
        });
    },

    /**
     * Remove all block highlight classes.
     */
    _clearBlockHighlights() {
        const blocksContainer = document.querySelector('[data-testid="pu-blocks-container"]');
        if (!blocksContainer) return;

        blocksContainer.classList.remove('pu-wc-highlighting');
        blocksContainer.querySelectorAll('.pu-block').forEach(block => {
            block.classList.remove('pu-highlight-match', 'pu-highlight-parent');
        });
    },

    // ============================================
    // Wildcard Focus Mode (bulb toggle, multi-focus OR)
    // ============================================

    /**
     * Toggle persistent focus for a wildcard (multi-focus OR union).
     * Each bulb click adds/removes a wildcard from the focused set.
     * Visible blocks = union of all focused wildcards' blocks.
     */
    toggleFocus(wcName) {
        const focused = PU.state.previewMode.focusedWildcards;
        const idx = focused.indexOf(wcName);
        if (idx >= 0) {
            // Remove from set
            focused.splice(idx, 1);
        } else {
            // Add to set
            focused.push(wcName);
        }

        if (focused.length === 0) {
            PU.rightPanel._removeFocus();
        } else {
            PU.rightPanel._applyFocusMulti();
        }
        PU.rightPanel.render();
    },

    /**
     * Clear all wildcard focus — restore all blocks.
     */
    clearFocus() {
        PU.state.previewMode.focusedWildcards = [];
        PU.rightPanel._removeFocus();
        PU.rightPanel.render();
    },

    /**
     * Apply multi-focus mode (OR union): show blocks matching ANY focused wildcard.
     */
    _applyFocusMulti() {
        const blocksContainer = document.querySelector('[data-testid="pu-blocks-container"]');
        if (!blocksContainer) return;

        const map = PU.editor._wildcardToBlocks;
        if (!map) return;

        const focused = PU.state.previewMode.focusedWildcards;
        if (focused.length === 0) return;

        // Union of all matching paths across focused wildcards
        const matchingPaths = new Set();
        for (const wcName of focused) {
            const paths = map[wcName] || new Set();
            for (const p of paths) matchingPaths.add(p);
        }

        // Compute parent paths
        const parentPaths = new Set();
        for (const path of matchingPaths) {
            const parts = path.split('.');
            for (let i = 1; i < parts.length; i++) {
                parentPaths.add(parts.slice(0, i).join('.'));
            }
        }
        for (const path of matchingPaths) {
            parentPaths.delete(path);
        }

        // Add focus class to container
        blocksContainer.classList.add('pu-wc-focus-active');
        blocksContainer.classList.remove('pu-wc-highlighting');

        // Classify blocks
        let hiddenCount = 0;
        let totalBlocks = 0;
        blocksContainer.querySelectorAll('.pu-block').forEach(block => {
            const path = block.dataset.path;
            totalBlocks++;
            block.classList.remove('pu-highlight-match', 'pu-highlight-parent', 'pu-focus-hidden');
            if (matchingPaths.has(path)) {
                block.classList.add('pu-highlight-match');
            } else if (parentPaths.has(path)) {
                block.classList.add('pu-highlight-parent');
            } else {
                block.classList.add('pu-focus-hidden');
                if (!path.includes('.')) hiddenCount++;
            }
        });

        // Show banner with all focused names + count
        const visibleCount = totalBlocks - document.querySelectorAll('.pu-block.pu-focus-hidden').length;
        PU.rightPanel._showFocusBanner(focused, visibleCount, totalBlocks);
    },

    /**
     * Remove focus mode — restore all blocks, remove banner.
     */
    _removeFocus() {
        const blocksContainer = document.querySelector('[data-testid="pu-blocks-container"]');
        if (!blocksContainer) return;

        blocksContainer.classList.remove('pu-wc-focus-active', 'pu-wc-highlighting');
        blocksContainer.querySelectorAll('.pu-block').forEach(block => {
            block.classList.remove('pu-highlight-match', 'pu-highlight-parent', 'pu-focus-hidden');
        });

        PU.rightPanel._hideFocusBanner();
    },

    /**
     * Show the focus mode banner above the blocks container.
     * Shows all focused wildcard names and block counts.
     */
    _showFocusBanner(focusedNames, visibleCount, totalCount) {
        let banner = document.querySelector('[data-testid="pu-focus-banner"]');
        const blocksContainer = document.querySelector('[data-testid="pu-blocks-container"]');
        if (!blocksContainer) return;

        if (!banner) {
            banner = document.createElement('div');
            banner.className = 'pu-focus-banner';
            banner.dataset.testid = 'pu-focus-banner';
            blocksContainer.parentNode.insertBefore(banner, blocksContainer);
        }

        const esc = PU.blocks.escapeHtml;
        const namesHtml = focusedNames.map(n => `<b>__${esc(n)}__</b>`).join(', ');
        const countText = ` &middot; ${visibleCount}/${totalCount} blocks`;
        banner.innerHTML = `<span class="pu-focus-banner-text">&#128161; ${namesHtml}${countText}</span><button class="pu-focus-banner-close" data-testid="pu-focus-banner-close" title="Clear all focus">&times;</button>`;
        banner.style.display = 'flex';

        banner.querySelector('.pu-focus-banner-close').addEventListener('click', () => {
            PU.rightPanel.clearFocus();
        });
    },

    /**
     * Hide the focus mode banner.
     */
    _hideFocusBanner() {
        const banner = document.querySelector('[data-testid="pu-focus-banner"]');
        if (banner) banner.style.display = 'none';
    },

    /**
     * Render a centered line divider: ─── label ───
     */
    _renderDivider(label) {
        return `<div class="pu-rp-wc-divider">
            <span class="pu-rp-wc-divider-line"></span>
            <span class="pu-rp-wc-divider-label">${PU.blocks.escapeHtml(label)}</span>
            <span class="pu-rp-wc-divider-line"></span>
        </div>`;
    },

    /**
     * Render a single wildcard entry with header (name + path) + flat chips.
     * Click = preview, Ctrl+Click = lock/unlock.
     * Operation mode: replaced-val chips show replacement text with asterisk.
     */
    _renderWcEntry(wc, values, activeIdx, blockPins, lockedValues) {
        const esc = PU.blocks.escapeHtml;
        const name = wc.name;
        const safeName = esc(name);
        const isShared = wc.source === 'theme' || wc.source === 'ext';

        // Operation mappings for this wildcard
        const opMappings = PU.rightPanel._getOpMappings(name);

        // Block-level per-block override indicator (shown as active chips instead of asterisk)

        // Override mark on name if operation has mappings for this wildcard
        const overrideMark = opMappings ? '<span class="pu-rp-wc-override-mark" title="Operation has replacements for this wildcard">*</span>' : '';

        // wc-path for shared wildcards (shows source like "professional/tones")
        let pathHtml = '';
        if (isShared && wc.path) {
            pathHtml = `<span class="pu-rp-wc-path">${esc(wc.path)}</span>`;
        }

        // Overlap warning: wildcard exists in both local and theme/ext sources
        // Clickable — opens push-to-theme popover
        let overlapWarning = '';
        if (wc.source === 'override') {
            const dirtyInfo = PU.rightPanel._getWildcardDirtyInfo(name);
            const isDirty = dirtyInfo && dirtyInfo.themes.some(t => t.added.length > 0 || t.removed.length > 0);
            const dirtyClass = isDirty ? ' pu-rp-push-dirty' : '';
            const themePath = PU.shared.buildThemeSourceMap()[name] || PU.shared.getExtWildcardPath(name);
            overlapWarning = `<span class="pu-rp-wc-overlap-warn pu-rp-push-trigger${dirtyClass}"
                data-testid="pu-rp-push-trigger-${safeName}"
                data-wc-name="${safeName}"
                title="${isDirty ? 'Local values differ from theme — click to push' : 'Also defined in ' + esc(themePath) + ' — click to push local values'}">&#9888;</span>`;
        }

        const wrappedIdx = values.length > 0 ? activeIdx % values.length : 0;

        // Helper: render a single chip with operation replacement applied
        const renderChip = (originalValue, i) => {
            let displayValue = originalValue;
            let cls = 'pu-rp-wc-v';
            let isReplaced = false;
            let extraAttrs = '';

            if (opMappings && opMappings[originalValue] !== undefined) {
                displayValue = opMappings[originalValue];
                cls += ' replaced-val';
                isReplaced = true;
                extraAttrs += ` data-original="${esc(originalValue)}"`;
            }

            // Active: global odometer position OR per-block override value
            const isBlockActive = blockPins[name] && blockPins[name].has(originalValue);
            if (i === wrappedIdx || isBlockActive) {
                cls += ' active';
            }

            // Locked value indicator
            const isLocked = lockedValues[name] && lockedValues[name].includes(originalValue);
            if (isLocked) cls += ' locked';

            const asterisk = isReplaced ? '<span class="asterisk">*</span>' : '';
            const lockIcon = isLocked ? '<span class="lock-icon">&#128274;</span>' : '';

            // Tooltip: locked > replacement > default
            let titleAttr;
            if (isReplaced) {
                titleAttr = ` title="replaces &quot;${esc(originalValue)}&quot;"`;
            } else if (isLocked) {
                titleAttr = ` title="Locked — Ctrl+Click to unlock"`;
            } else {
                titleAttr = ` title="Click to preview, Ctrl+Click to lock"`;
            }

            return `<span class="${cls}" data-testid="pu-rp-wc-chip-${safeName}-${i}" data-wc-name="${safeName}" data-value="${esc(originalValue)}" data-idx="${i}"${titleAttr}${extraAttrs}>${lockIcon}${esc(displayValue)}${asterisk}</span>`;
        };

        // All chips rendered flat — no bucket window framing
        const chipsHtml = values.map((v, i) => renderChip(v, i)).join('');

        // Unmatched operation rules warning
        let unmatchedHtml = '';
        if (opMappings) {
            const valuesSet = new Set(values);
            const unmatched = [];
            for (const [original, replacement] of Object.entries(opMappings)) {
                if (!valuesSet.has(original)) {
                    unmatched.push({ original, replacement });
                }
            }
            for (const u of unmatched) {
                unmatchedHtml += `<div class="pu-rp-wc-unmatched" data-testid="pu-rp-unmatched-${safeName}">
                    <span class="pu-rp-wc-unmatched-icon">&#9888;</span>
                    "${esc(u.original)}" &rarr; ${esc(u.replacement)} (no match in prompt)
                </div>`;
            }
        }

        const isFocused = PU.state.previewMode.focusedWildcards.includes(name);
        // Only show bulb icon when 2+ text blocks (focus is meaningless with 1 block)
        const promptData = PU.helpers.getActivePrompt();
        const textBlockCount = (promptData && Array.isArray(promptData.text)) ? promptData.text.length : 0;
        const focusIcon = textBlockCount >= 2
            ? `<span class="pu-wc-focus-icon${isFocused ? ' active' : ''}" data-testid="pu-wc-focus-${safeName}" data-wc-name="${safeName}" title="${isFocused ? 'Remove from focus' : 'Illuminate: show blocks using this wildcard'}">&#128161;</span>`
            : '';

        return `<div class="pu-rp-wc-entry${isFocused ? ' pu-wc-entry-focused' : ''}" data-testid="pu-rp-wc-entry-${safeName}" data-wc-name="${safeName}">
            <div class="pu-rp-wc-entry-header">
                <span class="pu-rp-wc-name">${safeName}${overrideMark}</span>
                ${pathHtml}
                ${overlapWarning}
                ${focusIcon}
            </div>
            <div class="pu-rp-wc-values">${chipsHtml}</div>
            ${unmatchedHtml}
        </div>`;
    },

    // ============================================
    // Compositions Section
    // ============================================

    /**
     * Render the compositions section: nav (N / total + window hint) + per-wildcard dims + export
     */
    async renderOpsSection() {
        const container = document.querySelector('[data-testid="pu-rp-ops-section"]');
        if (!container) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            container.innerHTML = '';
            return;
        }

        const { wcNames, wildcardCounts, extTextCount, total } = PU.shared.getCompositionParams();

        // Gap 5: Hide entirely when no wildcards exist
        if (wcNames.length === 0 && extTextCount <= 1) {
            container.innerHTML = '';
            return;
        }

        const lockedValues = PU.state.previewMode.lockedValues || {};

        // Composition count: product of locked value counts (or 1 per wildcard if unlocked)
        // This IS the export batch size
        const lockedTotal = PU.shared.computeLockedTotal(wildcardCounts, extTextCount, lockedValues);

        // Per-wildcard dimension summary
        let dimsHtml = '';
        if (wcNames.length > 0 || extTextCount > 1) {
            const dimParts = [];
            const sortedWc = wcNames.slice().sort();

            if (extTextCount > 1) {
                dimParts.push(`<span class="pu-rp-ops-dim">${extTextCount} txt</span>`);
            }

            for (const n of sortedWc) {
                const count = wildcardCounts[n];
                const locked = lockedValues[n];
                const abbr = n.length > 4 ? n.slice(0, 3) : n;
                if (locked && locked.length > 0) {
                    dimParts.push(`<span class="pu-rp-ops-dim"><b>${locked.length}</b><span class="dim-sep">/</span>${count} ${PU.blocks.escapeHtml(abbr)}</span>`);
                } else {
                    dimParts.push(`<span class="pu-rp-ops-dim">${count} ${PU.blocks.escapeHtml(abbr)}</span>`);
                }
            }

            dimsHtml = dimParts.join('<span class="pu-rp-ops-x">&times;</span>');
        }

        // Size estimate
        const sampleSize = 200;
        const sizeStr = PU.shared.formatBytes(sampleSize * lockedTotal);

        container.innerHTML = `
            <div class="pu-rp-ops-nav">
                <span class="pu-rp-ops-nav-text" data-testid="pu-rp-nav-label"><b>${lockedTotal.toLocaleString()}</b> compositions</span>
            </div>
            ${dimsHtml ? `<div class="pu-rp-ops-dims" data-testid="pu-rp-ops-dims">${dimsHtml}</div>` : ''}
            <div class="pu-rp-ops-bottom-row">
                <span class="pu-rp-ops-total" data-testid="pu-rp-ops-total">${lockedTotal.toLocaleString()} compositions</span>
                <span class="pu-rp-ops-size" data-testid="pu-rp-ops-size">~${sizeStr}</span>
                <button class="pu-rp-ops-export-btn" data-testid="pu-rp-export-btn" onclick="PU.buildComposition.exportTxt()">Export${PU.state.buildComposition.activeOperation ? `<span class="variant-label">&middot; ${PU.blocks.escapeHtml(PU.state.buildComposition.activeOperation)}</span>` : ' .txt'}</button>
            </div>
            ${PU.rightPanel.isSessionDirty() ? `<button class="pu-rp-session-save-btn" data-testid="pu-rp-session-save" onclick="PU.rightPanel.saveSession()">Save session</button>` : ''}
        `;

        // Resolve output and update size estimate
        await PU.rightPanel._resolveAndUpdateSize();
    },

    /**
     * Resolve output to get accurate size estimate
     */
    async _resolveAndUpdateSize() {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return;

        const textItems = prompt.text || [];
        if (!Array.isArray(textItems) || textItems.length === 0) return;

        try {
            const resolutions = await PU.preview.buildBlockResolutions(textItems, {
                skipOdometerUpdate: true,
                ignoreOverrides: true
            });

            const terminals = PU.preview.computeTerminalOutputs(textItems, resolutions);
            if (terminals.length > 0) {
                PU.rightPanel._updateSizeEstimate(terminals[0].text);
            }
        } catch (e) {
            // Silent — size stays at estimate
        }
    },

    /**
     * Update export size estimate from actual resolved output
     */
    _updateSizeEstimate(sampleText) {
        const sizeEl = document.querySelector('[data-testid="pu-rp-ops-size"]');
        const exportBtn = document.querySelector('[data-testid="pu-rp-export-btn"]');
        if (!sizeEl) return;

        const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        const lockedValues = PU.state.previewMode.lockedValues || {};
        const total = PU.shared.computeLockedTotal(wildcardCounts, extTextCount, lockedValues);
        const sampleBytes = new Blob([sampleText]).size;
        const headerBytes = 40;
        const totalBytes = (sampleBytes + headerBytes + 2) * total;
        const sizeStr = PU.shared.formatBytes(totalBytes);

        sizeEl.textContent = '~' + sizeStr;
        if (exportBtn) {
            const activeOp = PU.state.buildComposition.activeOperation;
            if (activeOp) {
                exportBtn.innerHTML = `Export (~${sizeStr})<span class="variant-label">&middot; ${PU.blocks.escapeHtml(activeOp)}</span>`;
            } else {
                exportBtn.textContent = `Export .txt (~${sizeStr})`;
            }
        }
    },

    // ============================================
    // Session Persistence
    // ============================================

    /**
     * Get a snapshot of the current session-saveable state.
     */
    _getSessionSnapshot() {
        return {
            composition: PU.state.previewMode.compositionId,
            locked_values: PU.helpers.deepClone(PU.state.previewMode.lockedValues),
            active_operation: PU.state.buildComposition.activeOperation || null
        };
    },

    /**
     * Load session state for the active prompt from the server.
     * Hydrates previewMode and sets the baseline for dirty detection.
     */
    async loadSession() {
        const jobId = PU.state.activeJobId;
        const promptId = PU.state.activePromptId;
        if (!jobId || !promptId) {
            PU.state.previewMode._sessionBaseline = PU.rightPanel._getSessionSnapshot();
            return;
        }

        try {
            const session = await PU.api.loadSession(jobId);
            const promptSession = (session.prompts && session.prompts[promptId]) || null;

            // Always clean up URL flag, regardless of session existence
            delete PU.state.previewMode._compositionFromUrl;

            if (promptSession) {
                // Hydrate state from session (URL params take precedence on initial load)
                if (typeof promptSession.composition === 'number') {
                    PU.state.previewMode.compositionId = promptSession.composition;
                }
                if (promptSession.locked_values && typeof promptSession.locked_values === 'object') {
                    PU.state.previewMode.lockedValues = promptSession.locked_values;
                }
                if (promptSession.active_operation !== undefined) {
                    const opName = promptSession.active_operation;
                    if (opName && PU.state.buildComposition.operations.includes(opName)) {
                        await PU.rightPanel.selectOperation(opName);
                    }
                }

                // Sync locked values to selectedWildcards['*'] for preview
                const locked = PU.state.previewMode.lockedValues;
                if (Object.keys(locked).length > 0) {
                    const sw = PU.state.previewMode.selectedWildcards;
                    if (!sw['*']) sw['*'] = {};
                    for (const [wcName, vals] of Object.entries(locked)) {
                        if (vals.length > 0) {
                            sw['*'][wcName] = vals[vals.length - 1];
                        }
                    }
                }
            }
        } catch (e) {
            console.warn('Failed to load session:', e);
        }

        // Set baseline from current state (after hydration)
        PU.state.previewMode._sessionBaseline = PU.rightPanel._getSessionSnapshot();
        // For debugging
        console.log('[Session] Baseline set:', JSON.stringify(PU.state.previewMode._sessionBaseline));
    },

    /**
     * Check if current state differs from the persisted session baseline.
     */
    isSessionDirty() {
        const baseline = PU.state.previewMode._sessionBaseline;
        if (!baseline) return false;

        const current = PU.rightPanel._getSessionSnapshot();

        if (current.composition !== baseline.composition) return true;
        if (current.active_operation !== baseline.active_operation) return true;
        if (JSON.stringify(current.locked_values) !== JSON.stringify(baseline.locked_values)) return true;

        return false;
    },

    /**
     * Save current session state to server and update baseline.
     */
    async saveSession() {
        const jobId = PU.state.activeJobId;
        const promptId = PU.state.activePromptId;
        if (!jobId || !promptId) return;

        const data = PU.rightPanel._getSessionSnapshot();

        try {
            await PU.api.saveSession(jobId, promptId, data);
            PU.state.previewMode._sessionBaseline = PU.helpers.deepClone(data);
            PU.actions.showToast('Session saved', 'success');
            PU.rightPanel.render();
        } catch (e) {
            console.warn('Failed to save session:', e);
            PU.actions.showToast('Failed to save session', 'error');
        }
    },

    // ============================================
    // Lock-based composition
    // ============================================

    /**
     * Toggle a locked wildcard value.
     * Locked values define the Cartesian product dimensions for export.
     * Click = preview (handled by previewValue), Ctrl+Click = lock (handled here).
     */
    async toggleLock(wcName, value) {
        const locked = PU.state.previewMode.lockedValues;
        if (!locked[wcName]) locked[wcName] = [];

        const idx = locked[wcName].indexOf(value);
        if (idx >= 0) {
            // Already locked — unlock
            locked[wcName].splice(idx, 1);
            if (locked[wcName].length === 0) {
                delete locked[wcName];
            }
        } else {
            // Lock this value
            locked[wcName].push(value);
        }

        // Sync preview override: set selectedWildcards['*'][wcName] to last locked value
        const sw = PU.state.previewMode.selectedWildcards;
        if (!sw['*']) sw['*'] = {};
        if (locked[wcName] && locked[wcName].length > 0) {
            sw['*'][wcName] = value;
        } else {
            delete sw['*'][wcName];
            if (Object.keys(sw['*']).length === 0) {
                delete sw['*'];
            }
        }

        // Re-render blocks instantly (no transitions)
        const container = document.querySelector('[data-testid="pu-blocks-container"]');
        if (container) container.classList.add('pu-no-transition');
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        if (container) {
            requestAnimationFrame(() => requestAnimationFrame(() => {
                container.classList.remove('pu-no-transition');
            }));
        }
        PU.rightPanel.render();
    },

    /**
     * Preview a wildcard value — updates the global preview without locking.
     * Sets selectedWildcards['*'][wcName] to the clicked value and re-renders.
     */
    async previewValue(wcName, value, idx) {
        // Set preview override
        const sw = PU.state.previewMode.selectedWildcards;
        if (!sw['*']) sw['*'] = {};
        sw['*'][wcName] = value;

        // Re-render blocks instantly (no transitions)
        const blockContainer = document.querySelector('[data-testid="pu-blocks-container"]');
        if (blockContainer) blockContainer.classList.add('pu-no-transition');
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        if (blockContainer) {
            requestAnimationFrame(() => requestAnimationFrame(() => {
                blockContainer.classList.remove('pu-no-transition');
            }));
        }
        PU.rightPanel.render();
    },

    // findCompositionForValue — removed (click-to-preview model doesn't need reverse odometer for chips)

    /**
     * Update the top bar with scope, variant selector, and wildcard count.
     */
    _updateTopBar(prompt, wcCount) {
        const topBar = document.querySelector('[data-testid="pu-rp-top-bar"]');
        if (!topBar) return;

        const hasData = prompt && wcCount > 0;

        // Hide/show content elements but always keep top bar visible (for collapse toggle)
        topBar.querySelector('[data-testid="pu-rp-scope"]').style.display = hasData ? '' : 'none';
        topBar.querySelector('.pu-rp-top-sep').style.display = 'none'; // updated below if needed
        topBar.querySelector('[data-testid="pu-rp-op-selector"]').style.display = 'none'; // updated below if needed
        topBar.querySelector('[data-testid="pu-rp-wc-count"]').style.display = hasData ? '' : 'none';

        if (!hasData) return;

        // Scope chip
        const scopeEl = topBar.querySelector('[data-testid="pu-rp-scope"]');
        const job = PU.helpers.getActiveJob();
        const extScope = (prompt && prompt.ext) || (job && job.defaults && job.defaults.ext) || '';
        if (scopeEl) {
            if (extScope) {
                scopeEl.textContent = extScope + '/';
                scopeEl.style.display = '';
            } else {
                scopeEl.style.display = 'none';
            }
        }

        // Separator visibility
        const sep = topBar.querySelector('.pu-rp-top-sep');
        if (sep) sep.style.display = extScope ? '' : 'none';

        // Variant selector (operation dropdown trigger)
        const opEl = topBar.querySelector('[data-testid="pu-rp-op-selector"]');
        if (opEl) {
            const activeOp = PU.state.buildComposition.activeOperation;
            if (activeOp) {
                opEl.className = 'pu-rp-op-selector';
                opEl.innerHTML = `${PU.blocks.escapeHtml(activeOp)} <span class="pu-rp-op-arrow">&#9662;</span>`;
            } else {
                opEl.className = 'pu-rp-op-selector pu-rp-op-none';
                opEl.innerHTML = `None <span class="pu-rp-op-arrow">&#9662;</span>`;
            }
            // Only show selector if there are operations available
            if (PU.state.buildComposition.operations.length > 0) {
                opEl.style.display = '';
                opEl.onclick = () => PU.rightPanel.toggleOpDropdown();
            } else {
                opEl.style.display = 'none';
            }
        }

        // Wildcard count
        const statsEl = topBar.querySelector('[data-testid="pu-rp-wc-count"]');
        if (statsEl) {
            statsEl.textContent = `${wcCount} wc`;
        }
    },

    // findCompositionForBuckets — removed (click-to-preview model doesn't use bucket navigation)

    // ============================================
    // Operation: Replacement Popover
    // ============================================

    /**
     * Show the replacement popover for a right-clicked chip.
     * If chip has a replacement (replaced-val), show edit mode with Remove link.
     * If chip has no replacement, show add mode.
     */
    showReplacePopover(chip, event) {
        PU.overlay.dismissPopovers();
        const popover = document.querySelector('[data-testid="pu-rp-replace-popover"]');
        if (!popover) return;

        const wcName = chip.dataset.wcName;
        const originalValue = chip.dataset.value; // Always the original value
        const isReplaced = chip.classList.contains('replaced-val');
        const opMappings = PU.rightPanel._getOpMappings(wcName);
        const currentReplacement = (opMappings && opMappings[originalValue]) || '';

        // Mark chip with context-target highlight
        document.querySelectorAll('.pu-rp-wc-v.context-target').forEach(el => el.classList.remove('context-target'));
        chip.classList.add('context-target');

        const esc = PU.blocks.escapeHtml;

        let html;
        if (isReplaced) {
            // Edit mode: show original, current replacement, edit input, Remove link
            html = `
                <div class="pu-rp-replace-popover-header">
                    <span class="pu-rp-replace-popover-original">${esc(originalValue)}</span>
                    <span class="pu-rp-replace-popover-arrow">&rarr;</span>
                </div>
                <div class="pu-rp-replace-popover-hint">Edit replacement value:</div>
                <input class="pu-rp-replace-popover-input" data-testid="pu-rp-replace-input"
                       type="text" value="${esc(currentReplacement)}">
                <div class="pu-rp-replace-popover-actions">
                    <button class="pu-rp-replace-popover-btn cancel" data-testid="pu-rp-replace-cancel"
                            onclick="PU.rightPanel.hideReplacePopover()">Cancel</button>
                    <button class="pu-rp-replace-popover-btn apply" data-testid="pu-rp-replace-apply"
                            onclick="PU.rightPanel.applyReplacement('${esc(wcName)}', '${esc(originalValue)}')">Update</button>
                </div>
                <div class="pu-rp-replace-popover-remove" data-testid="pu-rp-replace-remove"
                     onclick="PU.rightPanel.removeReplacement('${esc(wcName)}', '${esc(originalValue)}')">Remove this replacement</div>`;
        } else {
            // Add mode: show original, input placeholder, Apply button
            html = `
                <div class="pu-rp-replace-popover-header">
                    <span class="pu-rp-replace-popover-original">${esc(originalValue)}</span>
                    <span class="pu-rp-replace-popover-arrow">&rarr;</span>
                </div>
                <div class="pu-rp-replace-popover-hint">Replace with (in active operation):</div>
                <input class="pu-rp-replace-popover-input" data-testid="pu-rp-replace-input"
                       type="text" placeholder="e.g. replacement value">
                <div class="pu-rp-replace-popover-actions">
                    <button class="pu-rp-replace-popover-btn cancel" data-testid="pu-rp-replace-cancel"
                            onclick="PU.rightPanel.hideReplacePopover()">Cancel</button>
                    <button class="pu-rp-replace-popover-btn apply" data-testid="pu-rp-replace-apply"
                            onclick="PU.rightPanel.applyReplacement('${esc(wcName)}', '${esc(originalValue)}')">Apply</button>
                </div>`;
        }

        popover.innerHTML = html;

        // Position popover near the right-clicked chip
        const stream = document.querySelector('[data-testid="pu-rp-wc-stream"]');
        if (stream) {
            const streamRect = stream.getBoundingClientRect();
            const chipRect = chip.getBoundingClientRect();
            popover.style.top = (chipRect.bottom - streamRect.top + stream.scrollTop + 4) + 'px';
            popover.style.left = Math.max(4, chipRect.left - streamRect.left) + 'px';
        }

        popover.style.display = 'block';
        PU.overlay.showOverlay();

        // Focus the input
        const input = popover.querySelector('.pu-rp-replace-popover-input');
        if (input) {
            setTimeout(() => {
                input.focus();
                input.select();
            }, 50);

            // Enter key applies, Escape cancels
            input.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    e.preventDefault();
                    PU.rightPanel.applyReplacement(wcName, originalValue);
                } else if (e.key === 'Escape') {
                    e.preventDefault();
                    PU.rightPanel.hideReplacePopover();
                }
            });
        }
    },

    /**
     * Hide the replacement popover and clear context-target.
     */
    hideReplacePopover() {
        const popover = document.querySelector('[data-testid="pu-rp-replace-popover"]');
        if (popover) popover.style.display = 'none';
        document.querySelectorAll('.pu-rp-wc-v.context-target').forEach(el => el.classList.remove('context-target'));
    },

    /**
     * Apply a replacement to the active operation and save.
     * Reads the input value from the popover.
     */
    async applyReplacement(wcName, originalValue) {
        const input = document.querySelector('[data-testid="pu-rp-replace-input"]');
        if (!input) return;

        const newValue = input.value.trim();
        if (!newValue) {
            PU.actions.showToast('Replacement value cannot be empty', 'error');
            return;
        }

        const opData = PU.state.buildComposition.activeOperationData;
        const opName = PU.state.buildComposition.activeOperation;
        const jobId = PU.state.activeJobId;
        if (!opData || !opName || !jobId) return;

        // Update mappings in state
        if (!opData.mappings) opData.mappings = {};
        if (!opData.mappings[wcName]) opData.mappings[wcName] = {};
        opData.mappings[wcName][originalValue] = newValue;

        // Save to server
        try {
            await PU.api.saveOperation(jobId, opName, opData.mappings);
            PU.actions.showToast(`Saved: "${originalValue}" → "${newValue}"`, 'success');
        } catch (e) {
            console.warn('Failed to save operation:', e);
            PU.actions.showToast('Failed to save replacement', 'error');
        }

        PU.rightPanel.hideReplacePopover();
        PU.rightPanel.render();
    },

    /**
     * Remove a replacement from the active operation and save.
     */
    async removeReplacement(wcName, originalValue) {
        const opData = PU.state.buildComposition.activeOperationData;
        const opName = PU.state.buildComposition.activeOperation;
        const jobId = PU.state.activeJobId;
        if (!opData || !opName || !jobId) return;

        // Remove from mappings
        if (opData.mappings && opData.mappings[wcName]) {
            delete opData.mappings[wcName][originalValue];
            // Clean up empty wildcard entry
            if (Object.keys(opData.mappings[wcName]).length === 0) {
                delete opData.mappings[wcName];
            }
        }

        // Save to server
        try {
            await PU.api.saveOperation(jobId, opName, opData.mappings || {});
            PU.actions.showToast(`Removed replacement for "${originalValue}"`, 'success');
        } catch (e) {
            console.warn('Failed to save operation:', e);
            PU.actions.showToast('Failed to save', 'error');
        }

        PU.rightPanel.hideReplacePopover();
        PU.rightPanel.render();
    },

    // ============================================
    // Push to Theme (wildcard sync)
    // ============================================

    /**
     * Get dirty info for an override wildcard: local vs theme diff.
     * Returns { name, localValues, themes: [{path, themeValues, added, removed, unchanged}] }
     */
    _getWildcardDirtyInfo(name) {
        const prompt = PU.helpers.getActivePrompt();
        const localWc = (prompt && prompt.wildcards || []).find(w => w.name === name);
        if (!localWc) return null;
        const localValues = new Set(Array.isArray(localWc.text) ? localWc.text : [localWc.text]);

        const cache = PU.state.previewMode._extTextCache || {};
        const themes = [];

        for (const [cachePath, data] of Object.entries(cache)) {
            if (!data || !data.wildcards) continue;
            const themeWc = data.wildcards.find(w => w.name === name);
            if (!themeWc) continue;
            const themeValues = new Set(Array.isArray(themeWc.text) ? themeWc.text : [themeWc.text]);
            const added = [...localValues].filter(v => !themeValues.has(v));
            const removed = [...themeValues].filter(v => !localValues.has(v));
            const unchanged = [...localValues].filter(v => themeValues.has(v));
            themes.push({ path: cachePath, themeValues: [...themeValues], added, removed, unchanged });
        }

        return { name, localValues: [...localValues], themes };
    },

    /**
     * Show the push-to-theme popover for an override wildcard.
     */
    showPushPopover(triggerEl, wcName) {
        PU.overlay.dismissPopovers();
        const popover = document.querySelector('[data-testid="pu-rp-push-popover"]');
        if (!popover) return;

        const dirtyInfo = PU.rightPanel._getWildcardDirtyInfo(wcName);
        if (!dirtyInfo || dirtyInfo.themes.length === 0) {
            PU.actions.showToast('No theme targets found for this wildcard', 'error');
            return;
        }

        const esc = PU.blocks.escapeHtml;

        // Build theme rows
        let themesHtml = '';
        for (let i = 0; i < dirtyInfo.themes.length; i++) {
            const t = dirtyInfo.themes[i];
            const isDirty = t.added.length > 0 || t.removed.length > 0;
            const diffId = `pu-rp-push-diff-${i}`;

            let summaryHtml;
            if (isDirty) {
                const parts = [];
                if (t.added.length > 0) parts.push(`<span class="push-added-count">+${t.added.length} added</span>`);
                if (t.removed.length > 0) parts.push(`<span class="push-removed-count">-${t.removed.length} removed</span>`);
                summaryHtml = parts.join(', ');
            } else {
                summaryHtml = '<span class="push-identical">identical</span>';
            }

            let diffHtml = '';
            if (isDirty) {
                const diffLines = [];
                for (const v of t.added) diffLines.push(`<div class="pu-rp-push-added">+ ${esc(v)}</div>`);
                for (const v of t.removed) diffLines.push(`<div class="pu-rp-push-removed">- ${esc(v)}</div>`);
                diffHtml = `
                    <span class="pu-rp-push-diff-toggle" data-testid="pu-rp-push-diff-toggle-${i}"
                          onclick="document.getElementById('${diffId}').style.display = document.getElementById('${diffId}').style.display === 'none' ? 'block' : 'none'">show diff</span>
                    <div class="pu-rp-push-diff" id="${diffId}" style="display: none;">${diffLines.join('')}</div>`;
            }

            themesHtml += `
                <div class="pu-rp-push-theme-row" data-testid="pu-rp-push-theme-row-${i}">
                    <input type="checkbox" ${isDirty ? 'checked' : ''} data-theme-path="${esc(t.path)}" data-testid="pu-rp-push-check-${i}">
                    <div class="pu-rp-push-theme-info">
                        <div class="pu-rp-push-theme-path">${esc(t.path)}</div>
                        <div class="pu-rp-push-diff-summary">${summaryHtml}</div>
                        ${diffHtml}
                    </div>
                </div>`;
        }

        const html = `
            <div class="pu-rp-push-header" data-testid="pu-rp-push-header">Push __${esc(wcName)}__ to theme</div>
            ${themesHtml}
            <div class="pu-rp-push-actions">
                <button class="pu-rp-push-btn cancel" data-testid="pu-rp-push-cancel"
                        onclick="PU.rightPanel.hidePushPopover()">Cancel</button>
                <button class="pu-rp-push-btn push" data-testid="pu-rp-push-confirm"
                        onclick="PU.rightPanel.executePush('${esc(wcName)}')">Push</button>
            </div>`;

        popover.innerHTML = html;

        // Position popover near the trigger icon
        const stream = document.querySelector('[data-testid="pu-rp-wc-stream"]');
        if (stream) {
            const streamRect = stream.getBoundingClientRect();
            const triggerRect = triggerEl.getBoundingClientRect();
            popover.style.top = (triggerRect.bottom - streamRect.top + stream.scrollTop + 4) + 'px';
            popover.style.left = Math.max(4, triggerRect.left - streamRect.left) + 'px';
        }

        popover.style.display = 'block';
        PU.state.themes.pushToThemePopover = { visible: true, wildcardName: wcName };
        PU.overlay.showOverlay();
    },

    /**
     * Hide the push-to-theme popover.
     */
    hidePushPopover() {
        const popover = document.querySelector('[data-testid="pu-rp-push-popover"]');
        if (popover) popover.style.display = 'none';
        PU.state.themes.pushToThemePopover = { visible: false, wildcardName: null };
    },

    /**
     * Execute push: send local wildcard values to each checked theme.
     */
    async executePush(wcName) {
        const popover = document.querySelector('[data-testid="pu-rp-push-popover"]');
        if (!popover) return;

        // Gather checked themes
        const checkedThemes = [];
        popover.querySelectorAll('input[type="checkbox"]:checked').forEach(cb => {
            const path = cb.dataset.themePath;
            if (path) checkedThemes.push(path);
        });

        if (checkedThemes.length === 0) {
            PU.actions.showToast('No themes selected', 'error');
            return;
        }

        // Get local values
        const prompt = PU.helpers.getActivePrompt();
        const localWc = (prompt && prompt.wildcards || []).find(w => w.name === wcName);
        if (!localWc) {
            PU.actions.showToast('Wildcard not found locally', 'error');
            return;
        }
        const values = Array.isArray(localWc.text) ? localWc.text : [localWc.text];

        // Disable push button during request
        const pushBtn = popover.querySelector('[data-testid="pu-rp-push-confirm"]');
        if (pushBtn) pushBtn.disabled = true;

        let successCount = 0;
        let totalAdded = 0;
        let totalRemoved = 0;

        for (const themePath of checkedThemes) {
            try {
                const result = await PU.api.post('/api/pu/extension/push-wildcards', {
                    path: themePath,
                    wildcard_name: wcName,
                    values: values
                });
                if (result.success) {
                    successCount++;
                    totalAdded += (result.added || []).length;
                    totalRemoved += (result.removed || []).length;
                    // Bust ext text cache for this theme
                    delete PU.state.previewMode._extTextCache[themePath];
                }
            } catch (e) {
                console.warn('Push failed for', themePath, e);
                PU.actions.showToast(`Failed to push to ${themePath}`, 'error');
            }
        }

        PU.rightPanel.hidePushPopover();

        if (successCount > 0) {
            const parts = [];
            if (totalAdded > 0) parts.push(`+${totalAdded} added`);
            if (totalRemoved > 0) parts.push(`-${totalRemoved} removed`);
            const diffSummary = parts.length > 0 ? ` (${parts.join(', ')})` : ' (identical)';
            PU.actions.showToast(`Pushed __${wcName}__ to ${successCount} theme(s)${diffSummary}`, 'success');

            // Re-render to reflect updated dirty state
            PU.rightPanel.render();
            // Re-render blocks (ext cache was busted, will reload)
            PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        }
    },

    // ============================================
    // Extension Picker (preserved from inspector.js)
    // ============================================

    /**
     * Show extension picker popup.
     * @param {Function} onSelect - callback with ext ID
     * @param {Element} [anchorEl] - optional trigger button for anchored positioning
     */
    showExtensionPicker(onSelect, anchorEl) {
        PU.overlay.dismissAll();
        PU.state.extPickerCallback = onSelect;
        const popup = document.querySelector('[data-testid="pu-ext-picker-popup"]');
        const tree = document.querySelector('[data-testid="pu-ext-picker-tree"]');
        const searchInput = document.querySelector('[data-testid="pu-ext-picker-search"]');

        if (searchInput) searchInput.value = '';

        tree.innerHTML = PU.rightPanel.renderExtTreeForPicker(
            PU.state.globalExtensions.tree, ''
        );
        popup.style.display = 'flex';
        PU.overlay.showOverlay();

        // Position relative to anchor button (top-right origin).
        if (anchorEl) {
            popup.dataset.anchored = 'true';
            // Force layout so CSS [data-anchored] width takes effect
            // before we measure popRect.
            popup.offsetHeight;
            const btnRect = anchorEl.getBoundingClientRect();
            const popRect = popup.getBoundingClientRect();
            // Menu top-right corner at button bottom-right
            let left = btnRect.right - popRect.width;
            let top = btnRect.bottom + 4;
            // Keep within viewport
            if (left < 8) left = 8;
            if (left + popRect.width > window.innerWidth - 8) {
                left = window.innerWidth - popRect.width - 8;
            }
            if (top + popRect.height > window.innerHeight - 8) {
                top = btnRect.top - popRect.height - 4;
                if (top < 8) top = 8;
            }
            popup.style.left = left + 'px';
            popup.style.top = top + 'px';
            popup.style.bottom = 'auto';
            popup.style.transform = 'none';
        } else {
            // Reset to CSS defaults (centered or bottom-sheet)
            popup.style.left = '';
            popup.style.top = '';
            popup.style.bottom = '';
            popup.style.transform = '';
            delete popup.dataset.anchored;
        }
    },

    /**
     * Close extension picker popup
     */
    closeExtPicker() {
        const popup = document.querySelector('[data-testid="pu-ext-picker-popup"]');
        if (!popup) return;
        popup.style.display = 'none';
        // Reset anchored positioning
        popup.style.left = '';
        popup.style.top = '';
        popup.style.bottom = '';
        popup.style.transform = '';
        delete popup.dataset.anchored;
        PU.state.extPickerCallback = null;
    },

    /**
     * Filter extension picker tree
     */
    filterExtPicker(query) {
        const tree = document.querySelector('[data-testid="pu-ext-picker-tree"]');
        tree.innerHTML = PU.rightPanel.renderExtTreeForPicker(
            PU.state.globalExtensions.tree, '', query.toLowerCase()
        );
    },

    /**
     * Handle extension selection from picker
     */
    selectExtForPicker(extId) {
        if (PU.state.extPickerCallback) {
            PU.state.extPickerCallback(extId);
        }
        PU.rightPanel.closeExtPicker();
    },

    /**
     * Render extension tree for picker (click selects instead of showing details)
     */
    renderExtTreeForPicker(node, path, filter = '') {
        let html = '';

        for (const [key, value] of Object.entries(node)) {
            if (key === '_files') continue;

            const folderPath = path ? `${path}/${key}` : key;

            if (filter && !key.toLowerCase().includes(filter) && !PU.rightPanel.folderMatchesPickerFilter(value, filter)) {
                continue;
            }

            html += `
                <div class="pu-tree-item pu-picker-folder">
                    <span class="pu-tree-icon">&rsaquo;</span>
                    <span class="pu-tree-label">${key}</span>
                </div>
            `;

            html += `<div class="pu-tree-children">`;
            html += PU.rightPanel.renderExtTreeForPicker(value, folderPath, filter);
            html += `</div>`;
        }

        const files = node._files || [];
        for (const file of files) {
            const fileId = file.id || file.file.replace('.yaml', '');

            if (filter && !fileId.toLowerCase().includes(filter)) {
                continue;
            }

            const textCount = file.textCount || 0;
            const wildcardCount = file.wildcardCount || 0;
            let badge = '';
            if (textCount > 0 || wildcardCount > 0) {
                const parts = [];
                if (textCount > 0) parts.push(`${textCount} texts`);
                if (wildcardCount > 0) parts.push(`${wildcardCount} wildcards`);
                badge = `<span class="pu-tree-badge">${parts.join(', ')}</span>`;
            }

            html += `
                <div class="pu-tree-item pu-picker-file"
                     data-testid="pu-ext-picker-item-${fileId}"
                     onclick="PU.rightPanel.selectExtForPicker('${fileId}')">
                    <span class="pu-tree-label">${fileId}</span>
                    ${badge}
                </div>
            `;
        }

        return html;
    },

    /**
     * Check if folder contains files matching filter
     */
    folderMatchesPickerFilter(node, filter) {
        const files = node._files || [];
        for (const file of files) {
            const fileId = file.id || file.file.replace('.yaml', '');
            if (fileId.toLowerCase().includes(filter)) {
                return true;
            }
        }

        for (const [key, value] of Object.entries(node)) {
            if (key === '_files') continue;
            if (key.toLowerCase().includes(filter)) return true;
            if (PU.rightPanel.folderMatchesPickerFilter(value, filter)) return true;
        }

        return false;
    },

    // ============================================
    // Panel collapse / expand
    // ============================================

    /**
     * Collapse the right panel (fully hidden).
     */
    collapse() {
        const panel = document.querySelector('[data-testid="pu-right-panel"]');
        if (!panel) return;
        panel.classList.add('collapsed');
        PU.state.ui.rightPanelCollapsed = true;
        PU.rightPanel._updateToggleIcon(true);
        PU.helpers.saveUIState();
    },

    /**
     * Expand the right panel.
     */
    expand() {
        const panel = document.querySelector('[data-testid="pu-right-panel"]');
        if (!panel) return;
        panel.classList.remove('collapsed');
        PU.state.ui.rightPanelCollapsed = false;
        PU.rightPanel._updateToggleIcon(false);
        PU.helpers.saveUIState();
    },

    /**
     * Toggle the right panel open/closed.
     * On mobile/tablet, uses overlay slide-in instead of CSS collapse.
     */
    togglePanel() {
        if (PU.responsive && PU.responsive.isOverlay()) {
            const panel = document.querySelector('[data-testid="pu-right-panel"]');
            if (panel && panel.classList.contains('pu-panel-open')) {
                PU.responsive.closePanel('pu-right-panel');
            } else {
                PU.responsive.openPanel('pu-right-panel');
            }
            return;
        }
        if (PU.state.ui.rightPanelCollapsed) {
            PU.rightPanel.expand();
        } else {
            PU.rightPanel.collapse();
        }
    },

    /**
     * Apply persisted collapsed state (called on init).
     */
    applyCollapsedState() {
        if (PU.state.ui.rightPanelCollapsed) {
            const panel = document.querySelector('[data-testid="pu-right-panel"]');
            if (panel) panel.classList.add('collapsed');
            PU.rightPanel._updateToggleIcon(true);
        }
    },

    /**
     * Update toggle icon in panel header.
     */
    _updateToggleIcon(collapsed) {
        const headerBtn = document.querySelector('[data-testid="pu-rp-collapse-btn"]');
        if (headerBtn) headerBtn.innerHTML = collapsed ? '&#9664;' : '&#9654;';
    },

    /**
     * Show a contextual tip in the footer bar.
     */
    _showFooterTip(html) {
        const tip = document.querySelector('[data-testid="pu-footer-tip"]');
        if (!tip) return;
        tip.innerHTML = html;
        tip.classList.add('visible');
    },

    /**
     * Hide the footer tip.
     */
    _hideFooterTip() {
        const tip = document.querySelector('[data-testid="pu-footer-tip"]');
        if (!tip) return;
        tip.classList.remove('visible');
    }
};

// Register right-panel overlays
PU.overlay.registerPopover('opDropdown', () => PU.rightPanel.hideOpDropdown());
PU.overlay.registerPopover('replacePopover', () => PU.rightPanel.hideReplacePopover());
PU.overlay.registerPopover('pushPopover', () => PU.rightPanel.hidePushPopover());
PU.overlay.registerModal('extPicker', () => PU.rightPanel.closeExtPicker());

// ============================================
// Backward compatibility alias
// ============================================
PU.inspector = {
    init: PU.rightPanel.init,
    showOverview: () => PU.rightPanel.render(),
    updateWildcardsContext: () => PU.rightPanel.render(),
    showExtensionPicker: PU.rightPanel.showExtensionPicker,
    closeExtPicker: PU.rightPanel.closeExtPicker,
    filterExtPicker: PU.rightPanel.filterExtPicker,
    selectExtForPicker: PU.rightPanel.selectExtForPicker,
    renderExtTreeForPicker: PU.rightPanel.renderExtTreeForPicker,
    folderMatchesPickerFilter: PU.rightPanel.folderMatchesPickerFilter
};
