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
        });

        // Escape key: clear all locked values (power-user shortcut)
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && !(e.target && e.target.closest && e.target.closest('input, textarea, [contenteditable]'))) {
                const locked = PU.state.previewMode.lockedValues;
                if (Object.keys(locked).length > 0) {
                    // Clear all locks and revert all per-wildcard max overrides
                    PU.state.previewMode.lockedValues = {};
                    PU.state.previewMode.wildcardMaxOverrides = {};
                    // Clear global pin overrides
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
    // Operations (Phase 2)
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
        PU.rightPanel.renderWildcardStream();
        PU.rightPanel.renderOpsSection();
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
        const themeSourceMap = PU.rightPanel._buildThemeSourceMap();

        for (const name of allNames) {
            const isLocal = localNames.has(name);
            const isExt = !isLocal || PU.rightPanel._isExtWildcard(name);
            const themeSrc = themeSourceMap[name];

            if (isLocal && isExt) {
                localWildcards.push({ name, source: 'override' });
            } else if (isLocal) {
                localWildcards.push({ name, source: 'local' });
            } else if (themeSrc) {
                sharedWildcards.push({ name, source: 'theme', path: themeSrc });
            } else {
                sharedWildcards.push({ name, source: 'ext', path: PU.rightPanel._getExtWildcardPath(name) });
            }
        }

        // Get current composition indices for active chip highlighting
        const wildcardCounts = {};
        for (const name of allNames) {
            wildcardCounts[name] = fullLookup[name].length;
        }
        const extTextCount = PU.state.previewMode.extTextCount || 1;
        const extTextMax = PU.state.previewMode.extTextMax || 1;
        const compositionId = PU.state.previewMode.compositionId;
        const wcMax = PU.state.previewMode.wildcardsMax;
        const wcMaxMap = PU.state.previewMode.wildcardMaxOverrides || null;
        const hasOverrides = wcMaxMap && Object.keys(wcMaxMap).length > 0;

        let odometerIndices, bucketInfo = null;
        if (wcMax > 0 || hasOverrides) {
            const br = PU.preview.bucketCompositionToIndices(compositionId, extTextCount, extTextMax, wildcardCounts, wcMax, wcMaxMap);
            odometerIndices = br.wcValueIndices;
            bucketInfo = { wcMax, wcMaxMap, bucketResult: br, wildcardCounts };
        } else {
            [, odometerIndices] = PU.preview.compositionToIndices(compositionId, extTextCount, wildcardCounts);
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
                html += PU.rightPanel._renderWcEntry(wc, fullLookup[wc.name], odometerIndices[wc.name] || 0, bucketInfo, blockPins, lockedValues);
            }
            html += '</div>';
        }

        // Local wildcards section
        if (localWildcards.length > 0) {
            html += PU.rightPanel._renderDivider('local');
            html += '<div class="pu-rp-wc-section">';
            for (const wc of localWildcards) {
                html += PU.rightPanel._renderWcEntry(wc, fullLookup[wc.name], odometerIndices[wc.name] || 0, bucketInfo, blockPins, lockedValues);
            }
            html += '</div>';
        }

        container.innerHTML = html;

        // Update top bar
        PU.rightPanel._updateTopBar(prompt, allNames.length);

        // Attach chip click handlers
        // In-window: toggle lock (constrains navigation + sets preview)
        // Out-of-window: lock check → bucket jump or expand popover
        container.querySelectorAll('.pu-rp-wc-v').forEach(chip => {
            chip.addEventListener('click', () => {
                const wcName = chip.dataset.wcName;
                const val = chip.dataset.value;
                const inWindow = chip.dataset.inWindow === 'true';
                const idx = parseInt(chip.dataset.idx, 10);
                if (wcName && val !== undefined) {
                    if (inWindow) {
                        PU.rightPanel.toggleLock(wcName, val);
                    } else {
                        PU.rightPanel.handleOutOfWindowClick(wcName, val, idx);
                    }
                }
            });

            // Right-click: show replacement popover (Phase 3)
            chip.addEventListener('contextmenu', (e) => {
                if (!PU.state.buildComposition.activeOperation) return;
                e.preventDefault();
                PU.rightPanel.showReplacePopover(chip, e);
            });
        });
    },

    /**
     * Build a map of wildcard name -> theme source id for wildcards
     * that come from ext_text blocks in the current prompt.
     */
    _buildThemeSourceMap() {
        const map = {};
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text)) return map;

        const extTextNames = [];
        const walkBlocks = (items) => {
            for (const item of items) {
                if (typeof item === 'object' && 'ext_text' in item && item.ext_text) {
                    extTextNames.push(item.ext_text);
                }
                if (item && item.after) walkBlocks(item.after);
            }
        };
        walkBlocks(prompt.text);

        const cache = PU.state.previewMode._extTextCache || {};
        for (const extName of extTextNames) {
            const data = cache[extName];
            if (data && data.wildcards) {
                for (const wc of data.wildcards) {
                    if (wc.name && !map[wc.name]) {
                        map[wc.name] = extName;
                    }
                }
            }
        }

        return map;
    },

    /**
     * Check if a wildcard name exists in the extension cache
     */
    _isExtWildcard(name) {
        const cache = PU.state.previewMode._extTextCache || {};
        for (const cacheKey of Object.keys(cache)) {
            const data = cache[cacheKey];
            if (data && data.wildcards) {
                for (const wc of data.wildcards) {
                    if (wc.name === name) return true;
                }
            }
        }
        return false;
    },

    /**
     * Get the extension source path for a wildcard name
     */
    _getExtWildcardPath(name) {
        const cache = PU.state.previewMode._extTextCache || {};
        for (const cacheKey of Object.keys(cache)) {
            const data = cache[cacheKey];
            if (data && data.wildcards) {
                for (const wc of data.wildcards) {
                    if (wc.name === name) return cacheKey;
                }
            }
        }
        return '';
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
     * Render a single wildcard entry with header (name + path) + bordered chips.
     * Bucket mode: in-window chips inside a frame, out-of-window chips outside.
     * Operation mode: replaced-val chips show replacement text with asterisk.
     * No filter/deselected logic — chips navigate on click.
     */
    _renderWcEntry(wc, values, activeIdx, bucketInfo, blockPins, lockedValues) {
        const esc = PU.blocks.escapeHtml;
        const name = wc.name;
        const safeName = esc(name);
        const isShared = wc.source === 'theme' || wc.source === 'ext';

        // Operation mappings for this wildcard
        const opMappings = PU.rightPanel._getOpMappings(name);

        // Block-pin asterisk indicator
        const hasBlockPin = blockPins && blockPins[name];
        const pinIndicator = hasBlockPin ? '<span class="pin-indicator" title="Pinned via block dropdown">*</span>' : '';

        // Override mark on name if operation has mappings for this wildcard
        const overrideMark = opMappings ? '<span class="pu-rp-wc-override-mark" title="Operation has replacements for this wildcard">*</span>' : '';

        // wc-path for shared wildcards (shows source like "professional/tones")
        let pathHtml = '';
        if (isShared && wc.path) {
            pathHtml = `<span class="pu-rp-wc-path">${esc(wc.path)}</span>`;
        }

        const wrappedIdx = values.length > 0 ? activeIdx % values.length : 0;

        // Helper: render a single chip with operation replacement applied
        const renderChip = (originalValue, i, inWindow, isOutWindow) => {
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

            if (isOutWindow) {
                cls += ' out-window';
            } else if (i === wrappedIdx) {
                cls += ' active';
            }

            // Locked value indicator
            const isLocked = lockedValues[name] && lockedValues[name].includes(originalValue);
            if (isLocked) cls += ' locked';

            const asterisk = isReplaced ? '<span class="asterisk">*</span>' : '';
            const lockIcon = isLocked ? '<span class="lock-icon">&#128274;</span>' : '';

            // Tooltip: locked state > replacement > default
            let titleAttr;
            if (isReplaced) {
                titleAttr = ` title="replaces &quot;${esc(originalValue)}&quot;"`;
            } else if (isOutWindow) {
                titleAttr = ` title="Click to lock this value (may expand bucket)"`;
            } else if (isLocked) {
                titleAttr = ` title="Locked — click to unlock"`;
            } else {
                titleAttr = ` title="Click to lock this value"`;
            }

            return `<span class="${cls}" data-testid="pu-rp-wc-chip-${safeName}-${i}" data-wc-name="${safeName}" data-value="${esc(originalValue)}" data-in-window="${inWindow}" data-idx="${i}"${titleAttr}${extraAttrs}>${lockIcon}${esc(displayValue)}${asterisk}</span>`;
        };

        let chipsHtml;
        // Per-wildcard effective max for bucket window
        const effectiveWcMax = (bucketInfo && bucketInfo.wcMaxMap && bucketInfo.wcMaxMap[name]) || (bucketInfo && bucketInfo.wcMax) || 0;
        if (bucketInfo && effectiveWcMax > 0 && values.length > effectiveWcMax) {
            const bucketIdx = bucketInfo.bucketResult.wcBucketIndices[name] || 0;
            const bucketStart = bucketIdx * effectiveWcMax;
            const bucketEnd = Math.min(bucketStart + effectiveWcMax, values.length);

            let inWindowChips = '';
            for (let i = bucketStart; i < bucketEnd; i++) {
                inWindowChips += renderChip(values[i], i, 'true', false);
            }
            const frameHtml = `<div class="pu-rp-wc-window-frame">${inWindowChips}</div>`;

            let outWindowChips = '';
            for (let i = 0; i < values.length; i++) {
                if (i >= bucketStart && i < bucketEnd) continue;
                outWindowChips += renderChip(values[i], i, 'false', true);
            }
            chipsHtml = frameHtml + outWindowChips;
        } else {
            chipsHtml = values.map((v, i) => renderChip(v, i, 'true', false)).join('');
        }

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

        return `<div class="pu-rp-wc-entry" data-testid="pu-rp-wc-entry-${safeName}">
            <div class="pu-rp-wc-entry-header">
                <span class="pu-rp-wc-name">${safeName}${overrideMark}${pinIndicator}</span>
                ${pathHtml}
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

        const { wcNames, wildcardCounts, extTextCount, extTextMax, wcMax, wcMaxMap, total } = PU.buildComposition._getCompositionParams();
        const compId = PU.state.previewMode.compositionId;
        const effectiveId = total > 0 ? compId % total : 0;
        const effectiveMaxFn = (n) => (wcMaxMap && wcMaxMap[n]) || wcMax;

        // Bucket window hint
        let windowHint = '';
        if (wcMax > 0 || (wcMaxMap && Object.keys(wcMaxMap).length > 0)) {
            const sortedWc = Object.keys(wildcardCounts).sort();
            const extBucketCount = extTextMax > 0 ? Math.ceil(extTextCount / extTextMax) : 1;
            const bucketDims = [extBucketCount, ...sortedWc.map(n => { const em = effectiveMaxFn(n); return em > 0 ? Math.ceil(wildcardCounts[n] / em) : 1; })];
            const totalBuckets = bucketDims.reduce((a, b) => a * b, 1);
            // Compute current bucket index
            const br = PU.preview.bucketCompositionToIndices(compId, extTextCount, extTextMax, wildcardCounts, wcMax, wcMaxMap);
            // Compute overall bucket number from bucket indices
            const bucketIndices = [br.extBucketIdx, ...sortedWc.map(n => br.wcBucketIndices[n] || 0)];
            let currentBucket = 0;
            let multiplier = 1;
            for (let i = bucketDims.length - 1; i >= 0; i--) {
                currentBucket += bucketIndices[i] * multiplier;
                multiplier *= bucketDims[i];
            }
            windowHint = ` <span class="pu-rp-ops-nav-window">(window ${currentBucket + 1}/${totalBuckets})</span>`;
        }

        // Navigation label: "N / total (window X/M)"
        const navLabel = `<b>${(effectiveId + 1).toLocaleString()}</b> / <b>${total.toLocaleString()}</b>${windowHint}`;

        // Per-wildcard dimension summary
        let dimsHtml = '';
        if (wcNames.length > 0 || extTextCount > 1) {
            const dimParts = [];
            const sortedWc = wcNames.slice().sort();

            if (extTextCount > 1) {
                if (extTextMax > 0 && extTextCount > extTextMax) {
                    const buckets = Math.ceil(extTextCount / extTextMax);
                    dimParts.push(`<span class="pu-rp-ops-dim"><span class="dim-bucket">${buckets}</span><span class="dim-sep">/</span>${extTextCount} txt</span>`);
                } else {
                    dimParts.push(`<span class="pu-rp-ops-dim">${extTextCount} txt</span>`);
                }
            }

            for (const n of sortedWc) {
                const count = wildcardCounts[n];
                const em = effectiveMaxFn(n);
                const abbr = n.length > 4 ? n.slice(0, 3) : n;
                if (em > 0 && count > em) {
                    const buckets = Math.ceil(count / em);
                    dimParts.push(`<span class="pu-rp-ops-dim"><span class="dim-bucket">${buckets}</span><span class="dim-sep">/</span>${count} ${PU.blocks.escapeHtml(abbr)}</span>`);
                } else {
                    dimParts.push(`<span class="pu-rp-ops-dim">${count} ${PU.blocks.escapeHtml(abbr)}</span>`);
                }
            }

            dimsHtml = dimParts.join('<span class="pu-rp-ops-x">&times;</span>');
        }

        // Size estimate
        const sampleSize = 200;
        const sizeStr = PU.buildComposition._formatBytes(sampleSize * total);

        // Bucket count for bottom row
        let bucketLabel = '';
        if (wcMax > 0 || (wcMaxMap && Object.keys(wcMaxMap).length > 0)) {
            const sortedWc = Object.keys(wildcardCounts).sort();
            const extBucketCount = extTextMax > 0 ? Math.ceil(extTextCount / extTextMax) : 1;
            const bucketDims = [extBucketCount, ...sortedWc.map(n => { const em = effectiveMaxFn(n); return em > 0 ? Math.ceil(wildcardCounts[n] / em) : 1; })];
            const totalBuckets = bucketDims.reduce((a, b) => a * b, 1);
            bucketLabel = `${totalBuckets} buckets <span class="pu-rp-ops-total-detail">&middot; </span>`;
        }

        container.innerHTML = `
            <div class="pu-rp-ops-nav">
                <button class="pu-rp-ops-nav-btn" data-testid="pu-rp-nav-prev" onclick="PU.rightPanel.navigate(-1)" title="Previous">&lsaquo;</button>
                <span class="pu-rp-ops-nav-text" data-testid="pu-rp-nav-label">${navLabel}</span>
                <button class="pu-rp-ops-nav-btn" data-testid="pu-rp-nav-next" onclick="PU.rightPanel.navigate(1)" title="Next">&rsaquo;</button>
                <button class="pu-rp-ops-nav-btn" data-testid="pu-rp-nav-shuffle" onclick="PU.rightPanel.shuffle()" title="Shuffle">&#8635;</button>
            </div>
            ${dimsHtml ? `<div class="pu-rp-ops-dims" data-testid="pu-rp-ops-dims">${dimsHtml}</div>` : ''}
            <div class="pu-rp-ops-bottom-row">
                <span class="pu-rp-ops-total" data-testid="pu-rp-ops-total">${bucketLabel}${total.toLocaleString()} compositions</span>
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

        const { total } = PU.buildComposition._getCompositionParams();
        const sampleBytes = new Blob([sampleText]).size;
        const headerBytes = 40;
        const totalBytes = (sampleBytes + headerBytes + 2) * total;
        const sizeStr = PU.buildComposition._formatBytes(totalBytes);

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
            wildcard_overrides: PU.helpers.deepClone(PU.state.previewMode.wildcardMaxOverrides),
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

            if (promptSession) {
                // Hydrate state from session (URL params take precedence on initial load)
                if (typeof promptSession.composition === 'number' && !PU.state.previewMode._compositionFromUrl) {
                    PU.state.previewMode.compositionId = promptSession.composition;
                }
                delete PU.state.previewMode._compositionFromUrl;
                if (promptSession.locked_values && typeof promptSession.locked_values === 'object') {
                    PU.state.previewMode.lockedValues = promptSession.locked_values;
                }
                if (promptSession.wildcard_overrides && typeof promptSession.wildcard_overrides === 'object') {
                    PU.state.previewMode.wildcardMaxOverrides = promptSession.wildcard_overrides;
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
        if (JSON.stringify(current.wildcard_overrides) !== JSON.stringify(baseline.wildcard_overrides)) return true;

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
    // Navigation
    // ============================================

    /**
     * Navigate to prev/next composition (simple increment/decrement, wraps around).
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
    },

    /**
     * Toggle a locked wildcard value. In-window chips use this.
     * Locked values constrain bucket navigation and set preview overrides.
     * If the value is already locked, unlock it.
     * When all locks for a wildcard are cleared, revert its per-wildcard max override.
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
                // Revert per-wildcard max override when all locks cleared
                delete PU.state.previewMode.wildcardMaxOverrides[wcName];
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

        // Re-render blocks with new override (suppress transitions)
        const container = document.querySelector('[data-testid="pu-blocks-container"]');
        if (container) container.classList.add('pu-no-transition');
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        if (container) {
            container.offsetHeight;
            container.classList.remove('pu-no-transition');
        }
        PU.rightPanel.render();
    },

    /**
     * Handle out-of-window chip click.
     * Locks the value. If the locked value's bucket differs from current,
     * check if a composition exists that satisfies all locks.
     * If not, show expand popover to increase per-wildcard max.
     */
    async handleOutOfWindowClick(wcName, value, idx) {
        const locked = PU.state.previewMode.lockedValues;
        const wcMax = PU.state.previewMode.wildcardsMax;
        const wcMaxMap = PU.state.previewMode.wildcardMaxOverrides || {};
        const effectiveMax = wcMaxMap[wcName] || wcMax;

        // Lock the value first
        if (!locked[wcName]) locked[wcName] = [];
        if (!locked[wcName].includes(value)) {
            locked[wcName].push(value);
        }

        // Check if all locked values for this wildcard fit in one bucket window
        const lockedForWc = locked[wcName];
        if (effectiveMax > 0 && lockedForWc.length > 0) {
            // Get full values list for this wildcard
            const fullLookup = PU.preview.getFullWildcardLookup();
            const allValues = fullLookup[wcName] || [];

            // Find indices of all locked values
            const lockedIndices = lockedForWc.map(v => allValues.indexOf(v)).filter(i => i >= 0);
            if (lockedIndices.length > 0) {
                const minIdx = Math.min(...lockedIndices);
                const maxIdx = Math.max(...lockedIndices);
                const minBucket = Math.floor(minIdx / effectiveMax);
                const maxBucket = Math.floor(maxIdx / effectiveMax);

                if (minBucket !== maxBucket) {
                    // Locked values span multiple buckets — need expansion
                    const neededMax = maxIdx - (minBucket * effectiveMax) + 1;
                    // Ensure the needed max covers all locked values from the first locked bucket
                    const coverMax = Math.max(neededMax, lockedForWc.length);
                    const expandTo = Math.min(allValues.length, Math.max(coverMax, effectiveMax + 1));

                    PU.rightPanel._showExpandPopover(wcName, value, expandTo, allValues.length);
                    return;
                }
            }
        }

        // Values fit in one bucket — navigate to that bucket
        if (effectiveMax > 0) {
            const targetBucketIdx = Math.floor(idx / effectiveMax);
            const newId = PU.rightPanel.findCompositionForBuckets({ [wcName]: targetBucketIdx });
            if (newId !== null) {
                PU.state.previewMode.compositionId = newId;
                PU.preview.clearStaleBlockOverrides();
            }
        }

        // Sync preview override
        const sw = PU.state.previewMode.selectedWildcards;
        if (!sw['*']) sw['*'] = {};
        sw['*'][wcName] = value;

        PU.actions.updateUrl();
        const blockContainer = document.querySelector('[data-testid="pu-blocks-container"]');
        if (blockContainer) blockContainer.classList.add('pu-no-transition');
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        if (blockContainer) {
            blockContainer.offsetHeight;
            blockContainer.classList.remove('pu-no-transition');
        }
        PU.rightPanel.render();
    },

    /**
     * Show the expand popover when locked values span multiple buckets.
     * Offers to increase per-wildcard max to accommodate all locked values.
     */
    _showExpandPopover(wcName, clickedValue, expandTo, totalValues) {
        const popover = document.querySelector('[data-testid="pu-rp-replace-popover"]');
        if (!popover) return;

        const esc = PU.blocks.escapeHtml;
        const currentMax = PU.state.previewMode.wildcardMaxOverrides[wcName] || PU.state.previewMode.wildcardsMax;
        const lockedCount = (PU.state.previewMode.lockedValues[wcName] || []).length;

        // Compute composition counts for context
        const { total: currentTotal } = PU.buildComposition._getCompositionParams();
        // Estimate new total with expanded max
        const tempOverrides = { ...PU.state.previewMode.wildcardMaxOverrides, [wcName]: expandTo };
        const { wildcardCounts, extTextCount, extTextMax, wcMax } = PU.buildComposition._getCompositionParams();
        const newTotal = PU.preview.computeEffectiveTotal(extTextCount, wildcardCounts, extTextMax, wcMax, tempOverrides);

        const html = `
            <div class="pu-rp-expand-popover-header">
                <span class="pu-rp-expand-icon">&#128274;</span>
                Locked values span multiple buckets
            </div>
            <div class="pu-rp-expand-popover-detail">
                <b>${esc(wcName)}</b>: ${lockedCount} locked values need a window of ${expandTo} (currently ${currentMax})
            </div>
            <div class="pu-rp-expand-popover-impact">
                Compositions: ${currentTotal.toLocaleString()} &rarr; ${newTotal.toLocaleString()}
            </div>
            <div class="pu-rp-replace-popover-actions">
                <button class="pu-rp-replace-popover-btn cancel" data-testid="pu-rp-expand-cancel"
                        onclick="PU.rightPanel._cancelExpand('${esc(wcName)}', '${esc(clickedValue)}')">Cancel</button>
                <button class="pu-rp-replace-popover-btn apply" data-testid="pu-rp-expand-apply"
                        onclick="PU.rightPanel._applyExpand('${esc(wcName)}', ${expandTo})">Expand to ${expandTo}</button>
            </div>`;

        popover.innerHTML = html;

        // Position near the wildcard entry
        const stream = document.querySelector('[data-testid="pu-rp-wc-stream"]');
        const entry = document.querySelector(`[data-testid="pu-rp-wc-entry-${esc(wcName)}"]`);
        if (stream && entry) {
            const streamRect = stream.getBoundingClientRect();
            const entryRect = entry.getBoundingClientRect();
            popover.style.top = (entryRect.bottom - streamRect.top + stream.scrollTop + 4) + 'px';
            popover.style.left = '8px';
        }
        popover.style.display = 'block';
    },

    /**
     * Cancel expansion — remove the just-locked out-of-window value and hide popover.
     */
    async _cancelExpand(wcName, clickedValue) {
        // Remove the value that triggered the expand
        const locked = PU.state.previewMode.lockedValues;
        if (locked[wcName]) {
            const idx = locked[wcName].indexOf(clickedValue);
            if (idx >= 0) locked[wcName].splice(idx, 1);
            if (locked[wcName].length === 0) {
                delete locked[wcName];
                delete PU.state.previewMode.wildcardMaxOverrides[wcName];
            }
        }
        PU.rightPanel.hideReplacePopover();
        PU.rightPanel.render();
    },

    /**
     * Apply per-wildcard max expansion and navigate to a bucket containing all locked values.
     */
    async _applyExpand(wcName, expandTo) {
        PU.state.previewMode.wildcardMaxOverrides[wcName] = expandTo;

        // Navigate to the bucket containing the first locked value
        const locked = PU.state.previewMode.lockedValues[wcName] || [];
        if (locked.length > 0) {
            const fullLookup = PU.preview.getFullWildcardLookup();
            const allValues = fullLookup[wcName] || [];
            const firstLockedIdx = allValues.indexOf(locked[0]);
            if (firstLockedIdx >= 0) {
                const targetBucket = Math.floor(firstLockedIdx / expandTo);
                const newId = PU.rightPanel.findCompositionForBuckets({ [wcName]: targetBucket });
                if (newId !== null) {
                    PU.state.previewMode.compositionId = newId;
                    PU.preview.clearStaleBlockOverrides();
                }
            }
        }

        // Sync preview override to last locked value
        const sw = PU.state.previewMode.selectedWildcards;
        if (!sw['*']) sw['*'] = {};
        if (locked.length > 0) {
            sw['*'][wcName] = locked[locked.length - 1];
        }

        PU.rightPanel.hideReplacePopover();
        PU.actions.updateUrl();
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.rightPanel.render();
    },

    /**
     * Handle chip click: navigate to a composition that includes this value.
     * In-window chip: find composition in current bucket with that value active.
     * Out-of-window chip: jump to the bucket containing that value.
     */
    async navigateToValue(wcName, value, inWindow, idx) {
        const { wildcardCounts, extTextCount, extTextMax, wcMax, wcMaxMap, total } = PU.buildComposition._getCompositionParams();
        if (total <= 0) return;
        const effectiveMax = (wcMaxMap && wcMaxMap[wcName]) || wcMax;

        if (!inWindow && effectiveMax > 0) {
            // Out-of-window: jump to the bucket containing this value
            const targetBucketIdx = Math.floor(idx / effectiveMax);
            const newId = PU.rightPanel.findCompositionForBuckets({ [wcName]: targetBucketIdx });
            if (newId !== null) {
                PU.state.previewMode.compositionId = newId;
                PU.preview.clearStaleBlockOverrides();
                PU.actions.updateUrl();
                await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
                PU.rightPanel.render();
            }
        } else {
            // In-window (or no bucketing): find composition with this value active
            const newId = PU.rightPanel.findCompositionForValue(wcName, idx);
            if (newId !== null) {
                PU.state.previewMode.compositionId = newId;
                PU.preview.clearStaleBlockOverrides();
                PU.actions.updateUrl();
                await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
                PU.rightPanel.render();
            }
        }
    },

    /**
     * Find compositionId that produces a specific value index for one wildcard,
     * keeping all other wildcards at their current indices.
     * Uses reverse odometer to compute the target composition.
     * @param {string} wcName - Wildcard name to change
     * @param {number} targetIdx - Target value index
     * @returns {number|null} compositionId, or null if computation fails
     */
    findCompositionForValue(wcName, targetIdx) {
        const { wildcardCounts, extTextCount, extTextMax, wcMax, wcMaxMap, total } = PU.buildComposition._getCompositionParams();
        if (total <= 0) return null;

        const compositionId = PU.state.previewMode.compositionId;
        const sortedWc = Object.keys(wildcardCounts).sort();
        const effectiveMaxFn = (n) => (wcMaxMap && wcMaxMap[n]) || wcMax;
        const hasBucketing = wcMax > 0 || (wcMaxMap && Object.keys(wcMaxMap).length > 0);

        if (hasBucketing) {
            // Bucketed mode: navigate within current bucket
            const br = PU.preview.bucketCompositionToIndices(compositionId, extTextCount, extTextMax, wildcardCounts, wcMax, wcMaxMap);
            const currentIndices = br.wcValueIndices;

            // Build effective counts (capped by bucket window, per-wildcard max)
            const effectiveCounts = {};
            for (const n of sortedWc) {
                const em = effectiveMaxFn(n);
                const bucketIdx = br.wcBucketIndices[n] || 0;
                const bucketStart = bucketIdx * em;
                effectiveCounts[n] = em > 0 ? Math.min(em, wildcardCounts[n] - bucketStart) : wildcardCounts[n];
            }

            // Compute the target's offset within its bucket
            const wcPos = sortedWc.indexOf(wcName);
            if (wcPos < 0) return null;
            const em = effectiveMaxFn(wcName);
            const bucketIdx = br.wcBucketIndices[wcName] || 0;
            const bucketStart = bucketIdx * em;
            const offsetInBucket = targetIdx - bucketStart;
            if (offsetInBucket < 0 || offsetInBucket >= effectiveCounts[wcName]) return null;

            // Build dims for reverse odometer
            const extBucketCount = extTextMax > 0 ? Math.ceil(extTextCount / extTextMax) : 1;
            const dims = [extBucketCount];
            for (const n of sortedWc) {
                dims.push(effectiveCounts[n]);
            }

            // Current offsets within buckets
            const offsets = [br.extBucketIdx !== undefined ? (br.wcValueIndices._extTextOffset || 0) : 0];
            for (const n of sortedWc) {
                const bIdx = br.wcBucketIndices[n] || 0;
                const emN = effectiveMaxFn(n);
                const bStart = bIdx * emN;
                offsets.push((currentIndices[n] || 0) - bStart);
            }

            // Override the target
            offsets[wcPos + 1] = offsetInBucket;

            // Reconstruct bucket-local compositionId
            let localId = 0;
            let multiplier = 1;
            for (let i = dims.length - 1; i >= 0; i--) {
                localId += (offsets[i] % Math.max(1, dims[i])) * multiplier;
                multiplier *= Math.max(1, dims[i]);
            }

            // Reconstruct full compositionId from bucket indices + local offset
            // The bucket-composition system uses: bucketCompositionId * localProduct + localOffset
            const bucketDims = [extBucketCount, ...sortedWc.map(n => { const emN = effectiveMaxFn(n); return emN > 0 ? Math.ceil(wildcardCounts[n] / emN) : 1; })];
            let bucketCompId = 0;
            let bMult = 1;
            for (let i = bucketDims.length - 1; i >= 0; i--) {
                const bIdx = i === 0 ? br.extBucketIdx : (br.wcBucketIndices[sortedWc[i - 1]] || 0);
                bucketCompId += bIdx * bMult;
                bMult *= bucketDims[i];
            }
            const localProduct = dims.reduce((a, b) => a * Math.max(1, b), 1);
            return bucketCompId * localProduct + localId;
        } else {
            // Non-bucketed: simple reverse odometer
            const [extIdx, currentIndices] = PU.preview.compositionToIndices(compositionId, extTextCount, wildcardCounts);
            const dims = [Math.max(1, extTextCount)];
            const indices = [extIdx];
            for (const n of sortedWc) {
                dims.push(wildcardCounts[n]);
                indices.push(n === wcName ? targetIdx : (currentIndices[n] || 0));
            }

            let newId = 0;
            let multiplier = 1;
            for (let i = dims.length - 1; i >= 0; i--) {
                newId += (indices[i] % dims[i]) * multiplier;
                multiplier *= dims[i];
            }
            return newId;
        }
    },

    /**
     * Update the top bar with scope, variant selector, and wildcard count.
     */
    _updateTopBar(prompt, wcCount) {
        const topBar = document.querySelector('[data-testid="pu-rp-top-bar"]');
        if (!topBar) return;

        if (!prompt || wcCount === 0) {
            topBar.style.display = 'none';
            return;
        }

        topBar.style.display = '';

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

    /**
     * Compute compositionId that produces the given bucket indices for specified wildcards,
     * keeping all other bucket indices at their current values.
     * O(1) reverse odometer.
     * @param {Object} targetBuckets - { wcName: bucketIdx } overrides
     * @returns {number|null} compositionId, or null if computation fails
     */
    findCompositionForBuckets(targetBuckets) {
        const { wildcardCounts, extTextCount, extTextMax, wcMax, wcMaxMap } = PU.buildComposition._getCompositionParams();
        const effectiveMaxFn = (n) => (wcMaxMap && wcMaxMap[n]) || wcMax;
        if (wcMax <= 0 && (!wcMaxMap || Object.keys(wcMaxMap).length === 0)) return null;

        const compositionId = PU.state.previewMode.compositionId;
        const br = PU.preview.bucketCompositionToIndices(compositionId, extTextCount, extTextMax, wildcardCounts, wcMax, wcMaxMap);

        // Get current bucket indices, override targeted ones
        const sortedWc = Object.keys(wildcardCounts).sort();
        const extBucketCount = extTextMax > 0 ? Math.ceil(extTextCount / extTextMax) : 1;
        const bucketDims = [extBucketCount, ...sortedWc.map(n => { const em = effectiveMaxFn(n); return em > 0 ? Math.ceil(wildcardCounts[n] / em) : 1; })];
        const currentBuckets = [br.extBucketIdx, ...sortedWc.map(n => br.wcBucketIndices[n] || 0)];

        // Apply overrides
        for (const [wcName, bucketIdx] of Object.entries(targetBuckets)) {
            const wcPos = sortedWc.indexOf(wcName);
            if (wcPos >= 0) {
                currentBuckets[wcPos + 1] = bucketIdx;
            }
        }

        // Forward odometer: reconstruct compositionId from bucket indices
        let newId = 0;
        let multiplier = 1;
        for (let i = bucketDims.length - 1; i >= 0; i--) {
            newId += (currentBuckets[i] % bucketDims[i]) * multiplier;
            multiplier *= bucketDims[i];
        }

        return newId;
    },

    // ============================================
    // Replacement Popover (Phase 3)
    // ============================================

    /**
     * Show the replacement popover for a right-clicked chip.
     * If chip has a replacement (replaced-val), show edit mode with Remove link.
     * If chip has no replacement, show add mode.
     */
    showReplacePopover(chip, event) {
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
    // Extension Picker (preserved from inspector.js)
    // ============================================

    /**
     * Show extension picker popup
     */
    showExtensionPicker(onSelect) {
        PU.state.extPickerCallback = onSelect;
        const popup = document.querySelector('[data-testid="pu-ext-picker-popup"]');
        const tree = document.querySelector('[data-testid="pu-ext-picker-tree"]');
        const searchInput = document.querySelector('[data-testid="pu-ext-picker-search"]');

        if (searchInput) searchInput.value = '';

        tree.innerHTML = PU.rightPanel.renderExtTreeForPicker(
            PU.state.globalExtensions.tree, ''
        );
        popup.style.display = 'flex';
    },

    /**
     * Close extension picker popup
     */
    closeExtPicker() {
        const popup = document.querySelector('[data-testid="pu-ext-picker-popup"]');
        popup.style.display = 'none';
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
    }
};

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
