/**
 * PromptyUI - Build Composition
 *
 * Slide-out panel for composition management:
 * - Defaults (job-wide ext scope, ext_text_max, wc_max)
 * - Prompt section (dimensions + total, reflecting bucketing)
 * - Composition navigator (prev/next/shuffle)
 * - Resolved output preview
 * - Export .txt
 */

PU.buildComposition = {
    /**
     * Open the Build Composition panel
     */
    open() {
        const panel = document.querySelector('[data-testid="pu-build-panel"]');
        if (!panel) return;
        PU.state.buildComposition.visible = true;
        panel.style.display = 'flex';
        // Trigger reflow then add class for animation
        panel.offsetHeight;
        panel.classList.add('open');
        PU.buildComposition.render();
    },

    /**
     * Close the Build Composition panel
     */
    close() {
        const panel = document.querySelector('[data-testid="pu-build-panel"]');
        if (!panel) return;
        PU.state.buildComposition.visible = false;
        panel.classList.remove('open');
        setTimeout(() => {
            if (!PU.state.buildComposition.visible) {
                panel.style.display = 'none';
            }
        }, 200);
    },

    /**
     * Toggle panel open/close
     */
    toggle() {
        if (PU.state.buildComposition.visible) {
            PU.buildComposition.close();
        } else {
            PU.buildComposition.open();
        }
    },

    /**
     * Full render of all panel sections
     */
    render() {
        if (!PU.state.buildComposition.visible) return;
        PU.buildComposition.renderDefaults();
        PU.buildComposition.renderPromptSection();
        PU.buildComposition.renderNavigator();
    },

    /**
     * Shared computation of wildcard lookup, counts, and effective total.
     * Uses getFullWildcardLookup (prompt + extension wildcards) and
     * computeEffectiveTotal (respects ext_text_max and ext_wildcards_max bucketing).
     */
    _getCompositionParams() {
        const lookup = PU.preview.getFullWildcardLookup();
        const wcNames = Object.keys(lookup).sort();
        const wildcardCounts = {};
        for (const name of wcNames) {
            wildcardCounts[name] = lookup[name].length;
        }
        const extTextCount = PU.state.previewMode.extTextCount || 1;
        const extTextMax = PU.state.previewMode.extTextMax || 1;
        const wcMax = PU.state.previewMode.wildcardsMax || 0;

        const total = PU.preview.computeEffectiveTotal(extTextCount, wildcardCounts, extTextMax, wcMax);

        return { lookup, wcNames, wildcardCounts, extTextCount, extTextMax, wcMax, total };
    },

    /**
     * Render the Defaults section
     */
    renderDefaults() {
        const job = PU.helpers.getActiveJob();
        if (!job) return;
        const defaults = job.defaults || {};

        // Ext scope
        const extSelect = document.querySelector('[data-testid="pu-build-defaults-ext"]');
        if (extSelect) {
            PU.editor.populateExtDropdown(extSelect, defaults.ext || 'defaults');
        }

        // ext_text_max — read from previewMode (the actual runtime value)
        const etmInput = document.querySelector('[data-testid="pu-build-defaults-ext-text-max"]');
        if (etmInput) etmInput.value = PU.state.previewMode.extTextMax;

        // ext_wc_max — read from previewMode
        const ewmInput = document.querySelector('[data-testid="pu-build-defaults-ext-wc-max"]');
        if (ewmInput) ewmInput.value = PU.state.previewMode.wildcardsMax;
    },

    /**
     * Handle defaults field changes
     */
    async updateDefault(field, value) {
        const val = parseInt(value, 10);

        if (field === 'ext') {
            const job = PU.helpers.getActiveJob();
            if (!job) return;
            if (!job.defaults) job.defaults = {};
            job.defaults.ext = value;
            PU.helpers.markJobModified(PU.state.activeJobId, job);
            // Also update main editor ext dropdown
            const mainExt = document.querySelector('[data-testid="pu-defaults-ext"]');
            if (mainExt) mainExt.value = value;
        } else if (field === 'ext_text_max') {
            // Write to previewMode (runtime control) via preview API
            await PU.preview.updateExtTextMax(isNaN(val) || val < 1 ? 1 : val);
        } else if (field === 'wildcards_max') {
            // Write to previewMode via preview API
            await PU.preview.updateWildcardsMax(isNaN(val) || val < 0 ? 0 : val);
            // Clear pins and locks when wcMax changes
            PU.state.previewMode.selectedWildcards = {};
            PU.state.previewMode.lockedValues = {};
        }

        // Re-render prompt section (dimensions may change)
        PU.buildComposition.renderPromptSection();
        PU.buildComposition.renderNavigator();

        // Sync main editor blocks
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
    },

    /**
     * Render the Prompt section (dimensions + total)
     * Uses full wildcard lookup (prompt + extensions) and effective total (bucketed).
     */
    renderPromptSection() {
        const container = document.querySelector('[data-testid="pu-build-prompt-section"]');
        if (!container) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            container.innerHTML = '<div class="pu-build-empty">No prompt selected</div>';
            return;
        }

        const { wildcardCounts, extTextCount, extTextMax, wcMax, total } = PU.buildComposition._getCompositionParams();
        const wcNames = Object.keys(wildcardCounts).sort();

        // Build dimension display
        const dims = [];
        for (const name of wcNames) {
            const raw = wildcardCounts[name];
            if (wcMax > 0 && raw > wcMax) {
                const bucketed = Math.ceil(raw / wcMax);
                dims.push({ name, display: `${name}(${bucketed}/${raw})` });
            } else {
                dims.push({ name, display: `${name}(${raw})` });
            }
        }

        // Include ext_text dimension if present
        if (extTextCount > 1) {
            if (extTextMax > 1) {
                const bucketed = Math.ceil(extTextCount / extTextMax);
                dims.unshift({ name: 'ext_text', display: `ext_text(${bucketed}/${extTextCount})` });
            } else {
                dims.unshift({ name: 'ext_text', display: `ext_text(${extTextCount})` });
            }
        }

        const dimStr = dims.length > 0
            ? dims.map(d => d.display).join(' &times; ')
            : 'No wildcards';

        container.innerHTML = `
            <div class="pu-build-prompt-name" data-testid="pu-build-prompt-name">${PU.blocks.escapeHtml(PU.state.activePromptId || '')}</div>
            <div class="pu-build-dims" data-testid="pu-build-dims">
                <span class="pu-build-dims-label">Dimensions:</span> ${dimStr}
            </div>
            <div class="pu-build-total" data-testid="pu-build-total">
                Total: <strong>${total.toLocaleString()}</strong> compositions
            </div>
        `;
    },

    /**
     * Render the composition navigator with resolved output
     */
    async renderNavigator() {
        const navContainer = document.querySelector('[data-testid="pu-build-navigator"]');
        if (!navContainer) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            navContainer.innerHTML = '<div class="pu-build-empty">No prompt selected</div>';
            return;
        }

        const { lookup, wcNames, wildcardCounts, extTextCount, total } = PU.buildComposition._getCompositionParams();
        const compId = PU.state.previewMode.compositionId;
        const effectiveId = total > 0 ? compId % total : 0;

        // Get current wildcard values for this composition
        const [extIdx, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);
        const wcDetails = wcNames.map(name => ({
            name,
            value: lookup[name][wcIndices[name] || 0] || '?',
            index: wcIndices[name] || 0
        }));

        // Render nav controls
        const navHtml = `
            <div class="pu-build-nav-controls">
                <button class="pu-btn-icon-only" data-testid="pu-build-nav-prev" onclick="PU.buildComposition.navigate(-1)" title="Previous">&lsaquo;</button>
                <span class="pu-build-nav-label" data-testid="pu-build-nav-label">${effectiveId + 1} / ${total}</span>
                <button class="pu-btn-icon-only" data-testid="pu-build-nav-next" onclick="PU.buildComposition.navigate(1)" title="Next">&rsaquo;</button>
                <button class="pu-btn-icon-only" data-testid="pu-build-nav-shuffle" onclick="PU.buildComposition.shuffle()" title="Random">&#8635;</button>
            </div>
            <div class="pu-build-nav-details" data-testid="pu-build-nav-details">
                ${wcDetails.map(d => `<span class="pu-build-wc-tag">${PU.blocks.escapeHtml(d.name)}=<strong>"${PU.blocks.escapeHtml(d.value)}"</strong></span>`).join('')}
            </div>
            <div class="pu-build-nav-output" data-testid="pu-build-nav-output">
                <div class="pu-build-loading">Resolving...</div>
            </div>
        `;
        navContainer.innerHTML = navHtml;

        // Resolve output for current composition
        await PU.buildComposition._resolveCurrentOutput();

        // Update export estimate after output is resolved
        await PU.buildComposition.updateExportEstimate();
    },

    /**
     * Resolve and render the output for the current composition
     */
    async _resolveCurrentOutput() {
        const outputEl = document.querySelector('[data-testid="pu-build-nav-output"]');
        if (!outputEl) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return;

        const textItems = prompt.text || [];
        if (!Array.isArray(textItems) || textItems.length === 0) {
            outputEl.innerHTML = '<div class="pu-build-empty">No content blocks</div>';
            return;
        }

        const resolutions = await PU.preview.buildBlockResolutions(textItems, {
            skipOdometerUpdate: true,
            ignoreOverrides: true
        });

        const terminals = PU.preview.computeTerminalOutputs(textItems, resolutions);

        if (terminals.length === 0) {
            outputEl.innerHTML = '<div class="pu-build-empty">No resolved output</div>';
            return;
        }

        outputEl.innerHTML = terminals.map((t, i) =>
            `<div class="pu-build-output-item" data-testid="pu-build-output-item-${i}">${PU.blocks.escapeHtml(t.text)}</div>`
        ).join('');
    },

    /**
     * Navigate to prev/next composition (wraps around total).
     */
    async navigate(direction) {
        const { total } = PU.buildComposition._getCompositionParams();
        if (total <= 0) return;

        let newId = PU.state.previewMode.compositionId + direction;
        if (newId < 0) newId = total - 1;
        if (newId >= total) newId = 0;

        PU.state.previewMode.compositionId = newId;
        PU.preview.clearStaleBlockOverrides();
        PU.actions.updateUrl();
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.rightPanel.render();
        await PU.buildComposition.renderNavigator();
    },

    /**
     * Jump to random composition.
     */
    async shuffle() {
        const { total } = PU.buildComposition._getCompositionParams();
        if (total <= 0) return;

        const newId = Math.floor(Math.random() * total);
        PU.state.previewMode.compositionId = newId;
        PU.preview.clearStaleBlockOverrides();
        PU.actions.updateUrl();
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.rightPanel.render();
        await PU.buildComposition.renderNavigator();
    },

    /**
     * Estimate the .txt file size from a single sample composition.
     * Called whenever the navigator renders so the button stays current.
     */
    async updateExportEstimate() {
        const estimateEl = document.querySelector('[data-testid="pu-build-export-estimate"]');
        const exportBtn = document.querySelector('[data-testid="pu-build-export-btn"]');
        if (!estimateEl) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            estimateEl.textContent = '';
            return;
        }

        const { total } = PU.buildComposition._getCompositionParams();

        if (total === 0) {
            estimateEl.textContent = '';
            return;
        }

        // Sample: use the current composition's resolved output
        const outputEl = document.querySelector('[data-testid="pu-build-nav-output"]');
        const sampleText = outputEl ? outputEl.textContent.trim() : '';
        const sampleBodyBytes = new Blob([sampleText]).size;

        // Estimate header per entry: "---\nComposition N: wc1=val1, wc2=val2\n---\n"
        const navDetails = document.querySelector('[data-testid="pu-build-nav-details"]');
        const labelSample = navDetails ? navDetails.textContent.trim() : '';
        const headerBytes = 4 + 12 + String(total).length + 2 + new Blob([labelSample]).size + 5; // ---\n + "Composition " + id + ": " + label + "\n---\n"

        const perEntryBytes = headerBytes + sampleBodyBytes + 2; // + "\n\n"
        const totalBytes = perEntryBytes * total;

        const sizeStr = PU.buildComposition._formatBytes(totalBytes);
        estimateEl.textContent = `${total.toLocaleString()} compositions \u00B7 ~${sizeStr}`;

        if (exportBtn) {
            exportBtn.textContent = `Export .txt (~${sizeStr})`;
        }
    },

    /**
     * Format bytes to human-readable string
     */
    _formatBytes(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
    },

    /**
     * Export all compositions directly to .txt file.
     * Resolves one composition at a time to avoid holding everything in memory.
     */
    async exportTxt() {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return;

        const textItems = prompt.text || [];
        if (!Array.isArray(textItems) || textItems.length === 0) return;

        const { lookup, wcNames, wildcardCounts, extTextCount, total } = PU.buildComposition._getCompositionParams();

        if (total === 0) return;

        const btn = document.querySelector('[data-testid="pu-build-export-btn"]');
        if (btn) {
            btn.disabled = true;
            btn.textContent = `Exporting... 0/${total}`;
        }

        PU.state.buildComposition.generating = true;
        const savedCompId = PU.state.previewMode.compositionId;
        const chunks = [];
        const BATCH_SIZE = 100;

        for (let i = 0; i < total; i++) {
            if (!PU.state.buildComposition.generating) break;

            PU.state.previewMode.compositionId = i;

            const resolutions = await PU.preview.buildBlockResolutions(textItems, {
                skipOdometerUpdate: true,
                ignoreOverrides: true
            });
            const terminals = PU.preview.computeTerminalOutputs(textItems, resolutions);

            const [extIdx, wcIndices] = PU.preview.compositionToIndices(i, extTextCount, wildcardCounts);
            const label = wcNames.map(name => {
                const val = lookup[name][wcIndices[name] || 0] || '?';
                return `${name}=${val}`;
            }).join(', ');

            let entry = `---\nComposition ${i}: ${label}\n---\n`;
            entry += terminals.map(t => t.text).join('\n\n');
            entry += '\n\n';
            chunks.push(entry);

            // Update progress every batch
            if (i % BATCH_SIZE === 0 && btn) {
                btn.textContent = `Exporting... ${i + 1}/${total}`;
                // Yield to browser to prevent freeze
                await new Promise(r => setTimeout(r, 0));
            }
        }

        // Restore composition ID
        PU.state.previewMode.compositionId = savedCompId;
        PU.state.buildComposition.generating = false;

        // Build blob from chunks and download
        const blob = new Blob(chunks, { type: 'text/plain' });
        const jobId = PU.state.activeJobId || 'unknown';
        const promptId = PU.state.activePromptId || 'unknown';
        const filename = `${jobId}_${promptId}_compositions.txt`;

        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);

        const sizeStr = PU.buildComposition._formatBytes(blob.size);
        PU.actions.showToast(`Exported ${chunks.length} compositions (${sizeStr})`, 'success');

        if (btn) {
            btn.disabled = false;
            PU.buildComposition.updateExportEstimate();
        }

        // Re-render navigator to restore current composition preview
        await PU.buildComposition.renderNavigator();
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
    }
};
