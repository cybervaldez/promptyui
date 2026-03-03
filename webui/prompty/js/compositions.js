/**
 * Compositions Panel — Shows all resolved prompts with budget-limited allocation.
 *
 * Mirrors ALL variations computed for the current preview (wildcard + ext_text).
 * Data source: PU.state.previewMode.resolvedVariations (populated by editor-mode.js).
 * Users curate by **dimming** (excluding) entries instead of adding/removing.
 * **Pinned** entries survive composition navigation (cross-composition cherry-picking).
 * Orphaned pins (whose variations leave the preview) show warnings.
 *
 * Each entry is { text, sources: [{blockPath, comboKey}], _orphan? }.
 * Items live in PU.state.previewMode.compositions[].
 * Dimmed keys live in PU.state.previewMode.dimmedEntries (Set of "blockPath|comboKey").
 * Pinned keys live in PU.state.previewMode.pinnedEntries (Set of "blockPath|comboKey").
 * Frozen texts for orphan display in PU.state.previewMode.pinnedTexts (Map).
 */
PU.compositions = {

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

    /**
     * Split a key ("blockPath|comboKey") into [blockPath, comboKey].
     * blockPath is always before the first `|` that isn't part of a `name=value` pair.
     * Since blockPath is numeric dot-separated (e.g. "0.1") and never contains `=`,
     * we split on the first `|`.
     */
    _splitKey(key) {
        const sepIdx = key.indexOf('|');
        if (sepIdx < 0) return [key, ''];
        return [key.substring(0, sepIdx), key.substring(sepIdx + 1)];
    },

    // ── Queries ───────────────────────────────────────────────────────

    /** Total composition entries. */
    count() {
        return PU.state.previewMode.compositions.length;
    },

    // ── Auto-Populate ───────────────────────────────────────────────

    /**
     * Populate compositions from resolved variation data in state.
     * Reads PU.state.previewMode.resolvedVariations (set by editor-mode.js).
     * Pinned entries not in the data are injected as orphans.
     */
    populateFromPreview() {
        const variations = PU.state.previewMode.resolvedVariations || [];
        const items = [];
        const seenKeys = new Set();

        for (const v of variations) {
            const key = `${v.blockPath}|${v.comboKey}`;
            seenKeys.add(key);

            // Keep frozen text fresh for pinned entries
            if (PU.state.previewMode.pinnedEntries.has(key)) {
                PU.state.previewMode.pinnedTexts.set(key, v.text);
            }

            items.push({
                text: v.text,
                sources: [{ blockPath: v.blockPath, comboKey: v.comboKey }]
            });
        }

        // Inject orphaned pinned entries (not found in current data)
        for (const key of PU.state.previewMode.pinnedEntries) {
            if (!seenKeys.has(key)) {
                const [bp, ck] = PU.compositions._splitKey(key);
                const frozenText = PU.state.previewMode.pinnedTexts.get(key) || '(orphaned)';
                items.push({
                    text: frozenText,
                    sources: [{ blockPath: bp, comboKey: ck }],
                    _orphan: true
                });
            }
        }

        PU.state.previewMode.compositions = items;
    },

    // ── Dim State ────────────────────────────────────────────────────

    /** Check if a specific block+combo is dimmed. */
    _isDimmed(blockPath, comboKey) {
        return PU.state.previewMode.dimmedEntries.has(`${blockPath}|${comboKey}`);
    },

    /** Toggle dim state for a single entry. */
    toggleDim(blockPath, comboKey) {
        const key = `${blockPath}|${comboKey}`;
        const set = PU.state.previewMode.dimmedEntries;
        set.has(key) ? set.delete(key) : set.add(key);
        PU.compositions.render();
    },

    /**
     * Toggle dim for all entries in a separator range.
     * Range = the path itself + after siblings + all descendants of each.
     */
    toggleDimBlock(separatorPath) {
        const entries = PU.state.previewMode.compositions.filter(e =>
            PU.compositions._isInSeparatorRange(e.sources[0].blockPath, separatorPath)
        );
        const set = PU.state.previewMode.dimmedEntries;
        const allDimmed = entries.length > 0 && entries.every(e =>
            set.has(`${e.sources[0].blockPath}|${e.sources[0].comboKey}`)
        );
        for (const e of entries) {
            const key = `${e.sources[0].blockPath}|${e.sources[0].comboKey}`;
            if (allDimmed) {
                set.delete(key);
            } else {
                set.add(key);
            }
        }
        PU.compositions.render();
    },

    /**
     * Check if a blockPath falls within a separator range.
     * Range includes: separatorPath, its descendants, after siblings, and their descendants.
     * E.g., separator "0.1" matches "0.1", "0.1.0", "0.2", "0.2.3", but not "0.0" or "1.0".
     */
    _isInSeparatorRange(blockPath, separatorPath) {
        const sepParts = separatorPath.split('.');
        const bpParts = blockPath.split('.');

        // Must be at least as deep as the separator path
        if (bpParts.length < sepParts.length) return false;

        // All parent parts (before the last) must match exactly
        for (let i = 0; i < sepParts.length - 1; i++) {
            if (bpParts[i] !== sepParts[i]) return false;
        }

        // The part at separator depth must be >= separator's last index
        return parseInt(bpParts[sepParts.length - 1], 10) >= parseInt(sepParts[sepParts.length - 1], 10);
    },

    // ── Pin State ────────────────────────────────────────────────────

    /** Check if a specific block+combo is pinned. */
    _isPinned(blockPath, comboKey) {
        return PU.state.previewMode.pinnedEntries.has(`${blockPath}|${comboKey}`);
    },

    /**
     * Toggle pin state for a single entry.
     * On pin: capture current resolved text into pinnedTexts.
     * On unpin: remove from both sets.
     */
    togglePin(blockPath, comboKey) {
        const key = `${blockPath}|${comboKey}`;
        const pinned = PU.state.previewMode.pinnedEntries;
        const texts = PU.state.previewMode.pinnedTexts;

        if (pinned.has(key)) {
            pinned.delete(key);
            texts.delete(key);
        } else {
            pinned.add(key);
            const text = PU.compositions._resolveTextForKey(blockPath, comboKey);
            if (text) texts.set(key, text);
        }

        PU.compositions.render();
    },

    /** Resolve text for a given key from compositions array or resolved variations. */
    _resolveTextForKey(blockPath, comboKey) {
        const entry = PU.state.previewMode.compositions.find(e =>
            e.sources[0].blockPath === blockPath && e.sources[0].comboKey === comboKey
        );
        if (entry) return entry.text;

        const v = (PU.state.previewMode.resolvedVariations || []).find(
            v => v.blockPath === blockPath && v.comboKey === comboKey
        );
        return v ? v.text : null;
    },

    /**
     * Detect orphans: pinned entries not in current resolved variations.
     * Returns array of { blockPath, comboKey, text }.
     */
    _detectOrphans() {
        const variations = PU.state.previewMode.resolvedVariations || [];
        const activeKeys = new Set(variations.map(v => `${v.blockPath}|${v.comboKey}`));
        const orphans = [];
        for (const key of PU.state.previewMode.pinnedEntries) {
            if (!activeKeys.has(key)) {
                const [bp, ck] = PU.compositions._splitKey(key);
                orphans.push({
                    blockPath: bp,
                    comboKey: ck,
                    text: PU.state.previewMode.pinnedTexts.get(key) || '(unavailable)'
                });
            }
        }
        return orphans;
    },

    // ── UI Handlers ─────────────────────────────────────────────────

    /** Route click on a variation: Shift+click → pin, regular click → dim. */
    toggleVariation(blockPath, comboKey, event) {
        if (event && event.shiftKey) {
            PU.compositions.togglePin(blockPath, comboKey);
        } else {
            PU.compositions.toggleDim(blockPath, comboKey);
        }
    },

    /** Route click on a compositions item: Shift+click → pin, regular click → dim. */
    _handleItemClick(blockPath, comboKey, event) {
        if (event && event.shiftKey) {
            PU.compositions.togglePin(blockPath, comboKey);
        } else {
            PU.compositions.toggleDim(blockPath, comboKey);
        }
    },

    // ── Segment Highlighting (Preview ↔ Compositions) ────────────────────

    /** Highlight entire compositions items that contain a segment matching the given path. */
    _highlightItemsBySegmentPath(blockPath) {
        document.querySelectorAll(`.pu-compositions-segment[data-segment-path="${blockPath}"]`).forEach(seg => {
            const item = seg.closest('.pu-compositions-item');
            if (item) item.classList.add('pu-compositions-hover-from-preview');
        });
    },

    /** Highlight the compositions item matching a hovered preview block path. */
    _highlightCompositionsItem(blockPath, comboKey) {
        const panel = document.querySelector('[data-testid="pu-compositions-body"]');
        if (!panel) return;
        const selector = `.pu-compositions-item[data-block-path="${blockPath}"][data-combo-key="${comboKey || ''}"]`;
        const item = panel.querySelector(selector);
        if (item) {
            item.classList.add('pu-compositions-hover-from-preview');
            item.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
    },

    /** Clear all reverse hover highlights from compositions. */
    _clearCompositionsHighlights() {
        document.querySelectorAll('.pu-compositions-hover-from-preview').forEach(
            el => el.classList.remove('pu-compositions-hover-from-preview')
        );
    },

    /**
     * Attach mouseenter/mouseleave on compositions items to highlight
     * corresponding preview template blocks.
     */
    _attachCompositionsHoverListeners(body) {
        const items = body.querySelectorAll('.pu-compositions-item[data-block-path]');
        items.forEach(item => {
            item.addEventListener('mouseenter', () => {
                const container = document.querySelector('[data-testid="pu-preview-body"]');
                if (!container) return;

                // Highlight only the item's own preview block (not ancestors — structure already mirrors)
                const bp = item.dataset.blockPath;
                const ownBlock = container.querySelector(`.pu-preview-block[data-path="${bp}"]`);
                if (ownBlock) {
                    ownBlock.classList.add('pu-preview-block-hover');
                    ownBlock.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
                }
            });
            item.addEventListener('mouseleave', () => {
                const container = document.querySelector('[data-testid="pu-preview-body"]');
                if (!container) return;
                container.querySelectorAll('.pu-preview-block-hover').forEach(
                    el => el.classList.remove('pu-preview-block-hover')
                );
            });
        });

        // Separator hover: preview which compositions items are in the range + footer tip
        const seps = body.querySelectorAll('.pu-compositions-separator[data-separator-path]');
        seps.forEach(sep => {
            sep.addEventListener('mouseenter', (e) => {
                e.stopPropagation();
                const sepPath = sep.dataset.separatorPath;
                if (!sepPath) return;
                // Highlight all compositions items in range
                body.querySelectorAll('.pu-compositions-item[data-block-path]').forEach(item => {
                    if (PU.compositions._isInSeparatorRange(item.dataset.blockPath, sepPath)) {
                        item.classList.add('pu-compositions-hover-from-preview');
                    }
                });
                PU.rightPanel._showFooterTip('<kbd>click</kbd> magnify · <kbd>⇧click</kbd> dim');
            });
            sep.addEventListener('mouseleave', () => {
                PU.compositions._clearCompositionsHighlights();
                PU.rightPanel._hideFooterTip();
            });
        });
    },

    // ── Footer Panel ──────────────────────────────────────────────────

    /** Toggle the footer panel open/closed. */
    togglePanel() {
        const panel = document.querySelector('[data-testid="pu-compositions-panel"]');
        if (panel) panel.classList.toggle('collapsed');
    },

    /** Check if compositions UI should be visible. */
    _isVisible() {
        const mode = PU.state.ui.editorMode;
        return mode === 'preview' || mode === 'review';
    },

    /** Render the compositions footer panel. */
    render() {
        const panel = document.querySelector('[data-testid="pu-compositions-panel"]');
        if (!panel) return;

        if (!PU.compositions._isVisible()) {
            panel.style.display = 'none';
            return;
        }
        panel.style.display = '';

        const magnified = PU.state.previewMode.magnifiedPath;

        // Filter entries when magnified
        let items = PU.state.previewMode.compositions;
        if (magnified) {
            items = items.filter(e => {
                const bp = e.sources[0].blockPath;
                return bp === magnified || bp.startsWith(magnified + '.');
            });
        }

        const countEl = panel.querySelector('[data-testid="pu-compositions-count"]');
        if (countEl) countEl.textContent = items.length;

        const body = panel.querySelector('[data-testid="pu-compositions-body"]');
        if (body) {
            // Breadcrumb when magnified
            let breadcrumbHtml = '';
            if (magnified) {
                breadcrumbHtml = PU.compositions._renderBreadcrumb(magnified);
            }
            body.innerHTML = breadcrumbHtml + PU.compositions._renderTreeView(items);
            PU.compositions._attachCompositionsHoverListeners(body);
        }

        // Render action bar
        const actionBar = panel.querySelector('[data-testid="pu-compositions-action-bar"]');
        if (actionBar) {
            actionBar.innerHTML = PU.compositions._renderActionBar();
        }
    },

    // ── Magnifier ─────────────────────────────────────────────────────

    /** Magnify into a subtree (filter compositions to this path and descendants). */
    magnify(path) {
        PU.state.previewMode.magnifiedPath = path;
        PU.compositions.render();
    },

    /** Clear magnification — show all compositions. */
    clearMagnify() {
        PU.state.previewMode.magnifiedPath = null;
        PU.compositions.render();
    },

    /** Render breadcrumb for magnified path. */
    _renderBreadcrumb(magnifiedPath) {
        const esc = PU.blocks.escapeHtml;
        const parts = magnifiedPath.split('.');
        let html = '<div class="pu-compositions-breadcrumb" data-testid="pu-compositions-breadcrumb">';
        html += `<span class="pu-compositions-crumb pu-compositions-crumb-link" onclick="PU.compositions.clearMagnify()" data-testid="pu-compositions-crumb-all">All</span>`;

        for (let i = 0; i < parts.length; i++) {
            const subPath = parts.slice(0, i + 1).join('.');
            const isLast = i === parts.length - 1;

            // Try to get a label for this path segment from resolved variations
            let label = subPath;
            const entry = PU.state.previewMode.compositions.find(e => e.sources[0].blockPath === subPath);
            if (entry) {
                // Use first 30 chars of text as label
                label = entry.text.substring(0, 30).trim();
                if (entry.text.length > 30) label += '...';
            }

            html += '<span class="pu-compositions-crumb-sep"> &rsaquo; </span>';
            if (isLast) {
                html += `<span class="pu-compositions-crumb pu-compositions-crumb-current">${esc(label)}</span>`;
            } else {
                const safePath = esc(subPath).replace(/'/g, '&#39;');
                html += `<span class="pu-compositions-crumb pu-compositions-crumb-link" onclick="PU.compositions.magnify('${safePath}')">${esc(label)}</span>`;
            }
        }

        html += '<span style="flex:1"></span>';
        html += `<button class="pu-compositions-crumb-close" onclick="PU.compositions.clearMagnify()" data-testid="pu-compositions-crumb-close" title="Clear focus">&times;</button>`;
        html += '</div>';
        return html;
    },

    /** Clear all dim and pin states, re-populate, re-render. */
    clearAll() {
        PU.state.previewMode.dimmedEntries = new Set();
        PU.state.previewMode.pinnedEntries = new Set();
        PU.state.previewMode.pinnedTexts = new Map();
        // Re-populate to remove orphaned entries from compositions array
        PU.compositions.populateFromPreview();
        PU.compositions.render();
    },

    /** Common post-mutation handler (compositions panel only — no full re-render). */
    _afterChange() {
        PU.compositions.render();
    },

    // ── Action Bar ──────────────────────────────────────────────────

    /**
     * Render contextual action bar HTML.
     * Shows pin count, orphan resolve button, and commit selection button.
     */
    _renderActionBar() {
        const dimCount = PU.state.previewMode.dimmedEntries.size;
        const pinCount = PU.state.previewMode.pinnedEntries.size;
        const orphans = PU.compositions._detectOrphans();
        const hasCuration = dimCount > 0 || pinCount > 0;

        const esc = PU.blocks.escapeHtml;
        let html = '<div class="pu-compositions-actions">';

        if (pinCount > 0) {
            html += `<span class="pu-compositions-action-summary" data-testid="pu-compositions-pin-summary">\uD83D\uDCCC ${pinCount} pinned</span>`;
        }

        if (orphans.length > 0) {
            html += `<button class="pu-btn pu-btn-small pu-btn-warning" onclick="PU.compositions.showOrphanModal()" data-testid="pu-compositions-resolve-orphans">\u26A0 Resolve ${orphans.length} Orphan${orphans.length > 1 ? 's' : ''}</button>`;
        }

        html += '<span style="flex:1"></span>';

        const activeCount = PU.state.previewMode.compositions.filter(e => {
            const key = `${e.sources[0].blockPath}|${e.sources[0].comboKey}`;
            return !PU.state.previewMode.dimmedEntries.has(key);
        }).length;
        const disabledAttr = hasCuration ? '' : ' disabled';
        html += `<button class="pu-btn pu-btn-small pu-btn-primary" onclick="PU.compositions.commitSelection()"${disabledAttr} data-testid="pu-compositions-commit">Commit Selection (${activeCount})</button>`;

        html += '</div>';
        return html;
    },

    // ── Orphan Resolution Modal ─────────────────────────────────────

    /** Show the orphan resolution modal. */
    showOrphanModal() {
        const orphans = PU.compositions._detectOrphans();
        if (orphans.length === 0) return;

        PU.overlay.dismissAll();

        const esc = PU.blocks.escapeHtml;
        let listHtml = '';
        for (const o of orphans) {
            const key = `${o.blockPath}|${o.comboKey}`;
            const safeKey = esc(key).replace(/'/g, '&#39;');
            const wildcardInfo = PU.compositions._comboKeyToDisplay(o.comboKey) || 'no wildcards';
            const truncText = o.text.length > 120 ? o.text.substring(0, 117) + '...' : o.text;

            listHtml += `<div class="pu-orphan-entry" data-key="${esc(key)}" data-testid="pu-orphan-entry">`;
            listHtml += `<div class="pu-orphan-info">`;
            listHtml += `<div class="pu-orphan-path">${esc(o.blockPath)}</div>`;
            listHtml += `<div class="pu-orphan-wildcards">${esc(wildcardInfo)}</div>`;
            listHtml += `<div class="pu-orphan-text">${esc(truncText)}</div>`;
            listHtml += `</div>`;
            listHtml += `<div class="pu-orphan-actions">`;
            listHtml += `<button class="pu-btn pu-btn-small" onclick="PU.compositions.resolveOrphan('${safeKey}', 'unpin')">Unpin</button>`;
            listHtml += `</div>`;
            listHtml += `</div>`;
        }

        const modalHtml = `<div class="pu-modal-overlay" data-testid="pu-orphan-modal-overlay" onclick="if(event.target===this) PU.compositions.closeOrphanModal()">
            <div class="pu-modal" style="width: 560px;">
                <div class="pu-modal-header">
                    <h3>\u26A0 Orphaned Pins</h3>
                    <button class="pu-modal-close" onclick="PU.compositions.closeOrphanModal()">&times;</button>
                </div>
                <div class="pu-modal-body">
                    <p class="pu-orphan-desc">These pinned entries are no longer in the current composition. They may reappear when navigating to other compositions.</p>
                    ${listHtml}
                </div>
                <div class="pu-modal-footer">
                    <button class="pu-btn pu-btn-small" onclick="PU.compositions.unpinAllOrphans()">Unpin All Orphans</button>
                    <span style="flex:1"></span>
                    <button class="pu-btn pu-btn-small pu-btn-primary" onclick="PU.compositions.closeOrphanModal()">Done</button>
                </div>
            </div>
        </div>`;

        // Remove existing modal if any, then inject
        const existing = document.querySelector('[data-testid="pu-orphan-modal-overlay"]');
        if (existing) existing.remove();
        document.body.insertAdjacentHTML('beforeend', modalHtml);
    },

    /** Close orphan modal. */
    closeOrphanModal() {
        const modal = document.querySelector('[data-testid="pu-orphan-modal-overlay"]');
        if (modal) modal.remove();
    },

    /**
     * Resolve a single orphan by unpinning it.
     * Removes from pinnedEntries + pinnedTexts, removes entry from modal UI.
     */
    resolveOrphan(key, action) {
        if (action === 'unpin') {
            PU.state.previewMode.pinnedEntries.delete(key);
            PU.state.previewMode.pinnedTexts.delete(key);
        }

        // Remove from modal UI
        const entryEl = document.querySelector(`[data-testid="pu-orphan-modal-overlay"] .pu-orphan-entry[data-key="${key}"]`);
        if (entryEl) entryEl.remove();

        // Close modal if no more orphans
        const remaining = document.querySelectorAll('[data-testid="pu-orphan-modal-overlay"] .pu-orphan-entry');
        if (!remaining || remaining.length === 0) {
            PU.compositions.closeOrphanModal();
        }

        // Re-populate to remove orphaned entry from compositions
        PU.compositions.populateFromPreview();
        PU.compositions.render();
    },

    /** Unpin all orphaned entries at once. */
    unpinAllOrphans() {
        const orphans = PU.compositions._detectOrphans();
        for (const o of orphans) {
            const key = `${o.blockPath}|${o.comboKey}`;
            PU.state.previewMode.pinnedEntries.delete(key);
            PU.state.previewMode.pinnedTexts.delete(key);
        }
        PU.compositions.closeOrphanModal();
        PU.compositions.populateFromPreview();
        PU.compositions.render();
    },

    /**
     * Commit Selection: export the curated set (undimmed entries).
     * Future: integrate with build pipeline.
     */
    commitSelection() {
        const items = PU.state.previewMode.compositions.filter(e => {
            const key = `${e.sources[0].blockPath}|${e.sources[0].comboKey}`;
            return !PU.state.previewMode.dimmedEntries.has(key);
        });
        PU.actions.showToast(`Selection committed: ${items.length} entries`, 'success');
    },

    // ── Flat List Renderer ────────────────────────────────────────────

    /**
     * Render flat list — entries grouped by blockPath, no tree chrome.
     * Pinned entries sort first within each group.
     * Each item shows segmented resolved text (ancestor ── own) for hover targeting.
     */
    _renderTreeView(items) {
        if (items.length === 0) return '<div class="pu-rp-note">No items in preview</div>';

        const esc = PU.blocks.escapeHtml;

        // 1. Group entries by blockPath
        const groups = {};
        for (const entry of items) {
            const bp = entry.sources[0].blockPath;
            if (!groups[bp]) groups[bp] = [];
            groups[bp].push(entry);
        }

        // 2. Sort paths hierarchically
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

        // 3. Sort pinned entries first within each group
        for (const p of paths) {
            groups[p].sort((a, b) => {
                const aPinned = PU.compositions._isPinned(a.sources[0].blockPath, a.sources[0].comboKey) ? 0 : 1;
                const bPinned = PU.compositions._isPinned(b.sources[0].blockPath, b.sources[0].comboKey) ? 0 : 1;
                return aPinned - bPinned;
            });
        }

        // 4. Precompute ancestor text cache (first entry per path)
        const ancestorText = {};
        for (const path of paths) {
            ancestorText[path] = groups[path][0].text;
        }

        // 5. Render flat list with segmented text
        const overflow = PU.state.previewMode.pathOverflow || {};
        let html = '';
        for (const path of paths) {
            const entries = groups[path];
            const parts = path.split('.');

            // Build ancestor chain with paths
            const ancestorChain = [];
            for (let i = 1; i < parts.length; i++) {
                const aPath = parts.slice(0, i).join('.');
                if (ancestorText[aPath]) {
                    ancestorChain.push({ path: aPath, text: ancestorText[aPath] });
                }
            }

            const safePath = esc(path).replace(/'/g, '&#39;');

            for (const entry of entries) {
                const src = entry.sources[0];
                const isPinned = PU.compositions._isPinned(src.blockPath, src.comboKey);
                const isOrphan = entry._orphan || false;

                let cls = 'pu-compositions-item';
                if (PU.compositions._isDimmed(src.blockPath, src.comboKey)) cls += ' pu-compositions-dimmed';
                if (isPinned) cls += ' pu-compositions-pinned';
                if (isOrphan) cls += ' pu-compositions-orphan';

                const safeKey = esc(src.comboKey).replace(/'/g, '&#39;');
                const safeBp = esc(src.blockPath).replace(/'/g, '&#39;');

                const pinIcon = isPinned ? '<span class="pu-compositions-pin-icon">\uD83D\uDCCC</span>' : '';
                const orphanIcon = isOrphan ? '<span class="pu-compositions-orphan-icon" title="Not in current composition">\u26A0</span>' : '';

                // Build segmented text with separator range-select targets
                // Each separator's path = the NEXT segment's path (the range start)
                let textHtml = '';
                for (let j = 0; j < ancestorChain.length; j++) {
                    const a = ancestorChain[j];
                    const nextPath = j + 1 < ancestorChain.length ? ancestorChain[j + 1].path : path;
                    const safeNext = esc(nextPath).replace(/'/g, '&#39;');
                    textHtml += `<span class="pu-compositions-segment" data-segment-path="${esc(a.path)}">${esc(a.text)}</span>`;
                    textHtml += `<span class="pu-compositions-separator" data-separator-path="${esc(nextPath)}" onclick="event.stopPropagation(); if(event.shiftKey){PU.compositions.toggleDimBlock('${safeNext}')}else{PU.compositions.magnify('${safeNext}')}"> \u2500\u2500 </span>`;
                }
                textHtml += `<span class="pu-compositions-segment pu-compositions-segment-own" data-segment-path="${esc(path)}">${esc(entry.text)}</span>`;

                html += `<div class="${cls}" data-testid="pu-compositions-item-${esc(path)}" data-block-path="${esc(src.blockPath)}" data-combo-key="${esc(src.comboKey)}" onclick="PU.compositions._handleItemClick('${safeBp}', '${safeKey}', event)">`;
                html += pinIcon + orphanIcon;
                html += `<span class="pu-compositions-item-text" data-testid="pu-compositions-resolved">${textHtml}</span>`;
                html += '</div>';
            }

            // Render "+N more" link if this path has overflow
            if (overflow[path] && overflow[path] > 0) {
                html += `<div class="pu-compositions-show-more" data-testid="pu-compositions-show-more-${esc(path)}" onclick="event.stopPropagation(); PU.editorMode.showMoreVariations('${safePath}')">`;
                html += `<span class="pu-compositions-show-more-text">+${overflow[path].toLocaleString()} more</span>`;
                html += '</div>';
            }
        }
        return html;
    },

    // ── Display Helpers ──────────────────────────────────────────────

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

    /** Get compositions curation data for session snapshot. */
    getSessionData() {
        return {
            dimmed: [...PU.state.previewMode.dimmedEntries],
            pinned: [...PU.state.previewMode.pinnedEntries],
            pinnedTexts: Object.fromEntries(PU.state.previewMode.pinnedTexts)
        };
    },

    /** Hydrate compositions curation from session data (backward-compatible). */
    hydrateFromSession(data) {
        // Backward compat: Phase 1 stored dimmed_entries as a plain string array
        if (Array.isArray(data)) {
            PU.state.previewMode.dimmedEntries = new Set(
                data.filter(item => typeof item === 'string')
            );
            return;
        }

        if (!data || typeof data !== 'object') return;

        // Phase 2 format: { dimmed, pinned, pinnedTexts }
        if (Array.isArray(data.dimmed)) {
            PU.state.previewMode.dimmedEntries = new Set(
                data.dimmed.filter(item => typeof item === 'string')
            );
        }
        if (Array.isArray(data.pinned)) {
            PU.state.previewMode.pinnedEntries = new Set(
                data.pinned.filter(item => typeof item === 'string')
            );
        }
        if (data.pinnedTexts && typeof data.pinnedTexts === 'object') {
            PU.state.previewMode.pinnedTexts = new Map(
                Object.entries(data.pinnedTexts).filter(([k, v]) =>
                    typeof k === 'string' && typeof v === 'string'
                )
            );
        }
    }
};
