/**
 * PromptyUI - Shared Utilities
 *
 * Reusable functions extracted from mode-specific modules.
 * Any UI mode (Pipeline View, Quick Build, future Operations UI)
 * can use these without duplicating logic.
 *
 * Dependencies: state.js, blocks.js, preview.js (loaded before this file)
 */

PU.shared = {

    // ── Composition Space ────────────────────────────────────────

    /**
     * Compute wildcard lookup, counts, and effective total for the active prompt.
     * Combines prompt + extension wildcards and respects bucketing (extTextMax, wcMax).
     *
     * @returns {{ lookup, wcNames, wildcardCounts, extTextCount, extTextMax, wcMax, total }}
     */
    getCompositionParams() {
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
     * Count compositions when some wildcards are locked to specific values.
     * Locked wildcards contribute their locked count as the dimension instead of the full count.
     *
     * @param {Object} wildcardCounts - { name: count }
     * @param {number} extTextCount - number of ext_text sources
     * @param {Object} lockedValues - { name: [val1, val2] }
     * @returns {number}
     */
    computeLockedTotal(wildcardCounts, extTextCount, lockedValues) {
        let total = Math.max(1, extTextCount);
        const sortedWc = Object.keys(wildcardCounts).sort();
        for (const n of sortedWc) {
            const locked = lockedValues[n];
            const effectiveDim = (locked && locked.length > 0) ? locked.length : 1;
            total *= effectiveDim;
        }
        return total;
    },

    // ── Wildcard Source Detection ────────────────────────────────

    /**
     * Check if a wildcard comes from an extension/theme (not defined in the prompt itself).
     *
     * @param {string} name - wildcard name
     * @returns {boolean}
     */
    isExtWildcard(name) {
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
     * Get the extension source path for a wildcard name.
     *
     * @param {string} name - wildcard name
     * @returns {string} extension cache key, or '' if not found
     */
    getExtWildcardPath(name) {
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
     * Build a map of wildcard names to their theme/extension source paths.
     * Walks the prompt's text blocks to find ext_text references, then looks up
     * which wildcards each extension contributes.
     *
     * @returns {Object} { wildcardName: extTextSourcePath }
     */
    buildThemeSourceMap() {
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

    // ── Block Tree ───────────────────────────────────────────────

    /**
     * Build a flat block list with paths from nested text items.
     * Each block includes path, content preview, used wildcards, children, depth.
     *
     * @param {Array} items - prompt.text array (nested block structure)
     * @param {string} [pathPrefix] - parent path for recursion
     * @returns {Array<{path, content, usedWildcards, children, depth, hasChildren, isCheckpoint}>}
     */
    buildBlockTree(items, pathPrefix) {
        const blocks = [];
        if (!Array.isArray(items)) return blocks;

        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            const path = pathPrefix != null ? `${pathPrefix}.${i}` : String(i);
            const content = item.content || '';
            const preview = content.length > 60 ? content.substring(0, 60) + '...' : content;

            // Find wildcards used in this block
            const usedWildcards = [];
            const wcPattern = /__([a-zA-Z0-9_]+)__/g;
            let match;
            while ((match = wcPattern.exec(content)) !== null) {
                if (!usedWildcards.includes(match[1])) {
                    usedWildcards.push(match[1]);
                }
            }

            const children = item.after ? PU.shared.buildBlockTree(item.after, path) : [];

            blocks.push({
                path,
                content: preview,
                usedWildcards,
                children,
                depth: pathPrefix != null ? pathPrefix.split('.').length : 0,
                hasChildren: children.length > 0,
                isCheckpoint: !!item.checkpoint
            });
        }

        return blocks;
    },

    /**
     * Render dimension pills (wildcards + ext_text) as HTML.
     *
     * @param {string[]} wcNames - sorted wildcard names
     * @param {Object} wildcardCounts - { name: count }
     * @param {Object} lookup - full wildcard lookup
     * @param {number} extTextCount - number of ext_text sources
     * @returns {string} HTML string of pill spans
     */
    renderDimPills(wcNames, wildcardCounts, lookup, extTextCount) {
        let html = '';
        if (extTextCount > 1) {
            html += `<span class="pu-pipeline-pill pu-pipeline-pill-ext" data-testid="pu-pipeline-pill-ext" title="ext_text sources">ext_text(${extTextCount})</span>`;
        }
        for (const name of wcNames) {
            const count = wildcardCounts[name];
            const values = lookup[name] || [];
            const tooltip = values.slice(0, 5).join(', ') + (values.length > 5 ? `, ... +${values.length - 5} more` : '');
            const isExt = PU.shared.isExtWildcard(name);
            const extClass = isExt ? ' pu-pipeline-pill-ext' : '';
            html += `<span class="pu-pipeline-pill${extClass}" data-testid="pu-pipeline-pill-${name}" title="${PU.blocks.escapeHtml(tooltip)}">${PU.blocks.escapeHtml(name)}(${count})</span>`;
        }
        return html;
    },

    // ── Formatting ───────────────────────────────────────────────

    /**
     * Format bytes to human-readable string.
     *
     * @param {number} bytes
     * @returns {string}
     */
    formatBytes(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
    },

    /**
     * Format milliseconds to human-readable duration.
     *
     * @param {number} ms
     * @returns {string}
     */
    formatDuration(ms) {
        if (ms < 1000) return ms.toFixed(0) + 'ms';
        if (ms < 60000) return (ms / 1000).toFixed(1) + 's';
        return (ms / 60000).toFixed(1) + 'm';
    }
};
