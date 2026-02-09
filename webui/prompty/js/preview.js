/**
 * PromptyUI - Preview
 *
 * Live preview popup for showing resolved variations.
 * Also handles Preview Mode (checkpoint list view).
 */

PU.preview = {
    // ============================================
    // Preview Mode Functions (Checkpoint List View)
    // ============================================

    /**
     * Enter preview mode - transforms editor into checkpoint list
     * Now async to support loading ext_text content
     */
    async enterPreviewMode() {
        // Build checkpoint data (now async to load ext_text)
        const checkpoints = await PU.preview.buildCheckpointData();
        PU.state.previewMode.checkpoints = checkpoints;
        PU.state.previewMode.active = true;

        // Hide editor, show preview mode
        const editorContent = document.querySelector('[data-testid="pu-editor-content"]');
        const previewMode = document.querySelector('[data-testid="pu-preview-mode"]');

        if (editorContent) editorContent.style.display = 'none';
        if (previewMode) previewMode.style.display = 'flex';

        // Update prompt title in preview mode
        const promptTitleEl = document.querySelector('[data-testid="pu-preview-prompt-title"]');
        if (promptTitleEl) {
            promptTitleEl.textContent = PU.state.activePromptId || 'No prompt';
        }

        // Update composition input with current value
        const compositionInput = document.querySelector('[data-testid="pu-composition-input"]');
        if (compositionInput) {
            compositionInput.value = PU.state.previewMode.compositionId;
        }

        // Update ext_text_max input
        const extTextMaxInput = document.querySelector('[data-testid="pu-ext-text-max-input"]');
        if (extTextMaxInput) {
            extTextMaxInput.value = PU.state.previewMode.extTextMax;
        }

        // Update ext_wildcards_max input
        const extWildcardsMaxInput = document.querySelector('[data-testid="pu-ext-wildcards-max-input"]');
        if (extWildcardsMaxInput) {
            extWildcardsMaxInput.value = PU.state.previewMode.extWildcardsMax;
        }

        // Render checkpoints
        PU.preview.renderCheckpointRows(checkpoints);

        // Update button state
        PU.preview.updateModeButton();

        // Update URL to include preview mode
        PU.actions.updateUrl();
    },

    /**
     * Exit preview mode - return to editor
     */
    exitPreviewMode() {
        PU.state.previewMode.active = false;

        // Show editor, hide preview mode
        const editorContent = document.querySelector('[data-testid="pu-editor-content"]');
        const previewMode = document.querySelector('[data-testid="pu-preview-mode"]');

        if (editorContent) editorContent.style.display = 'flex';
        if (previewMode) previewMode.style.display = 'none';

        // Update button state
        PU.preview.updateModeButton();

        // Update URL to remove preview mode
        PU.actions.updateUrl();
    },

    /**
     * Toggle between edit and preview mode
     */
    async togglePreviewMode() {
        if (PU.state.previewMode.active) {
            PU.preview.exitPreviewMode();
        } else {
            await PU.preview.enterPreviewMode();
        }
    },

    /**
     * Update mode toggle button text and visibility
     */
    updateModeButton() {
        const btn = document.querySelector('[data-testid="pu-mode-toggle-btn"]');
        if (btn) {
            // Show button only when a prompt is selected
            const prompt = PU.helpers.getActivePrompt();
            btn.style.display = prompt ? 'inline-flex' : 'none';

            if (PU.state.previewMode.active) {
                btn.innerHTML = '&#9998; Edit Mode';
            } else {
                btn.innerHTML = '&#128065; Preview';
            }
        }
    },

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
    bucketCompositionToIndices(composition, extTextCount, extTextMax, wildcardCounts, wcMax) {
        // Calculate bucket counts
        const extBucketCount = extTextMax > 0 ? Math.ceil(extTextCount / extTextMax) : 1;

        const sortedWc = Object.keys(wildcardCounts).sort();
        const wcBucketCounts = {};
        for (const name of sortedWc) {
            wcBucketCounts[name] = wcMax > 0 ? Math.ceil(wildcardCounts[name] / wcMax) : 1;
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

        // Convert bucket indices to value indices
        const extBucketIdx = indices[0];
        const extValueIdx = extBucketIdx * extTextMax;

        const wcBucketIndices = {};
        const wcValueIndices = {};
        sortedWc.forEach((name, i) => {
            wcBucketIndices[name] = indices[i + 1];
            wcValueIndices[name] = indices[i + 1] * wcMax;
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
     * Build checkpoint data from prompt tree
     * Returns array of terminal nodes with resolved text
     * Now async to support loading ext_text content from API
     */
    async buildCheckpointData() {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return [];

        const job = PU.helpers.getActiveJob();
        const checkpoints = [];
        const compositionId = PU.state.previewMode.compositionId;

        // Step 1: Collect and load ext_text content
        const extTextNames = PU.preview.collectExtTextNames(prompt.text || []);
        const extTextData = {}; // {extName: {text: [...], wildcards: [...]}}

        // Get job's ext path prefix (e.g., "themes/pixel")
        const extPrefix = prompt.ext || job?.defaults?.ext || '';

        for (const extName of extTextNames) {
            try {
                // Build full path: ext_prefix + "/" + extName (or just extName if no prefix)
                const fullPath = extPrefix ? `${extPrefix}/${extName}` : extName;
                const data = await PU.api.loadExtension(fullPath);
                extTextData[extName] = data;
            } catch (e) {
                console.warn(`Failed to load ext_text: ${extName}`, e);
                extTextData[extName] = { text: [], wildcards: [] };
            }
        }

        // Step 2: Compute actual ext_text count from loaded data
        // Total ext_text values across all extensions
        let actualExtTextCount = 0;
        for (const extName of Object.keys(extTextData)) {
            const data = extTextData[extName];
            // Extensions can have 'text' as array
            if (data.text && Array.isArray(data.text)) {
                actualExtTextCount += data.text.length;
            }
        }
        actualExtTextCount = actualExtTextCount || 1; // At least 1 for odometer

        // Store computed count in state for use by renderCheckpointRows
        PU.state.previewMode.extTextCount = actualExtTextCount;

        // Step 3: Build wildcard lookup and counts, including ext_text wildcards
        // Start with prompt wildcards
        const wildcardLookup = PU.helpers.getWildcardLookup();

        // Merge extension wildcards into lookup
        for (const extName of Object.keys(extTextData)) {
            const extWildcards = extTextData[extName].wildcards || [];
            for (const wc of extWildcards) {
                if (wc.name && wc.text && !wildcardLookup[wc.name]) {
                    // Only add if not already defined in prompt
                    wildcardLookup[wc.name] = Array.isArray(wc.text) ? wc.text : [wc.text];
                }
            }
        }

        // Build wildcard counts for odometer calculation
        // ALWAYS use full wildcard counts - extWildcardsMax only limits BUILD scope, not PREVIEW scope
        // Per true_north_objectives.md: "ANY composition ID should map to the FULL wildcard space"
        const wildcardCounts = {};
        for (const wcName of Object.keys(wildcardLookup)) {
            wildcardCounts[wcName] = wildcardLookup[wcName].length;
        }

        // Step 4: Get bucket parameters
        // extTextMax = bucket size limit (user-controlled)
        // actualExtTextCount = computed from loaded data
        const extTextMax = PU.state.previewMode.extTextMax;
        const wcMax = PU.state.previewMode.extWildcardsMax;

        // Get odometer-based indices for this composition
        // When wcMax > 0, use bucket odometer - composition jumps between build scopes
        let extIdx, odometerIndices, bucketResult = null;
        if (wcMax > 0) {
            // Use bucket odometer - composition jumps between buckets
            // FIX: Use actualExtTextCount (count) and extTextMax (bucket size) separately
            bucketResult = PU.preview.bucketCompositionToIndices(
                compositionId, actualExtTextCount, extTextMax, wildcardCounts, wcMax
            );
            extIdx = bucketResult.extValueIdx;
            odometerIndices = bucketResult.wcValueIndices;
        } else {
            // Fallback to value odometer when no bucketing
            [extIdx, odometerIndices] = PU.preview.compositionToIndices(compositionId, actualExtTextCount, wildcardCounts);
        }

        // Update the odometer total display
        PU.preview.updateOdometerTotal(actualExtTextCount, wildcardCounts, extIdx, odometerIndices, bucketResult);

        // Helper to resolve wildcards in text using ODOMETER-based selection
        // Returns object with resolved text and wildcard tracking data
        // Respects user-selected overrides from selectedWildcards state
        function resolveTextWithTracking(text, pathSeed) {
            if (!text) return { text: '', wildcards: [] };

            const resolvedWildcards = [];
            const selectedOverrides = PU.state.previewMode.selectedWildcards || {};

            const resolvedText = text.replace(/__([a-zA-Z0-9_-]+)__/g, (match, wcName) => {
                const values = wildcardLookup[wcName];
                if (values && values.length > 0) {
                    let value, idx;

                    // Check for user-selected override first
                    if (selectedOverrides[wcName] !== undefined) {
                        value = selectedOverrides[wcName];
                        idx = values.indexOf(value);
                        if (idx === -1) idx = 0; // Fallback if value not found
                    } else {
                        // Use ODOMETER index (deterministic, not random)
                        idx = odometerIndices[wcName] !== undefined ? odometerIndices[wcName] : 0;
                        value = values[idx % values.length]; // Wrap around if index exceeds
                    }

                    // Track this resolution for pill rendering
                    resolvedWildcards.push({
                        name: wcName,
                        value: value,
                        index: idx,
                        isOverride: selectedOverrides[wcName] !== undefined
                    });

                    // Return temporary marker for pill rendering
                    return `{{${wcName}:${value}}}`;
                }
                return match; // Keep placeholder if undefined
            });

            return { text: resolvedText, wildcards: resolvedWildcards };
        }

        // Helper to get block text (content or ext_text reference)
        // Now uses loaded ext_text data and applies odometer index
        function getBlockText(block) {
            if ('content' in block) {
                return block.content || '';
            } else if ('ext_text' in block) {
                const extName = block.ext_text;
                const data = extTextData[extName];
                if (data && data.text && data.text.length > 0) {
                    // Apply ext_text odometer index (wrapping)
                    const wrappedIdx = extIdx % data.text.length;
                    return data.text[wrappedIdx];
                }
                return `[ext: ${extName} - no content]`;
            }
            return '';
        }

        /**
         * Generate a slug-based node ID from content text (for nodes without wildcards)
         * Matches v4/build-checkpoints.py generate_content_node_id()
         */
        function generateContentNodeId(content, siblingIndex) {
            // Clean and normalize text
            const clean = (content || '')
                .toLowerCase()
                .replace(/[^a-z0-9]+/g, '-')    // Replace non-alphanumeric with dash
                .replace(/^-+|-+$/g, '')         // Trim leading/trailing dashes
                .slice(0, 20);                   // Max 20 chars

            const slug = clean || 'content';
            return `${slug}[${siblingIndex}]`;
        }

        /**
         * Generate semantic node ID matching v4's path format.
         * This ensures PU and v4 produce identical path hashes for composition selection.
         *
         * Format:
         * - Wildcard nodes: "mood~pose" (wildcards sorted alphabetically, joined with ~)
         * - ext_text nodes: "ext_name"
         * - Content without wildcards: "slug[idx]" (first 20 chars of slugified content)
         */
        function generateNodeId(block, siblingIndex) {
            if ('ext_text' in block) {
                // ext_text node: use the ext_text name
                return block.ext_text;
            } else if ('content' in block) {
                const content = block.content || '';
                // Find wildcards in content
                const wcMatches = content.match(/__([a-zA-Z0-9_-]+)__/g) || [];
                const uniqueWcs = [...new Set(wcMatches.map(m => m.replace(/__/g, '')))];

                if (uniqueWcs.length > 0) {
                    // Has wildcards: join sorted wildcard names with ~
                    return uniqueWcs.sort().join('~');
                } else {
                    // No wildcards: use slug-based ID
                    return generateContentNodeId(content, siblingIndex);
                }
            }
            // Fallback
            return `node[${siblingIndex}]`;
        }

        /**
         * Smart join: direct concatenation if either text has separator at boundary.
         * Matches src/jobs.py smart spacing logic.
         */
        function smartJoin(parent, child) {
            if (!parent) return child;
            if (!child) return parent;

            const separators = [',', ' ', '\n', '\t'];
            const parentEndsWithSep = separators.some(s => parent.trimEnd().endsWith(s));
            const childStartsWithSep = separators.some(s => child.trimStart().startsWith(s));

            if (parentEndsWithSep || childStartsWithSep) {
                return parent + child;  // Direct concatenation
            }
            return parent.trimEnd() + ' ' + child.trimStart();  // Add space
        }

        // Count variations for a block (excluding parent-resolved wildcards)
        function countVariations(block, excludeWcNames = new Set()) {
            if ('content' in block) {
                const content = block.content || '';
                const wcMatches = content.match(/__([a-zA-Z0-9_-]+)__/g) || [];
                const uniqueWcs = [...new Set(wcMatches.map(m => m.replace(/__/g, '')))]
                    .filter(name => !excludeWcNames.has(name));  // Filter out parent wildcards
                let count = 1;
                uniqueWcs.forEach(wcName => {
                    const values = wildcardLookup[wcName];
                    if (values && values.length > 0) {
                        count *= values.length;
                    }
                });
                return count;
            } else if ('ext_text' in block) {
                // ext_text variations depend on extension content
                const max = block.ext_text_max || job?.defaults?.ext_text_max || 0;
                return max > 0 ? max : 1; // Simplified count
            }
            return 1;
        }

        // Get config count (from job defaults or estimate)
        function getConfigCount() {
            // This would normally come from lora configs
            // For now, return a placeholder
            return job?.loras?.length || 1;
        }

        // Extract wildcard dropdowns from block text
        // BUCKET MODEL: Show only values in the current bucket (sliding window)
        // odometerIndices provides the current wildcard indices for bucket calculation
        function extractWildcardDropdowns(text, odometerIndices) {
            const dropdowns = [];
            const wcMatches = text.match(/__([a-zA-Z0-9_-]+)__/g) || [];
            const seen = new Set();
            const wcMax = PU.state.previewMode.extWildcardsMax;

            // Get unique wildcard names in this text, sorted alphabetically
            const uniqueNames = [];
            wcMatches.forEach(match => {
                const name = match.replace(/__/g, '');
                if (!seen.has(name)) {
                    seen.add(name);
                    uniqueNames.push(name);
                }
            });
            uniqueNames.sort();

            // BUCKET MODEL: Calculate bucket from current composition's index
            // Show only values within the current bucket window (with wrapping)
            uniqueNames.forEach(name => {
                const allValues = wildcardLookup[name] || [];
                const currentIndex = odometerIndices[name] || 0;

                let values;
                if (wcMax > 0 && allValues.length > wcMax) {
                    // Calculate bucket from current index
                    const sharedBucket = Math.floor(currentIndex / wcMax);
                    const startIdx = sharedBucket * wcMax;

                    // Get values with wrapping to fill the bucket
                    values = [];
                    for (let i = 0; i < wcMax; i++) {
                        const idx = (startIdx + i) % allValues.length;
                        values.push(allValues[idx]);
                    }
                } else {
                    // No bucket limit or all values fit - show all
                    values = allValues;
                }

                dropdowns.push({
                    name: name,
                    values: values,                 // Show only bucket values
                    count: allValues.length,        // Total count for display
                    currentIndex: currentIndex      // Current composition's index
                });
            });
            return dropdowns;
        }

        // Generate text variations for a checkpoint using ODOMETER logic
        // Variations are always in fixed order starting from composition 0
        // The highlight moves based on current composition's bucket
        // excludeWcNames: Set of wildcard names already resolved by parent (keep as-is)
        function generateVariations(blockText, pathSeed, count, excludeWcNames = new Set()) {
            const variations = [];
            const selectedOverrides = PU.state.previewMode.selectedWildcards || {};

            for (let i = 0; i < count; i++) {
                // Always start from composition 0 for consistent ordering
                const [, varIndices] = PU.preview.compositionToIndices(i, actualExtTextCount, wildcardCounts);

                const varText = blockText.replace(/__([a-zA-Z0-9_-]+)__/g, (match, wcName) => {
                    // Keep parent-resolved wildcards as-is (they're already resolved in text)
                    if (excludeWcNames.has(wcName)) return match;

                    const values = wildcardLookup[wcName];
                    if (values && values.length > 0) {
                        // Check for user-selected override first
                        if (selectedOverrides[wcName] !== undefined) {
                            return selectedOverrides[wcName];
                        }
                        // Use ODOMETER index (deterministic)
                        const idx = varIndices[wcName] !== undefined ? varIndices[wcName] : 0;
                        return values[idx];
                    }
                    return match;
                });
                variations.push(varText);
            }
            return variations;
        }

        // Simple hash function for path string
        function hashPath(path) {
            let hash = 0;
            for (let i = 0; i < path.length; i++) {
                const char = path.charCodeAt(i);
                hash = ((hash << 5) - hash) + char;
                hash = hash & hash; // Convert to 32bit integer
            }
            return Math.abs(hash);
        }

        // Recursively traverse blocks to find terminal nodes
        // parentWildcards: Array of wildcard objects resolved by parent checkpoints
        function traverse(blocks, parentPath, parentResolvedText, parentRawText, parentWildcards = []) {
            if (!Array.isArray(blocks)) return;

            // Collect parent-resolved wildcard names for filtering
            const parentResolvedWcNames = new Set(parentWildcards.map(w => w.name));

            blocks.forEach((block, idx) => {
                // Use semantic node ID matching v4's path format
                const nodeId = generateNodeId(block, idx);
                const path = parentPath ? `${parentPath}/${nodeId}` : nodeId;
                const pathSeed = hashPath(path);
                const blockText = getBlockText(block);
                const { text: resolvedBlockText, wildcards } = resolveTextWithTracking(blockText, pathSeed);

                // Build full text (parent + this block)
                const fullRawText = parentRawText
                    ? smartJoin(parentRawText, blockText)
                    : blockText;
                const fullResolvedText = parentResolvedText
                    ? smartJoin(parentResolvedText, resolvedBlockText)
                    : resolvedBlockText;

                // Always add this node as a checkpoint (matching v4 behavior)
                const hasChildren = block.after && block.after.length > 0;

                // Generate variations based on actual wildcard count (excludes parent wildcards)
                const varCount = countVariations(block, parentResolvedWcNames);
                const rawVariations = varCount > 1
                    ? generateVariations(fullRawText, pathSeed, varCount, parentResolvedWcNames)
                    : [fullResolvedText.replace(/\{\{[^:]+:([^}]+)\}\}/g, '$1')];
                // Deduplicate variations (when wildcards are pinned, may produce duplicates)
                const variations = [...new Set(rawVariations)];

                // Extract wildcard dropdowns from THIS block only (not parent text)
                // Filter out parent-resolved wildcards
                // Pass odometerIndices for bucket-based value filtering
                const wildcardDropdowns = extractWildcardDropdowns(blockText, odometerIndices)
                    .filter(d => !parentResolvedWcNames.has(d.name));

                // All wildcards accumulated up to this point (parent + current)
                const allWildcards = [...parentWildcards, ...wildcards];

                checkpoints.push({
                    path: path,
                    fullText: fullResolvedText,
                    baseText: parentResolvedText || '',
                    newText: resolvedBlockText,
                    rawText: fullRawText,
                    wildcards: wildcards,  // Only this block's wildcards
                    parentWildcards: parentWildcards,  // Inherited from parent
                    variationCount: varCount,  // Only NEW wildcards count
                    configCount: getConfigCount(),
                    hasChildren: hasChildren,  // Mark parent nodes for styling
                    variations: variations,  // Array of resolved text variations
                    wildcardDropdowns: wildcardDropdowns  // Only NEW wildcards for dropdowns
                });

                // Continue traversing children if present
                if (hasChildren) {
                    traverse(block.after, path, fullResolvedText, fullRawText, allWildcards);
                }
            });
        }

        traverse(prompt.text || [], '', '', '', []);
        return checkpoints;
    },

    /**
     * Build output path using v4 formula
     * Formula: outputs/c{composition}/{prompt_id}/{path_string}
     */
    buildOutputPath(checkpoint) {
        const composition = PU.state.previewMode.compositionId;
        const promptId = PU.state.activePromptId;
        const pathString = checkpoint.path;

        return `outputs/c${composition}/${promptId}/${pathString}`;
    },

    /**
     * Build full image path (for reference)
     * v4 filename: {index:04d}_c{config}_{suffix}_{sampler}_{scheduler}.png
     */
    buildImagePath(checkpoint, imageIndex = 0, configIndex = 0) {
        const basePath = PU.preview.buildOutputPath(checkpoint);
        const filename = `${String(imageIndex).padStart(4, '0')}_c${configIndex}_base_euler_simple.png`;
        return `${basePath}/${filename}`;
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
     * Get composition-based color for visual distinction
     * Uses golden angle distribution for varied colors
     */
    getCompositionColor(compositionId) {
        // Golden angle (137.508°) for visual variety in sequential IDs
        const hue = (compositionId * 137.508) % 360;
        return `hsla(${hue}, 55%, 55%, 0.5)`;
    },

    /**
     * Normalize wildcard name: "money_type" → "Money Type", "role" → "Role"
     */
    normalizeWildcardName(name) {
        return name.split(/[-_]/).map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
    },

    /**
     * Build first line with wildcard dropdowns (uses FULL text for variations display)
     */
    buildFirstLineWithDropdowns(checkpoint) {
        let text = checkpoint.variations[0] || '';

        // Replace wildcards with dropdown spans
        checkpoint.wildcardDropdowns.forEach(wc => {
            const selectedOverrides = PU.state.previewMode.selectedWildcards || {};
            // Get the selected or first resolved value for this wildcard
            let selectedValue = selectedOverrides[wc.name];
            const isAny = selectedValue === undefined;
            if (!selectedValue && wc.values.length > 0) {
                // Find the value used in the first variation by matching
                const wcMatch = checkpoint.wildcards?.find(w => w.name === wc.name);
                selectedValue = wcMatch ? wcMatch.value : wc.values[0];
            }
            const displayValue = isAny ? `* (Any ${PU.preview.normalizeWildcardName(wc.name)})` : selectedValue;

            // BUCKET MODEL: Show "bucket_size/total" - value is always in bucket
            const countDisplay = wc.values.length < wc.count
                ? `${wc.values.length}/${wc.count}`
                : `${wc.count}`;

            // Create regex to find this specific value in text (word boundary match)
            const escapedValue = selectedValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            const valueRegex = new RegExp(`\\b${escapedValue}\\b`);

            if (valueRegex.test(text)) {
                const dropdownHtml = `<span class="pu-wc-dropdown" data-testid="pu-wc-dropdown-${PU.blocks.escapeHtml(wc.name)}" data-wc="${PU.blocks.escapeHtml(wc.name)}" data-path="${PU.blocks.escapeHtml(checkpoint.path)}">${PU.blocks.escapeHtml(displayValue)} <span class="pu-dropdown-arrow">▼</span><span class="pu-wc-count" data-testid="pu-wc-count-${PU.blocks.escapeHtml(wc.name)}">(${countDisplay})</span></span>`;
                text = text.replace(valueRegex, dropdownHtml);
            }
        });

        return text;
    },

    /**
     * Build NEW text portion with wildcard dropdowns
     * Uses cp.newText (only this checkpoint's contribution) instead of full variations
     */
    buildNewTextWithDropdowns(checkpoint) {
        // Start with newText which has {{wc:value}} markers
        let text = checkpoint.newText || '';

        // First, convert markers to resolved values
        // {{mood:sunny}} -> sunny
        text = text.replace(/\{\{([^:]+):([^}]+)\}\}/g, (match, wcName, value) => {
            // Check if this wildcard should have a dropdown
            const wc = checkpoint.wildcardDropdowns?.find(w => w.name === wcName);
            if (wc) {
                // Return a temporary marker for dropdown replacement
                return `__DROPDOWN_${wcName}__${value}__`;
            }
            // No dropdown, just return the resolved value
            return value;
        });

        // Now replace dropdown markers with actual dropdown HTML
        checkpoint.wildcardDropdowns?.forEach(wc => {
            const selectedOverrides = PU.state.previewMode.selectedWildcards || {};
            let selectedValue = selectedOverrides[wc.name];
            const isAny = selectedValue === undefined;
            if (!selectedValue && wc.values.length > 0) {
                const wcMatch = checkpoint.wildcards?.find(w => w.name === wc.name);
                selectedValue = wcMatch ? wcMatch.value : wc.values[0];
            }
            const displayValue = isAny ? `* (Any ${PU.preview.normalizeWildcardName(wc.name)})` : selectedValue;

            // BUCKET MODEL: Show "bucket_size/total" - value is always in bucket
            const countDisplay = wc.values.length < wc.count
                ? `${wc.values.length}/${wc.count}`
                : `${wc.count}`;

            const markerRegex = new RegExp(`__DROPDOWN_${wc.name}__([^_]+)__`, 'g');
            const dropdownHtml = `<span class="pu-wc-dropdown" data-testid="pu-wc-dropdown-${PU.blocks.escapeHtml(wc.name)}" data-wc="${PU.blocks.escapeHtml(wc.name)}" data-path="${PU.blocks.escapeHtml(checkpoint.path)}">${PU.blocks.escapeHtml(displayValue)} <span class="pu-dropdown-arrow">▼</span><span class="pu-wc-count" data-testid="pu-wc-count-${PU.blocks.escapeHtml(wc.name)}">(${countDisplay})</span></span>`;
            text = text.replace(markerRegex, dropdownHtml);
        });

        return text;
    },

    /**
     * Render checkpoint rows in preview mode
     */
    renderCheckpointRows(checkpoints) {
        const list = document.querySelector('[data-testid="pu-checkpoints-list"]');
        if (!list) return;

        // Update count in header - show total and breakdown
        const countEl = document.querySelector('[data-testid="pu-checkpoints-count"]');
        if (countEl) {
            const terminalCount = checkpoints.filter(cp => !cp.hasChildren).length;
            const parentCount = checkpoints.filter(cp => cp.hasChildren).length;
            if (parentCount > 0) {
                countEl.textContent = `(${checkpoints.length} total: ${parentCount} parent + ${terminalCount} terminal)`;
            } else {
                countEl.textContent = `(${checkpoints.length} total)`;
            }
        }

        if (checkpoints.length === 0) {
            list.innerHTML = `
                <div class="pu-inspector-empty">
                    No checkpoints found. Add content blocks to your prompt.
                </div>
            `;
            return;
        }

        // Count terminal vs parent nodes for stats display
        const terminalCount = checkpoints.filter(cp => !cp.hasChildren).length;
        const parentCount = checkpoints.filter(cp => cp.hasChildren).length;

        list.innerHTML = checkpoints.map((cp, idx) => {
            const outputPath = PU.preview.buildOutputPath(cp);
            const pathId = cp.path.replace(/\//g, '-');

            // Add visual distinction for parent nodes
            const parentClass = cp.hasChildren ? ' pu-checkpoint-parent' : '';
            const nodeTypeLabel = cp.hasChildren ? '[PARENT]' : '';

            // Build NEW text with dropdowns (only this checkpoint's contribution)
            const hasWildcards = cp.wildcardDropdowns && cp.wildcardDropdowns.length > 0;
            const newTextContent = hasWildcards
                ? PU.preview.buildNewTextWithDropdowns(cp)
                : PU.blocks.escapeHtml(cp.newText?.replace(/\{\{[^:]+:([^}]+)\}\}/g, '$1') || '');

            // Build display with separate styling for base vs new text (v4 homegrid style)
            // Base text (from parent): gray/muted
            // New text (this checkpoint): bold white/primary (only NEW content, not duplicated)
            const baseTextHtml = cp.baseText
                ? `<span class="pu-checkpoint-text-base">${PU.blocks.escapeHtml(cp.baseText.replace(/\{\{[^:]+:([^}]+)\}\}/g, '$1'))}</span> `
                : '';
            const newTextHtml = `<span class="pu-checkpoint-text-new">${newTextContent}</span>`;
            const checkpointTextHtml = baseTextHtml + newTextHtml;

            // Build variations list (show all if more than 1)
            // BUCKET MODEL: Highlight variations in the same bucket as current composition
            const compositionId = PU.state.previewMode.compositionId;
            const variationsHtml = cp.variations && cp.variations.length > 1
                ? `<div class="pu-checkpoint-variations" data-testid="pu-variations-${pathId}">
                    <div class="pu-variations-header" data-testid="pu-variations-header-${pathId}">Variations (${cp.variations.length}):</div>
                    ${cp.variations.map((v, vIdx) => {
                        const wcMax = PU.state.previewMode.extWildcardsMax;
                        const extTextCount = PU.state.previewMode.extTextCount; // Actual count from loaded data
                        const extTextMax = PU.state.previewMode.extTextMax;     // Bucket size limit
                        let inScope = true;
                        if (wcMax > 0) {
                            // Get indices for this variation using value odometer
                            const wildcardCounts = PU.preview.getWildcardCounts();
                            const [, varIndices] = PU.preview.compositionToIndices(vIdx, 1, wildcardCounts);

                            // Get current bucket indices using BUCKET odometer
                            // FIX: Use extTextCount (actual) and extTextMax (bucket size) separately
                            const bucketResult = PU.preview.bucketCompositionToIndices(
                                compositionId, extTextCount, extTextMax, wildcardCounts, wcMax
                            );

                            // BUCKET MODEL: Highlight if ALL variation indices are in the SAME BUCKET as current composition
                            inScope = Object.keys(varIndices).every(wcName => {
                                const varIdx = varIndices[wcName];
                                const currentBucket = bucketResult.wcBucketIndices[wcName] || 0;
                                const totalValues = wildcardCounts[wcName];
                                const bucketStart = currentBucket * wcMax;

                                // Check if varIdx is in the bucket (with wrapping)
                                for (let i = 0; i < wcMax; i++) {
                                    const bucketIdx = (bucketStart + i) % totalValues;
                                    if (varIdx === bucketIdx) return true;
                                }
                                return false;
                            });
                        }
                        return `<div class="pu-variation-item${inScope ? ' pu-in-build-scope' : ''}" data-testid="pu-variation-${pathId}-${vIdx}">• ${PU.blocks.escapeHtml(v)}</div>`;
                    }).join('')}
                   </div>`
                : '';

            return `
                <div class="pu-checkpoint-row${parentClass}" data-testid="pu-checkpoint-${pathId}" data-path="${PU.blocks.escapeHtml(cp.path)}">
                    <div class="pu-checkpoint-header" data-testid="pu-checkpoint-header-${pathId}">
                        <span class="pu-checkpoint-index" data-testid="pu-checkpoint-index-${pathId}">#${idx}</span>
                        <span class="pu-checkpoint-path-label" data-testid="pu-checkpoint-path-${pathId}">${PU.blocks.escapeHtml(cp.path)}</span>
                        ${nodeTypeLabel ? `<span class="pu-checkpoint-type" data-testid="pu-checkpoint-type-${pathId}">${nodeTypeLabel}</span>` : ''}
                        <span class="pu-checkpoint-stats" data-testid="pu-checkpoint-stats-${pathId}">${cp.variationCount} var × ${cp.configCount} cfg</span>
                    </div>
                    <div class="pu-checkpoint-first-line" data-testid="pu-first-line-${pathId}">${checkpointTextHtml}</div>
                    ${variationsHtml}
                    <div class="pu-checkpoint-output-path" data-testid="pu-output-path-${pathId}">
                        Path: ${outputPath}
                    </div>
                </div>
            `;
        }).join('');

        // Add click handlers for dropdowns
        PU.preview.attachDropdownHandlers();
    },

    /**
     * Update ext_text_max and rebuild checkpoints
     */
    async updateExtTextMax(newVal) {
        const val = parseInt(newVal, 10);
        if (isNaN(val) || val < 1) return;

        PU.state.previewMode.extTextMax = val;
        await PU.preview.rebuildCheckpoints();

        // Update URL with new ext_text value
        if (PU.state.previewMode.active) {
            PU.actions.updateUrl();
        }
    },

    /**
     * Update ext_wildcards_max and rebuild checkpoints
     * When > 0, overrides all wildcard counts (for testing odometer)
     */
    async updateExtWildcardsMax(newVal) {
        const val = parseInt(newVal, 10);
        if (isNaN(val) || val < 0) return;

        PU.state.previewMode.extWildcardsMax = val;
        await PU.preview.rebuildCheckpoints();

        // Update URL with new wc_max value
        if (PU.state.previewMode.active) {
            PU.actions.updateUrl();
        }
    },

    /**
     * Update the odometer total display showing composition breakdown
     * When bucketResult is provided (wc_max > 0), shows bucket-based info
     */
    updateOdometerTotal(extTextCount, wildcardCounts, extIdx, odometerIndices, bucketResult = null) {
        const totalEl = document.querySelector('[data-testid="pu-odometer-total"]');
        if (!totalEl) return;

        const sortedWc = Object.keys(wildcardCounts).sort();

        if (bucketResult) {
            // Bucket mode: show bucket breakdown
            const parts = [`ext_bucket=${bucketResult.extBucketIdx}`];
            for (const wc of sortedWc) {
                parts.push(`${wc}_bucket=${bucketResult.wcBucketIndices[wc]}`);
            }

            totalEl.textContent = `Total: ${bucketResult.totalBuckets} buckets | ${parts.join(', ')}`;

            // Build detailed tooltip showing both bucket and value info
            const wcMax = PU.state.previewMode.extWildcardsMax;
            const bucketDetails = sortedWc.map(w => {
                const bucketCount = Math.ceil(wildcardCounts[w] / wcMax);
                return `${w}: ${bucketCount} buckets (${wildcardCounts[w]} values / ${wcMax} max)`;
            }).join(', ');
            totalEl.title = `Bucket dimensions: ext=${Math.ceil(extTextCount / extTextCount)}, ${bucketDetails}`;
        } else {
            // Value mode: show value breakdown (original behavior)
            let total = extTextCount;
            for (const wc of sortedWc) {
                total *= wildcardCounts[wc];
            }

            const parts = [`ext=${extIdx}`];
            for (const wc of sortedWc) {
                parts.push(`${wc}=${odometerIndices[wc]}`);
            }

            totalEl.textContent = `Total: ${total} | ${parts.join(', ')}`;
            totalEl.title = `Dimensions: ext_text=${extTextCount}, ${sortedWc.map(w => `${w}=${wildcardCounts[w]}`).join(', ')}`;
        }
    },

    /**
     * Rebuild checkpoints (shared by all input handlers)
     * Now async to support loading ext_text content
     */
    async rebuildCheckpoints() {
        const checkpoints = await PU.preview.buildCheckpointData();
        PU.state.previewMode.checkpoints = checkpoints;
        PU.preview.renderCheckpointRows(checkpoints);
    },

    /**
     * Update composition ID and rebuild checkpoints
     * Composition affects both paths AND resolved prompts (odometer selection)
     */
    async updateCompositionId(newId) {
        const id = parseInt(newId, 10);
        if (isNaN(id) || id < 0) return;

        PU.state.previewMode.compositionId = id;
        await PU.preview.rebuildCheckpoints();

        // Update URL with new composition
        if (PU.state.previewMode.active) {
            PU.actions.updateUrl();
        }
    },

    /**
     * Randomize composition ID (dice button)
     */
    async randomizeCompositionId() {
        // Generate random composition ID between 0 and 9999
        const randomId = Math.floor(Math.random() * 10000);
        PU.state.previewMode.compositionId = randomId;

        // Update input field
        const compositionInput = document.querySelector('[data-testid="pu-composition-input"]');
        if (compositionInput) {
            compositionInput.value = randomId;
        }

        // Rebuild checkpoints with new composition (affects resolved prompts)
        const checkpoints = await PU.preview.buildCheckpointData();
        PU.state.previewMode.checkpoints = checkpoints;
        PU.preview.renderCheckpointRows(checkpoints);

        // Update URL with new composition
        if (PU.state.previewMode.active) {
            PU.actions.updateUrl();
        }
    },

    /**
     * Attach click handlers for wildcard dropdowns
     */
    attachDropdownHandlers() {
        const dropdowns = document.querySelectorAll('.pu-wc-dropdown');
        dropdowns.forEach(dropdown => {
            dropdown.addEventListener('click', (e) => {
                e.stopPropagation();
                PU.preview.toggleWildcardDropdown(dropdown);
            });
        });

        // Close dropdown when clicking outside
        document.addEventListener('click', (e) => {
            if (!e.target.closest('.pu-wc-dropdown-menu') && !e.target.closest('.pu-wc-dropdown')) {
                const existing = document.querySelector('.pu-wc-dropdown-menu');
                if (existing) existing.remove();
            }
        });
    },

    /**
     * Toggle wildcard dropdown menu
     */
    toggleWildcardDropdown(element) {
        const wcName = element.dataset.wc;
        const checkpointPath = element.dataset.path;
        const checkpoint = PU.state.previewMode.checkpoints.find(c => c.path === checkpointPath);

        if (!checkpoint) return;

        const wc = checkpoint.wildcardDropdowns.find(w => w.name === wcName);
        if (!wc || !wc.values.length) return;

        // Close existing dropdown
        const existing = document.querySelector('.pu-wc-dropdown-menu');
        if (existing) {
            existing.remove();
            // If clicking the same dropdown, just close it
            if (existing.dataset.wc === wcName && existing.dataset.path === checkpointPath) {
                return;
            }
        }

        // Get current selected value
        const selectedOverrides = PU.state.previewMode.selectedWildcards || {};
        const currentValue = selectedOverrides[wcName] || (checkpoint.wildcards?.find(w => w.name === wcName)?.value);

        // Create dropdown menu
        const menu = document.createElement('div');
        menu.className = 'pu-wc-dropdown-menu';
        menu.dataset.wc = wcName;
        menu.dataset.path = checkpointPath;
        menu.dataset.testid = `pu-wc-menu-${wcName}`;
        // BUCKET MODEL: Show only bucket values (already filtered in extractWildcardDropdowns)
        // Add "* (Any)" option at the top - selected when no override exists
        const isAnySelected = selectedOverrides[wcName] === undefined;
        const anyHtml = `<div class="pu-dropdown-item${isAnySelected ? ' selected' : ''}" data-testid="pu-wc-option-${PU.blocks.escapeHtml(wcName)}-any" data-wc="${PU.blocks.escapeHtml(wcName)}" data-value="*">* (Any ${PU.blocks.escapeHtml(PU.preview.normalizeWildcardName(wcName))})</div>`;
        menu.innerHTML = anyHtml + wc.values.map((v, vIdx) => {
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
                PU.preview.selectWildcardValue(item.dataset.wc, item.dataset.value);
            }
        });
    },

    /**
     * Handle wildcard value selection - propagates to all checkpoints
     */
    async selectWildcardValue(wcName, value) {
        // Update state — '*' means "Any" (un-pin this wildcard)
        if (value === '*') {
            delete PU.state.previewMode.selectedWildcards[wcName];
        } else {
            PU.state.previewMode.selectedWildcards[wcName] = value;
        }

        // Close dropdown
        const menu = document.querySelector('.pu-wc-dropdown-menu');
        if (menu) menu.remove();

        // Rebuild all checkpoints with new selection
        // This will re-resolve text using selectedWildcards overrides
        const checkpoints = await PU.preview.buildCheckpointData();
        PU.state.previewMode.checkpoints = checkpoints;
        PU.preview.renderCheckpointRows(checkpoints);
    },

    /**
     * Clear all wildcard selections (reset to random)
     */
    async clearWildcardSelections() {
        PU.state.previewMode.selectedWildcards = {};

        // Rebuild checkpoints
        const checkpoints = await PU.preview.buildCheckpointData();
        PU.state.previewMode.checkpoints = checkpoints;
        PU.preview.renderCheckpointRows(checkpoints);
    },

    // ============================================
    // Original Preview Popup Functions
    // ============================================

    /**
     * Show preview popup for a block
     */
    async show(path) {
        PU.state.preview.visible = true;
        PU.state.preview.targetPath = path;
        PU.state.preview.loading = true;

        const popup = document.querySelector('[data-testid="pu-preview-popup"]');
        if (popup) {
            popup.style.display = 'flex';
        }

        await PU.preview.loadPreview(path);
    },

    /**
     * Load preview data from API
     */
    async loadPreview(path) {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            PU.preview.renderError('No prompt selected');
            return;
        }

        const block = PU.blocks.findBlockByPath(prompt.text || [], path);
        if (!block) {
            PU.preview.renderError('Block not found');
            return;
        }

        // Build request
        const params = {
            job_id: PU.state.activeJobId,
            prompt_id: PU.state.activePromptId,
            wildcards: prompt.wildcards || [],
            include_nested: true,
            limit: 10
        };

        // For content blocks, pass the text
        if ('content' in block) {
            params.text = [block];
        } else if ('ext_text' in block) {
            params.text = [block];
        }

        try {
            const data = await PU.api.previewVariations(params);

            if (!data.variations) {
                console.warn('Preview API response missing variations field:', data);
            }
            PU.state.preview.variations = data.variations || [];
            PU.state.preview.totalCount = data.total_count || 0;
            PU.state.preview.loading = false;

            PU.preview.render(data);
        } catch (e) {
            console.error('Failed to load preview:', e);
            PU.preview.renderError('Failed to load preview: ' + e.message);
        }
    },

    /**
     * Render preview popup
     */
    render(data) {
        const variationsEl = document.querySelector('[data-testid="pu-preview-variations"]');
        const breakdownEl = document.querySelector('[data-testid="pu-preview-breakdown"]');

        if (variationsEl) {
            if (data.variations.length === 0) {
                variationsEl.innerHTML = '<div class="pu-preview-item">No variations generated</div>';
            } else {
                variationsEl.innerHTML = data.variations.map((v, idx) => `
                    <div class="pu-preview-item" data-testid="pu-preview-item-${idx}">
                        <span class="pu-preview-item-index">${idx + 1}.</span>
                        ${PU.blocks.escapeHtml(v.text)}
                    </div>
                `).join('');
            }
        }

        if (breakdownEl && data.breakdown) {
            breakdownEl.innerHTML = `
                <strong>&#128202; Breakdown:</strong>
                This level: ${data.breakdown.this_level} |
                Nested: ${data.breakdown.nested_paths} |
                <strong>Total: ${data.breakdown.total}</strong>
                ${data.total_count > data.variations.length ? ` (showing ${data.variations.length} of ${data.total_count})` : ''}
            `;
        }
    },

    /**
     * Render error state
     */
    renderError(message) {
        const variationsEl = document.querySelector('[data-testid="pu-preview-variations"]');
        if (variationsEl) {
            variationsEl.innerHTML = `<div class="pu-preview-item" style="color: var(--pu-error);">${message}</div>`;
        }
    },

    /**
     * Hide preview popup
     */
    hide() {
        PU.state.preview.visible = false;
        PU.state.preview.targetPath = null;

        const popup = document.querySelector('[data-testid="pu-preview-popup"]');
        if (popup) {
            popup.style.display = 'none';
        }
    },

    /**
     * Copy all variations to clipboard
     */
    async copyAll() {
        const variations = PU.state.preview.variations;
        if (variations.length === 0) {
            PU.actions.showToast('No variations to copy', 'error');
            return;
        }

        const text = variations.map(v => v.text).join('\n\n');

        try {
            await navigator.clipboard.writeText(text);
            PU.actions.showToast('Copied to clipboard', 'success');
        } catch (e) {
            console.error('Failed to copy to clipboard:', e);
            PU.actions.showToast('Failed to copy: ' + e.message, 'error');
        }
    },

    /**
     * Show all variations (load more)
     */
    async showAll() {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return;

        const path = PU.state.preview.targetPath;
        const block = PU.blocks.findBlockByPath(prompt.text || [], path);
        if (!block) return;

        const params = {
            job_id: PU.state.activeJobId,
            prompt_id: PU.state.activePromptId,
            wildcards: prompt.wildcards || [],
            include_nested: true,
            limit: 100  // Load more
        };

        if ('content' in block) {
            params.text = [block];
        } else if ('ext_text' in block) {
            params.text = [block];
        }

        try {
            const data = await PU.api.previewVariations(params);
            if (!data.variations) {
                console.warn('Preview API response missing variations field:', data);
            }
            PU.state.preview.variations = data.variations || [];
            PU.state.preview.totalCount = data.total_count || 0;
            PU.preview.render(data);
        } catch (e) {
            console.error('Failed to load more variations:', e);
            PU.actions.showToast('Failed to load more: ' + e.message, 'error');
        }
    }
};
