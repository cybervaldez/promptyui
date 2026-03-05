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
     * Check if a blockPath falls within a separator's subtree.
     * Matches the exact path and its descendants — same as magnify() isolation.
     * E.g., separator "0.1" matches "0.1", "0.1.0", "0.1.2.3", but not "0.2" or "0.0".
     */
    _isInSeparatorRange(blockPath, separatorPath) {
        return blockPath === separatorPath || blockPath.startsWith(separatorPath + '.');
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

    /** Highlight compositions items whose block path starts with the given path. */
    _highlightItemsBySegmentPath(blockPath) {
        document.querySelectorAll(`.pu-compositions-item[data-block-path]`).forEach(item => {
            const bp = item.dataset.blockPath;
            if (bp === blockPath || bp.startsWith(blockPath + '.')) {
                item.classList.add('pu-compositions-hover-from-preview');
            }
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

        // Group header hover: highlight all items in the group + footer tip
        const headers = body.querySelectorAll('.pu-compositions-header-row[data-header-path]');
        headers.forEach(header => {
            header.addEventListener('mouseenter', (e) => {
                e.stopPropagation();
                const headerPath = header.dataset.headerPath;
                if (!headerPath) return;
                const group = header.closest('.pu-compositions-group');
                if (group) {
                    group.querySelectorAll('.pu-compositions-item').forEach(item => {
                        item.classList.add('pu-compositions-hover-from-preview');
                    });
                }
                PU.rightPanel._showFooterTip('<kbd>click</kbd> magnify · <kbd>⇧click</kbd> dim');
            });
            header.addEventListener('mouseleave', () => {
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
        return mode === 'preview' || mode === 'export';
    },

    /** Render the compositions footer panel (C3 design). */
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

        // Append ephemeral preview entries from lock popup
        const previewItems = PU.state.previewMode.previewCompositions || [];
        if (previewItems.length > 0) {
            items = [...items, ...previewItems];
        }

        const countEl = panel.querySelector('[data-testid="pu-compositions-count"]');
        if (countEl) {
            const { wildcardCounts, extTextCount } = PU.shared.getCompositionParams();
            const lockedValues = PU.state.previewMode.lockedValues || {};
            const lockedTotal = PU.shared.computeLockedTotal(wildcardCounts, extTextCount, lockedValues);
            countEl.textContent = lockedTotal.toLocaleString();
        }

        const isExport = PU.state.ui.editorMode === 'export';

        // Apply view mode classes to panel
        const viewMode = PU.state.previewMode.compositionsViewMode || 'full';
        const showPaths = PU.state.previewMode.compositionsShowPaths || false;
        panel.classList.toggle('pu-compositions-view-leaf', viewMode === 'leaf');
        panel.classList.toggle('pu-compositions-view-flat', viewMode === 'flat');
        panel.classList.toggle('pu-compositions-show-paths', showPaths);
        panel.classList.toggle('pu-compositions-export-mode', isExport);

        // Render breadcrumb bar
        const breadcrumbEl = panel.querySelector('[data-testid="pu-compositions-breadcrumb"]');
        if (breadcrumbEl) {
            if (isExport) {
                breadcrumbEl.innerHTML = PU.compositions._renderExportStatusBar(items.length);
            } else {
                breadcrumbEl.innerHTML = PU.compositions._renderBreadcrumbBar(magnified, items.length);
            }
        }

        // Render lock strip in compositions area (hidden in export mode)
        const lockStripEl = panel.querySelector('[data-testid="pu-compositions-lock-strip"]');
        if (lockStripEl) {
            lockStripEl.innerHTML = isExport ? '' : PU.compositions._renderLockStrip();
        }

        const body = panel.querySelector('[data-testid="pu-compositions-body"]');
        if (body) {
            if (isExport) {
                body.innerHTML = PU.compositions._renderFlatExportView(items);
            } else {
                body.innerHTML = PU.compositions._renderTreeView(items);
                PU.compositions._applyLastVisible(body);
                PU.compositions._attachCompositionsHoverListeners(body);
                PU.compositions._attachSmartSticky(body);
            }
        }

        // Render action bar
        const actionBar = panel.querySelector('[data-testid="pu-compositions-action-bar"]');
        if (actionBar) {
            if (isExport) {
                actionBar.innerHTML = PU.compositions._renderExportActionBar(items.length);
            } else {
                actionBar.innerHTML = PU.compositions._renderActionBar();
            }
        }
    },

    // ── Magnifier ─────────────────────────────────────────────────────

    /** Magnify into a subtree (filter compositions to this path and descendants). */
    magnify(path) {
        PU.state.previewMode.magnifiedPath = path;
        // Track deepest path for togglable breadcrumb
        const deepest = PU.state.previewMode.deepestMagnifiedPath;
        if (!deepest || path.length > deepest.length || path.startsWith(deepest + '.') ||
            (!deepest.startsWith(path) && !path.startsWith(deepest))) {
            PU.state.previewMode.deepestMagnifiedPath = path;
        }
        PU.compositions.render();
        PU.actions.updateUrl();
    },

    /** Clear magnification — show all compositions. */
    clearMagnify() {
        PU.state.previewMode.magnifiedPath = null;
        PU.state.previewMode.deepestMagnifiedPath = null;
        PU.compositions.render();
        PU.actions.updateUrl();
    },

    // ── C3 View Controls ──────────────────────────────────────────────

    /** Set the view mode (full / leaf / flat). */
    setViewMode(mode) {
        PU.state.previewMode.compositionsViewMode = mode;
        PU.compositions.render();
    },

    /** Toggle path numbers visibility. */
    toggleShowPaths() {
        PU.state.previewMode.compositionsShowPaths = !PU.state.previewMode.compositionsShowPaths;
        PU.compositions.render();
    },

    /** Render the C3 breadcrumb bar (always visible, contains view controls). */
    _renderBreadcrumbBar(magnifiedPath, itemCount) {
        const esc = PU.blocks.escapeHtml;
        const viewMode = PU.state.previewMode.compositionsViewMode || 'full';
        const showPaths = PU.state.previewMode.compositionsShowPaths || false;
        let html = '';

        // Breadcrumb navigation
        if (magnifiedPath) {
            const parts = magnifiedPath.split('.');
            html += `<span class="pu-compositions-crumb" onclick="PU.compositions.clearMagnify()" data-testid="pu-compositions-crumb-all">All</span>`;

            for (let i = 0; i < parts.length; i++) {
                const subPath = parts.slice(0, i + 1).join('.');
                const isLast = i === parts.length - 1;
                const safePath = esc(subPath).replace(/'/g, '&#39;');
                html += '<span class="pu-compositions-crumb-sep">&rsaquo;</span>';
                if (isLast) {
                    html += `<span class="pu-compositions-crumb pu-compositions-crumb-current">${esc(subPath)}</span>`;
                } else {
                    html += `<span class="pu-compositions-crumb" onclick="PU.compositions.magnify('${safePath}')">${esc(subPath)}</span>`;
                }
            }

            // Show deeper crumbs from deepestMagnifiedPath (preserved for navigation back)
            const deepest = PU.state.previewMode.deepestMagnifiedPath;
            if (deepest && deepest !== magnifiedPath && deepest.startsWith(magnifiedPath + '.')) {
                const deeperParts = deepest.split('.');
                for (let i = parts.length; i < deeperParts.length; i++) {
                    const subPath = deeperParts.slice(0, i + 1).join('.');
                    const safePath = esc(subPath).replace(/'/g, '&#39;');
                    html += '<span class="pu-compositions-crumb-sep pu-compositions-crumb-deeper">&rsaquo;</span>';
                    html += `<span class="pu-compositions-crumb pu-compositions-crumb-deeper" onclick="PU.compositions.magnify('${safePath}')">${esc(subPath)}</span>`;
                }
            }
        } else {
            html += '<span class="pu-compositions-crumb pu-compositions-crumb-current">All</span>';
        }

        html += '<span style="flex:1"></span>';

        // Segmented view control
        html += '<div class="pu-compositions-view-seg" data-testid="pu-compositions-view-seg">';
        for (const m of ['full', 'leaf', 'flat']) {
            const label = m.charAt(0).toUpperCase() + m.slice(1);
            const cls = m === viewMode ? ' class="active"' : '';
            html += `<button${cls} onclick="PU.compositions.setViewMode('${m}')">${esc(label)}</button>`;
        }
        html += '</div>';

        // Paths toggle
        const pathsCls = showPaths ? ' active' : '';
        html += `<button class="pu-compositions-paths-btn${pathsCls}" onclick="PU.compositions.toggleShowPaths()" title="Show path numbers" data-testid="pu-compositions-paths-btn">#</button>`;

        // Close button when magnified
        if (magnifiedPath) {
            html += `<button class="pu-compositions-crumb-close" onclick="PU.compositions.clearMagnify()" data-testid="pu-compositions-crumb-close" title="Clear focus">&times;</button>`;
        } else {
            // Total count
            html += `<span style="font-size:10px;color:var(--pu-text-muted);">${itemCount.toLocaleString()}</span>`;
        }

        return html;
    },

    /** Render lock strip chips for the compositions area (mirrors editor lock strip). */
    _renderLockStrip() {
        const locked = PU.state.previewMode.lockedValues;
        if (!locked) return '';
        const entries = Object.entries(locked).filter(([, vals]) => vals && vals.length > 1);
        if (entries.length === 0) return '';

        const esc = PU.blocks.escapeHtml;
        let html = '<span style="font-size:10px;opacity:0.5;">\u{1F512}</span>';
        for (const [name, vals] of entries) {
            const eName = esc(name);
            const eVals = vals.map(v => esc(v)).join(', ');
            const safeName = eName.replace(/'/g, '&#39;');
            html += `<span class="pu-compositions-lock-chip" data-testid="pu-comp-lock-chip-${eName}"
                           onclick="PU.editorMode.openLockPopupByName('${safeName}')">
                <span class="pu-compositions-lock-chip-name">${eName}:</span>
                <span>${eVals}</span>
                <span class="pu-compositions-lock-chip-close" onclick="event.stopPropagation(); PU.editorMode.clearLock('${safeName}')">&times;</span>
            </span>`;
        }
        html += '<a class="pu-compositions-lock-clear" onclick="PU.editorMode.clearAllLocks()">Clear</a>';
        return html;
    },

    /**
     * Compute parent prefix for an entry by matching its comboKey against ancestor entries.
     * Returns the full resolved ancestor text chain (e.g., "CEO Engineering ").
     */
    _getParentPrefix(entry, groups) {
        const src = entry.sources[0];
        const parts = src.blockPath.split('.');
        if (parts.length <= 1) return '';

        const ancestorPaths = [];
        for (let i = 1; i < parts.length; i++) {
            ancestorPaths.push(parts.slice(0, i).join('.'));
        }

        const entryPairs = src.comboKey ? new Set(src.comboKey.split('|')) : new Set();
        const chain = [];
        for (const aPath of ancestorPaths) {
            const aEntries = groups[aPath];
            if (!aEntries) continue;
            if (aEntries.length === 1) {
                chain.push(aEntries[0].text);
            } else {
                const match = aEntries.find(ae => {
                    const aPairs = ae.sources[0].comboKey.split('|');
                    return aPairs.every(p => entryPairs.has(p));
                });
                chain.push(match ? match.text : aEntries[0].text);
            }
        }
        return chain.length > 0 ? chain.join(' ') + ' ' : '';
    },

    // ── Export Mode Renderers ─────────────────────────────────────────

    /** Render the export status bar (replaces breadcrumb bar in export mode). */
    _renderExportStatusBar(itemCount) {
        const dimCount = PU.state.previewMode.dimmedEntries.size;
        const pinCount = PU.state.previewMode.pinnedEntries.size;
        const activeCount = itemCount - PU.state.previewMode.compositions.filter(e => {
            const key = `${e.sources[0].blockPath}|${e.sources[0].comboKey}`;
            return PU.state.previewMode.dimmedEntries.has(key);
        }).length;

        let html = '<span class="pu-compositions-export-title" data-testid="pu-compositions-export-title">Export</span>';
        html += '<span style="flex:1"></span>';

        let summary = `${activeCount.toLocaleString()} composition${activeCount !== 1 ? 's' : ''}`;
        if (dimCount > 0) summary += ` (${dimCount} excluded)`;
        if (pinCount > 0) summary += ` (${pinCount} pinned)`;
        html += `<span class="pu-compositions-export-summary" data-testid="pu-compositions-export-summary">${summary}</span>`;
        return html;
    },

    /** Render flat export view — numbered list with parent prefix, no tree grouping, no interactions. */
    _renderFlatExportView(items) {
        if (items.length === 0) return '<div class="pu-rp-note">No compositions to export</div>';

        const esc = PU.blocks.escapeHtml;
        const dimmed = PU.state.previewMode.dimmedEntries;

        // Build groups for parent prefix lookup
        const groups = {};
        for (const entry of items) {
            const p = entry.sources[0].blockPath;
            if (!groups[p]) groups[p] = [];
            groups[p].push(entry);
        }

        // Filter out dimmed entries for export view
        const activeItems = items.filter(e => {
            const key = `${e.sources[0].blockPath}|${e.sources[0].comboKey}`;
            return !dimmed.has(key);
        });

        if (activeItems.length === 0) return '<div class="pu-rp-note">All compositions excluded</div>';

        let html = '';
        for (let i = 0; i < activeItems.length; i++) {
            const entry = activeItems[i];
            const isPinned = PU.compositions._isPinned(entry.sources[0].blockPath, entry.sources[0].comboKey);
            const pinBadge = isPinned ? '<span class="pu-compositions-pin-icon" title="Pinned from another composition">\uD83D\uDCCC</span>' : '';
            const parentPrefix = PU.compositions._getParentPrefix(entry, groups);
            const fullText = parentPrefix + entry.text;

            html += `<div class="pu-compositions-export-item" data-testid="pu-compositions-export-item">`;
            html += `<span class="pu-compositions-export-num">${i + 1}.</span>`;
            html += pinBadge;
            html += `<span class="pu-compositions-export-text">${esc(fullText)}</span>`;
            html += '</div>';
        }
        return html;
    },

    /** Render export action bar — Build + Copy All. */
    _renderExportActionBar(itemCount) {
        const dimmed = PU.state.previewMode.dimmedEntries;
        const activeCount = PU.state.previewMode.compositions.filter(e => {
            const key = `${e.sources[0].blockPath}|${e.sources[0].comboKey}`;
            return !dimmed.has(key);
        }).length;

        let html = '<div class="pu-compositions-actions">';
        html += `<button class="pu-btn pu-btn-small" onclick="PU.compositions.copyAllExport()" data-testid="pu-compositions-copy-all">Copy All</button>`;
        html += '<span style="flex:1"></span>';
        html += `<button class="pu-btn pu-btn-small pu-btn-primary" onclick="PU.compositions.commitSelection()" data-testid="pu-compositions-build">Commit Selection (${activeCount})</button>`;
        html += '</div>';
        return html;
    },

    /** Copy all active (non-dimmed) compositions to clipboard with parent prefix. */
    copyAllExport() {
        const dimmed = PU.state.previewMode.dimmedEntries;
        const allItems = PU.state.previewMode.compositions;
        const items = allItems.filter(e => {
            const key = `${e.sources[0].blockPath}|${e.sources[0].comboKey}`;
            return !dimmed.has(key);
        });
        // Build groups for parent prefix lookup
        const groups = {};
        for (const entry of allItems) {
            const p = entry.sources[0].blockPath;
            if (!groups[p]) groups[p] = [];
            groups[p].push(entry);
        }
        const text = items.map((e, i) => {
            const prefix = PU.compositions._getParentPrefix(e, groups);
            return `${i + 1}. ${prefix}${e.text}`;
        }).join('\n\n');
        navigator.clipboard.writeText(text).then(() => {
            PU.actions.showToast(`Copied ${items.length} compositions`, 'success');
        });
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
     * C3 Grouped Tree View — entries grouped by blockPath with sticky headers.
     * Parent text (from ancestors) shown in capped-width span, leaf text gets remaining space.
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

        // 3. Sort: pinned first, preview last within each group
        for (const p of paths) {
            groups[p].sort((a, b) => {
                const aPreview = a._preview ? 1 : 0;
                const bPreview = b._preview ? 1 : 0;
                if (aPreview !== bPreview) return aPreview - bPreview;
                const aPinned = PU.compositions._isPinned(a.sources[0].blockPath, a.sources[0].comboKey) ? 0 : 1;
                const bPinned = PU.compositions._isPinned(b.sources[0].blockPath, b.sources[0].comboKey) ? 0 : 1;
                return aPinned - bPinned;
            });
        }

        // 4. Ancestor entries by path (for per-entry parent prefix matching)
        const ancestorEntries = {};
        for (const path of paths) {
            ancestorEntries[path] = groups[path];
        }

        // 5. Build template text for group headers
        const templateHtml = PU.compositions._buildGroupTemplates(paths);

        // 6. Render grouped HTML
        const overflow = PU.state.previewMode.pathOverflow || {};
        let html = '';
        for (const path of paths) {
            const entries = groups[path];
            const parts = path.split('.');
            const depth = parts.length - 1;
            const isSingleEntry = entries.length === 1;
            const safePath = esc(path).replace(/'/g, '&#39;');

            // Group wrapper
            let groupCls = 'pu-compositions-group';
            if (isSingleEntry) groupCls += ' pu-compositions-single-entry';
            html += `<div class="${groupCls}" data-depth="${depth}" data-testid="pu-compositions-group-${esc(path)}">`;

            // Sticky header
            html += '<div class="pu-compositions-group-sticky">';
            html += `<div class="pu-compositions-header-row" data-header-path="${esc(path)}">`;

            // Path chain
            html += '<div class="pu-compositions-path-chain">';
            for (let i = 0; i < parts.length; i++) {
                const subPath = parts.slice(0, i + 1).join('.');
                const safeSubPath = esc(subPath).replace(/'/g, '&#39;');
                if (i > 0) html += '<span class="pu-compositions-path-sep">&gt;</span>';
                html += `<span class="pu-compositions-path-seg" onclick="PU.compositions.magnify('${safeSubPath}')">${esc(subPath)}</span>`;
            }
            html += '</div>';

            // Template text
            html += `<span class="pu-compositions-template-text">${templateHtml[path] || esc(path)}</span>`;

            // Entry count
            const total = entries.length + (overflow[path] || 0);
            html += `<span class="pu-compositions-entry-count">${total.toLocaleString()} ${total === 1 ? 'entry' : 'entries'}</span>`;

            html += '</div>'; // header-row
            html += '</div>'; // group-sticky

            // Entries
            const hasOverflow = overflow[path] && overflow[path] > 0;
            for (let ei = 0; ei < entries.length; ei++) {
                const entry = entries[ei];
                const src = entry.sources[0];
                const isPinned = PU.compositions._isPinned(src.blockPath, src.comboKey);
                const isOrphan = entry._orphan || false;
                const isPreview = entry._preview || false;
                const isLast = ei === entries.length - 1;

                let cls = 'pu-compositions-item';
                if (PU.compositions._isDimmed(src.blockPath, src.comboKey)) cls += ' pu-compositions-dimmed';
                if (isPinned) cls += ' pu-compositions-pinned';
                if (isOrphan) cls += ' pu-compositions-orphan';
                if (isPreview) cls += ' pu-compositions-preview';

                const safeKey = esc(src.comboKey).replace(/'/g, '&#39;');
                const safeBp = esc(src.blockPath).replace(/'/g, '&#39;');

                const pinIcon = isPinned ? '<span class="pu-compositions-pin-icon">\uD83D\uDCCC</span>' : '';
                const orphanIcon = isOrphan ? '<span class="pu-compositions-orphan-icon" title="Not in current composition">\u26A0</span>' : '';
                const previewIcon = isPreview ? '<span class="pu-compositions-preview-icon">\u2192</span>' : '';

                const parentPrefix = PU.compositions._getParentPrefix(entry, ancestorEntries);

                // Build parent/leaf text split
                let textHtml = `<span class="pu-compositions-parent-text">${esc(parentPrefix)}</span>`;
                textHtml += `<span class="pu-compositions-leaf-text">${esc(entry.text)}</span>`;

                const clickHandler = isPreview ? '' : ` onclick="PU.compositions._handleItemClick('${safeBp}', '${safeKey}', event)"`;
                html += `<div class="${cls}" data-testid="pu-compositions-item-${esc(path)}" data-block-path="${esc(src.blockPath)}" data-combo-key="${esc(src.comboKey)}" data-group-path="${esc(path)}"${clickHandler}>`;
                html += pinIcon + orphanIcon + previewIcon;
                html += `<span class="pu-compositions-item-text" data-testid="pu-compositions-resolved">${textHtml}</span>`;
                html += '</div>';

                // Preview overflow pill — standalone row after last preview entry in this group
                if (isPreview && entry._previewOverflow > 0 && isLast) {
                    html += `<div class="pu-compositions-preview-overflow-pill" data-testid="pu-compositions-preview-overflow-${esc(path)}">+${entry._previewOverflow.toLocaleString()} more</div>`;
                }
            }

            // Show more row (standalone)
            if (hasOverflow) {
                html += `<div class="pu-compositions-show-more-row" data-testid="pu-compositions-show-more-${esc(path)}" onclick="PU.editorMode.showMoreVariations('${safePath}')">+${overflow[path].toLocaleString()} more entries</div>`;
            }

            html += '</div>'; // group
        }
        return html;
    },

    /**
     * Build template HTML for group headers.
     * Uses the preview block's template view (wildcard pills + static text).
     */
    _buildGroupTemplates(paths) {
        const result = {};
        const esc = PU.blocks.escapeHtml;
        // Try to get template from preview blocks
        for (const path of paths) {
            const parts = path.split('.');
            const previewBlock = document.querySelector(`.pu-preview-block[data-path="${path}"]`);
            if (previewBlock) {
                // Extract the own segment text from the preview
                const seg = previewBlock.querySelector('.pu-preview-segment-own');
                if (seg) {
                    // Build chain: ancestor templates + own template
                    let chain = '';
                    for (let i = 1; i < parts.length; i++) {
                        const aPath = parts.slice(0, i).join('.');
                        const aBlock = document.querySelector(`.pu-preview-block[data-path="${aPath}"] .pu-preview-segment-own`);
                        if (aBlock && chain) chain += '<span class="pu-compositions-template-sep">\u2500\u2500</span>';
                        if (aBlock) chain += aBlock.innerHTML;
                    }
                    if (chain) chain += '<span class="pu-compositions-template-sep">\u2500\u2500</span>';
                    chain += seg.innerHTML;
                    result[path] = chain;
                    continue;
                }
            }
            // Fallback: use path as label
            result[path] = esc(path);
        }
        return result;
    },

    /** Apply .pu-compositions-last-visible class to last item before each show-more row. */
    _applyLastVisible(body) {
        body.querySelectorAll('.pu-compositions-last-visible').forEach(el =>
            el.classList.remove('pu-compositions-last-visible')
        );
        body.querySelectorAll('.pu-compositions-group').forEach(group => {
            const showMore = group.querySelector('.pu-compositions-show-more-row');
            if (!showMore) return;
            let prev = showMore.previousElementSibling;
            while (prev && !prev.classList.contains('pu-compositions-item')) {
                prev = prev.previousElementSibling;
            }
            if (prev) prev.classList.add('pu-compositions-last-visible');
        });
    },

    /** Attach smart sticky scroll listener (only active group header sticks). */
    _attachSmartSticky(body) {
        const groups = body.querySelectorAll('.pu-compositions-group');
        if (groups.length < 2) return;
        body.addEventListener('scroll', function _stickyHandler() {
            const scrollTop = body.scrollTop;
            let activeGroup = null;
            groups.forEach(g => {
                const top = g.offsetTop;
                const bottom = top + g.offsetHeight;
                if (top <= scrollTop + 2 && bottom > scrollTop + 2) activeGroup = g;
            });
            groups.forEach(g => {
                const header = g.querySelector('.pu-compositions-group-sticky');
                if (header) header.classList.toggle('stuck', g === activeGroup);
            });
        });
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
