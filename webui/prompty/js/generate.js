/**
 * PromptyUI - Generate Modal
 *
 * 1:1 port of the Build Flow Diagram preview.
 * Horizontal tree layout with depth-first single-cursor execution,
 * hook stage indicators, wildcard pill dropdowns, run state machine,
 * and failure cascade — all driven by the active prompt's block structure.
 */

PU.generate = {
    // ── State ──────────────────────────────────────────────────
    _runState: 'idle',
    _stopRequested: false,
    _completedCompositions: 0,
    _completedBlocks: 0,
    _depthFirstQueue: [],
    _queuePosition: 0,
    _variationResults: {},
    _failedBlocks: new Set(),
    _blockedBlocks: new Set(),
    _blockCompletedMap: {},
    _blockStartTimes: {},
    _currentBlockId: null,
    _visitedBlocks: new Set(),
    _annotationsCache: {},
    _blockDefs: [],
    _totalCompositions: 0,

    // ── Modal Lifecycle ────────────────────────────────────────

    open() {
        PU.overlay.dismissAll();
        const modal = document.querySelector('[data-testid="pu-generate-modal"]');
        if (!modal) return;
        modal.style.display = 'flex';

        // Reset if previous run completed
        if (this._runState === 'complete' || this._runState === 'failed') {
            this._resetState();
        }

        this.render();
        this._updateButtonUI();
    },

    close() {
        const modal = document.querySelector('[data-testid="pu-generate-modal"]');
        if (!modal) return;
        modal.style.display = 'none';
    },

    _resetState() {
        this._runState = 'idle';
        this._stopRequested = false;
        this._completedCompositions = 0;
        this._completedBlocks = 0;
        this._depthFirstQueue = [];
        this._queuePosition = 0;
        this._variationResults = {};
        this._failedBlocks = new Set();
        this._blockedBlocks = new Set();
        this._blockCompletedMap = {};
        this._blockStartTimes = {};
        this._currentBlockId = null;
        this._visitedBlocks = new Set();
        this._annotationsCache = {};
        this._blockDefs = [];
        this._totalCompositions = 0;
    },

    // ── Rendering ──────────────────────────────────────────────

    render() {
        const body = document.querySelector('[data-testid="pu-gen-body"]');
        if (!body) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            body.innerHTML = '<div style="padding:24px; color:var(--pu-text-muted);">No prompt selected.</div>';
            return;
        }

        // Build block definitions from active prompt
        this._blockDefs = this._buildBlockDefs();
        this._totalCompositions = this._blockDefs.reduce((s, d) => s + d.compositions, 0);

        // Header info
        const nameEl = document.querySelector('[data-testid="pu-gen-prompt-name"]');
        if (nameEl) nameEl.textContent = PU.state.activePromptId || '';
        const countEl = document.querySelector('[data-testid="pu-gen-comp-count"]');
        if (countEl) {
            countEl.textContent = this._totalCompositions.toLocaleString() + ' compositions';
            countEl.style.fontFamily = 'var(--pu-font-mono)';
            countEl.style.fontSize = '11px';
            countEl.style.color = 'var(--pu-text-muted)';
        }

        // Build lookup for wildcard values
        const lookup = PU.preview.getFullWildcardLookup();

        // Build the horizontal tree
        const blocks = PU.shared.buildBlockTree(prompt.text || []);
        let html = this._renderHorizontalTree(blocks, lookup);

        // State legend
        html += this._renderStateLegend();

        body.innerHTML = html;

        // Attach click handlers for annotation strip + ext_text pagination
        body.addEventListener('click', (e) => {
            // Annotation strip toggle
            const strip = e.target.closest('.pu-gen-ann-strip');
            if (strip) {
                e.stopPropagation();
                const stripId = strip.getAttribute('data-strip-id');
                const detail = body.querySelector(`[data-detail-for="${stripId}"]`);
                if (detail) {
                    const isOpen = detail.style.display !== 'none';
                    detail.style.display = isOpen ? 'none' : 'block';
                    const icon = strip.querySelector('.pu-gen-ann-toggle-icon');
                    if (icon) icon.innerHTML = isOpen ? '&#9656;' : '&#9662;';
                    strip.classList.toggle('expanded', !isOpen);
                }
                return;
            }
            // Dropdown pagination (wildcards + ext_text)
            const prevBtn = e.target.closest('[data-dd-prev]');
            if (prevBtn) {
                e.stopPropagation();
                const nav = prevBtn.closest('.pu-gen-wc-dropdown-nav');
                if (nav) this._paginateDropdown(nav, -1);
                return;
            }
            const nextBtn = e.target.closest('[data-dd-next]');
            if (nextBtn) {
                e.stopPropagation();
                const nav = nextBtn.closest('.pu-gen-wc-dropdown-nav');
                if (nav) this._paginateDropdown(nav, 1);
                return;
            }
        });
    },

    _buildBlockDefs() {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return [];
        const blocks = PU.shared.buildBlockTree(prompt.text || []);
        const lookup = PU.preview.getFullWildcardLookup();
        const defs = [];

        const walk = (blockList, parentId, inheritedWildcards) => {
            for (const block of blockList) {
                const nodeId = 'block-' + block.path.replace(/\./g, '-');

                // Wildcards for this block: own + inherited from parent
                const ownWc = block.usedWildcards || [];
                const allWc = [...new Set([...inheritedWildcards, ...ownWc])];

                // Compute compositions = product of all wildcard dimensions
                let compositions = 1;
                for (const wc of allWc) {
                    const vals = lookup[wc];
                    if (vals && vals.length > 0) compositions *= vals.length;
                }

                // For ext_text blocks, multiply by ext count
                const textItems = prompt.text || [];
                const item = this._findBlockItem(textItems, block.path);
                if (item && item.ext_text) {
                    const extCount = PU.state.previewMode.extTextCount || 1;
                    compositions *= extCount;
                }

                // childCompsPerParent: how many child compositions per parent variation
                const parentDef = parentId ? defs.find(d => d.id === parentId) : null;
                const parentComps = parentDef ? parentDef.compositions : 1;
                const childCompsPerParent = parentComps > 0 ? Math.max(1, Math.floor(compositions / parentComps)) : 1;

                defs.push({
                    id: nodeId,
                    path: block.path,
                    compositions,
                    parentId,
                    childCompsPerParent,
                    content: block.content,
                    usedWildcards: ownWc,
                    allWildcards: allWc,
                    isExt: !!block.isExt || !!(item && item.ext_text),
                    isLeaf: block.children.length === 0,
                });

                if (block.children.length > 0) {
                    walk(block.children, nodeId, allWc);
                }
            }
        };
        walk(blocks, null, []);
        return defs;
    },

    _findBlockItem(items, path) {
        const parts = path.split('.');
        let current = items;
        for (let i = 0; i < parts.length; i++) {
            const idx = parseInt(parts[i], 10);
            if (!current || !current[idx]) return null;
            if (i === parts.length - 1) return current[idx];
            current = current[idx].after || [];
        }
        return null;
    },

    _renderHorizontalTree(blocks, lookup) {
        if (blocks.length === 0) return '<div style="padding:24px; color:var(--pu-text-muted);">No blocks defined.</div>';

        const promptId = PU.state.activePromptId || 'prompt';

        let html = '<div class="pu-gen-tree" data-testid="pu-gen-tree">';

        // Prompt root node
        html += `<span class="pu-gen-node root" data-run-state="idle" data-node-id="prompt">
            ${PU.blocks.escapeHtml(promptId)}
            <span class="pu-gen-badge-progress" data-progress></span>
        </span>`;

        // Link from root to children
        html += '<div class="pu-gen-link" data-link-for="prompt"></div>';

        // Children
        html += '<div class="pu-gen-children">';
        for (const block of blocks) {
            html += this._renderBlockNode(block, lookup);
        }
        html += '</div>';

        html += '</div>';
        return html;
    },

    _renderBlockNode(block, lookup) {
        const nodeId = 'block-' + block.path.replace(/\./g, '-');
        const def = this._blockDefs.find(d => d.id === nodeId);
        const item = this._findBlockItem((PU.helpers.getActivePrompt() || {}).text || [], block.path);
        const isTheme = !!(item && item.ext_text);
        const typeClass = isTheme ? 'theme' : 'content';
        const leafClass = block.children.length === 0 ? ' leaf' : '';
        const hasWc = (def && def.usedWildcards && def.usedWildcards.length > 0) || isTheme;
        const annData = PU.annotations.resolve(block.path);
        const hasAnn = Object.keys(annData.computed).length > 0 || (Object.keys(annData.removed).length > 0);
        const hasDims = (hasWc || hasAnn) ? ' has-dims' : '';

        let html = '<div class="pu-gen-tree">';

        if (hasDims) {
            // Card mode with dimensions zone
            html += `<div class="pu-gen-node ${typeClass}${leafClass} has-dims" data-run-state="idle" data-node-id="${nodeId}" data-testid="pu-gen-node-${block.path}">`;
            html += '<div class="pu-gen-card-text">';
            html += `<span class="pu-gen-path">${block.path}</span>`;

            // Content with inline wildcard dropdowns (paginated at 5)
            let contentHtml = PU.blocks.escapeHtml(block.content);
            contentHtml = contentHtml.replace(/__([a-zA-Z0-9_]+)__/g, (match, wcName) => {
                const vals = lookup[wcName] || [];
                const isFromTheme = PU.shared.isExtWildcard(wcName);
                const themeClass = isFromTheme ? ' from-theme' : '';
                const wcId = `wc-${nodeId}-${wcName}`;
                return `<span class="pu-gen-wc-inline${themeClass}" data-wc-id="${wcId}">${PU.blocks.escapeHtml(wcName)}<span class="pu-gen-wc-count">&times;${vals.length}</span>${this._buildPaginatedDropdown(wcId, vals)}</span>`;
            });
            html += `<span class="pu-gen-text">${contentHtml}</span>`;

            html += '<span class="pu-gen-badge-progress" data-progress></span>';
            html += '<span class="pu-gen-stage" data-stage></span>';
            html += '<span class="pu-gen-badge-result" data-result></span>';
            html += '<span class="pu-gen-badge-error" data-error></span>';
            if (isTheme) {
                const extName = item.ext_text || '';
                const extItems = this._getExtTextItems(extName);
                const extId = `ext-${nodeId}`;
                html += `<span class="pu-gen-wc-inline from-theme" data-wc-id="${extId}" data-ext-name="${PU.blocks.escapeHtml(extName)}">${PU.blocks.escapeHtml(extName)}<span class="pu-gen-wc-count">&times;${extItems.length}</span>${this._buildPaginatedDropdown(extId, extItems)}</span>`;
            }
            html += '</div>';

            // Dims zone — annotation strip (replaces wildcard pills)
            const annKeys = Object.keys(annData.computed);
            const removedKeys = Object.keys(annData.removed);
            const totalAnnCount = annKeys.length + removedKeys.length;
            const hasAnnotations = totalAnnCount > 0;

            html += '<div class="pu-gen-dims">';

            if (hasAnnotations) {
                const stripId = `ann-strip-${nodeId}`;
                html += `<div class="pu-gen-ann-strip" data-strip-id="${stripId}" data-testid="pu-gen-ann-strip">`;
                html += `<span class="pu-gen-ann-toggle-icon">&#9656;</span>`;
                html += `<span class="pu-gen-ann-count">${totalAnnCount} annotation${totalAnnCount !== 1 ? 's' : ''}</span>`;
                if (def) {
                    html += `<span class="pu-gen-total">=${def.compositions.toLocaleString()}</span>`;
                }
                html += '</div>';

                html += `<div class="pu-gen-ann-detail" data-detail-for="${stripId}" style="display:none;" data-testid="pu-gen-ann-detail">`;

                for (const key of annKeys) {
                    const val = annData.computed[key];
                    const source = annData.sources[key] || 'block';
                    const strVal = String(val).trim();
                    const desc = PU.annotations._universals[key];
                    const label = (desc && desc.label) ? desc.label : key;
                    html += `<div class="pu-gen-ann-row">`;
                    html += `<span class="pu-gen-ann-key">${PU.blocks.escapeHtml(label)}</span>`;
                    html += `<span class="pu-gen-ann-val">${PU.blocks.escapeHtml(strVal.length > 60 ? strVal.substring(0, 60) + '...' : strVal)}</span>`;
                    html += `<span class="pu-gen-ann-source">${source}</span>`;
                    html += '</div>';
                }

                for (const key of removedKeys) {
                    const desc = PU.annotations._universals[key];
                    const label = (desc && desc.label) ? desc.label : key;
                    html += `<div class="pu-gen-ann-row removed">`;
                    html += `<span class="pu-gen-ann-key">${PU.blocks.escapeHtml(label)}</span>`;
                    html += `<span class="pu-gen-ann-val">null</span>`;
                    html += `<span class="pu-gen-ann-source">block</span>`;
                    html += '</div>';
                }

                html += '</div>';
            } else {
                if (def) {
                    html += `<span class="pu-gen-total">=${def.compositions.toLocaleString()}</span>`;
                }
            }

            html += '</div>'; // .pu-gen-dims
            html += '</div>'; // .pu-gen-node
        } else {
            // Simple inline node (no own wildcards)
            html += `<span class="pu-gen-node ${typeClass}${leafClass}" data-run-state="idle" data-node-id="${nodeId}" data-testid="pu-gen-node-${block.path}">`;
            html += `<span class="pu-gen-path">${block.path}</span>`;

            let contentHtml = PU.blocks.escapeHtml(block.content);
            // Render inline wildcards even on simple nodes (inherited wildcards)
            contentHtml = contentHtml.replace(/__([a-zA-Z0-9_]+)__/g, (match, wcName) => {
                const vals = lookup[wcName] || [];
                const isFromTheme = PU.shared.isExtWildcard(wcName);
                const themeClass = isFromTheme ? ' from-theme' : '';
                const wcId = `wc-${nodeId}-${wcName}`;
                return `<span class="pu-gen-wc-inline${themeClass}" data-wc-id="${wcId}">${PU.blocks.escapeHtml(wcName)}<span class="pu-gen-wc-count">&times;${vals.length}</span>${this._buildPaginatedDropdown(wcId, vals)}</span>`;
            });
            html += `<span class="pu-gen-text">${contentHtml}</span>`;

            if (def) {
                html += `<span class="pu-gen-total">=${def.compositions.toLocaleString()}</span>`;
            }

            html += '<span class="pu-gen-badge-progress" data-progress></span>';
            html += '<span class="pu-gen-stage" data-stage></span>';
            html += '<span class="pu-gen-badge-result" data-result></span>';
            html += '<span class="pu-gen-badge-error" data-error></span>';
            html += '<span class="pu-gen-badge-blocked">blocked</span>';
            html += '</span>';
        }

        // Children
        if (block.children.length > 0) {
            html += `<div class="pu-gen-link" data-link-for="${nodeId}"></div>`;
            html += '<div class="pu-gen-children">';
            for (const child of block.children) {
                html += this._renderBlockNode(child, lookup);
            }
            html += '</div>';
        }

        html += '</div>'; // .pu-gen-tree
        return html;
    },

    _renderStateLegend() {
        return `<div class="pu-gen-legend" data-testid="pu-gen-legend">
            <span style="font-family:var(--pu-font-mono);font-size:9px;letter-spacing:0.5px;text-transform:uppercase;opacity:0.4;">States:</span>
            <span class="pu-gen-legend-item"><span class="pu-gen-legend-swatch s-dormant"></span> Dormant</span>
            <span class="pu-gen-legend-item"><span class="pu-gen-legend-swatch s-running"></span> Running</span>
            <span class="pu-gen-legend-item"><span class="pu-gen-legend-swatch s-partial"></span> Partial</span>
            <span class="pu-gen-legend-item"><span class="pu-gen-legend-swatch s-paused"></span> Paused</span>
            <span class="pu-gen-legend-item"><span class="pu-gen-legend-swatch s-complete"></span> Complete</span>
            <span class="pu-gen-legend-item"><span class="pu-gen-legend-swatch s-failed"></span> Failed</span>
            <span class="pu-gen-legend-item"><span class="pu-gen-legend-swatch s-blocked"></span> Blocked</span>
        </div>`;
    },

    // ── Execution Simulation ───────────────────────────────────

    onRunClick() {
        switch (this._runState) {
            case 'idle':
            case 'complete':
            case 'failed':
                this._startRun();
                break;
            case 'running':
                this._requestStop();
                break;
            case 'paused':
                this._resumeRun();
                break;
        }
    },

    async _startRun() {
        this._resetState();
        this._blockDefs = this._buildBlockDefs();
        this._totalCompositions = this._blockDefs.reduce((s, d) => s + d.compositions, 0);
        this._depthFirstQueue = this._buildDepthFirstQueue();

        this._runState = 'running';
        this._updateButtonUI();

        // Show progress bar and status
        const bar = document.querySelector('[data-testid="pu-gen-progress-bar"]');
        const status = document.querySelector('[data-testid="pu-gen-status"]');
        const fill = document.querySelector('[data-testid="pu-gen-progress-fill"]');
        if (bar) bar.classList.add('visible');
        if (status) { status.classList.add('visible'); status.classList.remove('error'); status.textContent = `0 / ${this._totalCompositions.toLocaleString()}`; }
        if (fill) { fill.classList.remove('has-error'); fill.style.width = '0%'; }

        // Show legend
        const legend = document.querySelector('[data-testid="pu-gen-legend"]');
        if (legend) legend.classList.add('visible');

        // Reset all nodes to idle
        document.querySelectorAll('.pu-gen-node[data-run-state], .pu-gen-node[data-run-state]').forEach(el =>
            el.setAttribute('data-run-state', 'idle'));
        document.querySelectorAll('.pu-gen-node [data-progress]').forEach(el => el.textContent = '');
        document.querySelectorAll('.pu-gen-node [data-result]').forEach(el => el.textContent = '');
        document.querySelectorAll('.pu-gen-node [data-error]').forEach(el => el.textContent = '');
        document.querySelectorAll('.pu-gen-node [data-stage]').forEach(el => { el.textContent = ''; el.removeAttribute('data-stage-type'); });
        document.querySelectorAll('.pu-gen-link').forEach(el => el.removeAttribute('data-link-state'));

        // Phase 1: All dormant
        await this._sleep(200);
        document.querySelectorAll('.pu-gen-node[data-run-state]').forEach(el =>
            el.setAttribute('data-run-state', 'dormant'));
        document.querySelectorAll('.pu-gen-link').forEach(el =>
            el.setAttribute('data-link-state', 'dormant'));

        await this._sleep(400);

        // Phase 2: Prompt node
        this._setNodeState('prompt', 'running');
        this._setLinkState('prompt', 'running');
        await this._sleep(300);
        this._setNodeState('prompt', 'complete');
        this._setLinkState('prompt', 'complete');
        await this._sleep(200);

        // Phase 3: Process queue
        await this._processQueue();
        this._finalizeRunState();
        this._updateButtonUI();
    },

    _requestStop() {
        this._stopRequested = true;
        const btn = document.querySelector('[data-testid="pu-gen-run-btn"]');
        if (btn) { btn.textContent = 'Stopping\u2026'; btn.disabled = true; }
    },

    async _resumeRun() {
        this._stopRequested = false;
        this._runState = 'running';
        this._currentBlockId = null;
        this._updateButtonUI();

        const status = document.querySelector('[data-testid="pu-gen-status"]');
        if (status) {
            status.classList.remove('error');
            status.textContent = `${this._completedCompositions.toLocaleString()} / ${this._totalCompositions.toLocaleString()}`;
        }

        // Un-pause paused blocks
        document.querySelectorAll('.pu-gen-node[data-run-state="paused"]').forEach(el =>
            el.setAttribute('data-run-state', 'partial'));

        await this._processQueue();
        this._finalizeRunState();
        this._updateButtonUI();
    },

    async _processQueue() {
        while (this._queuePosition < this._depthFirstQueue.length && !this._stopRequested) {
            const entry = this._depthFirstQueue[this._queuePosition];
            const { blockId, idx, parentKey } = entry;
            const def = this._getBlockDef(blockId);

            // Skip failed/blocked
            if (this._failedBlocks.has(blockId) || this._blockedBlocks.has(blockId)) {
                this._queuePosition++;
                continue;
            }

            // Parent variation failed → block this
            if (parentKey && this._failedBlocks.has(parentKey.split(':')[0])) {
                this._blockedBlocks.add(blockId);
                this._setBlockVisual(blockId, 'blocked');
                this._queuePosition++;
                continue;
            }

            // Cursor movement
            if (this._currentBlockId !== blockId) {
                if (this._currentBlockId) {
                    const prevCompleted = this._blockCompletedMap[this._currentBlockId] || 0;
                    const prevDef = this._getBlockDef(this._currentBlockId);
                    if (prevDef && prevCompleted < prevDef.compositions && !this._failedBlocks.has(this._currentBlockId)) {
                        this._setBlockVisual(this._currentBlockId, 'partial');
                        this._setStage(this._currentBlockId, '');
                    }
                }
                this._currentBlockId = blockId;

                if (!this._blockStartTimes[blockId]) {
                    this._blockStartTimes[blockId] = performance.now();
                }
                this._setBlockVisual(blockId, 'running');
            }

            const parentResult = parentKey ? (this._variationResults[parentKey] || null) : null;
            const hookCtx = { blockId, compositionIndex: idx, compositionTotal: def.compositions, parentResult };

            // Block-level hooks (fire once)
            if (!this._visitedBlocks.has(blockId)) {
                this._visitedBlocks.add(blockId);

                this._setStage(blockId, 'start');
                let r = await this._simulateHookStage('node_start', hookCtx);
                if (this._stopRequested) break;

                this._setStage(blockId, 'ann');
                r = await this._simulateHookStage('ann', hookCtx);
                if (this._stopRequested) break;
                if (r.status === 'error') {
                    this._handleBlockFailure(blockId, idx, r);
                    this._queuePosition++;
                    continue;
                }
                this._annotationsCache[blockId] = r;
            }

            // Per-composition hooks
            this._setStage(blockId, 'pre');
            let stageResult = await this._simulateHookStage('pre', hookCtx);
            if (this._stopRequested) break;
            if (stageResult.status === 'error') {
                this._handleBlockFailure(blockId, idx, stageResult);
                this._queuePosition++;
                continue;
            }

            this._setStage(blockId, 'gen');
            stageResult = await this._simulateHookStage('gen', hookCtx);
            if (this._stopRequested) break;
            if (stageResult.status === 'error') {
                this._handleBlockFailure(blockId, idx, stageResult);
                this._queuePosition++;
                continue;
            }

            this._setStage(blockId, 'post');
            stageResult = await this._simulateHookStage('post', hookCtx);
            if (this._stopRequested) break;
            if (stageResult.status === 'error') {
                this._handleBlockFailure(blockId, idx, stageResult);
                this._queuePosition++;
                continue;
            }

            // Composition succeeded
            this._setStage(blockId, '');
            this._blockCompletedMap[blockId] = (this._blockCompletedMap[blockId] || 0) + 1;
            this._completedCompositions++;
            this._variationResults[`${blockId}:${idx}`] = stageResult;

            this._updateProgress(blockId, this._blockCompletedMap[blockId], def.compositions);
            this._updateGlobalProgress();

            // Block complete → node_end
            if (this._blockCompletedMap[blockId] === def.compositions) {
                this._setStage(blockId, 'end');
                await this._simulateHookStage('node_end', hookCtx);
                if (this._stopRequested) break;
                this._setStage(blockId, '');

                const wallTime = performance.now() - this._blockStartTimes[blockId];
                this._setBlockVisual(blockId, 'complete');
                this._setResult(blockId, wallTime);
                this._completedBlocks++;
                this._updatePromptProgress();
                this._currentBlockId = null;
            }

            this._queuePosition++;
        }

        // Mark paused if stopped mid-block
        if (this._stopRequested && this._currentBlockId) {
            const def = this._getBlockDef(this._currentBlockId);
            const completed = this._blockCompletedMap[this._currentBlockId] || 0;
            if (def && completed < def.compositions && !this._failedBlocks.has(this._currentBlockId)) {
                this._setBlockVisual(this._currentBlockId, 'paused');
                this._setStage(this._currentBlockId, '');
            }
        }
    },

    _simulateHookStage(stage, ctx) {
        const start = performance.now();
        const simFailEl = document.querySelector('[data-testid="pu-gen-sim-fail"]');
        const simFail = simFailEl ? simFailEl.checked : false;

        // Find first leaf block for sim failure
        const firstLeaf = this._blockDefs.find(d => d.isLeaf);
        const shouldFail = simFail
            && stage === 'gen'
            && firstLeaf
            && ctx.blockId === firstLeaf.id
            && ctx.compositionIndex === Math.min(5, Math.floor(firstLeaf.compositions / 2));

        const timings = {
            node_start: 5,
            ann: 10 + Math.random() * 20,
            pre: 2 + Math.random() * 5,
            gen: 15 + Math.random() * 60,
            post: 2 + Math.random() * 5,
            node_end: 5,
        };

        return new Promise(resolve => {
            setTimeout(() => {
                if (shouldFail) {
                    resolve({
                        status: 'error',
                        message: 'Hook timeout: generation service unavailable',
                        stage,
                        elapsed: performance.now() - start,
                    });
                } else {
                    resolve({
                        status: 'success',
                        stage,
                        elapsed: performance.now() - start,
                    });
                }
            }, timings[stage] || 5);
        });
    },

    _handleBlockFailure(blockId, idx, result) {
        this._failedBlocks.add(blockId);
        this._setBlockVisual(blockId, 'failed');
        this._setStage(blockId, '');
        const def = this._getBlockDef(blockId);
        this._setError(blockId, result.message, this._blockCompletedMap[blockId] || 0, def ? def.compositions : 0);
        this._variationResults[`${blockId}:${idx}`] = result;

        // Cascade: block children recursively
        const cascade = (parentId) => {
            const children = this._blockDefs.filter(b => b.parentId === parentId);
            for (const child of children) {
                this._blockedBlocks.add(child.id);
                this._setBlockVisual(child.id, 'blocked');
                cascade(child.id);
            }
        };
        cascade(blockId);
        this._currentBlockId = null;
    },

    _finalizeRunState() {
        const anyFailed = this._failedBlocks.size > 0;
        const allDone = this._queuePosition >= this._depthFirstQueue.length;

        if (this._stopRequested && !allDone) {
            this._runState = 'paused';
        } else if (allDone && anyFailed) {
            this._runState = 'failed';
            const fill = document.querySelector('[data-testid="pu-gen-progress-fill"]');
            if (fill) fill.classList.add('has-error');
            const status = document.querySelector('[data-testid="pu-gen-status"]');
            if (status) {
                const failNames = [...this._failedBlocks].join(', ');
                status.textContent = `${this._completedCompositions.toLocaleString()} done \u2014 failed: ${failNames}`;
                status.classList.add('error');
            }
        } else if (allDone) {
            this._runState = 'complete';
            const status = document.querySelector('[data-testid="pu-gen-status"]');
            if (status) status.textContent = `${this._completedCompositions.toLocaleString()} done`;
        }
    },

    _buildDepthFirstQueue() {
        const queue = [];
        const self = this;

        function enqueueSubtree(blockId, idx, parentKey) {
            queue.push({ blockId, idx, parentKey });

            const children = self._blockDefs.filter(b => b.parentId === blockId);
            for (const child of children) {
                const perParent = child.childCompsPerParent;
                const startIdx = idx * perParent;
                for (let c = 0; c < perParent; c++) {
                    const childIdx = startIdx + c;
                    if (childIdx < child.compositions) {
                        enqueueSubtree(child.id, childIdx, `${blockId}:${idx}`);
                    }
                }
            }
        }

        const roots = this._blockDefs.filter(b => b.parentId === null);
        for (const root of roots) {
            for (let i = 0; i < root.compositions; i++) {
                enqueueSubtree(root.id, i, null);
            }
        }

        return queue;
    },

    // ── DOM Helpers ────────────────────────────────────────────

    _getBlockDef(id) {
        return this._blockDefs.find(b => b.id === id);
    },

    _setNodeState(nodeId, state) {
        const el = document.querySelector(`.pu-gen-node[data-node-id="${nodeId}"]`);
        if (el) el.setAttribute('data-run-state', state);
    },

    _setLinkState(nodeId, state) {
        const link = document.querySelector(`.pu-gen-link[data-link-for="${nodeId}"]`);
        if (link) link.setAttribute('data-link-state', state);
    },

    _setBlockVisual(blockId, state) {
        this._setNodeState(blockId, state);
        this._setLinkState(blockId, state);
    },

    _updateProgress(nodeId, current, total) {
        const el = document.querySelector(`.pu-gen-node[data-node-id="${nodeId}"] [data-progress]`);
        if (el) el.textContent = `${current}/${total}`;
    },

    _setResult(nodeId, timeMs) {
        const el = document.querySelector(`.pu-gen-node[data-node-id="${nodeId}"] [data-result]`);
        if (el) el.textContent = `${(timeMs / 1000).toFixed(1)}s`;
    },

    _setError(nodeId, msg, completed, total) {
        const el = document.querySelector(`.pu-gen-node[data-node-id="${nodeId}"] [data-error]`);
        if (el) el.textContent = `FAIL @${completed}/${total}`;
        const progressEl = document.querySelector(`.pu-gen-node[data-node-id="${nodeId}"] [data-progress]`);
        if (progressEl) progressEl.textContent = `${completed}/${total}`;
    },

    _setStage(nodeId, stage) {
        const el = document.querySelector(`.pu-gen-node[data-node-id="${nodeId}"] [data-stage]`);
        if (!el) return;
        if (stage) {
            el.textContent = stage;
            el.setAttribute('data-stage-type', stage);
        } else {
            el.textContent = '';
            el.removeAttribute('data-stage-type');
        }
    },

    _updateGlobalProgress() {
        const pct = Math.min(100, (this._completedCompositions / this._totalCompositions) * 100);
        const fill = document.querySelector('[data-testid="pu-gen-progress-fill"]');
        if (fill) fill.style.width = pct + '%';
        const status = document.querySelector('[data-testid="pu-gen-status"]');
        if (status) status.textContent = `${this._completedCompositions.toLocaleString()} / ${this._totalCompositions.toLocaleString()}`;
    },

    _updatePromptProgress() {
        const el = document.querySelector('.pu-gen-node[data-node-id="prompt"] [data-progress]');
        if (el) el.textContent = `${this._completedBlocks}/${this._blockDefs.length}`;
    },

    _updateButtonUI() {
        const btn = document.querySelector('[data-testid="pu-gen-run-btn"]');
        if (!btn) return;
        btn.disabled = false;
        btn.className = 'pu-gen-btn-run';

        switch (this._runState) {
            case 'idle':
                btn.textContent = 'Run';
                break;
            case 'running':
                btn.textContent = 'Stop';
                btn.classList.add('stop-mode');
                break;
            case 'paused':
                btn.textContent = 'Resume';
                break;
            case 'complete':
                btn.textContent = 'Run Again';
                break;
            case 'failed':
                btn.textContent = 'Run Again';
                break;
        }
    },

    _getExtTextItems(extName) {
        const cache = PU.state.previewMode._extTextCache || {};
        let data = cache[extName];
        if (!data) {
            for (const key of Object.keys(cache)) {
                if (key.endsWith('/' + extName) || key === extName) {
                    data = cache[key];
                    break;
                }
            }
        }
        if (data && Array.isArray(data.text)) return data.text;
        return [];
    },

    /** Build a dropdown with first page of items + pagination nav if >5 */
    _buildPaginatedDropdown(ddId, items) {
        const PAGE_SIZE = 5;
        let html = `<div class="pu-gen-wc-dropdown" data-dropdown-for="${ddId}">`;
        const pageCount = Math.min(PAGE_SIZE, items.length);
        for (let i = 0; i < pageCount; i++) {
            html += `<div class="pu-gen-wc-dropdown-item" data-dd-page-item>${PU.blocks.escapeHtml(String(items[i]))}</div>`;
        }
        if (items.length > PAGE_SIZE) {
            html += `<div class="pu-gen-wc-dropdown-nav" data-dd-nav="${ddId}" data-dd-page="0" data-dd-total="${items.length}">`;
            html += `<button data-dd-prev disabled>&larr;</button>`;
            html += `<span class="pu-gen-wc-dropdown-page">1/${Math.ceil(items.length / PAGE_SIZE)}</span>`;
            html += `<button data-dd-next>&rarr;</button>`;
            html += '</div>';
        }
        html += '</div>';
        return html;
    },

    /** Paginate any dropdown (wildcard or ext_text) */
    _paginateDropdown(nav, direction) {
        const PAGE_SIZE = 5;
        const ddId = nav.getAttribute('data-dd-nav');
        let page = parseInt(nav.getAttribute('data-dd-page'), 10) || 0;
        const total = parseInt(nav.getAttribute('data-dd-total'), 10) || 0;
        const totalPages = Math.ceil(total / PAGE_SIZE);

        page = page + direction;
        if (page < 0) page = 0;
        if (page >= totalPages) page = totalPages - 1;
        nav.setAttribute('data-dd-page', page);

        // Resolve items: check if this is an ext_text pill or a wildcard pill
        const pill = document.querySelector(`[data-wc-id="${ddId}"]`);
        if (!pill) return;
        let items;
        if (ddId.startsWith('ext-')) {
            // ext_text: read from cache
            const extName = pill.getAttribute('data-ext-name') || '';
            items = this._getExtTextItems(extName);
        } else {
            // wildcard: read from lookup
            const lookup = PU.preview.getFullWildcardLookup();
            const wcName = ddId.replace(/^wc-block-[\d-]+-/, '');
            items = lookup[wcName] || [];
        }

        const dropdown = pill.querySelector('.pu-gen-wc-dropdown');
        if (!dropdown) return;
        dropdown.querySelectorAll('[data-dd-page-item]').forEach(el => el.remove());

        const start = page * PAGE_SIZE;
        const end = Math.min(start + PAGE_SIZE, items.length);
        const navEl = dropdown.querySelector('.pu-gen-wc-dropdown-nav');
        for (let i = start; i < end; i++) {
            const div = document.createElement('div');
            div.className = 'pu-gen-wc-dropdown-item';
            div.setAttribute('data-dd-page-item', '');
            div.textContent = String(items[i]);
            dropdown.insertBefore(div, navEl);
        }

        const prevBtn = nav.querySelector('[data-dd-prev]');
        const nextBtn = nav.querySelector('[data-dd-next]');
        const pageLabel = nav.querySelector('.pu-gen-wc-dropdown-page');
        if (prevBtn) prevBtn.disabled = page === 0;
        if (nextBtn) nextBtn.disabled = page >= totalPages - 1;
        if (pageLabel) pageLabel.textContent = `${page + 1}/${totalPages}`;
    },

    _sleep(ms) {
        return new Promise(r => setTimeout(r, ms));
    },
};

// Register modal for overlay dismiss
PU.overlay.registerModal('generate', () => PU.generate.close());
