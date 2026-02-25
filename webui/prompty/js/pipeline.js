/**
 * PromptyUI - Pipeline View
 *
 * Split button dropdown menu (Build ▾) and Pipeline modal.
 * Phase 1: Static block tree with wildcard dimensions + composition counts.
 * Phase 2: Live execution via SSE — Run/Stop/Resume, progress, node expansion.
 */

// === Build Menu (dropdown from the caret button) ===
PU.buildMenu = {
    _visible: false,

    toggle() {
        if (PU.buildMenu._visible) {
            PU.buildMenu.close();
        } else {
            PU.buildMenu.open();
        }
    },

    open() {
        PU.overlay.dismissPopovers();
        const dropdown = document.querySelector('[data-testid="pu-build-menu"]');
        if (!dropdown) return;
        dropdown.style.display = 'block';
        PU.buildMenu._visible = true;
        PU.overlay.showOverlay();
    },

    close() {
        const dropdown = document.querySelector('[data-testid="pu-build-menu"]');
        if (dropdown) dropdown.style.display = 'none';
        PU.buildMenu._visible = false;
    }
};

// Register as popover so overlay dismiss closes it
PU.overlay.registerPopover('buildMenu', () => PU.buildMenu.close());


// === Pipeline Modal ===
PU.pipeline = {
    _eventSource: null,    // Active EventSource connection
    _expandedNodes: {},    // block_path -> true if expanded

    /**
     * Open the pipeline modal and render block tree.
     */
    open() {
        PU.buildMenu.close();
        PU.overlay.dismissAll();

        const modal = document.querySelector('[data-testid="pu-pipeline-modal"]');
        if (!modal) return;

        PU.state.pipeline.visible = true;
        modal.style.display = 'flex';

        // Reset execution state if previous run is complete
        if (PU.state.pipeline.runState === 'complete' || PU.state.pipeline.runState === 'error') {
            PU.pipeline._resetRunState();
        }

        PU.pipeline.render();
        PU.pipeline._updateActionButton();
    },

    /**
     * Close the pipeline modal.
     */
    close() {
        const modal = document.querySelector('[data-testid="pu-pipeline-modal"]');
        if (!modal) return;
        PU.state.pipeline.visible = false;
        modal.style.display = 'none';
        // Don't close EventSource on modal close — execution continues
    },

    /**
     * Reset run state for a fresh run.
     */
    _resetRunState() {
        PU.state.pipeline.runState = 'idle';
        PU.state.pipeline.globalCompleted = 0;
        PU.state.pipeline.globalTotal = 0;
        PU.state.pipeline.blockStates = {};
        PU.state.pipeline.blockProgress = {};
        PU.state.pipeline.stageTimes = {};
        PU.pipeline._expandedNodes = {};
    },

    // ── Execution Control ──────────────────────────────────────

    /**
     * Start pipeline execution via SSE.
     */
    run() {
        const jobId = PU.state.activeJobId;
        const promptId = PU.state.activePromptId;
        if (!jobId || !promptId) return;

        // Reset state
        PU.pipeline._resetRunState();
        PU.state.pipeline.runState = 'running';
        PU.pipeline._updateActionButton();
        PU.pipeline._updateProgress(0, 0);

        // Reset all node states in DOM
        document.querySelectorAll('[data-testid^="pu-pipeline-node-"]').forEach(node => {
            node.dataset.runState = 'idle';
            const progress = node.querySelector('.pu-pipeline-node-progress');
            if (progress) progress.remove();
            const detail = node.querySelector('.pu-pipeline-node-detail');
            if (detail) detail.remove();
        });

        // Connect SSE
        const url = `/api/pu/job/${encodeURIComponent(jobId)}/pipeline/run?prompt_id=${encodeURIComponent(promptId)}`;
        const es = new EventSource(url);
        PU.pipeline._eventSource = es;

        es.addEventListener('init', (e) => {
            const data = JSON.parse(e.data);
            PU.state.pipeline.globalTotal = data.total_jobs;
        });

        es.addEventListener('block_start', (e) => {
            const data = JSON.parse(e.data);
            PU.pipeline._setNodeState(data.block_path, 'running');
            PU.state.pipeline.blockStates[data.block_path] = 'running';
        });

        es.addEventListener('stage', (e) => {
            const data = JSON.parse(e.data);
            PU.pipeline._updateNodeStage(data.block_path, data.stage, data.time_ms);
        });

        es.addEventListener('composition_complete', (e) => {
            const data = JSON.parse(e.data);
            PU.state.pipeline.globalCompleted = data.global_completed;
            PU.state.pipeline.globalTotal = data.global_total;
            PU.state.pipeline.blockProgress[data.block_path] = {
                completed: data.completed,
                total: data.total,
            };
            PU.pipeline._updateNodeProgress(data.block_path, data.completed, data.total);
            PU.pipeline._updateProgress(data.global_completed, data.global_total);

            // If block has more compositions, show partial
            if (data.completed < data.total) {
                PU.pipeline._setNodeState(data.block_path, 'running');
            }
        });

        es.addEventListener('block_complete', (e) => {
            const data = JSON.parse(e.data);
            PU.pipeline._setNodeState(data.block_path, 'complete');
            PU.state.pipeline.blockStates[data.block_path] = 'complete';
            if (data.stage_times) {
                PU.state.pipeline.stageTimes[data.block_path] = data.stage_times;
            }
        });

        es.addEventListener('block_failed', (e) => {
            const data = JSON.parse(e.data);
            PU.pipeline._setNodeState(data.block_path, 'failed');
            PU.state.pipeline.blockStates[data.block_path] = 'failed';
            PU.pipeline._setNodeError(data.block_path, data.error);
        });

        es.addEventListener('block_blocked', (e) => {
            const data = JSON.parse(e.data);
            PU.pipeline._setNodeState(data.block_path, 'blocked');
            PU.state.pipeline.blockStates[data.block_path] = 'blocked';
        });

        es.addEventListener('run_complete', (e) => {
            const data = JSON.parse(e.data);
            PU.state.pipeline.runState = 'complete';
            PU.state.pipeline.stats = data.stats;
            PU.pipeline._updateActionButton();
            PU.pipeline._eventSource = null;
            es.close();
        });

        es.addEventListener('error', (e) => {
            // SSE error — could be connection loss or server error event
            if (es.readyState === EventSource.CLOSED) {
                if (PU.state.pipeline.runState === 'running') {
                    PU.state.pipeline.runState = 'error';
                    PU.pipeline._updateActionButton();
                }
                PU.pipeline._eventSource = null;
            }
        });

        es.onerror = () => {
            if (PU.state.pipeline.runState === 'running') {
                // Connection closed by server (normal end)
                if (es.readyState === EventSource.CLOSED) {
                    if (PU.state.pipeline.runState !== 'complete') {
                        PU.state.pipeline.runState = 'complete';
                        PU.pipeline._updateActionButton();
                    }
                }
            }
            PU.pipeline._eventSource = null;
        };
    },

    /**
     * Stop the running pipeline.
     */
    stop() {
        const jobId = PU.state.activeJobId;
        if (!jobId) return;

        PU.state.pipeline.runState = 'stopping';
        PU.pipeline._updateActionButton();

        fetch(`/api/pu/job/${encodeURIComponent(jobId)}/pipeline/stop`)
            .then(r => r.json())
            .then(() => {
                PU.state.pipeline.runState = 'paused';
                PU.pipeline._updateActionButton();
            })
            .catch(() => {
                PU.state.pipeline.runState = 'paused';
                PU.pipeline._updateActionButton();
            });
    },

    /**
     * Resume from a paused state (re-runs — TreeExecutor state is server-side).
     */
    resume() {
        // For now, resume starts a fresh run since the server executor
        // was disposed after the SSE connection ended.
        PU.pipeline.run();
    },

    // ── Action Button ──────────────────────────────────────────

    /**
     * Handle the action button click (context-dependent).
     */
    handleAction() {
        const state = PU.state.pipeline.runState;
        if (state === 'idle' || state === 'error') {
            PU.pipeline.run();
        } else if (state === 'running') {
            PU.pipeline.stop();
        } else if (state === 'paused') {
            PU.pipeline.resume();
        } else if (state === 'complete') {
            PU.pipeline.close();
        }
    },

    /**
     * Update the action button text and state.
     */
    _updateActionButton() {
        const btn = document.querySelector('[data-testid="pu-pipeline-action-btn"]');
        if (!btn) return;

        const state = PU.state.pipeline.runState;
        const labels = {
            idle: '\u25b6 Run',
            running: '\u23f8 Stop',
            stopping: 'Stopping...',
            paused: '\u25b6 Resume',
            complete: 'Done',
            error: '\u25b6 Retry',
        };
        btn.textContent = labels[state] || '\u25b6 Run';
        btn.dataset.runState = state;

        // Disable during stopping
        btn.disabled = state === 'stopping';
    },

    // ── Progress Bar ───────────────────────────────────────────

    /**
     * Update the global progress bar.
     */
    _updateProgress(completed, total) {
        const bar = document.querySelector('[data-testid="pu-pipeline-progress-fill"]');
        const label = document.querySelector('[data-testid="pu-pipeline-progress-label"]');
        if (bar) {
            const pct = total > 0 ? (completed / total) * 100 : 0;
            bar.style.width = `${pct}%`;
        }
        if (label) {
            label.textContent = total > 0 ? `${completed} / ${total}` : '';
        }
    },

    // ── Node State Updates ─────────────────────────────────────

    /**
     * Set a node's run state (updates data-run-state attribute).
     */
    _setNodeState(blockPath, state) {
        const node = document.querySelector(`[data-node-id="${blockPath}"]`);
        if (node) {
            node.dataset.runState = state;
        }
    },

    /**
     * Update node with current stage label.
     */
    _updateNodeStage(blockPath, stage, timeMs) {
        const node = document.querySelector(`[data-node-id="${blockPath}"]`);
        if (!node) return;

        let stageEl = node.querySelector('.pu-pipeline-node-stage');
        if (!stageEl) {
            stageEl = document.createElement('span');
            stageEl.className = 'pu-pipeline-node-stage';
            const header = node.querySelector('.pu-pipeline-node-header');
            if (header) header.appendChild(stageEl);
        }
        stageEl.textContent = stage;
    },

    /**
     * Update per-block progress counter.
     */
    _updateNodeProgress(blockPath, completed, total) {
        const node = document.querySelector(`[data-node-id="${blockPath}"]`);
        if (!node) return;

        let progressEl = node.querySelector('.pu-pipeline-node-progress');
        if (!progressEl) {
            progressEl = document.createElement('div');
            progressEl.className = 'pu-pipeline-node-progress';
            node.appendChild(progressEl);
        }

        // Mini progress bar + counter
        const pct = total > 0 ? (completed / total) * 100 : 0;
        progressEl.innerHTML = `
            <div class="pu-pipeline-minibar">
                <div class="pu-pipeline-minibar-fill" style="width: ${pct}%"></div>
            </div>
            <span class="pu-pipeline-node-count">${completed}/${total}</span>`;
    },

    /**
     * Show error message on a failed node.
     */
    _setNodeError(blockPath, errorMsg) {
        const node = document.querySelector(`[data-node-id="${blockPath}"]`);
        if (!node) return;

        let errorEl = node.querySelector('.pu-pipeline-node-error');
        if (!errorEl) {
            errorEl = document.createElement('div');
            errorEl.className = 'pu-pipeline-node-error';
            node.appendChild(errorEl);
        }
        errorEl.textContent = errorMsg || 'Hook error';
    },

    // ── Node Expansion ─────────────────────────────────────────

    /**
     * Toggle detail expansion for a node (click handler).
     */
    toggleNodeDetail(blockPath) {
        const node = document.querySelector(`[data-node-id="${blockPath}"]`);
        if (!node) return;

        const isExpanded = PU.pipeline._expandedNodes[blockPath];
        if (isExpanded) {
            // Collapse
            const detail = node.querySelector('.pu-pipeline-node-detail');
            if (detail) detail.remove();
            delete PU.pipeline._expandedNodes[blockPath];
            node.classList.remove('expanded');
        } else {
            // Expand
            PU.pipeline._expandedNodes[blockPath] = true;
            node.classList.add('expanded');
            PU.pipeline._renderNodeDetail(blockPath, node);
        }
    },

    /**
     * Render the expanded detail view for a node.
     */
    _renderNodeDetail(blockPath, node) {
        const times = PU.state.pipeline.stageTimes[blockPath] || {};
        const progress = PU.state.pipeline.blockProgress[blockPath];
        const state = PU.state.pipeline.blockStates[blockPath] || 'idle';

        let detailHtml = '<div class="pu-pipeline-node-detail" data-testid="pu-pipeline-detail-' + blockPath + '">';
        detailHtml += '<div class="pu-pipeline-detail-title">Stage Breakdown</div>';
        detailHtml += '<div class="pu-pipeline-detail-stages">';

        const stageOrder = ['node_start', 'resolve', 'pre', 'generate', 'post', 'node_end'];
        let totalMs = 0;

        for (const stage of stageOrder) {
            const stageTimes = times[stage] || [];
            if (stageTimes.length === 0) {
                if (state !== 'idle') {
                    detailHtml += `<div class="pu-pipeline-detail-row"><span class="pu-pipeline-detail-stage">${stage}</span><span class="pu-pipeline-detail-time">-</span></div>`;
                }
                continue;
            }
            const sum = stageTimes.reduce((a, b) => a + b, 0);
            totalMs += sum;
            const avg = stageTimes.length > 1 ? ` (avg ${(sum / stageTimes.length).toFixed(0)}ms)` : '';
            const count = stageTimes.length > 1 ? ` \u00d7${stageTimes.length}` : '';
            const cached = stage === 'resolve' ? ' (cached)' : '';
            detailHtml += `<div class="pu-pipeline-detail-row">
                <span class="pu-pipeline-detail-stage">${stage}${count}</span>
                <span class="pu-pipeline-detail-time">${sum.toFixed(0)}ms${avg}${cached}</span>
            </div>`;
        }

        detailHtml += '</div>';

        if (totalMs > 0 && progress) {
            detailHtml += `<div class="pu-pipeline-detail-total">Total: ${totalMs.toFixed(0)}ms \u00b7 ${progress.completed} compositions</div>`;
        }

        detailHtml += '</div>';

        node.insertAdjacentHTML('beforeend', detailHtml);
    },

    // ── Render ─────────────────────────────────────────────────

    /**
     * Render the block tree inside the modal body.
     */
    render() {
        const body = document.querySelector('[data-testid="pu-pipeline-body"]');
        if (!body) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            body.innerHTML = `
                <div class="pu-pipeline-empty" data-testid="pu-pipeline-empty">
                    No prompt selected. Open a job and select a prompt first.
                </div>`;
            return;
        }

        const textItems = prompt.text || [];
        if (textItems.length === 0) {
            body.innerHTML = `
                <div class="pu-pipeline-empty" data-testid="pu-pipeline-empty">
                    No text blocks defined in this prompt.
                </div>`;
            return;
        }

        // Get wildcard + dimension info
        const lookup = PU.preview.getFullWildcardLookup();
        const wcNames = Object.keys(lookup).sort();
        const wildcardCounts = {};
        for (const name of wcNames) {
            wildcardCounts[name] = lookup[name].length;
        }
        const extTextCount = PU.state.previewMode.extTextCount || 1;

        // Build block tree
        const blocks = PU.shared.buildBlockTree(textItems);

        // Compute total compositions
        let totalComps = 1;
        for (const name of wcNames) {
            totalComps *= wildcardCounts[name];
        }
        totalComps *= extTextCount;

        // Render
        let html = `
            <div class="pu-pipeline-header-info" data-testid="pu-pipeline-info">
                <span class="pu-pipeline-prompt-name">${PU.blocks.escapeHtml(PU.state.activePromptId || '')}</span>
                <span class="pu-pipeline-stats">${blocks.length} block${blocks.length !== 1 ? 's' : ''} &middot; ${totalComps.toLocaleString()} compositions</span>
            </div>
            <div class="pu-pipeline-dims" data-testid="pu-pipeline-dims">
                ${PU.shared.renderDimPills(wcNames, wildcardCounts, lookup, extTextCount)}
            </div>
            <div class="pu-pipeline-tree" data-testid="pu-pipeline-tree">
                ${PU.pipeline._renderTree(blocks, wcNames, wildcardCounts, lookup)}
            </div>`;

        body.innerHTML = html;

        // Attach click handlers for node expansion
        body.querySelectorAll('.pu-pipeline-node').forEach(node => {
            node.addEventListener('click', (e) => {
                // Don't toggle if clicking a button inside the node
                if (e.target.closest('button')) return;
                PU.pipeline.toggleNodeDetail(node.dataset.nodeId);
            });
        });
    },

    /**
     * Render tree of blocks recursively.
     */
    _renderTree(blocks, wcNames, wildcardCounts, lookup) {
        let html = '';
        for (const block of blocks) {
            html += PU.pipeline._renderBlockNode(block, wcNames, wildcardCounts, lookup);
        }
        return html;
    },

    /**
     * Render a single block node.
     */
    _renderBlockNode(block, wcNames, wildcardCounts, lookup) {
        const indent = block.depth * 24;
        const connector = block.depth > 0 ? '<span class="pu-pipeline-connector"></span>' : '';

        // Wildcards used by this block
        const wcHtml = block.usedWildcards.map(name => {
            const count = wildcardCounts[name] || 0;
            const isExt = PU.shared.isExtWildcard(name);
            const extClass = isExt ? ' pu-pipeline-pill-ext' : '';
            return `<span class="pu-pipeline-node-pill${extClass}">${PU.blocks.escapeHtml(name)}(${count})</span>`;
        }).join('');

        let html = `
            <div class="pu-pipeline-node" data-testid="pu-pipeline-node-${block.path}" data-node-id="${block.path}" data-run-state="idle" style="margin-left: ${indent}px; cursor: pointer;">
                ${connector}
                <div class="pu-pipeline-node-header">
                    <span class="pu-pipeline-node-path">${block.path}</span>
                    <span class="pu-pipeline-node-content">${PU.blocks.escapeHtml(block.content)}</span>
                </div>
                <div class="pu-pipeline-node-meta">
                    ${wcHtml}
                    ${block.hasChildren ? `<span class="pu-pipeline-node-children">${block.children.length} child${block.children.length !== 1 ? 'ren' : ''}</span>` : ''}
                </div>
            </div>`;

        // Render children
        if (block.children.length > 0) {
            html += PU.pipeline._renderTree(block.children, wcNames, wildcardCounts, lookup);
        }

        return html;
    }
};

// Register pipeline modal for overlay dismiss
PU.overlay.registerModal('pipeline', () => PU.pipeline.close());
