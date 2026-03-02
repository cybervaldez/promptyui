/**
 * PromptyUI - Editor Mode Strip
 *
 * Progressive disclosure: Write / Preview / Review modes.
 * Write & Review toggle CSS visibility on the block editor.
 * Preview swaps to a resolved document view.
 * Gear popover exposes granular layer checkboxes.
 */

PU.editorMode = {
    // Preset → layer configuration
    PRESETS: {
        write:   { annotations: false, compositions: false, artifacts: false },
        preview: { annotations: false, compositions: true,  artifacts: false },
        review:  { annotations: true,  compositions: true,  artifacts: true  }
    },

    /** Apply a named preset (write | preview | review). */
    setPreset(mode) {
        const layers = PU.editorMode.PRESETS[mode];
        if (!layers) return;

        PU.state.ui.editorMode = mode;
        PU.state.ui.editorLayers = { ...layers };
        PU.editorMode._applyMode();
        PU.editorMode._updateStripButtons();
        PU.editorMode._syncGearCheckboxes();
        PU.helpers.saveUIState();
        PU.actions.updateUrl();
    },

    /** Toggle a single layer (from gear popover checkbox). */
    setLayer(layer, enabled) {
        if (!(layer in PU.state.ui.editorLayers)) return;

        PU.state.ui.editorLayers[layer] = enabled;

        // Check if current layers still match a preset
        const match = Object.entries(PU.editorMode.PRESETS).find(([, preset]) =>
            Object.keys(preset).every(k => preset[k] === PU.state.ui.editorLayers[k])
        );
        PU.state.ui.editorMode = match ? match[0] : 'custom';

        PU.editorMode._applyMode();
        PU.editorMode._updateStripButtons();
        PU.helpers.saveUIState();
    },

    /** Apply current mode to the DOM. */
    _applyMode() {
        const mode = PU.state.ui.editorMode;
        const layers = PU.state.ui.editorLayers;

        // Set data attribute on body for CSS-driven visibility
        document.body.dataset.editorMode = mode;

        // Set per-layer data attributes for granular CSS (custom mode)
        document.body.dataset.layerAnnotations = layers.annotations ? '1' : '0';
        document.body.dataset.layerCompositions = layers.compositions ? '1' : '0';
        document.body.dataset.layerArtifacts = layers.artifacts ? '1' : '0';

        // Toggle main content: preview vs block editor
        const blocksContainer = document.querySelector('[data-testid="pu-blocks-container"]');
        const previewContainer = document.querySelector('[data-testid="pu-preview-container"]');
        const addBlockArea = document.querySelector('.pu-add-block-area');

        if (mode === 'preview') {
            if (blocksContainer) blocksContainer.style.display = 'none';
            if (addBlockArea) addBlockArea.style.display = 'none';
            if (previewContainer) previewContainer.style.display = '';
            PU.editorMode.renderPreview();
        } else {
            if (blocksContainer) blocksContainer.style.display = '';
            if (addBlockArea) addBlockArea.style.display = '';
            if (previewContainer) previewContainer.style.display = 'none';
        }

        // Toggle sidebar content: editor vs preview
        const rpEditorContent = document.querySelector('[data-testid="pu-rp-editor-content"]');
        const rpPreviewContent = document.querySelector('[data-testid="pu-rp-preview-content"]');

        if (mode === 'preview') {
            if (rpEditorContent) rpEditorContent.style.display = 'none';
            if (rpPreviewContent) rpPreviewContent.style.display = '';
            PU.editorMode.renderSidebarPreview();
            PU.rightPanel.renderOpsSection();
        } else {
            if (rpEditorContent) rpEditorContent.style.display = '';
            if (rpPreviewContent) rpPreviewContent.style.display = 'none';

            // In Write mode, force wildcards tab if annotations tab was active
            if (mode === 'write' && PU.state.ui.rightPanelTab === 'annotations') {
                PU.rightPanel.switchTab('wildcards');
            }

            // Re-render write sidebar + block editor to sync lock state from preview mode
            PU.rightPanel.render();
            PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        }

        // Update sidebar toggle button label for the new mode
        PU.rightPanel._updateToggleButton(PU.state.ui.rightPanelCollapsed);
    },

    /** Highlight the active preset button in the mode strip. */
    _updateStripButtons() {
        const mode = PU.state.ui.editorMode;
        document.querySelectorAll('.pu-mode-btn').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.mode === mode);
        });
    },

    // ── Preview Mode ──────────────────────────────────────────────────────

    /** Render the template view for the current prompt. */
    async renderPreview() {
        const body = document.querySelector('[data-testid="pu-preview-body"]');
        if (!body) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text) || prompt.text.length === 0) {
            body.innerHTML = '<div class="pu-rp-note">No content blocks</div>';
            PU.editorMode._renderDepthStepper(1);
            PU.editorMode._renderLockStrip();
            return;
        }

        const textItems = prompt.text;
        const resolutions = await PU.preview.buildBlockResolutions(textItems, { skipOdometerUpdate: true });

        // Compute max tree depth
        const maxDepth = PU.editorMode._computeMaxDepth(textItems);
        PU.state.previewMode.maxTreeDepth = maxDepth;
        const effectiveDepth = PU.state.previewMode.previewDepth || maxDepth;

        // Get composition params for variations
        const { lookup } = PU.shared.getCompositionParams();
        const locked = PU.state.previewMode.lockedValues;

        // Render block-by-block (template view) + collect variation data
        const { blocks, variationData } = PU.editorMode._renderBlockByBlock(textItems, resolutions, effectiveDepth, lookup, locked);
        PU.state.previewMode.resolvedVariations = variationData;

        // Render depth stepper
        PU.editorMode._renderDepthStepper(maxDepth);

        // Render lock summary strip
        PU.editorMode._renderLockStrip();

        // Render blocks
        if (blocks.length === 0) {
            body.innerHTML = '<div class="pu-rp-note">No content blocks</div>';
            return;
        }

        // Render focus banner if bulbs are active
        const focused = PU.state.previewMode.focusedWildcards;
        const totalBlockCount = blocks.length;
        const matchCount = blocks.filter(b => b.focusState === 'match' || b.focusState === 'parent').length;
        let bannerHtml = '';
        if (focused.length > 0) {
            const esc = PU.blocks.escapeHtml;
            const namesHtml = focused.map(n => `<b>__${esc(n)}__</b>`).join(', ');
            bannerHtml = `<div class="pu-focus-banner pu-preview-focus-banner" data-testid="pu-preview-focus-banner" style="display: flex;">
                <span class="pu-focus-banner-text">&#128161; ${namesHtml} &middot; ${matchCount}/${totalBlockCount} blocks</span>
                <button class="pu-focus-banner-close" data-testid="pu-preview-focus-banner-close" title="Clear focus" onclick="PU.editorMode.clearPreviewFocus()">&times;</button>
            </div>`;
        }

        body.innerHTML = bannerHtml + blocks.map((b, i) => {
            const focusCls = b.focusState === 'dimmed' ? ' pu-preview-focus-dimmed' : (b.focusState === 'match' ? ' pu-preview-focus-match' : '');
            return `<div class="pu-preview-block${focusCls}" data-path="${PU.blocks.escapeHtml(b.path)}" data-testid="pu-preview-block-${i}" data-focus="${b.focusState || ''}">
                <div class="pu-preview-text">${b.html}</div>
            </div>`;
        }).join('');

        // Attach segment-level hover listeners for shortlist linking
        PU.editorMode._attachPreviewHoverListeners(body);

        // Auto-populate shortlist from state, render panel
        PU.shortlist.populateFromPreview();
        PU.shortlist.render();
    },

    /** Attach block-level hover on preview rows to highlight the block + matching shortlist items. */
    _attachPreviewHoverListeners(container) {
        if (PU.state.ui.editorMode === 'preview' || PU.state.ui.editorMode === 'review') {
            const allBlocks = container.querySelectorAll('.pu-preview-block[data-path]');
            allBlocks.forEach(block => {
                block.addEventListener('mouseenter', () => {
                    const path = block.dataset.path;
                    if (!path) return;
                    block.classList.add('pu-preview-block-hover');
                    PU.shortlist._highlightItemsBySegmentPath(path);
                });
                block.addEventListener('mouseleave', () => {
                    block.classList.remove('pu-preview-block-hover');
                    PU.shortlist._clearShortlistHighlights();
                });
            });
        }
    },

    /** Clear all wildcard focus in Preview mode. */
    clearPreviewFocus() {
        PU.state.previewMode.focusedWildcards = [];
        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
    },

    /**
     * Walk the block tree depth-first, render flat rows with ancestor segments.
     * Returns {blocks: [{path, depth, html}], variationData: [{blockPath, comboKey, text}]}.
     * Each row prepends faded ancestor text with ── separators, highlighting only the own block.
     */
    _renderBlockByBlock(textItems, resolutions, maxDepth, lookup, locked) {
        const results = [];
        const variationData = [];
        const hiddenBlocks = PU.state.previewMode.hiddenBlocks;
        const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        const compId = PU.state.previewMode.compositionId;
        const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);
        const varMode = PU.state.previewMode.variationMode || 'summary';

        const isPreviewMode = PU.state.ui.editorMode === 'preview' || PU.state.ui.editorMode === 'review';
        const esc = PU.blocks.escapeHtml;

        // Store each block's own template HTML for ancestor chain lookups
        const pathToTemplateHtml = {};

        // Compute focus filter (empty = no filtering)
        const focused = PU.state.previewMode.focusedWildcards;
        let focusMatchPaths = null;
        let focusParentPaths = null;
        if (focused.length > 0) {
            const wcBlockMap = PU.editorMode._buildPreviewWcBlockMap(textItems);
            focusMatchPaths = new Set();
            for (const wc of focused) {
                const paths = wcBlockMap[wc] || new Set();
                for (const p of paths) focusMatchPaths.add(p);
            }
            focusParentPaths = new Set();
            for (const path of focusMatchPaths) {
                const parts = path.split('.');
                for (let i = 1; i < parts.length; i++) {
                    focusParentPaths.add(parts.slice(0, i).join('.'));
                }
            }
            for (const path of focusMatchPaths) focusParentPaths.delete(path);
        }

        /** Build faded ancestor segments HTML for a given path. */
        function buildAncestorSegments(path) {
            const parts = path.split('.');
            let html = '';
            for (let i = 1; i < parts.length; i++) {
                const aPath = parts.slice(0, i).join('.');
                const aHtml = pathToTemplateHtml[aPath];
                if (aHtml) {
                    html += `<span class="pu-preview-segment pu-preview-segment-ancestor" data-segment-path="${esc(aPath)}">${aHtml}</span>`;
                    html += `<span class="pu-preview-separator"> \u2500\u2500 </span>`;
                }
            }
            return html;
        }

        function traverse(blocks, prefix, depth, hasTrailingMore) {
            if (!Array.isArray(blocks)) return;
            blocks.forEach((block, idx) => {
                const path = prefix ? `${prefix}.${idx}` : String(idx);
                if (hiddenBlocks.has(path)) return;
                if (depth > maxDepth) return;

                const res = resolutions.get(path);
                if (!res) return;

                const isExtText = 'ext_text' in block;
                const rawContent = block.content || '';
                const hasChildren = block.after && block.after.length > 0;

                // Find wildcards in this block
                const blockWcNames = [];
                if (!isExtText && rawContent) {
                    const wcPattern = /__([a-zA-Z0-9_-]+)__/g;
                    let m;
                    const seen = new Set();
                    while ((m = wcPattern.exec(rawContent)) !== null) {
                        if (!seen.has(m[1]) && lookup[m[1]]) {
                            seen.add(m[1]);
                            blockWcNames.push(m[1]);
                        }
                    }
                }

                let ownHtml;

                if (isExtText) {
                    const rawTemplate = (res.resolvedMarkerText || '').replace(/\{\{([^:]+):([^}]+)\}\}/g, '__$1__');
                    const hasExtWc = /__[a-zA-Z0-9_-]+__/.test(rawTemplate);
                    const labelHtml = `<span class="pu-ext-text-label">${esc(block.ext_text)}</span>`;
                    const templateHtml = hasExtWc ? ' ' + PU.editorMode._convertToTemplateView(rawTemplate) : '';
                    ownHtml = labelHtml + templateHtml;
                    if (isPreviewMode) {
                        const plainText = (res.resolvedMarkerText || '').replace(/\{\{([^:]+):([^}]+)\}\}/g, '$2');
                        variationData.push({ blockPath: path, comboKey: '', text: plainText });
                    }
                } else if (blockWcNames.length > 0) {
                    ownHtml = PU.editorMode._convertToTemplateView(rawContent);
                    if (isPreviewMode) {
                        const blockVars = PU.editorMode._computeBlockVariations(rawContent, blockWcNames, lookup, locked, wcIndices, varMode, path);
                        for (const v of blockVars) variationData.push(v);
                    }
                } else {
                    ownHtml = esc(rawContent);
                    if (isPreviewMode) {
                        variationData.push({ blockPath: path, comboKey: '', text: rawContent });
                    }
                }

                // Store own template HTML for ancestor lookups by child blocks
                pathToTemplateHtml[path] = ownHtml;

                // Build segmented row: faded ancestor segments + separators + own segment
                const ancestorHtml = buildAncestorSegments(path);
                const segmentedHtml = ancestorHtml
                    + `<span class="pu-preview-segment pu-preview-segment-own" data-segment-path="${esc(path)}">${ownHtml}</span>`;

                // Determine focus state
                let focusState = null;
                if (focusMatchPaths) {
                    if (focusMatchPaths.has(path)) focusState = 'match';
                    else if (focusParentPaths.has(path)) focusState = 'parent';
                    else focusState = 'dimmed';
                }

                results.push({ path, depth, html: segmentedHtml, focusState, hasChildren });

                // Traverse children
                if (hasChildren) {
                    const maxBranches = 3;
                    if (block.after.length > maxBranches) {
                        traverse(block.after.slice(0, maxBranches), path, depth + 1, true);
                        if (depth + 1 <= maxDepth) {
                            const moreCount = block.after.length - maxBranches;
                            // "More" row: ancestor chain includes current path
                            const moreAncestorHtml = buildAncestorSegments(path)
                                + `<span class="pu-preview-segment pu-preview-segment-ancestor" data-segment-path="${esc(path)}">${ownHtml}</span>`
                                + `<span class="pu-preview-separator"> \u2500\u2500 </span>`;
                            results.push({
                                path: `${path}._more`, depth: depth + 1,
                                html: moreAncestorHtml + `<span class="pu-preview-variant-label">+${moreCount} more branch${moreCount > 1 ? 'es' : ''}</span>`
                            });
                        }
                    } else {
                        traverse(block.after, path, depth + 1, false);
                    }
                }
            });
        }

        traverse(textItems, '', 1, false);
        return { blocks: results, variationData };
    },

    /** Compute deepest level in the block tree (1-based). */
    _computeMaxDepth(textItems) {
        let max = 0;
        function walk(blocks, depth) {
            if (!Array.isArray(blocks)) return;
            blocks.forEach(block => {
                if (depth > max) max = depth;
                if (block.after && block.after.length > 0) {
                    walk(block.after, depth + 1);
                }
            });
        }
        walk(textItems, 1);
        return max || 1;
    },

    /** Convert {{name:value}} markers to <mark> highlight tags. */
    _convertMarkersToHighlights(markerText) {
        if (!markerText) return '';
        const safe = PU.preview.escapeHtmlPreservingMarkers(markerText);
        return safe.replace(/\{\{([^:]+):([^}]+)\}\}/g, (_, name, value) => {
            const eName = PU.blocks.escapeHtml(name);
            const eValue = PU.blocks.escapeHtml(value);
            return `<mark class="pu-wc-sub" data-wc="${eName}" title="__${eName}__ = ${eValue}">${eValue}</mark>`;
        });
    },

    // ── Template View Helpers ────────────────────────────────────────────

    /** Convert block content to template view with clickable wildcard name slots. */
    _convertToTemplateView(content) {
        if (!content) return '';
        const parts = [];
        let lastIndex = 0;
        const pattern = /__([a-zA-Z0-9_-]+)__/g;
        let m;
        while ((m = pattern.exec(content)) !== null) {
            if (m.index > lastIndex) {
                parts.push(PU.blocks.escapeHtml(content.substring(lastIndex, m.index)));
            }
            const eName = PU.blocks.escapeHtml(m[1]);
            parts.push(`<span class="pu-wc-slot" data-wc="${eName}" data-testid="pu-wc-slot-${eName}" onclick="PU.editorMode.openLockPopup('${eName}', this)">${eName}</span>`);
            lastIndex = pattern.lastIndex;
        }
        if (lastIndex < content.length) {
            parts.push(PU.blocks.escapeHtml(content.substring(lastIndex)));
        }
        return parts.join('');
    },

    /**
     * Compute resolved text variations for a block with wildcards.
     * Returns array of {blockPath, comboKey, text} for shortlist population.
     * Summary mode: deduplicated, capped at 20. Expanded: capped at 100.
     */
    _computeBlockVariations(content, blockWcNames, lookup, locked, wcIndices, mode, blockPath) {
        if (!blockWcNames || blockWcNames.length === 0 || !content) return [];

        // Build dimensions — locked wildcards vary, unlocked pinned to current value
        const dims = [];
        for (const name of blockWcNames) {
            const lockedVals = (locked[name] && locked[name].length > 0) ? locked[name] : null;
            const allVals = lookup[name] || [];
            if (lockedVals) {
                dims.push({ name, values: lockedVals });
            } else {
                // Unlocked: pin to current composition value
                const idx = wcIndices[name] || 0;
                dims.push({ name, values: [allVals[idx % allVals.length] || '?'] });
            }
        }

        // Total combos (capped computation)
        let totalCombos = 1;
        for (const dim of dims) {
            totalCombos *= dim.values.length;
            if (totalCombos > 10000) { totalCombos = 10001; break; }
        }

        const isSummary = mode !== 'expanded';
        const MAX_SHOW = isSummary ? 20 : 100;
        const sampleCount = isSummary ? Math.min(totalCombos, MAX_SHOW * 3) : Math.min(totalCombos, MAX_SHOW);
        const combos = PU.editorMode._cartesianProduct(dims, sampleCount);

        const results = [];
        const seen = isSummary ? new Set() : null;
        for (const combo of combos) {
            if (results.length >= MAX_SHOW) break;

            // Compute plain resolved text
            let plain = content;
            for (const { name, value } of combo) {
                plain = plain.split(`__${name}__`).join(value);
            }
            // Resolve remaining wildcards with odometer values
            plain = plain.replace(/__([a-zA-Z0-9_-]+)__/g, (match, wcName) => {
                const allVals = lookup[wcName] || [];
                if (allVals.length === 0) return match;
                const idx = wcIndices[wcName] || 0;
                return allVals[idx % allVals.length];
            });

            if (isSummary) {
                if (seen.has(plain)) continue;
                seen.add(plain);
            }

            results.push({
                blockPath,
                comboKey: PU.shortlist.comboToKey(combo),
                text: plain
            });
        }

        return results;
    },

    /** Compute Cartesian product of dimensions (capped at maxCount).
     *  Cap is checked only after the last dimension so every combo is complete. */
    _cartesianProduct(dims, maxCount) {
        if (dims.length === 0) return [];
        maxCount = maxCount || 1000;
        let result = [[]];
        for (let d = 0; d < dims.length; d++) {
            const dim = dims[d];
            const isLast = d === dims.length - 1;
            const next = [];
            for (const combo of result) {
                for (const value of dim.values) {
                    next.push([...combo, { name: dim.name, value }]);
                    if (isLast && next.length >= maxCount) return next;
                }
            }
            result = next;
        }
        return result;
    },

    /** Set variation mode (summary | expanded) and re-render. */
    setVariationMode(mode) {
        PU.state.previewMode.variationMode = mode;
        PU.editorMode.renderPreview();
    },

    // ── Lock Popup ──────────────────────────────────────────────────────

    _lockPopupState: null, // { wcName, initialChecked: Set, anchor: Element }

    /** Open the lock popup for a wildcard. */
    openLockPopup(wcName, anchorEl) {
        PU.overlay.dismissPopovers();

        const lookup = PU.preview.getFullWildcardLookup();
        const allVals = lookup[wcName];
        if (!allVals || allVals.length === 0) return;

        const locked = PU.state.previewMode.lockedValues;
        const lockedVals = (locked[wcName] && locked[wcName].length > 0) ? locked[wcName] : null;

        // Determine current value for this wildcard
        const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        const compId = PU.state.previewMode.compositionId;
        const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);
        const currentIdx = wcIndices[wcName] || 0;
        const currentVal = allVals[currentIdx];

        // Initial checked set: locked values if any, otherwise just current value
        const initialChecked = new Set(lockedVals ? lockedVals : [currentVal]);

        PU.editorMode._lockPopupState = {
            wcName,
            initialChecked: new Set(initialChecked),
            currentChecked: new Set(initialChecked),
            currentVal,
            anchor: anchorEl
        };

        PU.editorMode._renderLockPopupContent(wcName, allVals, currentVal);

        const popup = document.querySelector('[data-testid="pu-lock-popup"]');
        if (!popup) return;

        // Position below the triggering element, accounting for container scroll
        const rect = anchorEl.getBoundingClientRect();
        const container = popup.parentElement;
        const containerRect = container.getBoundingClientRect();
        popup.style.left = Math.max(0, rect.left - containerRect.left + container.scrollLeft) + 'px';
        popup.style.top = (rect.bottom - containerRect.top + container.scrollTop + 4) + 'px';
        popup.style.display = '';

        PU.overlay.showOverlay();
    },

    /** Render lock popup inner content. */
    _renderLockPopupContent(wcName, allVals, currentVal) {
        const popup = document.querySelector('[data-testid="pu-lock-popup"]');
        if (!popup || !PU.editorMode._lockPopupState) return;

        const state = PU.editorMode._lockPopupState;
        const checked = state.currentChecked;

        // Compute impact
        const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        const locked = PU.state.previewMode.lockedValues;
        const hypothetical = { ...locked };
        // If all are checked, that's effectively "no lock"
        if (checked.size === allVals.length) {
            delete hypothetical[wcName];
        } else {
            hypothetical[wcName] = [...checked];
        }
        const impact = PU.shared.computeLockedTotal(wildcardCounts, extTextCount, hypothetical);

        let html = `<div class="pu-lock-popup-header">
            <span class="pu-lock-popup-title" data-testid="pu-lock-popup-title">__${PU.blocks.escapeHtml(wcName)}__</span>
            <div class="pu-lock-popup-toggle">
                <a data-testid="pu-lock-popup-all" onclick="PU.editorMode._lockPopupSelectAll()">All</a>
                <a data-testid="pu-lock-popup-only" onclick="PU.editorMode._lockPopupSelectOnly()">Only</a>
            </div>
        </div>
        <div class="pu-lock-popup-body" data-testid="pu-lock-popup-body">`;

        for (let i = 0; i < allVals.length; i++) {
            const val = allVals[i];
            const isChecked = checked.has(val) ? 'checked' : '';
            const isCurrent = val === currentVal;
            const currentClass = isCurrent ? ' is-current' : '';
            const dot = isCurrent ? '<span class="pu-lock-current-dot">\u25CF</span>' : '';
            const eVal = PU.blocks.escapeHtml(val);
            html += `<div class="pu-lock-popup-item${currentClass}">
                <input type="checkbox" ${isChecked} data-val="${eVal}"
                       onchange="PU.editorMode._lockPopupToggle('${eVal.replace(/'/g, "\\'")}', this.checked)">
                <label onclick="this.previousElementSibling.click()" title="${eVal}">${eVal}</label>
                ${dot}
            </div>`;
        }

        html += `</div>
        <div class="pu-lock-popup-footer" data-testid="pu-lock-popup-footer">
            ${checked.size} of ${allVals.length} \u2192 ${impact.toLocaleString()} comps
        </div>`;

        popup.innerHTML = html;
    },

    /** Toggle a value in the lock popup. */
    _lockPopupToggle(val, isChecked) {
        const state = PU.editorMode._lockPopupState;
        if (!state) return;
        if (isChecked) {
            state.currentChecked.add(val);
        } else {
            state.currentChecked.delete(val);
        }
        PU.editorMode._lockPopupUpdate();
    },

    /** Select all values in lock popup. */
    _lockPopupSelectAll() {
        const state = PU.editorMode._lockPopupState;
        if (!state) return;
        const lookup = PU.preview.getFullWildcardLookup();
        state.currentChecked = new Set(lookup[state.wcName] || []);
        PU.editorMode._lockPopupUpdate();
    },

    /** Select only the current value in lock popup. */
    _lockPopupSelectOnly() {
        const state = PU.editorMode._lockPopupState;
        if (!state) return;
        state.currentChecked = new Set([state.currentVal]);
        PU.editorMode._lockPopupUpdate();
    },

    /** Re-render popup content and live-apply lock changes (debounced). */
    _lockPopupUpdate() {
        const state = PU.editorMode._lockPopupState;
        if (!state) return;
        const lookup = PU.preview.getFullWildcardLookup();
        const allVals = lookup[state.wcName] || [];
        PU.editorMode._renderLockPopupContent(state.wcName, allVals, state.currentVal);
        // Live-apply with debounce
        clearTimeout(PU.editorMode._lockPopupDebounce);
        PU.editorMode._lockPopupDebounce = setTimeout(() => {
            PU.editorMode._applyLockPopupState();
        }, 150);
    },
    _lockPopupDebounce: null,

    /** Apply current lock popup state to lockedValues and re-render preview. */
    _applyLockPopupState() {
        const state = PU.editorMode._lockPopupState;
        if (!state) return;
        const lookup = PU.preview.getFullWildcardLookup();
        const allVals = lookup[state.wcName] || [];
        const current = state.currentChecked;
        const locked = PU.state.previewMode.lockedValues;

        if (current.size === 0 || current.size === allVals.length) {
            delete locked[state.wcName];
        } else {
            locked[state.wcName] = [...current];
        }

        // Sync to selectedWildcards for preview
        const sw = PU.state.previewMode.selectedWildcards;
        if (!sw['*']) sw['*'] = {};
        if (locked[state.wcName] && locked[state.wcName].length > 0) {
            sw['*'][state.wcName] = locked[state.wcName][locked[state.wcName].length - 1];
        } else {
            delete sw['*'][state.wcName];
        }

        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
        PU.rightPanel.renderOpsSection();
    },

    /** Close the lock popup. Changes already live-applied. */
    closeLockPopup() {
        const popup = document.querySelector('[data-testid="pu-lock-popup"]');
        if (popup) popup.style.display = 'none';
        clearTimeout(PU.editorMode._lockPopupDebounce);
        // Flush any pending debounced apply
        if (PU.editorMode._lockPopupState) {
            PU.editorMode._applyLockPopupState();
        }
        PU.editorMode._lockPopupState = null;
    },

    // ── Lock Summary Strip ──────────────────────────────────────────────

    /** Render the lock summary strip showing all active locks. */
    _renderLockStrip() {
        const strip = document.querySelector('[data-testid="pu-lock-strip"]');
        if (!strip) return;

        const locked = PU.state.previewMode.lockedValues;
        const entries = Object.entries(locked).filter(([, vals]) => vals && vals.length > 0);

        if (entries.length === 0) {
            strip.style.display = 'none';
            return;
        }

        let html = '<span class="pu-lock-strip-icon">\u{1F512}</span>';
        for (const [name, vals] of entries) {
            const eName = PU.blocks.escapeHtml(name);
            const eVals = vals.map(v => PU.blocks.escapeHtml(v)).join(', ');
            html += `<span class="pu-lock-strip-chip" data-testid="pu-lock-chip-${eName}"
                           onclick="PU.editorMode.openLockPopupByName('${eName}')">
                <span class="pu-lock-strip-chip-name">${eName}:</span>
                <span>${eVals}</span>
                <span class="pu-lock-strip-chip-close" onclick="event.stopPropagation(); PU.editorMode.clearLock('${eName}')">&times;</span>
            </span>`;
        }
        html += '<a class="pu-lock-strip-clear" data-testid="pu-lock-strip-clear" onclick="PU.editorMode.clearAllLocks()">Clear All</a>';

        strip.innerHTML = html;
        strip.style.display = '';

        // Attach hover-to-highlight on lock strip chips
        strip.querySelectorAll('.pu-lock-strip-chip').forEach(chip => {
            const wcName = chip.querySelector('.pu-lock-strip-chip-name')?.textContent?.replace(':', '').trim();
            if (!wcName) return;
            chip.addEventListener('mouseenter', () => {
                PU.editorMode._highlightPreviewBlocksForWildcard(wcName);
            });
            chip.addEventListener('mouseleave', () => {
                PU.editorMode._clearPreviewBlockHighlights();
            });
        });
    },

    /** Highlight preview blocks that contain a wildcard (hover from lock strip). */
    _highlightPreviewBlocksForWildcard(wcName) {
        const body = document.querySelector('[data-testid="pu-preview-body"]');
        if (!body) return;
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return;
        const wcBlockMap = PU.editorMode._buildPreviewWcBlockMap(prompt.text);
        const matchPaths = wcBlockMap[wcName] || new Set();
        // Compute parent paths
        const parentPaths = new Set();
        for (const path of matchPaths) {
            const parts = path.split('.');
            for (let i = 1; i < parts.length; i++) {
                const pp = parts.slice(0, i).join('.');
                if (!matchPaths.has(pp)) parentPaths.add(pp);
            }
        }
        body.classList.add('pu-preview-wc-highlighting');
        body.querySelectorAll('.pu-preview-block').forEach(block => {
            const path = block.dataset.path;
            if (matchPaths.has(path)) {
                block.classList.add('pu-preview-highlight-match');
            } else if (parentPaths.has(path)) {
                block.classList.add('pu-preview-highlight-parent');
            }
        });
    },

    /** Clear preview block highlight classes. */
    _clearPreviewBlockHighlights() {
        const body = document.querySelector('[data-testid="pu-preview-body"]');
        if (!body) return;
        body.classList.remove('pu-preview-wc-highlighting');
        body.querySelectorAll('.pu-preview-highlight-match, .pu-preview-highlight-parent').forEach(el => {
            el.classList.remove('pu-preview-highlight-match', 'pu-preview-highlight-parent');
        });
    },

    /** Open lock popup by wildcard name (from strip chip or summary click). */
    openLockPopupByName(wcName) {
        const slot = document.querySelector(`.pu-wc-slot[data-wc="${wcName}"]`);
        if (slot) {
            PU.editorMode.openLockPopup(wcName, slot);
        }
    },

    /** Clear locks for a single wildcard. */
    clearLock(wcName) {
        const locked = PU.state.previewMode.lockedValues;
        delete locked[wcName];
        const sw = PU.state.previewMode.selectedWildcards;
        if (sw['*']) delete sw['*'][wcName];
        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
        PU.rightPanel.renderOpsSection();
    },

    /** Clear all wildcard locks. */
    clearAllLocks() {
        PU.state.previewMode.lockedValues = {};
        const sw = PU.state.previewMode.selectedWildcards;
        delete sw['*'];
        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
        PU.rightPanel.renderOpsSection();
    },

    /** Set preview depth and re-render. */
    setPreviewDepth(depth) {
        PU.state.previewMode.previewDepth = depth; // null = all
        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
        PU.actions.updateUrl();
    },

    /** Render depth stepper buttons in the nav bar. */
    _renderDepthStepper(maxDepth) {
        const container = document.querySelector('[data-testid="pu-preview-depth-stepper"]');
        if (!container) return;

        if (maxDepth <= 1) {
            container.innerHTML = '';
            return;
        }

        const currentDepth = PU.state.previewMode.previewDepth;
        let html = '<span class="pu-depth-label">Depth</span>';
        for (let d = 1; d <= maxDepth; d++) {
            const active = currentDepth === d ? ' active' : '';
            html += `<button class="pu-depth-btn${active}" data-testid="pu-depth-btn-${d}"
                             onclick="PU.editorMode.setPreviewDepth(${d})">${d}</button>`;
        }
        const allActive = currentDepth === null ? ' active' : '';
        html += `<button class="pu-depth-btn${allActive}" data-testid="pu-depth-btn-all"
                         onclick="PU.editorMode.setPreviewDepth(null)">All</button>`;
        container.innerHTML = html;
    },

    /** Toggle a block's visibility in preview (sidebar tree checkbox). Cascades to descendants. */
    toggleBlockVisibility(path, hidden) {
        const prompt = PU.helpers.getActivePrompt();
        const textItems = prompt ? prompt.text : [];
        const hiddenBlocks = PU.state.previewMode.hiddenBlocks;

        if (hidden) {
            hiddenBlocks.add(path);
            // Cascade: hide all descendants
            const block = PU.editorMode._getBlockAtPath(textItems, path);
            if (block) {
                for (const dp of PU.editorMode._getAllDescendantPaths(block, path)) {
                    hiddenBlocks.add(dp);
                }
            }
        } else {
            hiddenBlocks.delete(path);
            // Cascade: show all descendants
            const block = PU.editorMode._getBlockAtPath(textItems, path);
            if (block) {
                for (const dp of PU.editorMode._getAllDescendantPaths(block, path)) {
                    hiddenBlocks.delete(dp);
                }
            }
        }
        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
    },

    /** Get the block object at a given dot-separated path (e.g. "0.1.2"). */
    _getBlockAtPath(textItems, path) {
        const parts = path.split('.');
        let blocks = textItems;
        let block = null;
        for (const p of parts) {
            const idx = parseInt(p, 10);
            if (!Array.isArray(blocks) || idx >= blocks.length) return null;
            block = blocks[idx];
            blocks = block.after || [];
        }
        return block;
    },

    /** Return all descendant paths for a given block. */
    _getAllDescendantPaths(block, prefix) {
        const paths = [];
        if (!block || !block.after) return paths;
        block.after.forEach((child, idx) => {
            const childPath = `${prefix}.${idx}`;
            paths.push(childPath);
            paths.push(...PU.editorMode._getAllDescendantPaths(child, childPath));
        });
        return paths;
    },

    /** Build wildcard-to-block path map from prompt data (no DOM needed). */
    _buildPreviewWcBlockMap(textItems) {
        const map = {};
        function walk(blocks, prefix) {
            if (!Array.isArray(blocks)) return;
            blocks.forEach((block, idx) => {
                const path = prefix ? `${prefix}.${idx}` : String(idx);
                const content = block.content || '';
                const matches = content.match(/__([a-zA-Z0-9_-]+)__/g) || [];
                for (const m of matches) {
                    const name = m.replace(/__/g, '');
                    if (!map[name]) map[name] = new Set();
                    map[name].add(path);
                }
                if (block.after) walk(block.after, path);
            });
        }
        walk(textItems, '');
        return map;
    },

    /** Check if any descendant of a block is in the hidden set. */
    _hasHiddenDescendant(block, prefix, hiddenSet) {
        if (!block || !block.after) return false;
        return block.after.some((child, idx) => {
            const childPath = `${prefix}.${idx}`;
            if (hiddenSet.has(childPath)) return true;
            return PU.editorMode._hasHiddenDescendant(child, childPath, hiddenSet);
        });
    },

    /** Navigate to previous composition (sidebar only — main content is static template). */
    prevComposition() {
        const { total, wildcardCounts, lookup, extTextCount } = PU.shared.getCompositionParams();
        if (total <= 0) return;
        const locked = PU.state.previewMode.lockedValues;
        const hasLocks = Object.keys(locked).some(k => locked[k] && locked[k].length > 0);
        let next = PU.state.previewMode.compositionId;

        if (!hasLocks) {
            next = (next - 1 + total) % total;
        } else {
            for (let i = 0; i < total; i++) {
                next = (next - 1 + total) % total;
                if (PU.editorMode._compositionMatchesLocks(next, locked, lookup, wildcardCounts, extTextCount)) break;
            }
        }

        PU.state.previewMode.compositionId = next;
        PU.editorMode.renderSidebarPreview();
        PU.rightPanel.renderOpsSection();
    },

    /** Navigate to next composition (sidebar only — main content is static template). */
    nextComposition() {
        const { total, wildcardCounts, lookup, extTextCount } = PU.shared.getCompositionParams();
        if (total <= 0) return;
        const locked = PU.state.previewMode.lockedValues;
        const hasLocks = Object.keys(locked).some(k => locked[k] && locked[k].length > 0);
        let next = PU.state.previewMode.compositionId;

        if (!hasLocks) {
            next = (next + 1) % total;
        } else {
            for (let i = 0; i < total; i++) {
                next = (next + 1) % total;
                if (PU.editorMode._compositionMatchesLocks(next, locked, lookup, wildcardCounts, extTextCount)) break;
            }
        }

        PU.state.previewMode.compositionId = next;
        PU.editorMode.renderSidebarPreview();
        PU.rightPanel.renderOpsSection();
    },

    /** Check if a composition matches all locked value constraints. */
    _compositionMatchesLocks(compId, locked, lookup, wildcardCounts, extTextCount) {
        const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);
        for (const [name, vals] of Object.entries(locked)) {
            if (!vals || vals.length === 0) continue;
            const idx = wcIndices[name] || 0;
            const allValues = lookup[name] || [];
            const currentValue = allValues[idx];
            if (!vals.includes(currentValue)) return false;
        }
        return true;
    },

    // ── Sidebar Preview (block tree + filtered wildcards) ────────────────

    /** Render the Preview mode sidebar with block tree, wildcards, and resolved output. */
    renderSidebarPreview() {
        const container = document.querySelector('[data-testid="pu-rp-comp-values"]');
        if (!container) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text) || prompt.text.length === 0) {
            container.innerHTML = '<div class="pu-rp-note">No content to inspect</div>';
            return;
        }

        const { total, wcNames, lookup, wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        if (total <= 0) {
            container.innerHTML = '<div class="pu-rp-note">No compositions</div>';
            return;
        }

        const textItems = prompt.text;
        const hiddenBlocks = PU.state.previewMode.hiddenBlocks;
        const esc = PU.blocks.escapeHtml;

        // Section 1: Block tree checklist
        let html = '<div class="pu-rp-bt-title" data-testid="pu-rp-bt-title">BLOCK TREE</div>';
        html += PU.editorMode._renderBlockTreeChecklist(textItems, '', hiddenBlocks);

        // Section 2: Direct lock panel (mirrors write view's wildcard panel)
        const visibleWcNames = PU.editorMode._collectVisibleWildcards(textItems, '', hiddenBlocks);
        const filteredNames = wcNames.filter(n => visibleWcNames.has(n));
        const lockedValues = PU.state.previewMode.lockedValues || {};

        // Get current composition indices for active chip highlighting
        const compId = PU.state.previewMode.compositionId;
        const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);

        // Build wildcard-to-block map for bulb icons (show bulb when 2+ total blocks)
        const totalBlocks = PU.rightPanel._countAllBlocks(textItems);
        const wcBlockMap = totalBlocks >= 2 ? PU.editorMode._buildPreviewWcBlockMap(textItems) : {};
        const focusedWildcards = PU.state.previewMode.focusedWildcards;

        html += `<div class="pu-rp-bt-title" data-testid="pu-rp-bt-wc-title" style="margin-top: var(--pu-space-md);">WILDCARDS</div>`;
        html += '<div class="pu-rp-preview-wc-panel" data-testid="pu-rp-preview-wc-panel">';

        for (const name of filteredNames) {
            const vals = lookup[name] || [];
            const safeName = esc(name);
            const lockedVals = lockedValues[name] || [];
            const activeIdx = wcIndices[name] || 0;
            const wrappedIdx = vals.length > 0 ? activeIdx % vals.length : 0;

            let chipsHtml = '';
            for (let i = 0; i < vals.length; i++) {
                const val = vals[i];
                const eVal = esc(val);
                let cls = 'pu-rp-wc-v';
                if (i === wrappedIdx) cls += ' active';
                if (lockedVals.includes(val)) cls += ' locked';
                const lockIcon = lockedVals.includes(val) ? '<span class="lock-icon">&#128274;</span>' : '';
                chipsHtml += `<span class="${cls}" data-testid="pu-rp-lock-chip-${safeName}-${i}" data-wc-name="${safeName}" data-value="${eVal}" data-idx="${i}" title="${eVal}">${lockIcon}${eVal}</span>`;
            }

            // Bulb icon for focus mode (only when 2+ blocks exist)
            const isFocused = focusedWildcards.includes(name);
            const hasPaths = wcBlockMap[name] && wcBlockMap[name].size > 0;
            const focusIcon = totalBlocks >= 2 && hasPaths
                ? `<span class="pu-wc-focus-icon${isFocused ? ' active' : ''}" data-testid="pu-preview-focus-${safeName}" data-wc-name="${safeName}" title="${isFocused ? 'Remove from focus' : 'Illuminate: show blocks using this wildcard'}">&#128161;</span>`
                : '';

            html += `<div class="pu-rp-wc-entry${isFocused ? ' pu-wc-entry-focused' : ''}" data-testid="pu-rp-wc-entry-${safeName}" data-wc-name="${safeName}">
                <div class="pu-rp-wc-entry-header">
                    <span class="pu-rp-wc-name">${safeName}</span>
                    <span class="pu-rp-wc-lock-count">${lockedVals.length > 0 ? lockedVals.length + '/' + vals.length : ''}</span>
                    ${focusIcon}
                </div>
                <div class="pu-rp-wc-values">${chipsHtml}</div>
            </div>`;
        }

        html += '</div>';
        container.innerHTML = html;

        // Set indeterminate state on checkboxes (can't be set via HTML attribute)
        container.querySelectorAll('input[data-indeterminate="true"]').forEach(cb => {
            cb.indeterminate = true;
        });

        // Attach click handlers: click = toggle lock directly
        container.querySelectorAll('.pu-rp-preview-wc-panel .pu-rp-wc-v').forEach(chip => {
            chip.addEventListener('click', () => {
                const wcName = chip.dataset.wcName;
                const val = chip.dataset.value;
                if (wcName && val !== undefined) {
                    PU.editorMode.toggleSidebarLock(wcName, val);
                }
            });
        });

        // Attach bulb icon click handlers for preview focus mode
        container.querySelectorAll('.pu-wc-focus-icon').forEach(icon => {
            icon.addEventListener('click', (e) => {
                e.stopPropagation();
                const wcName = icon.dataset.wcName;
                if (!wcName) return;
                PU.editorMode.togglePreviewFocus(wcName);
            });
        });
    },

    /** Toggle a wildcard in preview focus mode — re-renders preview + sidebar. */
    togglePreviewFocus(wcName) {
        const focused = PU.state.previewMode.focusedWildcards;
        const idx = focused.indexOf(wcName);
        if (idx >= 0) {
            focused.splice(idx, 1);
        } else {
            focused.push(wcName);
        }
        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
    },

    /** Toggle lock for a wildcard value from the sidebar direct lock panel. */
    toggleSidebarLock(wcName, value) {
        const locked = PU.state.previewMode.lockedValues;
        if (!locked[wcName]) locked[wcName] = [];

        const idx = locked[wcName].indexOf(value);
        if (idx >= 0) {
            locked[wcName].splice(idx, 1);
            if (locked[wcName].length === 0) {
                delete locked[wcName];
            }
        } else {
            locked[wcName].push(value);
        }

        // Sync preview override
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

        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
        PU.rightPanel.renderOpsSection();
    },

    /** Build checkbox tree HTML for the block tree sidebar. Supports indeterminate state. */
    _renderBlockTreeChecklist(blocks, prefix, hiddenSet) {
        if (!Array.isArray(blocks)) return '';
        let html = '';
        blocks.forEach((block, idx) => {
            const path = prefix ? `${prefix}.${idx}` : String(idx);
            const depth = path.split('.').length;
            const isHidden = hiddenSet.has(path);
            const checked = isHidden ? '' : 'checked';

            // Indeterminate: block visible but some descendants are hidden
            const hasChildren = block.after && block.after.length > 0;
            const isIndeterminate = hasChildren && !isHidden && PU.editorMode._hasHiddenDescendant(block, path, hiddenSet);
            const indeterminateAttr = isIndeterminate ? ' data-indeterminate="true"' : '';

            // Tree connector for child items (├── / └──)
            const isChild = depth > 1;
            const isLast = idx === blocks.length - 1;
            const connectorHtml = isChild
                ? `<span class="pu-rp-bt-connector">${isLast ? '\u2514\u2500\u2500 ' : '\u251C\u2500\u2500 '}</span>`
                : '';

            // Build preview text (40 chars, wildcards replaced with ...)
            let preview;
            if ('ext_text' in block) {
                preview = `[${block.ext_text}]`;
            } else {
                const content = block.content || '';
                preview = content.replace(/__[a-zA-Z0-9_-]+__/g, '...').trim().substring(0, 40);
                if (content.length > 40) preview += '...';
            }
            if (!preview) preview = `Block ${idx + 1}`;

            const indent = (depth - 1) * 16;
            html += `<div class="pu-rp-bt-item" data-testid="pu-rp-bt-${path}" style="padding-left: ${indent}px;">
                <label>
                    ${connectorHtml}<input type="checkbox" ${checked}${indeterminateAttr}
                           onchange="PU.editorMode.toggleBlockVisibility('${path}', !this.checked)">
                    <span class="pu-rp-bt-text" title="${PU.blocks.escapeHtml(block.content || block.ext_text || '')}">${PU.blocks.escapeHtml(preview)}</span>
                </label>
            </div>`;

            // Recurse children
            if (hasChildren) {
                html += PU.editorMode._renderBlockTreeChecklist(block.after, path, hiddenSet);
            }
        });
        return html;
    },

    /** Collect wildcard names from visible (non-hidden) blocks. */
    _collectVisibleWildcards(blocks, prefix, hiddenSet) {
        const names = new Set();
        if (!Array.isArray(blocks)) return names;
        blocks.forEach((block, idx) => {
            const path = prefix ? `${prefix}.${idx}` : String(idx);
            if (hiddenSet.has(path)) return;

            const content = block.content || '';
            const matches = content.match(/__([a-zA-Z0-9_-]+)__/g) || [];
            for (const m of matches) {
                names.add(m.replace(/__/g, ''));
            }

            if (block.after && block.after.length > 0) {
                const childNames = PU.editorMode._collectVisibleWildcards(block.after, path, hiddenSet);
                for (const n of childNames) names.add(n);
            }
        });
        return names;
    },

    // ── Gear Popover (Phase 3) ──────────────────────────────────────────

    _gearOpen: false,

    /** Toggle the gear popover with layer checkboxes. */
    toggleGearPopover(event) {
        if (event) event.stopPropagation();
        const popover = document.querySelector('[data-testid="pu-mode-gear-popover"]');
        if (!popover) return;

        if (PU.editorMode._gearOpen) {
            PU.editorMode.closeGearPopover();
            return;
        }

        PU.overlay.dismissPopovers();
        PU.editorMode._gearOpen = true;
        PU.overlay.showOverlay();

        const layers = PU.state.ui.editorLayers;
        const mode = PU.state.ui.editorMode;
        const varMode = PU.state.previewMode.variationMode || 'summary';

        let gearHtml = '<div class="pu-gear-popover-content">';

        // Preview mode: show Variations toggle
        if (mode === 'preview') {
            gearHtml += `
                <div class="pu-gear-title">Variations</div>
                <label class="pu-gear-row" data-testid="pu-gear-var-summary">
                    <input type="radio" name="var-mode" value="summary" ${varMode === 'summary' ? 'checked' : ''}
                           onchange="PU.editorMode.setVariationMode('summary')">
                    <span>Summary</span>
                </label>
                <label class="pu-gear-row" data-testid="pu-gear-var-expanded">
                    <input type="radio" name="var-mode" value="expanded" ${varMode === 'expanded' ? 'checked' : ''}
                           onchange="PU.editorMode.setVariationMode('expanded')">
                    <span>Expanded</span>
                </label>
                <div style="border-top: 1px solid var(--pu-border); margin: var(--pu-space-xs) 0;"></div>
            `;
        }

        gearHtml += `
                <div class="pu-gear-title">Display Layers</div>
                <label class="pu-gear-row" data-testid="pu-gear-annotations">
                    <input type="checkbox" ${layers.annotations ? 'checked' : ''}
                           onchange="PU.editorMode.setLayer('annotations', this.checked)">
                    <span>Annotations</span>
                </label>
                <label class="pu-gear-row" data-testid="pu-gear-compositions">
                    <input type="checkbox" ${layers.compositions ? 'checked' : ''}
                           onchange="PU.editorMode.setLayer('compositions', this.checked)">
                    <span>Compositions</span>
                </label>
                <label class="pu-gear-row" data-testid="pu-gear-artifacts">
                    <input type="checkbox" ${layers.artifacts ? 'checked' : ''}
                           onchange="PU.editorMode.setLayer('artifacts', this.checked)">
                    <span>Artifacts</span>
                </label>
                <div class="pu-gear-presets">
                    <span class="pu-gear-presets-label">Presets:</span>
                    <button class="pu-gear-preset-btn${mode === 'write' ? ' active' : ''}"
                            onclick="PU.editorMode.setPreset('write')">Write</button>
                    <button class="pu-gear-preset-btn${mode === 'preview' ? ' active' : ''}"
                            onclick="PU.editorMode.setPreset('preview')">Preview</button>
                    <button class="pu-gear-preset-btn${mode === 'review' ? ' active' : ''}"
                            onclick="PU.editorMode.setPreset('review')">Review</button>
                </div>
            </div>
        `;

        popover.innerHTML = gearHtml;
        popover.style.display = '';
    },

    /** Close the gear popover. */
    closeGearPopover() {
        const popover = document.querySelector('[data-testid="pu-mode-gear-popover"]');
        if (popover) popover.style.display = 'none';
        PU.editorMode._gearOpen = false;
    },

    /** Sync gear popover checkboxes with current layer state (if popover is open). */
    _syncGearCheckboxes() {
        if (!PU.editorMode._gearOpen) return;
        const layers = PU.state.ui.editorLayers;
        const popover = document.querySelector('[data-testid="pu-mode-gear-popover"]');
        if (!popover) return;
        Object.entries(layers).forEach(([key, val]) => {
            const row = popover.querySelector(`[data-testid="pu-gear-${key}"] input`);
            if (row) row.checked = val;
        });
        // Update preset highlights
        popover.querySelectorAll('.pu-gear-preset-btn').forEach(btn => {
            const preset = btn.textContent.trim().toLowerCase();
            btn.classList.toggle('active', preset === PU.state.ui.editorMode);
        });
    },

    // ── Init ─────────────────────────────────────────────────────────────

    /** Initialize editor mode from persisted state. */
    init() {
        const mode = PU.state.ui.editorMode;
        // Ensure layers match the persisted mode (if it's a named preset)
        if (mode !== 'custom' && PU.editorMode.PRESETS[mode]) {
            PU.state.ui.editorLayers = { ...PU.editorMode.PRESETS[mode] };
        }
        PU.editorMode._applyMode();
        PU.editorMode._updateStripButtons();
    }
};

// Register gear popover with overlay lifecycle
PU.overlay.registerPopover('gearPopover', () => PU.editorMode.closeGearPopover());

// Register lock popup with overlay lifecycle
PU.overlay.registerPopover('lockPopup', () => PU.editorMode.closeLockPopup());

// ── Debug API ──────────────────────────────────────────────────────────
PU.debug = PU.debug || {};
PU.debug.sidebar = function() {
    const mode = PU.state.ui.editorMode;
    const rpEditor = document.querySelector('[data-testid="pu-rp-editor-content"]');
    const rpPreview = document.querySelector('[data-testid="pu-rp-preview-content"]');
    const ops = document.querySelector('[data-testid="pu-rp-ops-section"]');
    return {
        mode,
        activeContent: mode === 'preview' ? 'preview' : 'editor',
        tabStrip: mode === 'review' ? 'visible' : 'hidden',
        activeTab: PU.state.ui.rightPanelTab,
        layers: { ...PU.state.ui.editorLayers },
        editorContentVisible: rpEditor ? rpEditor.style.display !== 'none' : null,
        previewContentVisible: rpPreview ? rpPreview.style.display !== 'none' : null,
        opsVariant: ops ? ops.dataset.debugVariant : null,
        opsTotal: ops ? ops.dataset.debugTotal : null
    };
};
