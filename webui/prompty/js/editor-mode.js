/**
 * PromptyUI - Editor Mode Strip
 *
 * Progressive disclosure: Write / Preview / Export modes.
 * Write & Review toggle CSS visibility on the block editor.
 * Preview swaps to a resolved document view.
 * Gear popover exposes granular layer checkboxes.
 */

PU.editorMode = {
    // Preset → layer configuration
    PRESETS: {
        write:   { annotations: false, compositions: false, artifacts: false },
        preview: { annotations: false, compositions: true,  artifacts: false },
        export:  { annotations: true,  compositions: true,  artifacts: true  }
    },

    /** Apply a named preset (write | preview | export). */
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

        if (mode === 'preview' || mode === 'export') {
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

        if (mode === 'preview' || mode === 'export') {
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
            PU.editorMode._renderLockStrip();
            return;
        }

        const textItems = prompt.text;
        const resolutions = await PU.preview.buildBlockResolutions(textItems, { skipOdometerUpdate: true });

        // Compute max tree depth
        const maxDepth = PU.editorMode._computeMaxDepth(textItems);
        PU.state.previewMode.maxTreeDepth = maxDepth;

        // Get composition params for variations
        const { lookup } = PU.shared.getCompositionParams();
        PU.editorMode._ensureLockDefaults(); // auto-fill first-value defaults
        const locked = PU.state.previewMode.lockedValues;

        // Render block-by-block (template view) + collect variation data
        const { blocks, variationData } = PU.editorMode._renderBlockByBlock(textItems, resolutions, maxDepth, lookup, locked);
        PU.state.previewMode.resolvedVariations = variationData;

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

        // Strip interactivity from wildcard slots in ancestor segments
        body.querySelectorAll('.pu-preview-segment-ancestor .pu-wc-slot').forEach(slot => {
            slot.removeAttribute('onclick');
            slot.classList.add('pu-wc-slot-ancestor');
        });

        // Attach segment-level hover listeners for compositions linking
        PU.editorMode._attachPreviewHoverListeners(body);

        // Auto-populate compositions from state, render panel
        PU.compositions.populateFromPreview();
        PU.compositions.render();
    },

    /** Attach block-level hover on preview rows to highlight the block + matching compositions items. */
    _attachPreviewHoverListeners(container) {
        if (PU.state.ui.editorMode === 'preview' || PU.state.ui.editorMode === 'export') {
            const allBlocks = container.querySelectorAll('.pu-preview-block[data-path]');
            allBlocks.forEach(block => {
                block.addEventListener('mouseenter', () => {
                    const path = block.dataset.path;
                    if (!path) return;
                    block.classList.add('pu-preview-block-hover');
                    PU.compositions._highlightItemsBySegmentPath(path);
                });
                block.addEventListener('mouseleave', () => {
                    block.classList.remove('pu-preview-block-hover');
                    PU.compositions._clearCompositionsHighlights();
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
     *
     * Two-pass allocation for compositions: first counts effectiveCombos per block,
     * then computes sqrt-proportional budgets, then generates variations to budget.
     */
    _renderBlockByBlock(textItems, resolutions, maxDepth, lookup, locked) {
        const results = [];
        const variationData = [];
        const hiddenBlocks = PU.state.previewMode.hiddenBlocks;
        const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        const compId = PU.state.previewMode.compositionId;
        const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);
        const varMode = PU.state.previewMode.variationMode || 'summary';

        const isPreviewMode = PU.state.ui.editorMode === 'preview' || PU.state.ui.editorMode === 'export';
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

        // ── Pass 1: Collect block metadata (effectiveCombos, type) ──
        const blockMeta = []; // { path, type, effectiveCombos, blockWcNames, rawContent, block, res, depth, ancestorWcNames }
        function collectMeta(blocks, prefix, depth, ancestorWcNames) {
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

                // Find wildcards in this block's content (or ext_text resolved template)
                const blockWcNames = [];
                let extTextValues = null; // Array of ext_text strings for ext_text blocks
                if (isExtText) {
                    // Get ext_text values from cache
                    const extName = block.ext_text;
                    const extPrefix = PU.helpers.getActivePrompt()?.ext || PU.helpers.getActiveJob()?.defaults?.ext || '';
                    const needsPrefix = extPrefix && !extName.startsWith(extPrefix + '/');
                    const cacheKey = needsPrefix ? `${extPrefix}/${extName}` : extName;
                    const extData = (PU.state.previewMode._extTextCache || {})[cacheKey];
                    if (extData && extData.text && extData.text.length > 0) {
                        extTextValues = extData.text;
                    }
                    // Find wildcards in the ext_text template (from resolved marker text)
                    const rawTemplate = (res.resolvedMarkerText || '').replace(/\{\{([^:]+):([^}]+)\}\}/g, '__$1__');
                    if (rawTemplate) {
                        const wcPattern = /__([a-zA-Z0-9_-]+)__/g;
                        let m;
                        const seen = new Set();
                        while ((m = wcPattern.exec(rawTemplate)) !== null) {
                            if (!seen.has(m[1]) && lookup[m[1]]) {
                                seen.add(m[1]);
                                blockWcNames.push(m[1]);
                            }
                        }
                    }
                } else if (rawContent) {
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

                // Merge ancestor wildcards (exclude any already in this block's own wildcards)
                const ownWcSet = new Set(blockWcNames);
                const inheritedWcNames = (ancestorWcNames || []).filter(n => !ownWcSet.has(n));
                // allWcNames = own + inherited ancestor wildcards
                const allWcNames = [...blockWcNames, ...inheritedWcNames];

                // Compute effectiveCombos for this block (own + ancestor wildcards)
                let effectiveCombos = 1;
                if (isExtText && extTextValues) {
                    effectiveCombos = extTextValues.length;
                    // Multiply by locked wildcard dimensions (own + inherited)
                    for (const name of allWcNames) {
                        const lockedVals = (locked[name] && locked[name].length > 0) ? locked[name] : null;
                        if (lockedVals) effectiveCombos *= lockedVals.length;
                    }
                } else if (allWcNames.length > 0) {
                    for (const name of allWcNames) {
                        const lockedVals = (locked[name] && locked[name].length > 0) ? locked[name] : null;
                        if (lockedVals) {
                            effectiveCombos *= lockedVals.length;
                        }
                    }
                }

                const type = isExtText ? 'ext_text' : (allWcNames.length > 0 ? 'wildcard' : 'static');
                blockMeta.push({ path, type, effectiveCombos, blockWcNames: allWcNames, rawContent, block, res, depth, hasChildren, extTextValues });

                // Recurse children — pass accumulated wildcard names (own + inherited)
                if (hasChildren) {
                    const childAncestorWcs = [...allWcNames];
                    const maxBranches = 3;
                    if (block.after.length > maxBranches) {
                        collectMeta(block.after.slice(0, maxBranches), path, depth + 1, childAncestorWcs);
                    } else {
                        collectMeta(block.after, path, depth + 1, childAncestorWcs);
                    }
                }
            });
        }
        if (isPreviewMode) collectMeta(textItems, '', 1, []);

        // ── Pass 2: Compute sqrt-proportional allocation ──
        const pathBudgets = PU.state.previewMode.pathBudgets;
        const pathOverflow = {};
        const allocatedBudgets = {}; // { path: budget }

        if (isPreviewMode && blockMeta.length > 0) {
            // Each block gets its full Cartesian product, capped per-block
            const PER_BLOCK_CAP = 100;
            for (const b of blockMeta) {
                if (pathBudgets[b.path]) {
                    // Explicit show-more budget: allow exceeding default cap
                    allocatedBudgets[b.path] = pathBudgets[b.path];
                } else {
                    allocatedBudgets[b.path] = Math.min(b.effectiveCombos, PER_BLOCK_CAP);
                }
            }
        }

        // ── Pass 3: Traverse and generate (same depth-first order) ──
        function traverse(blocks, prefix, depth, hasTrailingMore, ancestorWcNames) {
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

                // Find wildcards in this block's own content
                const ownWcNames = [];
                if (!isExtText && rawContent) {
                    const wcPattern = /__([a-zA-Z0-9_-]+)__/g;
                    let m;
                    const seen = new Set();
                    while ((m = wcPattern.exec(rawContent)) !== null) {
                        if (!seen.has(m[1]) && lookup[m[1]]) {
                            seen.add(m[1]);
                            ownWcNames.push(m[1]);
                        }
                    }
                }

                // Merge ancestor wildcards (exclude duplicates with own)
                const ownWcSet = new Set(ownWcNames);
                const inheritedWcNames = (ancestorWcNames || []).filter(n => !ownWcSet.has(n));
                // allWcNames = own + inherited for variation generation
                const allWcNames = [...ownWcNames, ...inheritedWcNames];

                let ownHtml;

                if (isExtText) {
                    const rawTemplate = (res.resolvedMarkerText || '').replace(/\{\{([^:]+):([^}]+)\}\}/g, '__$1__');
                    const hasExtWc = /__[a-zA-Z0-9_-]+__/.test(rawTemplate);
                    const labelHtml = `<span class="pu-ext-text-label">${esc(block.ext_text)}</span>`;
                    const templateHtml = hasExtWc ? ' ' + PU.editorMode._convertToTemplateView(rawTemplate) : '';
                    ownHtml = labelHtml + templateHtml;
                    if (isPreviewMode) {
                        // Get ext_text values from cache
                        const extName = block.ext_text;
                        const extPrefix = PU.helpers.getActivePrompt()?.ext || PU.helpers.getActiveJob()?.defaults?.ext || '';
                        const needsPrefix = extPrefix && !extName.startsWith(extPrefix + '/');
                        const cacheKey = needsPrefix ? `${extPrefix}/${extName}` : extName;
                        const extData = (PU.state.previewMode._extTextCache || {})[cacheKey];
                        const extValues = (extData && extData.text && extData.text.length > 0) ? extData.text : null;

                        if (extValues && extValues.length > 1) {
                            // Expand ext_text as a dimension: each value produces an entry
                            const budget = allocatedBudgets[path] || 20;
                            // Find wildcards in the ext_text template
                            const extOwnWcNames = [];
                            if (rawTemplate) {
                                const wcPattern = /__([a-zA-Z0-9_-]+)__/g;
                                let m;
                                const seen = new Set();
                                while ((m = wcPattern.exec(rawTemplate)) !== null) {
                                    if (!seen.has(m[1]) && lookup[m[1]]) {
                                        seen.add(m[1]);
                                        extOwnWcNames.push(m[1]);
                                    }
                                }
                            }
                            // Merge ancestor wildcards for ext_text blocks too
                            const extOwnSet = new Set(extOwnWcNames);
                            const extAllWcNames = [...extOwnWcNames, ...(ancestorWcNames || []).filter(n => !extOwnSet.has(n))];
                            // Vary on all wildcards (own + inherited) for full Cartesian product.
                            const blockVars = PU.editorMode._computeExtTextVariations(
                                extValues, extAllWcNames, lookup, locked, wcIndices, path, budget
                            );
                            for (const v of blockVars) variationData.push(v);

                            // Compute overflow using same dimensions
                            let effectiveCombos = extValues.length;
                            for (const name of extAllWcNames) {
                                const lv = (locked[name] && locked[name].length > 0) ? locked[name] : null;
                                if (lv) effectiveCombos *= lv.length;
                            }
                            const remaining = effectiveCombos - blockVars.length;
                            if (remaining > 0) {
                                pathOverflow[path] = remaining;
                            }
                        } else {
                            // Single ext_text value: one entry (original behavior)
                            const plainText = (res.resolvedMarkerText || '').replace(/\{\{([^:]+):([^}]+)\}\}/g, '$2');
                            variationData.push({ blockPath: path, comboKey: '', text: plainText });
                        }
                    }
                } else if (allWcNames.length > 0) {
                    ownHtml = ownWcNames.length > 0 ? PU.editorMode._convertToTemplateView(rawContent) : esc(rawContent);
                    if (isPreviewMode) {
                        const budget = allocatedBudgets[path] || 20;
                        // Vary on all wildcards (own + inherited) — inherited ones produce
                        // same text but distinct comboKeys for each parent context.
                        const blockVars = PU.editorMode._computeBlockVariations(rawContent, allWcNames, lookup, locked, wcIndices, varMode, path, budget);
                        for (const v of blockVars) variationData.push(v);

                        // Compute overflow using same dimensions
                        let effectiveCombos = 1;
                        for (const name of allWcNames) {
                            const lv = (locked[name] && locked[name].length > 0) ? locked[name] : null;
                            if (lv) effectiveCombos *= lv.length;
                        }
                        const remaining = effectiveCombos - blockVars.length;
                        if (remaining > 0) {
                            pathOverflow[path] = remaining;
                        }
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

                // Traverse children — pass accumulated wildcard names
                if (hasChildren) {
                    const childAncestorWcs = [...allWcNames];
                    const maxBranches = 3;
                    if (block.after.length > maxBranches) {
                        traverse(block.after.slice(0, maxBranches), path, depth + 1, true, childAncestorWcs);
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
                        traverse(block.after, path, depth + 1, false, childAncestorWcs);
                    }
                }
            });
        }

        traverse(textItems, '', 1, false, []);

        // Store overflow for compositions renderer
        PU.state.previewMode.pathOverflow = pathOverflow;

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
     * Returns array of {blockPath, comboKey, text} for compositions population.
     * Budget param controls max entries (from allocation). Falls back to 20/100.
     */
    _computeBlockVariations(content, blockWcNames, lookup, locked, wcIndices, mode, blockPath, budget) {
        if (!blockWcNames || blockWcNames.length === 0) {
            if (!content) return [];
            // No wildcards at all — shouldn't reach here, but safety
            return [];
        }

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
        const MAX_SHOW = budget || (isSummary ? 20 : 100);
        const sampleCount = isSummary ? Math.min(totalCombos, MAX_SHOW * 3) : Math.min(totalCombos, MAX_SHOW);
        const combos = PU.editorMode._cartesianProduct(dims, sampleCount);

        const results = [];
        const seen = isSummary ? new Set() : null;
        for (const combo of combos) {
            if (results.length >= MAX_SHOW) break;

            // Compute plain resolved text (only own wildcards affect the text)
            let plain = content || '';
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

            // Dedup by combo key (not plain text) — ancestor wildcards produce
            // same text but distinct compositions
            const comboKey = PU.compositions.comboToKey(combo);
            if (isSummary) {
                if (seen.has(comboKey)) continue;
                seen.add(comboKey);
            }

            results.push({
                blockPath,
                comboKey: PU.compositions.comboToKey(combo),
                text: plain
            });
        }

        return results;
    },

    /**
     * Compute variations for an ext_text block.
     * Each ext_text value is a dimension; wildcards within are additional dimensions.
     * Returns array of {blockPath, comboKey, text} for compositions panel.
     */
    _computeExtTextVariations(extValues, extWcNames, lookup, locked, wcIndices, blockPath, budget) {
        // Build dimensions: ext_text values + locked wildcards
        const dims = [{ name: '_ext', values: extValues }];
        for (const name of extWcNames) {
            const lockedVals = (locked[name] && locked[name].length > 0) ? locked[name] : null;
            const allVals = lookup[name] || [];
            if (lockedVals) {
                dims.push({ name, values: lockedVals });
            } else {
                const idx = wcIndices[name] || 0;
                dims.push({ name, values: [allVals[idx % allVals.length] || '?'] });
            }
        }

        let totalCombos = 1;
        for (const dim of dims) {
            totalCombos *= dim.values.length;
            if (totalCombos > 10000) { totalCombos = 10001; break; }
        }

        const MAX_SHOW = budget || 20;
        const sampleCount = Math.min(totalCombos, MAX_SHOW * 3);
        const combos = PU.editorMode._cartesianProduct(dims, sampleCount);

        const results = [];
        const seen = new Set();
        for (const combo of combos) {
            if (results.length >= MAX_SHOW) break;

            // The _ext dimension holds the raw ext_text template string
            const extEntry = combo.find(c => c.name === '_ext');
            let plain = extEntry ? extEntry.value : '';

            // Resolve wildcards in the ext_text template
            for (const { name, value } of combo) {
                if (name === '_ext') continue;
                plain = plain.split(`__${name}__`).join(value);
            }
            // Resolve remaining wildcards with odometer values
            plain = plain.replace(/__([a-zA-Z0-9_-]+)__/g, (match, wcName) => {
                const allVals = lookup[wcName] || [];
                if (allVals.length === 0) return match;
                const idx = wcIndices[wcName] || 0;
                return allVals[idx % allVals.length];
            });

            if (seen.has(plain)) continue;
            seen.add(plain);

            // Build combo key: ext=<short label> + wildcard dims
            const wcCombo = combo.filter(c => c.name !== '_ext');
            // Use first few chars of ext value as label
            const extLabel = (extEntry ? extEntry.value : '').substring(0, 40).replace(/__[a-zA-Z0-9_-]+__/g, '*').trim();
            const fullCombo = [{ name: 'ext', value: extLabel }, ...wcCombo];
            results.push({
                blockPath,
                comboKey: PU.compositions.comboToKey(fullCombo),
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

    // ── Preview Compositions (ephemeral lock popup feedback) ────────────

    /**
     * Walk block tree and find blocks whose content contains __wcName__.
     * Returns [{blockPath, content, ownWcNames}] for non-ext_text blocks.
     */
    _findBlocksWithWildcard(textItems, wcName) {
        const results = [];
        const walk = (items, prefix) => {
            if (!Array.isArray(items)) return;
            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                const path = prefix != null ? `${prefix}.${i}` : String(i);
                const content = item.content || '';
                const isExt = 'ext_text' in item;
                if (!isExt && content.includes(`__${wcName}__`)) {
                    // Collect own wildcards from content
                    const ownWcNames = [];
                    const seen = new Set();
                    const matches = content.match(/__([a-zA-Z0-9_-]+)__/g) || [];
                    for (const m of matches) {
                        const name = m.replace(/__/g, '');
                        if (!seen.has(name)) { seen.add(name); ownWcNames.push(name); }
                    }
                    results.push({ blockPath: path, content, ownWcNames });
                }
                if (item.after) walk(item.after, path);
            }
        };
        walk(textItems, null);
        return results;
    },

    /**
     * Compute preview compositions from lock popup state.
     * Iterates ALL staged wildcards and builds hypothetical locked state.
     */
    _computePreviewCompositions() {
        const state = PU.editorMode._lockPopupState;
        if (!state || !state.staged) {
            PU.state.previewMode.previewCompositions = [];
            return;
        }

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !prompt.text) {
            PU.state.previewMode.previewCompositions = [];
            return;
        }

        const lookup = PU.preview.getFullWildcardLookup();
        const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        const compId = PU.state.previewMode.compositionId;
        const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);

        // Collect new values across ALL staged wildcards
        const dirtyWildcards = []; // [{wcName, newValues}]
        for (const [wcName, wcStaged] of Object.entries(state.staged)) {
            const newValues = [...wcStaged.currentChecked].filter(v => !wcStaged.initialChecked.has(v));
            if (newValues.length > 0) {
                dirtyWildcards.push({ wcName, newValues });
            }
        }

        if (dirtyWildcards.length === 0) {
            PU.state.previewMode.previewCompositions = [];
            return;
        }

        // Build hypothetical locked state with new values from all dirty wildcards
        const locked = {};
        const realLocked = PU.state.previewMode.lockedValues;
        for (const k of Object.keys(realLocked)) {
            locked[k] = [...realLocked[k]];
        }
        for (const { wcName, newValues } of dirtyWildcards) {
            locked[wcName] = newValues;
        }

        // Collect preview entries across all dirty wildcards
        const MAX_PREVIEW = 5;
        const wcNames = dirtyWildcards.map(d => d.wcName);
        const results = PU.editorMode._collectSubtreePreview(
            prompt.text, wcNames, lookup, locked, wcIndices, MAX_PREVIEW
        );

        PU.state.previewMode.previewCompositions = results;
    },

    /**
     * Collect preview entries for wildcard(s) across the full subtree.
     * @param {string|string[]} wcNameOrNames - single wcName or array of wcNames
     * Walks the block tree to find all blocks affected by any of the wcNames,
     * generates variations using allWcNames (own + inherited) so descendant blocks
     * produce entries for each parent wildcard value.
     */
    _collectSubtreePreview(textItems, wcNameOrNames, lookup, locked, wcIndices, maxEntries) {
        const wcNameSet = new Set(Array.isArray(wcNameOrNames) ? wcNameOrNames : [wcNameOrNames]);
        // Staging always uses full view — independent of main panel's view mode
        const leafOnly = false;

        // Helper: extract wildcards and ext_text info for a block
        const _blockInfo = (item, path) => {
            const content = item.content || '';
            const isExt = 'ext_text' in item;
            const ownWcNames = [];
            let extValues = null;
            if (isExt) {
                const extName = item.ext_text;
                const prompt = PU.helpers.getActivePrompt();
                const extPrefix = prompt?.ext || PU.helpers.getActiveJob()?.defaults?.ext || '';
                const needsPrefix = extPrefix && !extName.startsWith(extPrefix + '/');
                const cacheKey = needsPrefix ? `${extPrefix}/${extName}` : extName;
                const extData = (PU.state.previewMode._extTextCache || {})[cacheKey];
                if (extData && extData.text && extData.text.length > 0) {
                    extValues = extData.text;
                    const rawTemplate = extValues[0] || '';
                    const seen = new Set();
                    const matches = rawTemplate.match(/__([a-zA-Z0-9_-]+)__/g) || [];
                    for (const m of matches) {
                        const name = m.replace(/__/g, '');
                        if (!seen.has(name) && lookup[name]) { seen.add(name); ownWcNames.push(name); }
                    }
                }
            } else {
                const seen = new Set();
                const matches = content.match(/__([a-zA-Z0-9_-]+)__/g) || [];
                for (const m of matches) {
                    const name = m.replace(/__/g, '');
                    if (!seen.has(name)) { seen.add(name); ownWcNames.push(name); }
                }
            }
            return { content, isExt, ownWcNames, extValues };
        };

        // Pass 1: Discover affected paths and their total variation counts
        const pathTotals = []; // [{path, total, isExt, extValues, allWcNames, content}]
        const discover = (items, prefix, ancestorWcs) => {
            if (!Array.isArray(items)) return;
            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                const path = prefix != null ? `${prefix}.${i}` : String(i);
                const info = _blockInfo(item, path);
                const ownSet = new Set(info.ownWcNames);
                const allWcNames = [...info.ownWcNames, ...ancestorWcs.filter(n => !ownSet.has(n))];
                const hasChildren = item.after && item.after.length > 0;
                // Include blocks where any staged wcName appears in own or inherited wildcards.
                const affectedByWc = allWcNames.some(n => wcNameSet.has(n));

                // In leaf mode, skip parent blocks from budget — only leaves get preview entries
                if (affectedByWc && !(leafOnly && hasChildren)) {
                    let total = 0;
                    if (info.isExt && info.extValues) {
                        total = info.extValues.length;
                        for (const name of allWcNames) {
                            const lv = (locked[name] && locked[name].length > 0) ? locked[name] : null;
                            if (lv) total *= lv.length;
                        }
                    } else if (!info.isExt && info.content) {
                        total = 1;
                        for (const name of allWcNames) {
                            const lv = (locked[name] && locked[name].length > 0) ? locked[name] : null;
                            if (lv) total *= lv.length;
                        }
                    }
                    if (total > 0) {
                        pathTotals.push({ path, total, isExt: info.isExt, extValues: info.extValues, allWcNames, content: info.content });
                    }
                }

                if (item.after) {
                    const maxBranches = 3;
                    const children = item.after.length > maxBranches ? item.after.slice(0, maxBranches) : item.after;
                    discover(children, path, allWcNames);
                }
            }
        };
        discover(textItems, null, []);

        if (pathTotals.length === 0) return [];

        // Distribute budget across affected paths
        const numPaths = pathTotals.length;
        const perPath = Math.max(1, Math.floor(maxEntries / numPaths));
        let remainder = maxEntries - perPath * numPaths;
        const pathBudgets = {};
        for (const pt of pathTotals) {
            pathBudgets[pt.path] = perPath + (remainder > 0 ? 1 : 0);
            if (remainder > 0) remainder--;
        }

        // Pass 2: Collect entries per path with per-path budgets
        const results = [];
        for (const pt of pathTotals) {
            const budget = pathBudgets[pt.path];
            let vars;
            if (pt.isExt && pt.extValues) {
                vars = PU.editorMode._computeExtTextVariations(
                    pt.extValues, pt.allWcNames, lookup, locked, wcIndices, pt.path, budget
                );
            } else {
                vars = PU.editorMode._computeBlockVariations(
                    pt.content, pt.allWcNames, lookup, locked, wcIndices, 'summary', pt.path, budget
                );
            }

            const pathEntries = [];
            for (const v of vars) {
                if (pathEntries.length >= budget) break;
                pathEntries.push({
                    text: v.text,
                    sources: [{ blockPath: v.blockPath, comboKey: v.comboKey }],
                    _preview: true
                });
            }

            // Per-path overflow on last entry
            const pathOverflow = pt.total - pathEntries.length;
            if (pathOverflow > 0 && pathEntries.length > 0) {
                pathEntries[pathEntries.length - 1]._previewOverflow = pathOverflow;
            }

            for (const e of pathEntries) results.push(e);
        }

        return results;
    },

    // ── Chip Hover Preview ─────────────────────────────────────────────

    _chipHoverActive: false,

    /** Show preview entries for a new (unlocked) wildcard value on chip hover. */
    _showChipHoverPreview(wcName, value) {
        // Don't overwrite staging entries with hover preview
        if (PU.editorMode._lockPopupState) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !prompt.text) return;

        const lookup = PU.preview.getFullWildcardLookup();
        const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        const compId = PU.state.previewMode.compositionId;
        const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);

        // Build hypothetical locked state: just this one value
        const locked = {};
        const realLocked = PU.state.previewMode.lockedValues;
        for (const k of Object.keys(realLocked)) {
            locked[k] = [...realLocked[k]];
        }
        locked[wcName] = [value];

        const MAX_PREVIEW = 3;
        const results = PU.editorMode._collectSubtreePreview(
            prompt.text, wcName, lookup, locked, wcIndices, MAX_PREVIEW
        );

        if (results.length > 0) {
            PU.state.previewMode.previewCompositions = results;
            PU.editorMode._chipHoverActive = true;
            PU.compositions.render();
        }
    },

    /** Clear ephemeral hover preview entries (does not touch staging). */
    _clearChipHoverPreview() {
        if (!PU.editorMode._chipHoverActive) return;
        PU.editorMode._chipHoverActive = false;
        // Don't clear if staging is active — staging owns previewCompositions
        if (PU.editorMode._lockPopupState) return;
        PU.state.previewMode.previewCompositions = [];
        PU.compositions.render();
    },

    /** Highlight a specific value's text within a composition item. */
    _highlightValueInItem(item, value) {
        const leafEl = item.querySelector('.pu-compositions-leaf-text');
        if (!leafEl) return;
        const text = leafEl.textContent;
        const idx = text.toLowerCase().indexOf(value.toLowerCase());
        if (idx < 0) {
            // Inherited wildcard — value not in text, use background highlight
            item.classList.add('pu-compositions-wc-highlight');
            return;
        }
        // Store original HTML for restore
        if (!leafEl.dataset.originalHtml) {
            leafEl.dataset.originalHtml = leafEl.innerHTML;
        }
        const esc = PU.blocks.escapeHtml;
        const before = esc(text.substring(0, idx));
        const match = esc(text.substring(idx, idx + value.length));
        const after = esc(text.substring(idx + value.length));
        leafEl.innerHTML = `${before}<mark class="pu-wc-value-mark">${match}</mark>${after}`;
    },

    /** Remove all inline value highlights, restoring original text. */
    _clearValueHighlights() {
        document.querySelectorAll('.pu-compositions-leaf-text[data-original-html]').forEach(el => {
            el.innerHTML = el.dataset.originalHtml;
            delete el.dataset.originalHtml;
        });
        // Clear background highlights from inherited wildcard matches
        document.querySelectorAll('.pu-compositions-item.pu-compositions-wc-highlight').forEach(el => {
            el.classList.remove('pu-compositions-wc-highlight');
        });
    },

    // ── Lock Popup ──────────────────────────────────────────────────────

    // Multi-wildcard staging state.
    // { staged: { wcName: { initialChecked: Set, currentChecked: Set, currentVal: string } },
    //   popupWc: string|null, anchor: Element|null, blockPath: string|null,
    //   inactiveShuffled: {}, shuffleIndex: number }
    _lockPopupState: null,

    /** Hide the lock popup UI element without clearing staging state. */
    _hideLockPopup() {
        const popup = document.querySelector('[data-testid="pu-lock-popup"]');
        if (popup) popup.style.display = 'none';
    },

    /** Open the lock popup for a wildcard. */
    openLockPopup(wcName, anchorEl) {
        PU.overlay.dismissPopovers();

        // Re-find anchor if it was detached by dismissPopovers() → compositions.render()
        if (!anchorEl.isConnected) {
            const candidates = document.querySelectorAll(`.pu-wc-slot[data-wc="${wcName}"]`);
            for (const c of candidates) {
                if (c.getBoundingClientRect().width > 0) { anchorEl = c; break; }
            }
        }

        const lookup = PU.preview.getFullWildcardLookup();
        const allVals = lookup[wcName];
        if (!allVals || allVals.length === 0) return;

        // Discover which block this wildcard slot belongs to
        const previewBlock = anchorEl.closest('.pu-preview-block[data-path]');
        const blockPath = previewBlock ? previewBlock.dataset.path : null;

        // Ensure staging state exists
        if (!PU.editorMode._lockPopupState) {
            PU.state.previewMode.previewCompositions = [];
            PU.editorMode._lockPopupState = {
                staged: {},
                popupWc: null,
                anchor: null,
                blockPath: null,
                inactiveShuffled: {},
                shuffleIndex: 0
            };
        }

        const state = PU.editorMode._lockPopupState;
        state.popupWc = wcName;
        state.anchor = anchorEl;
        if (blockPath) state.blockPath = blockPath;
        state.inactiveShuffled = PU.editorMode._buildInactiveShuffled(wcName, blockPath, lookup);

        // Ensure per-wildcard staging entry exists
        if (!state.staged[wcName]) {
            const locked = PU.state.previewMode.lockedValues;
            const lockedVals = (locked[wcName] && locked[wcName].length > 0) ? locked[wcName] : null;

            const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
            const compId = PU.state.previewMode.compositionId;
            const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);
            const currentIdx = wcIndices[wcName] || 0;
            const currentVal = allVals[currentIdx];

            const initialChecked = new Set(lockedVals ? lockedVals : [currentVal]);
            state.staged[wcName] = {
                initialChecked: new Set(initialChecked),
                currentChecked: new Set(initialChecked),
                currentVal
            };
        }

        const currentVal = state.staged[wcName].currentVal;
        PU.editorMode._renderLockPopupContent(wcName, allVals, currentVal);

        const popup = document.querySelector('[data-testid="pu-lock-popup"]');
        if (!popup) return;

        // Position below the triggering element
        const rect = anchorEl.getBoundingClientRect();
        const container = popup.parentElement;
        const anchorInContainer = container.contains(anchorEl);

        if (anchorInContainer) {
            const containerRect = container.getBoundingClientRect();
            popup.style.position = 'absolute';
            popup.style.left = Math.max(0, rect.left - containerRect.left + container.scrollLeft) + 'px';
            popup.style.top = (rect.bottom - containerRect.top + container.scrollTop + 4) + 'px';
        } else {
            popup.style.position = 'fixed';
            popup.style.left = Math.max(8, rect.left) + 'px';
            popup.style.top = Math.min(rect.bottom + 4, window.innerHeight - 500) + 'px';
        }
        popup.style.display = '';

        PU.overlay.showOverlay();
    },

    /** Render lock popup inner content. */
    _renderLockPopupContent(wcName, allVals, currentVal) {
        const popup = document.querySelector('[data-testid="pu-lock-popup"]');
        if (!popup || !PU.editorMode._lockPopupState) return;

        const state = PU.editorMode._lockPopupState;
        const wcStaged = state.staged[wcName];
        if (!wcStaged) return;
        const checked = wcStaged.currentChecked;

        // Compute impact from ALL staged wildcards
        const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        const locked = PU.state.previewMode.lockedValues;
        const hypothetical = { ...locked };
        for (const [wn, ws] of Object.entries(state.staged)) {
            hypothetical[wn] = ws.currentChecked.size === 0 ? [allVals[0]] : [...ws.currentChecked];
        }
        // Ensure current wildcard is correct (allVals may differ per wildcard)
        const lookup = PU.preview.getFullWildcardLookup();
        for (const [wn, ws] of Object.entries(state.staged)) {
            if (wn !== wcName && ws.currentChecked.size === 0) {
                const wVals = lookup[wn] || [];
                hypothetical[wn] = [wVals[0] || ''];
            }
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
            const eVal = PU.blocks.escapeHtml(val);
            html += `<div class="pu-lock-popup-item">
                <input type="checkbox" ${isChecked} data-val="${eVal}"
                       onchange="PU.editorMode._lockPopupToggle('${eVal.replace(/'/g, "\\'")}', this.checked)">
                <label onclick="this.previousElementSibling.click()" title="${eVal}">${eVal}</label>
            </div>`;
        }

        html += `</div>`;

        // Live preview section
        const previewHtml = PU.editorMode._buildLockPopupPreview(wcName, checked);
        if (previewHtml) html += previewHtml;

        // Check if selection differs from initial (committed) state
        const initial = wcStaged.initialChecked;
        const changed = checked.size !== initial.size || [...checked].some(v => !initial.has(v));

        // Build "Total Compositions: orig → new" footer
        const origTotal = PU.shared.computeLockedTotal(wildcardCounts, extTextCount, locked);
        const totalLabel = origTotal !== impact
            ? `Total Compositions: ${origTotal.toLocaleString()} \u2192 <strong>${impact.toLocaleString()}</strong>`
            : `Total Compositions: <strong>${impact.toLocaleString()}</strong>`;

        // Per-path computation disclosure
        const computationHtml = PU.editorMode._buildComputationBreakdown(wcName, hypothetical, extTextCount);

        html += `<div class="pu-lock-popup-footer" data-testid="pu-lock-popup-footer">
            <div class="pu-lock-popup-footer-info">
                <div data-testid="pu-lock-popup-footer-total">${totalLabel}</div>
                ${computationHtml ? `<details class="pu-lock-popup-computation" data-testid="pu-lock-popup-computation">
                    <summary>see computation</summary>
                    ${computationHtml}
                </details>` : ''}
            </div>
        </div>`;

        // Capture open states of disclosure elements before replacing innerHTML
        const prevDescOpen = popup.querySelector('[data-testid="pu-lock-popup-desc-disclosure"]')?.open;
        const prevCompOpen = popup.querySelector('[data-testid="pu-lock-popup-computation"]')?.open;

        popup.innerHTML = html;

        // Restore disclosure open states
        if (prevDescOpen) {
            const desc = popup.querySelector('[data-testid="pu-lock-popup-desc-disclosure"]');
            if (desc) desc.open = true;
        }
        if (prevCompOpen) {
            const comp = popup.querySelector('[data-testid="pu-lock-popup-computation"]');
            if (comp) comp.open = true;
        }
    },

    /** Toggle a value in the lock popup. */
    _lockPopupToggle(val, isChecked) {
        const state = PU.editorMode._lockPopupState;
        if (!state || !state.popupWc) return;
        const wcStaged = state.staged[state.popupWc];
        if (!wcStaged) return;
        if (isChecked) {
            wcStaged.currentChecked.add(val);
        } else {
            wcStaged.currentChecked.delete(val);
        }
        PU.editorMode._lockPopupUpdate();
    },

    /** Select all values in lock popup. */
    _lockPopupSelectAll() {
        const state = PU.editorMode._lockPopupState;
        if (!state || !state.popupWc) return;
        const wcStaged = state.staged[state.popupWc];
        if (!wcStaged) return;
        const lookup = PU.preview.getFullWildcardLookup();
        wcStaged.currentChecked = new Set(lookup[state.popupWc] || []);
        PU.editorMode._lockPopupUpdate();
    },

    /** Select only the current value in lock popup. */
    _lockPopupSelectOnly() {
        const state = PU.editorMode._lockPopupState;
        if (!state || !state.popupWc) return;
        const wcStaged = state.staged[state.popupWc];
        if (!wcStaged) return;
        wcStaged.currentChecked = new Set([wcStaged.currentVal]);
        PU.editorMode._lockPopupUpdate();
    },

    /** Re-render popup content and staging (preview only, no auto-commit). */
    _lockPopupUpdate() {
        const state = PU.editorMode._lockPopupState;
        if (!state) return;
        // Re-render popup if it's visible
        if (state.popupWc) {
            const lookup = PU.preview.getFullWildcardLookup();
            const allVals = lookup[state.popupWc] || [];
            const wcStaged = state.staged[state.popupWc];
            if (wcStaged) {
                PU.editorMode._renderLockPopupContent(state.popupWc, allVals, wcStaged.currentVal);
            }
        }
        // Update preview compositions in the compositions panel
        PU.editorMode._computePreviewCompositions();
        PU.compositions.render();
        PU.rightPanel.render(); // Sync chip staged/unstaged visual state
    },

    /** Apply current lock popup state to lockedValues and re-render preview. */
    _applyLockPopupState(stateOverride) {
        const state = stateOverride || PU.editorMode._lockPopupState;
        if (!state || !state.staged) return;
        const lookup = PU.preview.getFullWildcardLookup();
        const locked = PU.state.previewMode.lockedValues;
        const sw = PU.state.previewMode.selectedWildcards;
        if (!sw['*']) sw['*'] = {};

        // Apply ALL staged wildcards
        for (const [wcName, wcStaged] of Object.entries(state.staged)) {
            const allVals = lookup[wcName] || [];
            const current = wcStaged.currentChecked;

            if (current.size === 0) {
                locked[wcName] = [allVals[0]]; // Default to first value
            } else {
                locked[wcName] = [...current];
            }

            sw['*'][wcName] = locked[wcName][locked[wcName].length - 1];
        }

        // Reset show-more budgets — lock change invalidates allocation
        PU.state.previewMode.pathBudgets = {};

        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
        PU.rightPanel.renderOpsSection();
    },

    /** Check if any staged wildcard has unsaved changes. */
    _isLockPopupDirty() {
        const state = PU.editorMode._lockPopupState;
        if (!state || !state.staged) return false;
        for (const wcStaged of Object.values(state.staged)) {
            const initial = wcStaged.initialChecked;
            const current = wcStaged.currentChecked;
            if (current.size !== initial.size) return true;
            for (const v of current) {
                if (!initial.has(v)) return true;
            }
        }
        return false;
    },

    /** Cancel staging: discard all staged changes and close popup + staging column. */
    closeLockPopup() {
        PU.state.previewMode.previewCompositions = [];
        PU.editorMode._lockPopupState = null;
        PU.editorMode._hideLockPopup();
        PU.overlay.hideOverlay();
        PU.compositions.render();
        PU.rightPanel.render();
    },

    /** Commit staged selection to lockedValues and close popup + staging column. */
    commitLockPopup() {
        const state = PU.editorMode._lockPopupState;
        if (!state) return;
        PU.state.previewMode.previewCompositions = [];
        PU.editorMode._lockPopupState = null; // Clear before render so staging hides
        PU.editorMode._applyLockPopupState(state);
        PU.editorMode._hideLockPopup();
        PU.overlay.hideOverlay();
        PU.rightPanel.render();
    },

    /**
     * Stage a chip toggle from the right panel.
     * Accumulates across wildcards into _lockPopupState.staged.
     */
    stageChipToggle(wcName, value) {
        const lookup = PU.preview.getFullWildcardLookup();
        const allVals = lookup[wcName];
        if (!allVals || allVals.length === 0) return;

        // Ensure staging state exists
        if (!PU.editorMode._lockPopupState) {
            PU.state.previewMode.previewCompositions = [];
            PU.editorMode._lockPopupState = {
                staged: {},
                popupWc: null,
                anchor: null,
                blockPath: null,
                inactiveShuffled: {},
                shuffleIndex: 0
            };
        }

        const state = PU.editorMode._lockPopupState;

        // Ensure per-wildcard staging entry exists
        if (!state.staged[wcName]) {
            const locked = PU.state.previewMode.lockedValues;
            const lockedVals = (locked[wcName] && locked[wcName].length > 0) ? locked[wcName] : null;

            const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
            const compId = PU.state.previewMode.compositionId;
            const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);
            const currentIdx = wcIndices[wcName] || 0;
            const currentVal = allVals[currentIdx];

            const initialChecked = new Set(lockedVals ? lockedVals : [currentVal]);
            state.staged[wcName] = {
                initialChecked: new Set(initialChecked),
                currentChecked: new Set(initialChecked),
                currentVal
            };
        }

        // Toggle the value in currentChecked
        const current = state.staged[wcName].currentChecked;
        if (current.has(value)) {
            current.delete(value);
        } else {
            current.add(value);
        }

        // Recompute preview and render staging
        PU.editorMode._computePreviewCompositions();
        PU.compositions.render();
        PU.rightPanel.render();

        // Sync lock popup checkboxes if open for the same wildcard
        const popup = document.querySelector('[data-testid="pu-lock-popup"]');
        if (popup && popup.style.display !== 'none' && state.popupWc === wcName) {
            PU.editorMode._renderLockPopupContent(
                wcName, allVals, state.staged[wcName].currentVal
            );
        }
    },

    /** Build rotated inactive wildcard map for preview diversity.
     *  Uses shuffleIndex from state to rotate values deterministically. */
    _buildInactiveShuffled(wcName, blockPath, lookup) {
        const result = {};
        if (!blockPath) return result;
        const block = PU.editorMode._getBlockAtPath(
            PU.helpers.getActivePrompt()?.text || [], blockPath);
        if (!block || !block.content) return result;
        const offset = PU.editorMode._lockPopupState?.shuffleIndex ?? 0;
        block.content.replace(/__([a-zA-Z0-9_-]+)__/g, (match, name) => {
            if (name !== wcName && !result[name]) {
                const vals = lookup[name];
                if (vals && vals.length > 0) {
                    // Rotate values by offset for deterministic stepping
                    const rotated = [];
                    const len = vals.length;
                    const shift = ((offset % len) + len) % len; // handle negatives
                    for (let j = 0; j < len; j++) {
                        rotated.push(vals[(j + shift) % len]);
                    }
                    result[name] = rotated;
                }
            }
            return match;
        });
        return result;
    },

    /** Step prev/next through different inactive wildcard combinations. */
    stepLockPopupPreview(delta) {
        const state = PU.editorMode._lockPopupState;
        if (!state || !state.popupWc) return;
        state.shuffleIndex = (state.shuffleIndex || 0) + delta;
        const lookup = PU.preview.getFullWildcardLookup();
        state.inactiveShuffled = PU.editorMode._buildInactiveShuffled(
            state.popupWc, state.blockPath, lookup);
        PU.editorMode._lockPopupUpdate();
    },

    /** Copy resolved preview text to clipboard.
     *  Mirrors the compositions panel waterfall: ancestor chain + own text per variation.
     *  Uses the same resolution as resolvedVariations + buildBlockResolutions. */
    // ── Lock Popup Preview ──────────────────────────────────────────────

    /**
     * Build live preview HTML for the lock popup.
     * Shows resolved text for the clicked block (one line per checked value)
     * plus collapsed descendant disclosure.
     */
    _buildLockPopupPreview(wcName, checkedValues) {
        const state = PU.editorMode._lockPopupState;
        if (!state || !state.blockPath) return null;
        if (checkedValues.size === 0) return null;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !prompt.text) return null;

        const textItems = prompt.text;
        const blockPath = state.blockPath;
        const block = PU.editorMode._getBlockAtPath(textItems, blockPath);
        if (!block) return null;

        // Skip ext_text blocks (v1)
        if ('ext_text' in block) return null;

        const content = block.content || '';
        if (!content.includes(`__${wcName}__`)) return null;

        const lookup = PU.preview.getFullWildcardLookup();
        const esc = PU.blocks.escapeHtml;
        const checkedArr = [...checkedValues];
        const wcRegex = new RegExp(`__${wcName.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')}__`, 'g');
        const shuffled = state.inactiveShuffled || {};

        let html = '<div class="pu-lock-popup-preview" data-testid="pu-lock-popup-preview">';
        html += `<div class="pu-lock-popup-preview-label">Previewing ${checkedArr.length} value${checkedArr.length !== 1 ? 's' : ''}
            <span class="pu-lock-popup-preview-nav">
                <button class="pu-lock-popup-nav-btn" data-testid="pu-lock-popup-prev"
                    onclick="PU.editorMode.stepLockPopupPreview(-1)" title="Previous combination">\u25C0</button>
                <button class="pu-lock-popup-nav-btn" data-testid="pu-lock-popup-next"
                    onclick="PU.editorMode.stepLockPopupPreview(1)" title="Next combination">\u25B6</button>
            </span>
        </div>`;
        html += '<div class="pu-wc-inline-variations">';

        // ── Current block: one line per checked value (cap at 5) ──
        const maxShow = Math.min(checkedArr.length, 5);
        for (let i = 0; i < maxShow; i++) {
            const val = checkedArr[i];
            let resolved = content.replace(wcRegex, `{{${wcName}:${val}}}`);
            // Cycle inactive wildcards through shuffled values for diversity
            resolved = resolved.replace(/__([a-zA-Z0-9_-]+)__/g, (match, name) => {
                const s = shuffled[name];
                if (s && s.length > 0) return `{{${name}:${s[i % s.length]}}}`;
                const vals = lookup[name] || [];
                if (vals.length === 0) return match;
                return `{{${name}:${vals[0]}}}`;
            });
            const escaped = PU.preview.escapeHtmlPreservingMarkers(resolved);
            let pillHtml = PU.preview.renderWildcardPills(escaped);
            pillHtml = pillHtml.replace(
                new RegExp(`data-wc-name="${esc(wcName)}"`, 'g'),
                `data-wc-name="${esc(wcName)}" data-wc-active`
            );
            html += `<div class="pu-wc-inline-variation-item">
                <span class="pu-wc-inline-variation-index">${i + 1}.</span>
                <span class="pu-wc-inline-variation-text">${pillHtml}</span>
            </div>`;
        }
        if (checkedArr.length > maxShow) {
            html += `<div class="pu-lock-popup-preview-more">+${checkedArr.length - maxShow} more</div>`;
        }
        html += '</div>';

        // ── Descendants: show all non-ext_text descendant blocks, render up to 3 ──
        const descendantPaths = PU.editorMode._getAllDescendantPaths(block, blockPath);
        const firstVal = checkedArr[0];
        const textDescPaths = descendantPaths.filter(dPath => {
            const dBlock = PU.editorMode._getBlockAtPath(textItems, dPath);
            if (!dBlock || !dBlock.content) return false;
            if ('ext_text' in dBlock) return false;
            return true;
        });

        if (textDescPaths.length > 0) {
            let descHtml = '';
            const descMax = Math.min(textDescPaths.length, 3);
            for (let d = 0; d < descMax; d++) {
                const dPath = textDescPaths[d];
                const dBlock = PU.editorMode._getBlockAtPath(textItems, dPath);
                // Resolve the focused wildcard with the first checked value
                let resolved = dBlock.content.replace(wcRegex, `{{${wcName}:${firstVal}}}`);
                const dOffset = maxShow + d;
                // Resolve all other wildcards with shuffled values
                resolved = resolved.replace(/__([a-zA-Z0-9_-]+)__/g, (match, name) => {
                    const s = shuffled[name];
                    if (s && s.length > 0) return `{{${name}:${s[dOffset % s.length]}}}`;
                    const vals = lookup[name] || [];
                    if (vals.length === 0) return match;
                    return `{{${name}:${vals[0]}}}`;
                });
                const escaped = PU.preview.escapeHtmlPreservingMarkers(resolved);
                let pillHtml = PU.preview.renderWildcardPills(escaped);
                // Highlight the focused wildcard if it appears in this descendant
                pillHtml = pillHtml.replace(
                    new RegExp(`data-wc-name="${esc(wcName)}"`, 'g'),
                    `data-wc-name="${esc(wcName)}" data-wc-active`
                );
                const relPath = dPath.startsWith(blockPath + '.') ? dPath.slice(blockPath.length + 1) : dPath;
                const isLast = d === descMax - 1 && textDescPaths.length <= descMax;
                const connector = isLast ? '\u2514\u2500\u2500' : '\u251C\u2500\u2500';
                descHtml += `<div class="pu-wc-inline-variation-item pu-lock-popup-desc-item">
                    <span class="pu-wc-inline-variation-index" title="${esc(dPath)}">${connector}</span>
                    <span class="pu-wc-inline-variation-text">${pillHtml}</span>
                </div>`;
            }
            if (textDescPaths.length > descMax) {
                descHtml += `<div class="pu-lock-popup-preview-more">+${textDescPaths.length - descMax} more</div>`;
            }

            const n = textDescPaths.length;
            html += `<details class="pu-lock-popup-desc-section" data-testid="pu-lock-popup-desc-disclosure">
                <summary class="pu-lock-popup-desc-summary">${n} descendant block${n !== 1 ? 's' : ''}</summary>
                ${descHtml}
            </details>`;
        }

        html += '</div>';
        return html;
    },

    /**
     * Build per-path Cartesian breakdown HTML for the computation disclosure.
     * Walks the block tree depth-first, collecting wildcards and ext_text per root-to-leaf path.
     *
     * @param {string} focusedWc - the wildcard currently being edited (highlighted in accent)
     * @param {Object} hypothetical - { wcName: [values] } locked dimensions
     * @param {number} extTextCount - number of ext_text sources
     * @returns {string} HTML for the computation paths
     */
    _buildComputationBreakdown(focusedWc, hypothetical, extTextCount) {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text)) return '';
        const esc = PU.blocks.escapeHtml;

        const paths = [];

        // Walk tree depth-first, collecting wildcards along each root-to-leaf path
        const walk = (items, prefix, inheritedWcs) => {
            if (!Array.isArray(items)) return;
            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                const path = prefix != null ? `${prefix}.${i}` : String(i);
                const content = item.content || '';
                const isExt = 'ext_text' in item;

                // Collect wildcards from this block's content
                const blockWcs = [];
                if (!isExt) {
                    const matches = content.match(/__([a-zA-Z0-9_-]+)__/g) || [];
                    for (const m of matches) {
                        const name = m.replace(/__/g, '');
                        if (!blockWcs.includes(name)) blockWcs.push(name);
                    }
                }

                // Accumulated wildcards along this path
                const pathWcs = [...inheritedWcs, ...blockWcs.filter(w => !inheritedWcs.includes(w))];

                const hasChildren = item.after && item.after.length > 0;

                if (!hasChildren) {
                    // Leaf node — record this path
                    paths.push({
                        path,
                        wildcards: pathWcs,
                        extText: isExt ? item.ext_text : null,
                        extCount: isExt ? extTextCount : 0
                    });
                } else {
                    walk(item.after, path, pathWcs);
                }
            }
        };
        walk(prompt.text, null, []);

        if (paths.length === 0) return '';

        let html = '<div class="pu-lock-popup-computation-paths">';
        for (const p of paths) {
            const parts = [];
            // ext_text block shows as ext_name(count)
            if (p.extText && p.extCount > 1) {
                parts.push(`<span>${esc(p.extText)}(${p.extCount})</span>`);
            }
            // Wildcard dimensions along this path
            for (const wc of p.wildcards) {
                const dim = (hypothetical[wc] && hypothetical[wc].length > 0) ? hypothetical[wc].length : 1;
                const cls = wc === focusedWc ? ' class="pu-lock-popup-breakdown-active"' : '';
                parts.push(`<span${cls}>${esc(wc)}(${dim})</span>`);
            }
            if (parts.length === 0) {
                parts.push('<span>1</span>');
            }
            html += `<div class="pu-lock-popup-computation-path" title="${esc(p.path)}">${esc(p.path)}: ${parts.join(' \u00d7 ')}</div>`;
        }
        html += '</div>';
        return html;
    },

    // ── Lock Summary Strip ──────────────────────────────────────────────

    /** Render the lock summary strip showing all active locks. */
    _renderLockStrip() {
        const strip = document.querySelector('[data-testid="pu-lock-strip"]');
        if (!strip) return;

        const locked = PU.state.previewMode.lockedValues;
        const entries = Object.entries(locked).filter(([, vals]) => vals && vals.length > 1);

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

    /** Highlight wildcard slots that match a wildcard name (hover from lock strip). */
    _highlightPreviewBlocksForWildcard(wcName) {
        const body = document.querySelector('[data-testid="pu-preview-body"]');
        if (!body) return;
        body.classList.add('pu-preview-wc-highlighting');
        body.querySelectorAll(`.pu-wc-slot[data-wc="${wcName}"]`).forEach(slot => {
            slot.classList.add('pu-wc-slot-highlight');
        });
    },

    /** Clear wildcard slot highlight classes. */
    _clearPreviewBlockHighlights() {
        const body = document.querySelector('[data-testid="pu-preview-body"]');
        if (!body) return;
        body.classList.remove('pu-preview-wc-highlighting');
        body.querySelectorAll('.pu-wc-slot-highlight').forEach(el => {
            el.classList.remove('pu-wc-slot-highlight');
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

    /** Ensure every wildcard has a locked default (first value).
     *  If reset=true, wipe existing locks first. */
    _ensureLockDefaults(reset = false) {
        const lookup = PU.preview.getFullWildcardLookup();
        const locked = reset ? {} : PU.state.previewMode.lockedValues;
        if (reset) PU.state.previewMode.lockedValues = locked;
        for (const [name, values] of Object.entries(lookup)) {
            if ((!locked[name] || locked[name].length === 0) && values.length > 0) {
                locked[name] = [values[0]];
            } else if (locked[name] && values.length > 0) {
                // Filter out stale values no longer in the wildcard lookup (mutate in-place)
                for (let i = locked[name].length - 1; i >= 0; i--) {
                    if (!values.includes(locked[name][i])) locked[name].splice(i, 1);
                }
                if (locked[name].length === 0) locked[name].push(values[0]);
            }
        }
        // Clean stale entries for wildcards that no longer exist
        for (const name of Object.keys(locked)) {
            if (!lookup[name]) delete locked[name];
        }
    },

    /** Clear all wildcard locks (reset to first-value defaults). */
    clearAllLocks() {
        PU.editorMode._ensureLockDefaults(true);
        PU.state.previewMode.pathBudgets = {}; // Reset all show-more expansions
        PU.state.previewMode.magnifiedPath = null; // Clear magnifier
        const sw = PU.state.previewMode.selectedWildcards;
        delete sw['*'];
        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
        PU.rightPanel.renderOpsSection();
    },

    /** Expand all wildcards to their full value set (full Cartesian product). */
    expandAllLocks() {
        const lookup = PU.preview.getFullWildcardLookup();
        const locked = PU.state.previewMode.lockedValues;
        for (const [name, values] of Object.entries(lookup)) {
            if (values.length > 0) {
                locked[name] = [...values];
            }
        }
        PU.editorMode.renderPreview();
        PU.editorMode.renderSidebarPreview();
        PU.rightPanel.renderOpsSection();
    },

    /** Show more variations for a specific block path (doubles shown count, caps at 500). */
    showMoreVariations(blockPath) {
        const budgets = PU.state.previewMode.pathBudgets;
        // Use current compositions count for this path as the base (not the stored budget)
        const currentCount = PU.state.previewMode.compositions.filter(
            i => i.sources[0].blockPath === blockPath
        ).length;
        const base = Math.max(currentCount, budgets[blockPath] || 2);
        budgets[blockPath] = Math.min(base * 2, 500);
        PU.editorMode.renderPreview();
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

    /**
     * Get wildcard names actually referenced in block content or ext_text templates,
     * in depth-first encounter order (order they first appear walking the block tree).
     * @param {Array} textItems - Root text blocks from prompt
     * @returns {{ set: Set<string>, ordered: string[] }} Used names as set + encounter-ordered array
     */
    _getUsedWildcardNames(textItems) {
        const seen = new Set();
        const ordered = [];
        const wcPattern = /__([a-zA-Z0-9_-]+)__/g;

        const prompt = PU.helpers.getActivePrompt();
        const extPrefix = prompt?.ext || PU.helpers.getActiveJob()?.defaults?.ext || '';
        const cache = PU.state.previewMode._extTextCache || {};

        function addName(name) {
            if (!seen.has(name)) { seen.add(name); ordered.push(name); }
        }

        function scanContent(text) {
            wcPattern.lastIndex = 0;
            let m;
            while ((m = wcPattern.exec(text)) !== null) addName(m[1]);
        }

        // Depth-first walk: block content + ext_text entries + children
        function walk(blocks) {
            if (!Array.isArray(blocks)) return;
            for (const block of blocks) {
                if (block.content) scanContent(block.content);
                if ('ext_text' in block && block.ext_text) {
                    const extName = block.ext_text;
                    const needsPrefix = extPrefix && !extName.startsWith(extPrefix + '/');
                    const cacheKey = needsPrefix ? `${extPrefix}/${extName}` : extName;
                    const extData = cache[cacheKey];
                    if (extData && Array.isArray(extData.text)) {
                        for (const entry of extData.text) {
                            scanContent(typeof entry === 'string' ? entry : (entry?.content || ''));
                        }
                    }
                }
                if (block.after) walk(block.after);
            }
        }
        walk(textItems);

        return { set: seen, ordered };
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

        // Filter to wildcards used in block content/ext_text, in prompt encounter order
        const { set: usedSet, ordered: usedOrdered } = PU.editorMode._getUsedWildcardNames(textItems);
        // Use encounter order, but only include names that exist in the full lookup
        const filteredNames = usedOrdered.filter(name => lookup[name]);
        const lockedValues = PU.state.previewMode.lockedValues || {};

        // Get current composition indices for active chip highlighting
        const compId = PU.state.previewMode.compositionId;
        const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);

        // Build wildcard-to-block map for bulb icons (show bulb when 2+ total blocks)
        const totalBlocks = PU.rightPanel._countAllBlocks(textItems);
        const wcBlockMap = totalBlocks >= 2 ? PU.editorMode._buildPreviewWcBlockMap(textItems) : {};
        const focusedWildcards = PU.state.previewMode.focusedWildcards;

        let html = '';
        html += `<div class="pu-rp-bt-title" data-testid="pu-rp-bt-wc-title">WILDCARDS</div>`;
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
                    PU.editorMode._clearValueHighlights();
                    PU.editorMode._clearChipHoverPreview();
                    PU.editorMode.toggleSidebarLock(wcName, val);
                }
            });
        });

        // Hover individual chip → inline-highlight value text or preview-add
        container.querySelectorAll('.pu-rp-preview-wc-panel .pu-rp-wc-v').forEach(chip => {
            chip.addEventListener('mouseenter', (e) => {
                e.stopPropagation();
                const wcName = chip.dataset.wcName;
                const val = chip.dataset.value;
                if (!wcName || val === undefined) return;
                const needle = wcName + '=' + val;

                // Clear any entry-level highlights first
                document.querySelectorAll('.pu-compositions-wc-highlight').forEach(el => {
                    el.classList.remove('pu-compositions-wc-highlight');
                });
                PU.editorMode._clearValueHighlights();

                // Find existing composition items that contain this exact value
                let matchCount = 0;
                document.querySelectorAll('.pu-compositions-item[data-combo-key]').forEach(item => {
                    if (item.dataset.comboKey.split('|').some(pair => pair === needle)) {
                        // Highlight only the value text within the item
                        PU.editorMode._highlightValueInItem(item, val);
                        matchCount++;
                    }
                });

                // If no matches — this value is new, show ephemeral preview entries
                if (matchCount === 0) {
                    PU.editorMode._showChipHoverPreview(wcName, val);
                }
            });
            chip.addEventListener('mouseleave', () => {
                PU.editorMode._clearValueHighlights();
                PU.editorMode._clearChipHoverPreview();
            });
        });

        // Hover wildcard entry header → highlight all matching composition items
        container.querySelectorAll('.pu-rp-preview-wc-panel .pu-rp-wc-entry-header').forEach(header => {
            header.addEventListener('mouseenter', () => {
                const entry = header.closest('.pu-rp-wc-entry');
                const wcName = entry ? entry.dataset.wcName : null;
                if (!wcName) return;
                document.querySelectorAll('.pu-compositions-item[data-combo-key]').forEach(item => {
                    if (item.dataset.comboKey.includes(wcName + '=')) {
                        item.classList.add('pu-compositions-wc-highlight');
                    }
                });
            });
        });
        container.querySelectorAll('.pu-rp-preview-wc-panel .pu-rp-wc-entry').forEach(entry => {
            entry.addEventListener('mouseleave', () => {
                document.querySelectorAll('.pu-compositions-wc-highlight').forEach(el => {
                    el.classList.remove('pu-compositions-wc-highlight');
                });
                PU.editorMode._clearChipHoverPreview();
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
                    <button class="pu-gear-preset-btn${mode === 'export' ? ' active' : ''}"
                            onclick="PU.editorMode.setPreset('export')">Export</button>
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

// Register lock popup with overlay lifecycle — only hides the popup UI,
// staging persists until explicit Cancel/Confirm in the staging column
PU.overlay.registerPopover('lockPopup', () => PU.editorMode._hideLockPopup());

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
        tabStrip: mode === 'export' ? 'visible' : 'hidden',
        activeTab: PU.state.ui.rightPanelTab,
        layers: { ...PU.state.ui.editorLayers },
        editorContentVisible: rpEditor ? rpEditor.style.display !== 'none' : null,
        previewContentVisible: rpPreview ? rpPreview.style.display !== 'none' : null,
        opsVariant: ops ? ops.dataset.debugVariant : null,
        opsTotal: ops ? ops.dataset.debugTotal : null
    };
};
