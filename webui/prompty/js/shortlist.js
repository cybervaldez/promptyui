/**
 * Shortlist — Composition curation via ancestor expansion.
 *
 * Each shortlist entry is { text, sources: [{blockPath, comboKey}] }.
 * - text: Resolved text for a single block
 * - sources: Always length 1, pointing to this block's path + combo
 *
 * Clicking a child auto-adds ancestors as separate entries:
 * - Ancestors without existing entries get ALL combos (locked wildcards expand)
 * - Ancestors already in shortlist are skipped
 * - Leaf gets just the specific clicked combo
 *
 * Items live in PU.state.previewMode.shortlist[].
 */
PU.shortlist = {

    MAX_PICKS: 100,

    // ── Combo Key Utility ─────────────────────────────────────────────

    /** Convert combo array [{name, value}, ...] to deterministic key string. */
    comboToKey(combo) {
        if (!combo || combo.length === 0) return '';
        return combo.slice()
            .sort((a, b) => a.name.localeCompare(b.name))
            .map(c => `${c.name}=${c.value}`)
            .join('|');
    },

    /** Parse comboKey string back to {name: value} map. */
    _parseComboKey(comboKey) {
        const values = {};
        if (!comboKey) return values;
        for (const pair of comboKey.split('|')) {
            const eqIdx = pair.indexOf('=');
            if (eqIdx > 0) values[pair.substring(0, eqIdx)] = pair.substring(eqIdx + 1);
        }
        return values;
    },

    // ── Lookup Cache ──────────────────────────────────────────────────

    _lookupSet: null,

    /** Build a Set of "blockPath|comboKey" from ALL sources for O(1) has() checks. */
    _buildLookup() {
        const entries = PU.state.previewMode.shortlist;
        const set = new Set();
        for (const entry of entries) {
            for (const src of entry.sources) {
                set.add(`${src.blockPath}|${src.comboKey}`);
            }
        }
        PU.shortlist._lookupSet = set;
        return set;
    },

    // ── Queries ───────────────────────────────────────────────────────

    /** Check if a specific block+combo is in ANY entry's sources. */
    has(blockPath, comboKey) {
        const set = PU.shortlist._lookupSet || PU.shortlist._buildLookup();
        return set.has(`${blockPath}|${comboKey}`);
    },

    /** Check if a block appears in ANY entry's sources. */
    hasBlock(blockPath) {
        return PU.state.previewMode.shortlist.some(entry =>
            entry.sources.some(s => s.blockPath === blockPath)
        );
    },

    /** Total shortlisted entries. */
    count() {
        return PU.state.previewMode.shortlist.length;
    },

    // ── Core API ──────────────────────────────────────────────────────

    /**
     * Add a variation to the shortlist with ancestor expansion.
     * For each block in the ancestor chain (root → leaf):
     * - Ancestors with existing entries → skip
     * - Ancestors without entries → add ALL combos (locked wildcards expand)
     * - Leaf → add just the clicked combo
     */
    add(blockPath, combo) {
        const items = PU.state.previewMode.shortlist;
        const comboKey = PU.shortlist.comboToKey(combo);

        // Check if this exact leaf+combo already exists
        if (items.some(e => e.sources[0].blockPath === blockPath && e.sources[0].comboKey === comboKey)) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !prompt.text) return;

        const lookup = PU.preview.getFullWildcardLookup();
        const locked = PU.state.previewMode.lockedValues;
        const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
        const compId = PU.state.previewMode.compositionId;
        const [, wcIndices] = PU.preview.compositionToIndices(compId, extTextCount, wildcardCounts);
        const container = document.querySelector('[data-testid="pu-preview-body"]');

        // Build ancestor chain: ["0", "0.0", ..., blockPath]
        const parts = blockPath.split('.');
        const chain = [];
        for (let i = 1; i <= parts.length; i++) {
            chain.push(parts.slice(0, i).join('.'));
        }

        let addedCount = 0;
        let skippedCount = 0;

        for (const path of chain) {
            const block = PU.shortlist._getBlock(prompt.text, path);
            if (!block) continue;

            if (path === blockPath) {
                // LEAF: add just the specific clicked combo
                if (items.length >= PU.shortlist.MAX_PICKS) { skippedCount++; break; }
                const text = PU.shortlist._resolveBlockText(path, comboKey, block, container, lookup, wcIndices);
                items.push({ text, sources: [{ blockPath: path, comboKey }] });
                addedCount++;
            } else {
                // ANCESTOR: skip if block already has ANY entries
                if (items.some(e => e.sources[0].blockPath === path)) continue;

                // Build ALL combos for this block (locked wildcards expand)
                const allCombos = PU.shortlist._buildBlockCombos(block, lookup, locked, wcIndices);

                for (const ancestorCombo of allCombos) {
                    if (items.length >= PU.shortlist.MAX_PICKS) {
                        skippedCount += allCombos.length - allCombos.indexOf(ancestorCombo);
                        break;
                    }
                    const ck = PU.shortlist.comboToKey(ancestorCombo);
                    const text = PU.shortlist._resolveBlockText(path, ck, block, container, lookup, wcIndices);
                    items.push({ text, sources: [{ blockPath: path, comboKey: ck }] });
                    addedCount++;
                }
            }
        }

        if (skippedCount > 0) {
            PU.actions.showToast(`Added ${addedCount} of ${addedCount + skippedCount} (limit reached)`, 'info');
        }

        PU.shortlist._lookupSet = null;
        PU.shortlist._afterChange();
    },

    /**
     * Build ALL Cartesian combos for a block's wildcards, respecting locks.
     * Locked wildcards expand to multiple values; unlocked pin to odometer.
     */
    _buildBlockCombos(block, lookup, locked, wcIndices) {
        const wcNames = PU.shortlist._getBlockWildcards(block);
        if (wcNames.length === 0) return [[]]; // 1 empty combo (no wildcards)

        const dims = [];
        for (const name of wcNames) {
            const lockedVals = (locked[name] && locked[name].length > 0) ? locked[name] : null;
            const allVals = lookup[name] || [];
            if (lockedVals) {
                dims.push({ name, values: lockedVals });
            } else {
                const idx = wcIndices[name] || 0;
                dims.push({ name, values: [allVals[idx % allVals.length] || '?'] });
            }
        }

        return PU.editorMode._cartesianProduct(dims, PU.shortlist.MAX_PICKS);
    },

    /**
     * Resolve a block's text for a given combo.
     * For blocks without wildcards (ext_text, plain), grabs from DOM.
     * For blocks with wildcards, uses inline resolution with combo values.
     */
    _resolveBlockText(blockPath, comboKey, block, container, lookup, wcIndices) {
        const hasWildcards = PU.shortlist._getBlockWildcards(block).length > 0;

        // For blocks WITHOUT wildcards (ext_text or plain), grab from DOM
        if (!hasWildcards && container) {
            const blockEl = container.querySelector(`.pu-preview-block[data-path="${blockPath}"]`);
            if (blockEl) {
                const textDiv = blockEl.querySelector('.pu-preview-text');
                if (textDiv) {
                    const clone = textDiv.cloneNode(true);
                    clone.querySelectorAll('.pu-tree-connector, .pu-preview-parent-conn').forEach(el => el.remove());
                    return clone.textContent.trim();
                }
            }
        }

        // For blocks WITH wildcards, try matching variation div first
        if (hasWildcards && comboKey && container) {
            const blockEl = container.querySelector(`.pu-preview-block[data-path="${blockPath}"]`);
            if (blockEl) {
                const varDiv = blockEl.querySelector(`.pu-preview-variation[data-combo-key="${comboKey}"]`);
                if (varDiv) return varDiv.textContent.trim();
            }
        }

        // Inline resolution — replace wildcards with combo values
        const content = block.content || '';
        if (!comboKey) return content;
        const values = PU.shortlist._parseComboKey(comboKey);
        return content.replace(/__([a-zA-Z0-9_-]+)__/g, (match, name) => {
            if (values[name] !== undefined) return values[name];
            const allVals = lookup[name] || [];
            if (allVals.length === 0) return match;
            const idx = wcIndices[name] || 0;
            return allVals[idx % allVals.length];
        });
    },

    /** Remove an entry by blockPath + comboKey (used by footer × button). */
    remove(blockPath, comboKey) {
        PU.shortlist._removeWithCascadeCheck(blockPath, comboKey,
            e => e.sources[0].blockPath === blockPath && e.sources[0].comboKey === comboKey
        );
    },

    /** Remove entry matching this block+combo (used by preview toggle). */
    _removeBySource(blockPath, comboKey) {
        PU.shortlist._removeWithCascadeCheck(blockPath, comboKey,
            e => e.sources.some(s => s.blockPath === blockPath && s.comboKey === comboKey)
        );
    },

    /** Remove all entries for a blockPath. */
    removeBlock(blockPath) {
        PU.shortlist._removeWithCascadeCheck(blockPath, null,
            e => e.sources[0].blockPath === blockPath
        );
    },

    /** Check if any shortlist entries exist for descendant paths. */
    _hasDescendantEntries(blockPath) {
        const prefix = blockPath + '.';
        return PU.state.previewMode.shortlist.some(e =>
            e.sources[0].blockPath.startsWith(prefix)
        );
    },

    /** Remove with cascade confirmation when descendants exist. */
    _removeWithCascadeCheck(blockPath, comboKey, removeFilter) {
        const hasDescendants = PU.shortlist._hasDescendantEntries(blockPath);

        if (hasDescendants) {
            const prefix = blockPath + '.';
            const descCount = PU.state.previewMode.shortlist.filter(e =>
                e.sources[0].blockPath.startsWith(prefix)
            ).length;

            if (confirm(`Also remove ${descCount} descendant entries?`)) {
                PU.state.previewMode.shortlist = PU.state.previewMode.shortlist.filter(e => {
                    const bp = e.sources[0].blockPath;
                    return !removeFilter(e) && !bp.startsWith(prefix);
                });
            } else {
                PU.state.previewMode.shortlist = PU.state.previewMode.shortlist.filter(e => !removeFilter(e));
            }
        } else {
            PU.state.previewMode.shortlist = PU.state.previewMode.shortlist.filter(e => !removeFilter(e));
        }

        PU.shortlist._lookupSet = null;
        PU.shortlist._afterChange();
    },

    /** Clear the entire shortlist. */
    clearAll() {
        PU.state.previewMode.shortlist = [];
        PU.state.previewMode.dimmedEntries = new Set();
        PU.shortlist._lookupSet = null;
        PU.shortlist._afterChange();
    },

    /** Common post-mutation handler. */
    _afterChange() {
        PU.shortlist.render();
        if (PU.state.ui.editorMode === 'review' || PU.state.ui.editorMode === 'preview') {
            PU.editorMode.renderPreview();
        }
    },

    // ── UI Handlers ─────────────────────────────────────────────────

    /** Toggle a variation in/out of the shortlist. */
    toggleVariation(blockPath, comboKey) {
        if (PU.shortlist.has(blockPath, comboKey)) {
            // Green → remove all entries containing this source
            PU.shortlist._removeBySource(blockPath, comboKey);
        } else {
            const combo = comboKey.split('|').filter(p => p).map(pair => {
                const eqIdx = pair.indexOf('=');
                return { name: pair.substring(0, eqIdx), value: pair.substring(eqIdx + 1) };
            });
            PU.shortlist.add(blockPath, combo);
        }
    },

    // ── Hover Preview ───────────────────────────────────────────────

    /**
     * Highlight ancestor blocks when hovering a variation.
     * If ancestor has a pick → green highlight on that variation.
     * If ancestor has no pick → blue highlight on ALL variations.
     */
    _highlightAncestors(blockPath, container) {
        const parts = blockPath.split('.');
        for (let i = 1; i < parts.length; i++) {
            const ancestorPath = parts.slice(0, i).join('.');
            const ancestorBlock = container.querySelector(`.pu-preview-block[data-path="${ancestorPath}"]`);
            if (!ancestorBlock) continue;

            const ancestorVars = ancestorBlock.querySelectorAll('.pu-preview-variation');

            if (ancestorVars.length === 0) {
                // Block has no variation divs (e.g., ext_text) — highlight the block text
                const textDiv = ancestorBlock.querySelector('.pu-preview-text');
                if (textDiv) textDiv.classList.add('pu-shortlist-hover-all');
                continue;
            }

            if (PU.shortlist.hasBlock(ancestorPath)) {
                // Collect combo keys from all sources that reference this ancestor
                const pickKeys = new Set();
                for (const entry of PU.state.previewMode.shortlist) {
                    for (const src of entry.sources) {
                        if (src.blockPath === ancestorPath) pickKeys.add(src.comboKey);
                    }
                }
                let matched = false;
                ancestorVars.forEach(av => {
                    if (pickKeys.has(av.dataset.comboKey)) {
                        av.classList.add('pu-shortlist-hover-pick');
                        matched = true;
                    }
                });
                // Pick exists but isn't visible at current composition — highlight all
                if (!matched) {
                    ancestorVars.forEach(av => av.classList.add('pu-shortlist-hover-all'));
                }
            } else {
                ancestorVars.forEach(av => av.classList.add('pu-shortlist-hover-all'));
            }
        }
    },

    /** Remove all ancestor hover highlights. */
    _clearAncestorHighlights(container) {
        container.querySelectorAll('.pu-shortlist-hover-pick').forEach(
            el => el.classList.remove('pu-shortlist-hover-pick')
        );
        container.querySelectorAll('.pu-shortlist-hover-all').forEach(
            el => el.classList.remove('pu-shortlist-hover-all')
        );
    },

    // ── Hover Tip ─────────────────────────────────────────────────────

    /** Compute variation count for a block (locked wildcards multiply, unlocked = 1). */
    _blockVariationCount(block, lookup, locked) {
        const wcNames = PU.shortlist._getBlockWildcards(block);
        let count = 1;
        for (const name of wcNames) {
            const lockedVals = (locked[name] && locked[name].length > 0) ? locked[name] : null;
            if (lockedVals) count *= lockedVals.length;
        }
        return count;
    },

    /** Show hover tip describing what clicking a variation will add. */
    _showHoverTip(blockPath, comboKey, variationText) {
        const tip = document.querySelector('[data-testid="pu-footer-tip"]');
        if (!tip) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !prompt.text) return;

        const lookup = PU.preview.getFullWildcardLookup();
        const locked = PU.state.previewMode.lockedValues;

        // Build ancestor chain
        const parts = blockPath.split('.');
        const chain = [];
        for (let i = 1; i <= parts.length; i++) {
            chain.push(parts.slice(0, i).join('.'));
        }

        const segments = [];
        let total = 1;

        for (const path of chain) {
            const block = PU.shortlist._getBlock(prompt.text, path);
            if (!block) continue;
            const count = PU.shortlist._blockVariationCount(block, lookup, locked);
            total *= count;

            if (path === blockPath) {
                // Leaf: show the hovered text (truncated)
                const truncated = variationText.length > 60
                    ? variationText.substring(0, 57) + '...'
                    : variationText;
                segments.push(truncated);
            } else {
                // Ancestor: show path + count
                const hasEntries = PU.state.previewMode.shortlist.some(e => e.sources[0].blockPath === path);
                if (hasEntries) {
                    const pickCount = PU.state.previewMode.shortlist.filter(e => e.sources[0].blockPath === path).length;
                    segments.push(`${path}: ${pickCount} pick${pickCount !== 1 ? 's' : ''}`);
                } else {
                    segments.push(`${path}: ${count} item${count !== 1 ? 's' : ''}`);
                }
            }
        }

        const isShortlisted = PU.shortlist.has(blockPath, comboKey);
        const action = isShortlisted ? 'click to remove' : 'click to add';
        const chainText = segments.join(' \u00b7 ');
        const totalSuffix = chain.length > 1 ? ` (Total: ${total.toLocaleString()})` : '';

        tip.textContent = `${action} "${chainText}${totalSuffix}"`;
        tip.classList.add('visible');
    },

    /** Hide the hover tip. */
    _hideHoverTip() {
        const tip = document.querySelector('[data-testid="pu-footer-tip"]');
        if (tip) {
            tip.classList.remove('visible');
            tip.textContent = '';
        }
    },

    // ── Footer Panel ──────────────────────────────────────────────────

    /** Toggle the footer panel open/closed. */
    togglePanel() {
        const panel = document.querySelector('[data-testid="pu-shortlist-panel"]');
        if (panel) panel.classList.toggle('collapsed');
    },

    /** Check if shortlist UI should be visible. */
    _isVisible() {
        const mode = PU.state.ui.editorMode;
        return (mode === 'preview' || mode === 'review') && PU.state.previewMode.shortlist.length > 0;
    },

    /** Render the shortlist footer panel. */
    render() {
        const panel = document.querySelector('[data-testid="pu-shortlist-panel"]');
        if (!panel) return;

        if (!PU.shortlist._isVisible()) {
            panel.style.display = 'none';
            return;
        }
        panel.style.display = '';

        const countEl = panel.querySelector('[data-testid="pu-shortlist-count"]');
        if (countEl) countEl.textContent = PU.shortlist.count();

        const body = panel.querySelector('[data-testid="pu-shortlist-body"]');
        if (!body) return;

        body.innerHTML = PU.shortlist._renderTreeView(PU.state.previewMode.shortlist);
    },

    // ── Dim State ────────────────────────────────────────────────────

    /** Check if a specific block+combo is dimmed. */
    _isDimmed(blockPath, comboKey) {
        return (PU.state.previewMode.dimmedEntries || new Set()).has(`${blockPath}|${comboKey}`);
    },

    /** Toggle dim state for a single entry. */
    toggleDim(blockPath, comboKey) {
        if (!PU.state.previewMode.dimmedEntries) PU.state.previewMode.dimmedEntries = new Set();
        const key = `${blockPath}|${comboKey}`;
        if (PU.state.previewMode.dimmedEntries.has(key)) {
            PU.state.previewMode.dimmedEntries.delete(key);
        } else {
            PU.state.previewMode.dimmedEntries.add(key);
        }
        PU.shortlist.render();
    },

    /** Toggle dim for all entries under a block path. */
    toggleDimBlock(blockPath) {
        if (!PU.state.previewMode.dimmedEntries) PU.state.previewMode.dimmedEntries = new Set();
        const entries = PU.state.previewMode.shortlist.filter(e => e.sources[0].blockPath === blockPath);
        const allDimmed = entries.every(e =>
            PU.state.previewMode.dimmedEntries.has(`${e.sources[0].blockPath}|${e.sources[0].comboKey}`)
        );
        for (const e of entries) {
            const key = `${e.sources[0].blockPath}|${e.sources[0].comboKey}`;
            if (allDimmed) {
                PU.state.previewMode.dimmedEntries.delete(key);
            } else {
                PU.state.previewMode.dimmedEntries.add(key);
            }
        }
        PU.shortlist.render();
    },

    // ── Tree View Renderer ───────────────────────────────────────────

    /**
     * Render tree view — entries grouped by blockPath with tree connectors.
     * Each item shows the full resolved prompt (ancestor texts ── joined).
     */
    _renderTreeView(items) {
        if (items.length === 0) return '<div class="pu-rp-note">No items shortlisted</div>';

        const esc = PU.blocks.escapeHtml;

        // 1. Group entries by blockPath
        const groups = {};
        for (const entry of items) {
            const bp = entry.sources[0].blockPath;
            if (!groups[bp]) groups[bp] = [];
            groups[bp].push(entry);
        }

        // 2. Sort paths hierarchically (tree order)
        const paths = Object.keys(groups).sort((a, b) => {
            const ap = a.split('.').map(Number);
            const bp = b.split('.').map(Number);
            for (let i = 0; i < Math.max(ap.length, bp.length); i++) {
                if (i >= ap.length) return -1;
                if (i >= bp.length) return 1;
                if (ap[i] !== bp[i]) return ap[i] - bp[i];
            }
            return 0;
        });

        // 3. Precompute ancestor text cache (first entry per path)
        const ancestorText = {};
        for (const path of paths) {
            ancestorText[path] = groups[path][0].text;
        }

        // Helper: is this path the last sibling at its depth?
        function isLastSibling(path) {
            const parts = path.split('.');
            if (parts.length <= 1) return true;
            const parentPrefix = parts.slice(0, -1).join('.') + '.';
            const siblings = paths.filter(p => {
                const pp = p.split('.');
                return pp.length === parts.length && p.startsWith(parentPrefix);
            });
            return siblings[siblings.length - 1] === path;
        }

        // 4. Render tree groups
        let html = '';
        for (const path of paths) {
            const entries = groups[path];
            const depth = path.split('.').length;
            const lastSib = isLastSibling(path);

            // Tree connector prefix for path header
            let connectorStr = '';
            if (depth > 1) {
                const parentParts = path.split('.');
                let parentPrefix = '';
                for (let d = 1; d < parentParts.length - 1; d++) {
                    const ap = parentParts.slice(0, d).join('.');
                    parentPrefix += isLastSibling(ap) ? '\u00a0\u00a0' : '\u2502\u00a0';
                }
                connectorStr = parentPrefix + (lastSib ? '\u2514\u2500\u2500\u00a0' : '\u251c\u2500\u2500\u00a0');
            }

            // Build ancestor chain text for this block's entries
            const ancestorChain = [];
            const parts = path.split('.');
            for (let i = 1; i < parts.length; i++) {
                const aPath = parts.slice(0, i).join('.');
                if (ancestorText[aPath]) ancestorChain.push(ancestorText[aPath]);
            }

            const safePath = esc(path).replace(/'/g, '&#39;');

            // Path header (clickable for batch dim)
            html += `<div class="pu-shortlist-group" data-path="${esc(path)}" data-testid="pu-shortlist-group-${esc(path)}">`;
            html += `<div class="pu-shortlist-path-header" onclick="PU.shortlist.toggleDimBlock('${safePath}')" data-testid="pu-shortlist-path-header-${esc(path)}">`;
            html += `<span class="pu-shortlist-connector">${connectorStr}</span>`;
            html += `<span class="pu-shortlist-path-label">${esc(path)}</span>`;
            html += `<span class="pu-shortlist-group-count">(${entries.length})</span>`;
            html += '</div>';

            // Entries
            for (const entry of entries) {
                const src = entry.sources[0];
                const isDimmed = PU.shortlist._isDimmed(src.blockPath, src.comboKey);
                const dimCls = isDimmed ? ' pu-shortlist-dimmed' : '';

                // Full text = ancestor segments + own text, joined with ──
                const fullText = [...ancestorChain, entry.text].join(' \u2500\u2500 ');

                const safeKey = esc(src.comboKey).replace(/'/g, '&#39;');
                const safeBlockPath = esc(src.blockPath).replace(/'/g, '&#39;');

                html += `<div class="pu-shortlist-item${dimCls}" data-testid="pu-shortlist-item-${esc(path)}" data-block-path="${esc(src.blockPath)}" data-combo-key="${esc(src.comboKey)}" onclick="PU.shortlist.toggleDim('${safeBlockPath}', '${safeKey}')">`;
                html += `<span class="pu-shortlist-connector">\u250a\u00a0</span>`;
                html += `<span class="pu-shortlist-item-text" data-testid="pu-shortlist-resolved">${esc(fullText)}</span>`;
                html += '</div>';
            }

            html += '</div>';
        }
        return html;
    },

    // ── Block Helpers ────────────────────────────────────────────────

    /** Navigate the block tree to get a block at a given path. */
    _getBlock(blocks, path) {
        const parts = path.split('.');
        let current = blocks;
        for (let i = 0; i < parts.length; i++) {
            const idx = parseInt(parts[i], 10);
            if (!current || !current[idx]) return null;
            if (i === parts.length - 1) return current[idx];
            current = current[idx].after;
        }
        return null;
    },

    /** Get wildcard names from block content. */
    _getBlockWildcards(block) {
        const content = block.content || '';
        const names = [];
        const seen = new Set();
        const pattern = /__([a-zA-Z0-9_-]+)__/g;
        let m;
        while ((m = pattern.exec(content)) !== null) {
            if (!seen.has(m[1])) { seen.add(m[1]); names.push(m[1]); }
        }
        return names;
    },

    /**
     * Convert a comboKey to a display string.
     * "persona=CEO|tone=formal" → "persona: CEO, tone: formal"
     */
    _comboKeyToDisplay(comboKey) {
        if (!comboKey) return '';
        return comboKey.split('|').map(pair => {
            const eqIdx = pair.indexOf('=');
            return `${pair.substring(0, eqIdx)}: ${pair.substring(eqIdx + 1)}`;
        }).join(', ');
    },

    // ── Persistence ───────────────────────────────────────────────────

    /** Get shortlist data for session snapshot. */
    getSessionData() {
        return PU.state.previewMode.shortlist.map(entry => ({
            text: entry.text,
            sources: entry.sources.map(s => ({ block: s.blockPath, combo: s.comboKey }))
        }));
    },

    /** Hydrate shortlist from session data. */
    hydrateFromSession(data) {
        if (!Array.isArray(data)) return;
        PU.state.previewMode.shortlist = data
            .filter(entry => entry && entry.text && Array.isArray(entry.sources))
            .map(entry => ({
                text: String(entry.text),
                sources: entry.sources
                    .filter(s => s && s.block !== undefined)
                    .map(s => ({ blockPath: String(s.block), comboKey: String(s.combo || '') }))
            }));
        PU.shortlist._lookupSet = null;
    }
};
