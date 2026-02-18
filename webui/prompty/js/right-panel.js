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

        let odometerIndices, bucketInfo = null;
        if (wcMax > 0) {
            const br = PU.preview.bucketCompositionToIndices(compositionId, extTextCount, extTextMax, wildcardCounts, wcMax);
            odometerIndices = br.wcValueIndices;
            bucketInfo = { wcMax, bucketResult: br, wildcardCounts };
        } else {
            [, odometerIndices] = PU.preview.compositionToIndices(compositionId, extTextCount, wildcardCounts);
        }

        // Collect block-level pins for asterisk indicator
        const blockPins = {};
        for (const [bPath, overrides] of Object.entries(PU.state.previewMode.selectedWildcards)) {
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
                html += PU.rightPanel._renderWcEntry(wc, fullLookup[wc.name], odometerIndices[wc.name] || 0, bucketInfo, blockPins);
            }
            html += '</div>';
        }

        // Local wildcards section
        if (localWildcards.length > 0) {
            html += PU.rightPanel._renderDivider('local');
            html += '<div class="pu-rp-wc-section">';
            for (const wc of localWildcards) {
                html += PU.rightPanel._renderWcEntry(wc, fullLookup[wc.name], odometerIndices[wc.name] || 0, bucketInfo, blockPins);
            }
            html += '</div>';
        }

        container.innerHTML = html;

        // Update top bar
        PU.rightPanel._updateTopBar(prompt, allNames.length);

        // Attach chip click handlers (navigate-to-value)
        container.querySelectorAll('.pu-rp-wc-v').forEach(chip => {
            chip.addEventListener('click', () => {
                const wcName = chip.dataset.wcName;
                const val = chip.dataset.value;
                const inWindow = chip.dataset.inWindow === 'true';
                const idx = parseInt(chip.dataset.idx, 10);
                if (wcName && val !== undefined) {
                    PU.rightPanel.navigateToValue(wcName, val, inWindow, idx);
                }
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
     * No filter/deselected logic — chips navigate on click.
     */
    _renderWcEntry(wc, values, activeIdx, bucketInfo, blockPins) {
        const esc = PU.blocks.escapeHtml;
        const name = wc.name;
        const safeName = esc(name);
        const isShared = wc.source === 'theme' || wc.source === 'ext';

        // Block-pin asterisk indicator
        const hasBlockPin = blockPins && blockPins[name];
        const pinIndicator = hasBlockPin ? '<span class="pin-indicator" title="Pinned via block dropdown">*</span>' : '';

        // wc-path for shared wildcards (shows source like "professional/tones")
        let pathHtml = '';
        if (isShared && wc.path) {
            pathHtml = `<span class="pu-rp-wc-path">${esc(wc.path)}</span>`;
        }

        const wrappedIdx = values.length > 0 ? activeIdx % values.length : 0;

        let chipsHtml;
        if (bucketInfo && values.length > bucketInfo.wcMax) {
            // Bucket mode: split chips into in-window and out-of-window
            const wcMax = bucketInfo.wcMax;
            const bucketIdx = bucketInfo.bucketResult.wcBucketIndices[name] || 0;
            const bucketStart = bucketIdx * wcMax;
            const bucketEnd = Math.min(bucketStart + wcMax, values.length);

            // In-window chips (inside frame)
            let inWindowChips = '';
            for (let i = bucketStart; i < bucketEnd; i++) {
                const v = values[i];
                let cls = 'pu-rp-wc-v';
                if (i === wrappedIdx) cls += ' active';
                inWindowChips += `<span class="${cls}" data-testid="pu-rp-wc-chip-${safeName}-${i}" data-wc-name="${safeName}" data-value="${esc(v)}" data-in-window="true" data-idx="${i}">${esc(v)}</span>`;
            }

            const frameHtml = `<div class="pu-rp-wc-window-frame">${inWindowChips}</div>`;

            // Out-of-window chips
            let outWindowChips = '';
            for (let i = 0; i < values.length; i++) {
                if (i >= bucketStart && i < bucketEnd) continue;
                const v = values[i];
                outWindowChips += `<span class="pu-rp-wc-v out-window" data-testid="pu-rp-wc-chip-${safeName}-${i}" data-wc-name="${safeName}" data-value="${esc(v)}" data-in-window="false" data-idx="${i}">${esc(v)}</span>`;
            }

            chipsHtml = frameHtml + outWindowChips;
        } else {
            // No bucketing: render all chips inline
            chipsHtml = values.map((v, i) => {
                let cls = 'pu-rp-wc-v';
                if (i === wrappedIdx) cls += ' active';
                return `<span class="${cls}" data-testid="pu-rp-wc-chip-${safeName}-${i}" data-wc-name="${safeName}" data-value="${esc(v)}" data-in-window="true" data-idx="${i}">${esc(v)}</span>`;
            }).join('');
        }

        return `<div class="pu-rp-wc-entry" data-testid="pu-rp-wc-entry-${safeName}">
            <div class="pu-rp-wc-entry-header">
                <span class="pu-rp-wc-name">${safeName}${pinIndicator}</span>
                ${pathHtml}
            </div>
            <div class="pu-rp-wc-values">${chipsHtml}</div>
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

        const { wcNames, wildcardCounts, extTextCount, extTextMax, wcMax, total } = PU.buildComposition._getCompositionParams();
        const compId = PU.state.previewMode.compositionId;
        const effectiveId = total > 0 ? compId % total : 0;

        // Bucket window hint
        let windowHint = '';
        if (wcMax > 0) {
            const sortedWc = Object.keys(wildcardCounts).sort();
            const extBucketCount = extTextMax > 0 ? Math.ceil(extTextCount / extTextMax) : 1;
            const bucketDims = [extBucketCount, ...sortedWc.map(n => Math.ceil(wildcardCounts[n] / wcMax))];
            const totalBuckets = bucketDims.reduce((a, b) => a * b, 1);
            // Compute current bucket index
            const br = PU.preview.bucketCompositionToIndices(compId, extTextCount, extTextMax, wildcardCounts, wcMax);
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
                const abbr = n.length > 4 ? n.slice(0, 3) : n;
                if (wcMax > 0 && count > wcMax) {
                    const buckets = Math.ceil(count / wcMax);
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
        if (wcMax > 0) {
            const sortedWc = Object.keys(wildcardCounts).sort();
            const extBucketCount = extTextMax > 0 ? Math.ceil(extTextCount / extTextMax) : 1;
            const bucketDims = [extBucketCount, ...sortedWc.map(n => Math.ceil(wildcardCounts[n] / wcMax))];
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
                <button class="pu-rp-ops-export-btn" data-testid="pu-rp-export-btn" onclick="PU.buildComposition.exportTxt()">Export .txt</button>
            </div>
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
            exportBtn.textContent = `Export .txt (~${sizeStr})`;
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
     * Handle chip click: navigate to a composition that includes this value.
     * In-window chip: find composition in current bucket with that value active.
     * Out-of-window chip: jump to the bucket containing that value.
     */
    async navigateToValue(wcName, value, inWindow, idx) {
        const { wildcardCounts, extTextCount, extTextMax, wcMax, total } = PU.buildComposition._getCompositionParams();
        if (total <= 0) return;

        if (!inWindow && wcMax > 0) {
            // Out-of-window: jump to the bucket containing this value
            const targetBucketIdx = Math.floor(idx / wcMax);
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
        const { wildcardCounts, extTextCount, extTextMax, wcMax, total } = PU.buildComposition._getCompositionParams();
        if (total <= 0) return null;

        const compositionId = PU.state.previewMode.compositionId;
        const sortedWc = Object.keys(wildcardCounts).sort();

        if (wcMax > 0) {
            // Bucketed mode: navigate within current bucket
            const br = PU.preview.bucketCompositionToIndices(compositionId, extTextCount, extTextMax, wildcardCounts, wcMax);
            const currentIndices = br.wcValueIndices;

            // Build effective counts (capped by bucket window)
            const effectiveCounts = {};
            for (const n of sortedWc) {
                const bucketIdx = br.wcBucketIndices[n] || 0;
                const bucketStart = bucketIdx * wcMax;
                effectiveCounts[n] = Math.min(wcMax, wildcardCounts[n] - bucketStart);
            }

            // Compute the target's offset within its bucket
            const wcPos = sortedWc.indexOf(wcName);
            if (wcPos < 0) return null;
            const bucketIdx = br.wcBucketIndices[wcName] || 0;
            const bucketStart = bucketIdx * wcMax;
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
                const bStart = bIdx * wcMax;
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
            const bucketDims = [extBucketCount, ...sortedWc.map(n => Math.ceil(wildcardCounts[n] / wcMax))];
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

        // Variant selector (operations not yet implemented — show "None")
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
        const { wildcardCounts, extTextCount, extTextMax, wcMax } = PU.buildComposition._getCompositionParams();
        if (wcMax <= 0) return null;

        const compositionId = PU.state.previewMode.compositionId;
        const br = PU.preview.bucketCompositionToIndices(compositionId, extTextCount, extTextMax, wildcardCounts, wcMax);

        // Get current bucket indices, override targeted ones
        const sortedWc = Object.keys(wildcardCounts).sort();
        const extBucketCount = extTextMax > 0 ? Math.ceil(extTextCount / extTextMax) : 1;
        const bucketDims = [extBucketCount, ...sortedWc.map(n => wcMax > 0 ? Math.ceil(wildcardCounts[n] / wcMax) : 1)];
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
