/**
 * PromptyUI - Preview
 *
 * Live preview popup for showing resolved variations.
 * Also handles Preview Mode (checkpoint list view).
 */

PU.preview = {
    // ============================================
    // Block Resolution Functions (Resolved Tree View)
    // ============================================

    /**
     * Convert composition ID to wildcard indices using odometer logic.
     * Matches v4's composition_to_indices() in webui/v4/server/api/modal.py:41-77
     *
     * Order: ext_text OUTERMOST (slowest), wildcards ALPHABETICAL (fastest)
     *
     * Example: ext_text=3, wildcards={mood: 2, pose: 4}, Total=24
     *   comp 0  → ext=0, mood=0, pose=0
     *   comp 1  → ext=0, mood=0, pose=1
     *   comp 4  → ext=0, mood=1, pose=0
     *   comp 8  → ext=1, mood=0, pose=0
     *   comp 24 → wraps to comp 0
     *
     * @param {number} composition - The composition ID
     * @param {number} extTextCount - Number of ext_text values (or 1 if none)
     * @param {Object} wildcardCounts - Dict of {wildcardName: count}
     * @returns {[number, Object]} - [ext_text_idx, {wildcardName: idx}]
     */
    compositionToIndices(composition, extTextCount, wildcardCounts) {
        extTextCount = Math.max(1, extTextCount || 1);
        const sortedWc = Object.keys(wildcardCounts).sort();
        const dimensions = [extTextCount, ...sortedWc.map(n => Math.max(1, wildcardCounts[n] || 1))];

        let total = 1;
        for (const d of dimensions) {
            total *= d;
        }

        let idx = total > 0 ? composition % total : 0;

        const indices = [];
        for (let i = dimensions.length - 1; i >= 0; i--) {
            indices.unshift(idx % dimensions[i]);
            idx = Math.floor(idx / dimensions[i]);
        }

        const wcIndices = {};
        sortedWc.forEach((name, i) => {
            wcIndices[name] = indices[i + 1];
        });

        return [indices[0], wcIndices];
    },

    /**
     * Convert composition ID to bucket indices.
     * Each composition maps to a unique build scope (bucket combination).
     *
     * Mental Model:
     *   ext_text: 4 values, ext_text_max=2 → 2 buckets
     *   pose: 5 values, wc_max=2 → 3 buckets
     *   Total bucket compositions = 2 × 3 = 6
     *
     *   comp 0 → ext_bucket=0, pose_bucket=0 → ext[0], pose[0]
     *   comp 1 → ext_bucket=0, pose_bucket=1 → ext[0], pose[2]  ← jumps to next pose bucket!
     *   comp 2 → ext_bucket=0, pose_bucket=2 → ext[0], pose[4]
     *   comp 3 → ext_bucket=1, pose_bucket=0 → ext[2], pose[0]  ← jumps to next ext bucket!
     *
     * Key insight:
     * - Dropdown = navigate WITHIN bucket (fine-grained)
     * - Composition = jump BETWEEN buckets (coarse-grained, new build scope)
     *
     * @param {number} composition - The composition ID
     * @param {number} extTextCount - Number of ext_text values
     * @param {number} extTextMax - Max ext_text per bucket (0 = no bucketing)
     * @param {Object} wildcardCounts - Dict of {wildcardName: count}
     * @param {number} wcMax - Max wildcards per bucket (0 = no bucketing)
     * @returns {Object} - {extBucketIdx, wcBucketIndices, extValueIdx, wcValueIndices, totalBuckets}
     */
    bucketCompositionToIndices(composition, extTextCount, extTextMax, wildcardCounts, wcMax, wcMaxMap) {
        // Per-wildcard effective max: wcMaxMap[name] || wcMax
        const effectiveMax = (name) => (wcMaxMap && wcMaxMap[name]) || wcMax;

        // Calculate bucket counts
        const extBucketCount = extTextMax > 0 ? Math.ceil(extTextCount / extTextMax) : 1;

        const sortedWc = Object.keys(wildcardCounts).sort();
        const wcBucketCounts = {};
        for (const name of sortedWc) {
            const em = effectiveMax(name);
            wcBucketCounts[name] = em > 0 ? Math.ceil(wildcardCounts[name] / em) : 1;
        }

        // Apply odometer on bucket dimensions
        const bucketDimensions = [extBucketCount, ...sortedWc.map(n => wcBucketCounts[n])];

        let total = bucketDimensions.reduce((a, b) => a * b, 1);
        let idx = total > 0 ? composition % total : 0;

        const indices = [];
        for (let i = bucketDimensions.length - 1; i >= 0; i--) {
            indices.unshift(idx % bucketDimensions[i]);
            idx = Math.floor(idx / bucketDimensions[i]);
        }

        // Convert bucket indices to value indices (uses per-wildcard max)
        const extBucketIdx = indices[0];
        const extValueIdx = extBucketIdx * extTextMax;

        const wcBucketIndices = {};
        const wcValueIndices = {};
        sortedWc.forEach((name, i) => {
            const em = effectiveMax(name);
            wcBucketIndices[name] = indices[i + 1];
            wcValueIndices[name] = indices[i + 1] * em;
        });

        return {
            extBucketIdx,
            wcBucketIndices,
            extValueIdx,
            wcValueIndices,
            totalBuckets: total
        };
    },

    /**
     * Get wildcard counts from lookup for odometer calculations
     * @returns {Object} - Dict of {wildcardName: count}
     */
    getWildcardCounts() {
        const wildcardLookup = PU.helpers.getWildcardLookup();
        const wildcardCounts = {};
        for (const wcName of Object.keys(wildcardLookup)) {
            wildcardCounts[wcName] = wildcardLookup[wcName].length;
        }
        return wildcardCounts;
    },

    /**
     * Collect all ext_text names from a prompt tree
     * Recursively scans blocks for ext_text references
     * @param {Array} blocks - Array of text blocks
     * @returns {Array} - Unique ext_text names found
     */
    collectExtTextNames(blocks) {
        const names = new Set();

        function traverse(blockList) {
            if (!Array.isArray(blockList)) return;

            for (const block of blockList) {
                if ('ext_text' in block) {
                    names.add(block.ext_text);
                }
                if (block.after && Array.isArray(block.after)) {
                    traverse(block.after);
                }
            }
        }

        traverse(blocks);
        return [...names];
    },

    /**
     * Simple seeded random number generator (mulberry32)
     * Returns a function that generates deterministic random numbers 0-1
     * @deprecated Use compositionToIndices() for wildcard selection instead
     */
    seededRandom(seed) {
        return function() {
            let t = seed += 0x6D2B79F5;
            t = Math.imul(t ^ t >>> 15, t | 1);
            t ^= t + Math.imul(t ^ t >>> 7, t | 61);
            return ((t ^ t >>> 14) >>> 0) / 4294967296;
        };
    },


    /**
     * Generate semantic node ID matching v4's path format.
     * Exposed as shared method for use by focus mode's editPathToSemanticPath.
     *
     * Format:
     * - Wildcard nodes: "mood~pose" (wildcards sorted alphabetically, joined with ~)
     * - ext_text nodes: "ext_name"
     * - Content without wildcards: "slug[idx]" (first 20 chars of slugified content)
     */
    generateNodeId(block, siblingIndex) {
        if ('ext_text' in block) {
            return block.ext_text;
        } else if ('content' in block) {
            const content = block.content || '';
            const wcMatches = content.match(/__([a-zA-Z0-9_-]+)__/g) || [];
            const uniqueWcs = [...new Set(wcMatches.map(m => m.replace(/__/g, '')))];

            if (uniqueWcs.length > 0) {
                return uniqueWcs.sort().join('~');
            } else {
                // Slug-based ID
                const clean = (content || '')
                    .toLowerCase()
                    .replace(/[^a-z0-9]+/g, '-')
                    .replace(/^-+|-+$/g, '')
                    .slice(0, 20);
                const slug = clean || 'content';
                return `${slug}[${siblingIndex}]`;
            }
        }
        return `node[${siblingIndex}]`;
    },

    /**
     * Build resolved HTML + dropdown data for each block in the tree.
     * Returns Map<path, { resolvedHtml, wildcardDropdowns }>
     * Caches ext_text data in PU.state after first load.
     */
    async buildBlockResolutions(textItems, options) {
        const resolutions = new Map();
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return resolutions;

        const job = PU.helpers.getActiveJob();
        const compositionId = PU.state.previewMode.compositionId;

        // Step 1: Collect and load ext_text content (with caching)
        const extTextNames = PU.preview.collectExtTextNames(textItems);
        const extPrefix = prompt.ext || job?.defaults?.ext || '';

        // Use cached ext_text data if available
        if (!PU.state.previewMode._extTextCache) {
            PU.state.previewMode._extTextCache = {};
        }
        const extTextData = {};
        for (const extName of extTextNames) {
            // Avoid double-prefixing when extName already includes the ext prefix
            const needsPrefix = extPrefix && !extName.startsWith(extPrefix + '/');
            const cacheKey = needsPrefix ? `${extPrefix}/${extName}` : extName;
            if (PU.state.previewMode._extTextCache[cacheKey]) {
                extTextData[extName] = PU.state.previewMode._extTextCache[cacheKey];
            } else {
                try {
                    const fullPath = needsPrefix ? `${extPrefix}/${extName}` : extName;
                    const data = await PU.api.loadExtension(fullPath);
                    extTextData[extName] = data;
                    PU.state.previewMode._extTextCache[cacheKey] = data;
                } catch (e) {
                    console.warn(`Failed to load ext_text: ${extName}`, e);
                    extTextData[extName] = { text: [], wildcards: [] };
                }
            }
        }

        // Step 2: Compute ext_text count (warn on empty ext_text, once per name)
        if (!PU.preview._emptyExtTextWarned) PU.preview._emptyExtTextWarned = new Set();
        let actualExtTextCount = 0;
        for (const extName of Object.keys(extTextData)) {
            const data = extTextData[extName];
            if (data.text && Array.isArray(data.text)) {
                if (data.text.length === 0 && !PU.preview._emptyExtTextWarned.has(extName)) {
                    PU.preview._emptyExtTextWarned.add(extName);
                    PU.actions.showToast(`ext_text "${extName}" has no text values — check the path`, 'warning');
                }
                actualExtTextCount += data.text.length;
            }
        }
        actualExtTextCount = actualExtTextCount || 1;
        PU.state.previewMode.extTextCount = actualExtTextCount;

        // Step 3: Build wildcard lookup (prompt + extension wildcards)
        const wildcardLookup = PU.helpers.getWildcardLookup();
        for (const extName of Object.keys(extTextData)) {
            const extWildcards = extTextData[extName].wildcards || [];
            for (const wc of extWildcards) {
                if (wc.name && wc.text && !wildcardLookup[wc.name]) {
                    wildcardLookup[wc.name] = Array.isArray(wc.text) ? wc.text : [wc.text];
                }
            }
        }

        const wildcardCounts = {};
        for (const wcName of Object.keys(wildcardLookup)) {
            wildcardCounts[wcName] = wildcardLookup[wcName].length;
        }

        // Step 4: Get odometer indices (simple — no bucketed mode in UI)
        let extIdx, odometerIndices;
        [extIdx, odometerIndices] = PU.preview.compositionToIndices(compositionId, actualExtTextCount, wildcardCounts);

        const allSelectedOverrides = (options && options.ignoreOverrides)
            ? {}
            : (PU.state.previewMode.selectedWildcards || {});

        // Helper: get block text
        function getBlockText(block) {
            if ('content' in block) {
                return block.content || '';
            } else if ('ext_text' in block) {
                const extName = block.ext_text;
                const data = extTextData[extName];
                if (data && data.text && data.text.length > 0) {
                    const wrappedIdx = extIdx % data.text.length;
                    return data.text[wrappedIdx];
                }
                return `[ext: ${extName} - no content]`;
            }
            return '';
        }

        // Helper: resolve wildcards in text (per-block overrides)
        function resolveText(text, blockPath) {
            if (!text) return { resolved: '', wildcards: [] };

            const globalOverrides = allSelectedOverrides['*'] || {};
            const blockSpecific = allSelectedOverrides[blockPath] || {};
            const blockOverrides = { ...globalOverrides, ...blockSpecific };
            const resolvedWildcards = [];
            const resolved = text.replace(/__([a-zA-Z0-9_-]+)__/g, (match, wcName) => {
                const values = wildcardLookup[wcName];
                if (values && values.length > 0) {
                    let value, idx;
                    if (blockOverrides[wcName] !== undefined) {
                        value = blockOverrides[wcName];
                        idx = values.indexOf(value);
                        if (idx === -1) idx = 0;
                    } else {
                        idx = odometerIndices[wcName] !== undefined ? odometerIndices[wcName] : 0;
                        value = values[idx % values.length];
                    }
                    resolvedWildcards.push({ name: wcName, value, index: idx, isOverride: blockOverrides[wcName] !== undefined });
                    return `{{${wcName}:${value}}}`;
                }
                return match;
            });

            return { resolved, wildcards: resolvedWildcards };
        }

        // Accumulated text helpers
        function stripMarkers(text) {
            return text.replace(/\{\{[^:]+:([^}]+)\}\}/g, '$1');
        }
        function smartJoin(parent, child) {
            if (!parent) return child;
            if (!child) return parent;
            const seps = [',', ' ', '\n', '\t'];
            if (seps.some(s => parent.trimEnd().endsWith(s)) || seps.some(s => child.trimStart().startsWith(s)))
                return parent + child;
            return parent.trimEnd() + ' ' + child.trimStart();
        }

        // Step 5: Traverse tree and build resolutions
        function traverse(blocks, pathPrefix, parentAccText) {
            if (!Array.isArray(blocks)) return;

            blocks.forEach((block, idx) => {
                const path = pathPrefix ? `${pathPrefix}.${idx}` : String(idx);
                const blockText = getBlockText(block);
                const { resolved, wildcards } = resolveText(blockText, path);

                // Compute accumulated text
                const plainText = stripMarkers(resolved);
                const accumulatedText = smartJoin(parentAccText, plainText);

                // Extract dropdown data
                const dropdowns = PU.preview.extractBlockDropdowns(blockText, odometerIndices, wildcardLookup);

                // Build resolved HTML
                const resolvedHtml = PU.blocks.renderResolvedTextWithDropdowns(resolved, dropdowns, path);

                resolutions.set(path, {
                    resolvedHtml,
                    resolvedMarkerText: resolved,
                    wildcardDropdowns: dropdowns,
                    wildcards,
                    plainText,
                    accumulatedText,
                    parentAccumulatedText: parentAccText || ''
                });

                // Recurse into children
                if (block.after && block.after.length > 0) {
                    traverse(block.after, path, accumulatedText);
                }
            });
        }

        traverse(textItems, '', '');
        return resolutions;
    },

    /**
     * Compute terminal outputs by collecting leaf paths from each root block
     * and producing the cartesian product across roots.
     * @param {Array} textItems - Root text blocks
     * @param {Map} resolutions - Map from buildBlockResolutions
     * @returns {Array<{label: string, text: string}>}
     */
    computeTerminalOutputs(textItems, resolutions) {
        if (!textItems || !resolutions || resolutions.size === 0) return [];

        function smartJoin(parent, child) {
            if (!parent) return child;
            if (!child) return parent;
            const seps = [',', ' ', '\n', '\t'];
            if (seps.some(s => parent.trimEnd().endsWith(s)) || seps.some(s => child.trimStart().startsWith(s)))
                return parent + child;
            return parent.trimEnd() + ' ' + child.trimStart();
        }

        // Collect leaf paths for a single root block
        function collectLeaves(block, path) {
            const leaves = [];
            if (block.after && block.after.length > 0) {
                block.after.forEach((child, idx) => {
                    const childPath = `${path}.${idx}`;
                    leaves.push(...collectLeaves(child, childPath));
                });
            } else {
                leaves.push(path);
            }
            return leaves;
        }

        // Get leaf sets per root
        const rootLeafSets = [];
        textItems.forEach((block, idx) => {
            const path = String(idx);
            const leaves = collectLeaves(block, path);
            rootLeafSets.push(leaves);
        });

        // Cartesian product across root leaf sets
        const MAX_OUTPUTS = 50;
        const outputs = [];
        const seen = new Set();

        function cartesian(rootIdx, currentLabels, currentText) {
            if (outputs.length >= MAX_OUTPUTS) return;

            if (rootIdx >= rootLeafSets.length) {
                const text = currentText;
                if (!seen.has(text)) {
                    seen.add(text);
                    outputs.push({ label: currentLabels.join(' + '), text });
                }
                return;
            }

            for (const leafPath of rootLeafSets[rootIdx]) {
                if (outputs.length >= MAX_OUTPUTS) return;
                const res = resolutions.get(leafPath);
                if (!res) continue;
                const newText = smartJoin(currentText, res.accumulatedText);
                cartesian(rootIdx + 1, [...currentLabels, leafPath], newText);
            }
        }

        cartesian(0, [], '');
        return outputs;
    },

    /**
     * Extract wildcard dropdowns from block text.
     * Shows ALL values — block dropdowns are unrestricted for preview exploration.
     */
    extractBlockDropdowns(text, odometerIndices, wildcardLookup) {
        const dropdowns = [];
        const wcMatches = text.match(/__([a-zA-Z0-9_-]+)__/g) || [];
        const seen = new Set();

        const uniqueNames = [];
        wcMatches.forEach(match => {
            const name = match.replace(/__/g, '');
            if (!seen.has(name)) {
                seen.add(name);
                uniqueNames.push(name);
            }
        });
        uniqueNames.sort();

        uniqueNames.forEach(name => {
            const allValues = wildcardLookup[name] || [];
            const currentIndex = odometerIndices[name] || 0;

            dropdowns.push({
                name: name,
                values: allValues,
                count: allValues.length,
                currentIndex: currentIndex
            });
        });
        return dropdowns;
    },

    /**
     * Convert wildcard markers to pill HTML
     * Converts {{wildcard:value}} markers to styled pill spans
     */
    renderWildcardPills(markedText) {
        if (!markedText) return '';

        // Convert {{wildcard:value}} markers to pill HTML
        return markedText.replace(/\{\{([^:]+):([^}]+)\}\}/g, (match, name, value) => {
            return `<span class="pu-wc-pill" data-wc-name="${PU.blocks.escapeHtml(name)}" title="Wildcard: ${PU.blocks.escapeHtml(name)}">${PU.blocks.escapeHtml(value)}</span>`;
        });
    },

    /**
     * Mark wildcard values in resolved text with {{name:value}} markers.
     * Takes plain resolved text + wildcard_values dict from API.
     * Sorts entries by value length descending to prevent partial matches.
     * Two-pass: replace with null-byte placeholders, then with {{name:value}} markers.
     */
    markWildcardValues(text, wildcardValues) {
        if (!text || !wildcardValues || Object.keys(wildcardValues).length === 0) return text;

        // Sort entries by value length descending (prevents partial matches)
        const entries = Object.entries(wildcardValues)
            .filter(([, value]) => value && value.length > 0)
            .sort((a, b) => b[1].length - a[1].length);

        if (entries.length === 0) return text;

        // Pass 1: replace values with null-byte placeholders
        let result = text;
        const placeholders = [];
        entries.forEach(([name, value], idx) => {
            const placeholder = `\x00${idx}\x00`;
            placeholders.push({ placeholder, name, value });
            // Replace all occurrences of the value
            const escapedValue = value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            result = result.replace(new RegExp(escapedValue, 'g'), placeholder);
        });

        // Pass 2: replace placeholders with {{name:value}} markers
        placeholders.forEach(({ placeholder, name, value }) => {
            while (result.includes(placeholder)) {
                result = result.replace(placeholder, `{{${name}:${value}}}`);
            }
        });

        return result;
    },

    /**
     * Escape HTML while preserving {{name:value}} markers.
     * Extracts markers as placeholders before escaping, then restores them.
     */
    escapeHtmlPreservingMarkers(text) {
        if (!text) return '';

        // Extract {{name:value}} markers as placeholders
        const markers = [];
        let result = text.replace(/\{\{([^:]+):([^}]+)\}\}/g, (match) => {
            const idx = markers.length;
            markers.push(match);
            return `\x01${idx}\x01`;
        });

        // Escape HTML on the rest
        result = PU.blocks.escapeHtml(result);

        // Restore markers
        markers.forEach((marker, idx) => {
            result = result.replace(`\x01${idx}\x01`, marker);
        });

        return result;
    },

    /**
     * Normalize wildcard name: "money_type" → "Money Type", "role" → "Role"
     */
    normalizeWildcardName(name) {
        return name.split(/[-_]/).map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
    },

    /**
     * Update ext_text_max and re-render
     */
    async updateExtTextMax(newVal) {
        const val = parseInt(newVal, 10);
        if (isNaN(val) || val < 1) return;

        PU.state.previewMode.extTextMax = val;
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.rightPanel.render();
        PU.actions.updateUrl();
    },

    /**
     * Update wildcards_max and re-render
     */
    async updateWildcardsMax(newVal) {
        const val = parseInt(newVal, 10);
        if (isNaN(val) || val < 0) return;

        PU.state.previewMode.wildcardsMax = val;
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.rightPanel.render();
        PU.actions.updateUrl();
    },

    /**
     * Update composition ID and re-render
     */
    async updateCompositionId(newId) {
        const id = parseInt(newId, 10);
        if (isNaN(id) || id < 0) return;

        PU.state.previewMode.compositionId = id;
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.actions.updateUrl();
    },

    /**
     * Randomize composition ID (dice button)
     */
    async randomizeCompositionId() {
        const randomId = Math.floor(Math.random() * 10000);
        PU.state.previewMode.compositionId = randomId;

        const compositionInput = document.querySelector('[data-testid="pu-odometer-composition"]');
        if (compositionInput) {
            compositionInput.value = randomId;
        }

        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.actions.updateUrl();
    },

    /**
     * Compute total number of compositions from ext_text count and wildcard counts.
     * @param {number} extTextCount - Number of ext_text values (or 1 if none)
     * @param {Object} wildcardCounts - Dict of {wildcardName: count}
     * @returns {number} Total compositions (product of all dimensions)
     */
    computeTotalCompositions(extTextCount, wildcardCounts) {
        let total = Math.max(1, extTextCount || 1);
        for (const name of Object.keys(wildcardCounts)) {
            total *= Math.max(1, wildcardCounts[name] || 1);
        }
        return total;
    },

    /**
     * Compute effective total compositions respecting bucketing.
     * When wcMax > 0 or extTextMax > 1, dimensions are ceil-divided into buckets.
     * @param {number} extTextCount - Raw ext_text value count
     * @param {Object} wildcardCounts - Dict of {wildcardName: rawCount}
     * @param {number} extTextMax - Bucket size for ext_text (default 1 = no bucketing)
     * @param {number} wcMax - Bucket size for wildcards (0 = no bucketing)
     * @returns {number} Effective total (bucketed if applicable)
     */
    computeEffectiveTotal(extTextCount, wildcardCounts, extTextMax, wcMax, wcMaxMap) {
        extTextMax = Math.max(1, extTextMax || 1);
        wcMax = wcMax || 0;
        const effectiveMax = (name) => (wcMaxMap && wcMaxMap[name]) || wcMax;

        if (wcMax <= 0 && (!wcMaxMap || Object.keys(wcMaxMap).length === 0) && extTextMax <= 1) {
            return PU.preview.computeTotalCompositions(extTextCount, wildcardCounts);
        }

        // Bucketed: ceil-divide each dimension (per-wildcard effective max)
        let total = Math.max(1, Math.ceil((extTextCount || 1) / extTextMax));
        for (const name of Object.keys(wildcardCounts)) {
            const raw = Math.max(1, wildcardCounts[name] || 1);
            const em = effectiveMax(name);
            total *= em > 0 ? Math.max(1, Math.ceil(raw / em)) : raw;
        }
        return total;
    },

    /**
     * Count filtered compositions analytically.
     * For each wildcard, multiply the number of selected values (or full count if no filter).
     * @param {Object} wildcardCounts - { wcName: count }
     * @param {Object} selectedValues - { wcName: Set(allowedValues) } — empty = all selected
     * @param {number} extTextCount - Number of ext_text values
     * @returns {number} Filtered total
     */
    countFilteredCompositions(wildcardCounts, selectedValues, extTextCount) {
        const extTextMax = PU.state.previewMode.extTextMax || 1;
        const wcMax = PU.state.previewMode.wildcardsMax || 0;
        const total = PU.preview.computeEffectiveTotal(extTextCount, wildcardCounts, extTextMax, wcMax);

        if (!selectedValues || Object.keys(selectedValues).length === 0) {
            return total;
        }

        if (wcMax <= 0 && extTextMax <= 1) {
            // Non-bucketed: analytical product of selected counts
            let filtered = Math.max(1, extTextCount || 1);
            for (const [name, count] of Object.entries(wildcardCounts)) {
                const selected = selectedValues[name];
                const effectiveCount = selected ? selected.size : count;
                filtered *= Math.max(1, effectiveCount);
            }
            return filtered;
        }

        // Bucketed: iterate all compositions (total is small in bucketed mode)
        let count = 0;
        for (let i = 0; i < total; i++) {
            if (PU.preview.compositionPassesFilter(i, extTextCount, wildcardCounts, selectedValues)) {
                count++;
            }
        }
        return count;
    },

    /**
     * Check if a composition passes the multi-select filter.
     * Bucket-aware: uses bucketCompositionToIndices when wcMax > 0 to check
     * the actual displayed value per composition.
     * @param {number} compId - Composition ID
     * @param {number} extTextCount - Number of ext_text values
     * @param {Object} wildcardCounts - { wcName: count }
     * @param {Object} selectedValues - { wcName: Set(allowedValues) }
     * @returns {boolean} True if composition matches all filter constraints
     */
    compositionPassesFilter(compId, extTextCount, wildcardCounts, selectedValues) {
        if (!selectedValues || Object.keys(selectedValues).length === 0) return true;

        const fullLookup = PU.preview.getFullWildcardLookup();

        let wcIndices;
        [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);

        for (const [wcName, filterSet] of Object.entries(selectedValues)) {
            const allValues = fullLookup[wcName];
            if (!allValues) continue;
            const idx = wcIndices[wcName];
            if (idx === undefined) continue;
            const value = allValues[idx % allValues.length];
            if (!filterSet.has(value)) return false;
        }
        return true;
    },

    /**
     * Clear stale block-level overrides whose values no longer exist in the wildcard lookup.
     * Called after composition changes to keep editor consistent.
     */
    clearStaleBlockOverrides() {
        const fullLookup = PU.preview.getFullWildcardLookup();

        for (const [blockPath, overrides] of Object.entries(PU.state.previewMode.selectedWildcards)) {
            for (const [wcName, pinnedValue] of Object.entries(overrides)) {
                const allValues = fullLookup[wcName];
                if (!allValues || !allValues.includes(pinnedValue)) {
                    delete overrides[wcName];
                }
            }
            if (Object.keys(overrides).length === 0) {
                delete PU.state.previewMode.selectedWildcards[blockPath];
            }
        }
    },

    /**
     * Get the full wildcard lookup merging prompt + extension wildcards.
     * Uses cached extension data from _extTextCache (populated by buildBlockResolutions).
     * @returns {Object} Dict of {wildcardName: [value1, value2, ...]}
     */
    getFullWildcardLookup() {
        const lookup = PU.helpers.getWildcardLookup();
        const cache = PU.state.previewMode._extTextCache || {};

        for (const cacheKey of Object.keys(cache)) {
            const data = cache[cacheKey];
            if (data && data.wildcards) {
                for (const wc of data.wildcards) {
                    if (wc.name && wc.text && !lookup[wc.name]) {
                        lookup[wc.name] = Array.isArray(wc.text) ? wc.text : [wc.text];
                    }
                }
            }
        }
        return lookup;
    },

    /**
     * Sample N unique composition IDs evenly spaced across the composition space.
     * Always includes currentId. Deterministic (no randomness).
     * @param {number} total - Total number of compositions
     * @param {number} n - Max samples to return
     * @param {number} currentId - The current composition ID (always included)
     * @returns {Array<number>} Array of composition IDs
     */
    sampleCompositionIds(total, n, currentId) {
        if (total <= n) {
            // Return all IDs
            const ids = [];
            for (let i = 0; i < total; i++) ids.push(i);
            return ids;
        }

        const ids = new Set();
        ids.add(currentId % total);

        // Evenly spaced samples across the composition space
        const step = total / n;
        for (let i = 0; i < n && ids.size < n; i++) {
            ids.add(Math.floor(i * step) % total);
        }

        return [...ids];
    },

    /**
     * Build terminal outputs from multiple sampled compositions.
     * Produces diverse outputs by varying non-pinned wildcards.
     * @param {Array} textItems - Root text blocks
     * @param {Map} primaryResolutions - Resolutions from current composition
     * @param {number} maxSamples - Max compositions to sample (default 20)
     * @returns {Promise<{outputs: Array, total: number}>}
     */
    async buildMultiCompositionOutputs(textItems, primaryResolutions, maxSamples = 20) {
        const extTextCount = PU.state.previewMode.extTextCount || 1;
        const wildcardLookup = PU.helpers.getWildcardLookup();
        const wildcardCounts = {};
        for (const wcName of Object.keys(wildcardLookup)) {
            wildcardCounts[wcName] = wildcardLookup[wcName].length;
        }

        const total = PU.preview.computeTotalCompositions(extTextCount, wildcardCounts);

        // Footer ignores pins — all wildcards are free dimensions
        const hasFreeVariation = Object.keys(wildcardCounts).length > 0 || extTextCount > 1;

        if (!hasFreeVariation || total <= 1) {
            const cleanRes = await PU.preview.buildBlockResolutions(textItems, { skipOdometerUpdate: true, ignoreOverrides: true });
            const outputs = PU.preview.computeTerminalOutputs(textItems, cleanRes);
            return { outputs, total: 1 };
        }

        const currentId = PU.state.previewMode.compositionId;
        const sampleIds = PU.preview.sampleCompositionIds(total, maxSamples, currentId);

        // Derive prompt-appearance order for wildcard names (matches header dropdown order)
        const orderedWcNames = [];
        const seenWc = new Set();
        for (const [, res] of primaryResolutions) {
            if (!res.wildcards) continue;
            for (const wc of res.wildcards) {
                if (wildcardCounts[wc.name] && !seenWc.has(wc.name)) {
                    seenWc.add(wc.name);
                    orderedWcNames.push(wc.name);
                }
            }
        }

        const allOutputTexts = new Set();
        const allOutputs = [];
        const MAX_UNIQUE = 50;

        for (const compId of sampleIds) {
            if (allOutputs.length >= MAX_UNIQUE) break;

            // Compute wildcard-index label for this composition
            const [compExtIdx, compWcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);
            const idxParts = orderedWcNames.map(n => compWcIndices[n]);
            if (extTextCount > 1) idxParts.unshift(compExtIdx);
            const versionLabel = idxParts.join('.');
            // Build expanded label with name=value pairs for hybrid hover
            const wcDetails = orderedWcNames.map(n => ({
                name: n,
                value: (wildcardLookup[n] && wildcardLookup[n][compWcIndices[n]]) || String(compWcIndices[n])
            }));
            if (extTextCount > 1) wcDetails.unshift({ name: 'ext', value: String(compExtIdx) });

            let resolutions;
            // Always rebuild with ignoreOverrides — footer is pin-independent
            const savedId = PU.state.previewMode.compositionId;
            PU.state.previewMode.compositionId = compId;
            resolutions = await PU.preview.buildBlockResolutions(textItems, {
                skipOdometerUpdate: true,
                ignoreOverrides: true
            });
            PU.state.previewMode.compositionId = savedId;

            const outputs = PU.preview.computeTerminalOutputs(textItems, resolutions);
            for (const out of outputs) {
                if (allOutputs.length >= MAX_UNIQUE) break;
                if (!allOutputTexts.has(out.text)) {
                    allOutputTexts.add(out.text);
                    // Use version label if wildcards exist, otherwise keep block-path label
                    const useVersionLabel = orderedWcNames.length > 0 || extTextCount > 1;
                    allOutputs.push({
                        label: useVersionLabel ? versionLabel : out.label,
                        wcDetails: useVersionLabel ? wcDetails : null,
                        text: out.text
                    });
                }
            }
        }

        return { outputs: allOutputs, total };
    },

    /**
     * Install global close-on-outside-click handler for dropdown menus.
     * Called once on init.
     */
    initDropdownCloseHandler() {
        document.addEventListener('click', (e) => {
            if (!e.target.closest('.pu-wc-dropdown-menu') &&
                !e.target.closest('.pu-wc-dropdown')) {
                const existing = document.querySelector('.pu-wc-dropdown-menu');
                if (existing) existing.remove();
            }
        });
    },

    /**
     * Toggle wildcard dropdown menu
     * Reads values from data-values attribute on the dropdown element
     */
    toggleWildcardDropdown(element) {
        const wcName = element.dataset.wc;
        const blockEl = element.closest('.pu-block[data-path]');
        const blockPath = blockEl ? blockEl.dataset.path : element.dataset.path;

        // Read values from data attribute
        let values = [];
        try {
            values = JSON.parse(element.dataset.values || '[]');
        } catch (e) {
            console.warn('Failed to parse dropdown values:', e);
            return;
        }

        if (!values.length) return;

        // Close existing dropdown
        const existing = document.querySelector('.pu-wc-dropdown-menu');
        if (existing) {
            existing.remove();
            if (existing.dataset.wc === wcName && existing.dataset.path === blockPath) {
                return;
            }
        }

        // Get current selected value (per-block)
        const blockOverrides = (PU.state.previewMode.selectedWildcards || {})[blockPath] || {};
        const currentValue = blockOverrides[wcName];

        // Create dropdown menu
        const menu = document.createElement('div');
        menu.className = 'pu-wc-dropdown-menu';
        menu.dataset.wc = wcName;
        menu.dataset.path = blockPath;
        menu.dataset.testid = `pu-wc-menu-${wcName}`;

        const isAnySelected = currentValue === undefined;
        const anyHtml = `<div class="pu-dropdown-item${isAnySelected ? ' selected' : ''}" data-testid="pu-wc-option-${PU.blocks.escapeHtml(wcName)}-any" data-wc="${PU.blocks.escapeHtml(wcName)}" data-value="*">* (Any ${PU.blocks.escapeHtml(PU.preview.normalizeWildcardName(wcName))})</div>`;
        menu.innerHTML = anyHtml + values.map((v, vIdx) => {
            const isSelected = !isAnySelected && v === currentValue;
            return `<div class="pu-dropdown-item${isSelected ? ' selected' : ''}" data-testid="pu-wc-option-${PU.blocks.escapeHtml(wcName)}-${vIdx}" data-wc="${PU.blocks.escapeHtml(wcName)}" data-value="${PU.blocks.escapeHtml(v)}">${PU.blocks.escapeHtml(v)}</div>`;
        }).join('');

        // Position the menu
        element.style.position = 'relative';
        element.appendChild(menu);

        // Handle selection
        menu.addEventListener('click', (e) => {
            const item = e.target.closest('.pu-dropdown-item');
            if (item) {
                e.stopPropagation();
                PU.preview.selectWildcardValue(item.dataset.wc, item.dataset.value, blockPath);
            }
        });
    },

    /**
     * Handle wildcard value selection - re-renders all blocks
     */
    async selectWildcardValue(wcName, value, blockPath) {
        if (!blockPath) return;
        // Update state — '*' means "Any" (un-pin this wildcard for this block)
        if (value === '*') {
            if (PU.state.previewMode.selectedWildcards[blockPath]) {
                delete PU.state.previewMode.selectedWildcards[blockPath][wcName];
                if (Object.keys(PU.state.previewMode.selectedWildcards[blockPath]).length === 0) {
                    delete PU.state.previewMode.selectedWildcards[blockPath];
                }
            }
        } else {
            if (!PU.state.previewMode.selectedWildcards[blockPath]) {
                PU.state.previewMode.selectedWildcards[blockPath] = {};
            }
            PU.state.previewMode.selectedWildcards[blockPath][wcName] = value;
        }

        // Close dropdown
        const menu = document.querySelector('.pu-wc-dropdown-menu');
        if (menu) menu.remove();

        // Re-render blocks instantly (no transitions)
        const container = document.querySelector('[data-testid="pu-blocks-container"]');
        if (container) container.classList.add('pu-no-transition');
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        if (container) {
            requestAnimationFrame(() => requestAnimationFrame(() => {
                container.classList.remove('pu-no-transition');
            }));
        }
    },

    /**
     * Clear all wildcard selections (reset to random)
     */
    async clearWildcardSelections() {
        PU.state.previewMode.selectedWildcards = {};

        // Re-render blocks instantly (no transitions)
        const container = document.querySelector('[data-testid="pu-blocks-container"]');
        if (container) container.classList.add('pu-no-transition');
        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        if (container) {
            requestAnimationFrame(() => requestAnimationFrame(() => {
                container.classList.remove('pu-no-transition');
            }));
        }
    },

};
