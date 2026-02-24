/**
 * PromptyUI - Theme Management
 *
 * Blocks-first theme management: swap, diff, save-as-theme, dissolve.
 * Terminology: ext (code) = theme (UI), ext_text (code) = theme block (UI).
 */

PU.themes = {

    // ── Feature 1: Add Theme as Child ──

    addThemeAsChild(parentPath, anchorEl) {
        PU.rightPanel.showExtensionPicker((extId) => {
            PU.themes.insertExtTextAsChild(parentPath, extId);
        }, anchorEl);
    },

    insertExtTextAsChild(parentPath, extId) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;
        if (!Array.isArray(prompt.text)) prompt.text = [];

        const parent = PU.blocks.findBlockByPath(prompt.text, parentPath);
        if (!parent) return;
        if (!parent.after) parent.after = [];
        parent.after.push({ ext_text: extId });
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        const shortName = extId.split('/').pop();
        PU.actions.showToast(`Added theme: ${shortName}`, 'success');
    },

    // ── Feature 2: Swap Theme + Diff ──

    async openSwapDropdown(event, path, currentTheme) {
        event.stopPropagation();
        PU.overlay.dismissAll();

        const state = PU.state.themes.swapDropdown;
        state.visible = true;
        state.path = path;
        state.currentTheme = currentTheme;

        const alternatives = PU.themes._getAlternatives(currentTheme);
        PU.themes._renderSwapDropdown(event.target.closest('.pu-theme-label'), alternatives);
        PU.overlay.showOverlay();
    },

    _getAlternatives(currentTheme) {
        const parts = currentTheme.split('/');
        const fileName = parts[parts.length - 1];
        const tree = PU.state.globalExtensions.tree;

        // Navigate to the parent folder in the tree
        let node = tree;
        for (let i = 0; i < parts.length - 1; i++) {
            node = node && node[parts[i]] ? node[parts[i]] : null;
        }

        if (!node || !node._files) return [];

        const folder = parts.slice(0, -1).join('/');
        return node._files
            .filter(f => f.id !== fileName)
            .map(f => ({
                id: folder ? `${folder}/${f.id}` : f.id,
                name: f.id,
                wildcardCount: f.wildcardCount || 0
            }));
    },

    _renderSwapDropdown(anchor, alternatives) {
        // Remove existing
        const existing = document.getElementById('pu-theme-swap-dropdown');
        if (existing) existing.remove();

        const dd = document.createElement('div');
        dd.id = 'pu-theme-swap-dropdown';
        dd.setAttribute('data-testid', 'pu-theme-swap-dropdown');

        if (alternatives.length === 0) {
            dd.innerHTML = '<div class="pu-swap-empty">No alternatives in folder</div>';
        } else {
            let html = '<div class="pu-swap-header">Swap to</div>';
            alternatives.forEach(alt => {
                const eName = PU.blocks.escapeHtml(alt.name);
                const eId = PU.blocks.escapeAttr(alt.id);
                html += `<div class="pu-swap-item" data-testid="pu-theme-swap-item-${PU.blocks.escapeAttr(alt.name)}"
                              onclick="PU.themes.performSwap('${eId}')"
                              onmouseenter="PU.themes.showDiffPopover('${eId}', this)"
                              onmouseleave="PU.themes._hideDiffPopover()">
                    <span>${eName}</span>
                    <span class="pu-swap-badge">${alt.wildcardCount} wc</span>
                </div>`;
            });
            dd.innerHTML = html;
        }

        document.body.appendChild(dd);

        // Position below anchor
        const rect = anchor.getBoundingClientRect();
        dd.style.left = rect.left + 'px';
        dd.style.top = (rect.bottom + 4) + 'px';

        // Keep within viewport
        const ddRect = dd.getBoundingClientRect();
        if (ddRect.right > window.innerWidth) {
            dd.style.left = (window.innerWidth - ddRect.width - 8) + 'px';
        }
        if (ddRect.bottom > window.innerHeight) {
            dd.style.top = (rect.top - ddRect.height - 4) + 'px';
        }
    },

    async showDiffPopover(targetThemeId, anchorEl) {
        const currentId = PU.state.themes.swapDropdown.currentTheme;
        if (!currentId) return;

        try {
            const [currentExt, targetExt] = await Promise.all([
                PU.api.loadExtension(currentId),
                PU.api.loadExtension(targetThemeId)
            ]);

            const currentWcList = (currentExt.wildcards || []).filter(w => w.name);
            const targetWcList = (targetExt.wildcards || []).filter(w => w.name);
            const currentNames = currentWcList.map(w => w.name);
            const targetNames = targetWcList.map(w => w.name);

            // Build lookup maps for values
            const currentValMap = {};
            currentWcList.forEach(w => { currentValMap[w.name] = w.text || []; });
            const targetValMap = {};
            targetWcList.forEach(w => { targetValMap[w.name] = w.text || []; });

            // Mapped: in both current and target (values transfer)
            const mapped = currentNames.filter(n => targetNames.includes(n)).map(n => ({
                name: n,
                values: targetValMap[n]
            }));
            // Orphaned: in target but not in current (need values)
            const orphaned = targetNames.filter(n => !currentNames.includes(n)).map(n => ({
                name: n,
                values: targetValMap[n]
            }));
            // Removed: in current but not in target (will be lost)
            const removed = currentNames.filter(n => !targetNames.includes(n)).map(n => ({
                name: n,
                oldValues: currentValMap[n]
            }));

            PU.state.themes.diffPopover = {
                visible: true,
                targetTheme: targetThemeId,
                diffData: { mapped, orphaned, removed, total: currentNames.length }
            };

            PU.themes._renderDiffPopover(anchorEl);
        } catch (e) {
            // Silently fail — diff is optional enhancement
            console.warn('Failed to load diff:', e);
        }
    },

    _renderDiffPopover(anchorEl) {
        const existing = document.getElementById('pu-theme-diff-popover');
        if (existing) existing.remove();

        const diff = PU.state.themes.diffPopover.diffData;
        if (!diff) return;

        const dp = document.createElement('div');
        dp.id = 'pu-theme-diff-popover';
        dp.setAttribute('data-testid', 'pu-theme-diff-popover');

        const esc = PU.blocks.escapeHtml;
        const targetName = (PU.state.themes.diffPopover.targetTheme || '').split('/').pop();

        // Subtitle: compatibility level
        const matchCount = diff.mapped.length;
        const total = diff.total;
        let subtitle = '';
        if (matchCount === total && total > 0) {
            subtitle = `Full match &mdash; all ${total} wildcards shared`;
        } else if (matchCount > 0) {
            subtitle = `Partial match &mdash; ${matchCount} of ${total} wildcards shared`;
        } else {
            subtitle = `No match &mdash; 0 of ${total} wildcards shared`;
        }

        let html = `<div class="pu-diff-header-bar">
            <div class="pu-diff-title">&#128230; ${esc(targetName)}</div>
            <div class="pu-diff-subtitle">${subtitle}</div>
        </div>`;

        html += '<div class="pu-diff-body">';

        // Mapped section
        if (diff.mapped.length > 0) {
            html += `<div class="pu-diff-section">
                <div class="pu-diff-slabel mapped">&#10003; Mapped (${diff.mapped.length})</div>`;
            for (const wc of diff.mapped) {
                const vals = Array.isArray(wc.values) ? wc.values.slice(0, 3).join(', ') : '';
                html += `<div class="pu-diff-row">
                    <span class="pu-diff-wc">__${esc(wc.name)}__</span>
                    <span class="pu-diff-arrow">&rarr;</span>
                    <span class="pu-diff-vals new">${esc(vals)}</span>
                </div>`;
            }
            html += '</div>';
        }

        // Orphaned section (in target, not in current — will need values)
        if (diff.orphaned.length > 0) {
            html += `<div class="pu-diff-section">
                <div class="pu-diff-slabel orphaned">&#9888; New in target (${diff.orphaned.length})</div>`;
            for (const wc of diff.orphaned) {
                const vals = Array.isArray(wc.values) ? wc.values.slice(0, 3).join(', ') : '';
                html += `<div class="pu-diff-row">
                    <span class="pu-diff-wc">__${esc(wc.name)}__</span>
                    <span class="pu-diff-arrow">&larr;</span>
                    <span class="pu-diff-vals fresh">${esc(vals)}</span>
                </div>`;
            }
            html += '</div>';
        }

        // Removed section (in current, not in target — will be lost)
        if (diff.removed.length > 0) {
            html += `<div class="pu-diff-section">
                <div class="pu-diff-slabel removed">&#10005; Removed (${diff.removed.length})</div>`;
            for (const wc of diff.removed) {
                const vals = Array.isArray(wc.oldValues) ? wc.oldValues.slice(0, 3).join(', ') : '';
                html += `<div class="pu-diff-row">
                    <span class="pu-diff-wc">__${esc(wc.name)}__</span>
                    <span class="pu-diff-arrow">&rarr;</span>
                    <span class="pu-diff-vals old">${esc(vals)}</span>
                </div>`;
            }
            html += '</div>';
        }

        html += '</div>';

        // Footer button
        const hasOrphaned = diff.orphaned.length > 0;
        const btnClass = hasOrphaned ? 'warn' : 'safe';
        const btnText = hasOrphaned ? 'Swap &amp; fill missing values' : 'Swap theme';
        html += `<div class="pu-diff-footer">
            <button class="pu-diff-btn ${btnClass}" onclick="PU.themes.performSwap('${PU.blocks.escapeAttr(PU.state.themes.diffPopover.targetTheme)}')">${btnText}</button>
        </div>`;

        if (!diff.mapped.length && !diff.orphaned.length && !diff.removed.length) {
            dp.innerHTML = '<div class="pu-swap-empty">No wildcard data</div>';
        } else {
            dp.innerHTML = html;
        }

        document.body.appendChild(dp);

        // Position to the right of the dropdown
        const dd = document.getElementById('pu-theme-swap-dropdown');
        if (dd) {
            const ddRect = dd.getBoundingClientRect();
            dp.style.left = (ddRect.right + 4) + 'px';

            // Vertically align with the hovered item
            if (anchorEl) {
                const itemRect = anchorEl.getBoundingClientRect();
                dp.style.top = itemRect.top + 'px';
            } else {
                dp.style.top = ddRect.top + 'px';
            }

            // Keep within viewport
            const dpRect = dp.getBoundingClientRect();
            if (dpRect.right > window.innerWidth) {
                dp.style.left = (ddRect.left - dpRect.width - 4) + 'px';
            }
            if (dpRect.bottom > window.innerHeight) {
                dp.style.top = (window.innerHeight - dpRect.height - 8) + 'px';
            }
        }
    },

    _hideDiffPopover() {
        PU.state.themes.diffPopover = { visible: false, targetTheme: null, diffData: null };
        const dp = document.getElementById('pu-theme-diff-popover');
        if (dp) dp.remove();
    },

    performSwap(targetThemeId) {
        const path = PU.state.themes.swapDropdown.path;
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (block && 'ext_text' in block) {
            block.ext_text = targetThemeId;
        }

        PU.themes.closeSwapDropdown();
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        const shortName = targetThemeId.split('/').pop();
        PU.actions.showToast(`Swapped to ${shortName}`, 'success');
    },

    closeSwapDropdown() {
        PU.state.themes.swapDropdown = { visible: false, path: null, currentTheme: null };
        PU.state.themes.diffPopover = { visible: false, targetTheme: null, diffData: null };
        const dd = document.getElementById('pu-theme-swap-dropdown');
        if (dd) dd.remove();
        const dp = document.getElementById('pu-theme-diff-popover');
        if (dp) dp.remove();
    },

    // ── Feature 3: Context Menu ──

    openContextMenu(event, path, isTheme) {
        event.stopPropagation();
        PU.overlay.dismissAll();

        PU.state.themes.contextMenu = { visible: true, path, isTheme };

        // Mark the source block so its ⋯ button stays visible
        const block = document.querySelector(`.pu-block[data-path="${path}"]`);
        if (block) block.classList.add('pu-ctx-active');

        PU.themes._renderContextMenu(event);
        PU.overlay.showOverlay();
    },

    _renderContextMenu(event) {
        const cm = document.createElement('div');
        cm.id = 'pu-theme-context-menu';
        cm.setAttribute('data-testid', 'pu-theme-context-menu');

        const { path, isTheme } = PU.state.themes.contextMenu;
        const ePath = PU.blocks.escapeAttr(path);
        const isChild = path.includes('.');

        let items = '';

        // Primary actions: Edit, Annotate, Move to Theme
        items += `<div class="pu-ctx-item" data-testid="pu-ctx-edit" onclick="PU.themes.closeContextMenu(); PU.actions.selectBlock('${ePath}'); PU.focus.enter('${ePath}')">&#9998; Edit</div>`;
        items += `<div class="pu-ctx-item" data-testid="pu-ctx-annotate" onclick="PU.themes.closeContextMenu(); PU.annotations.toggleEditor('${ePath}')">&#127991; Annotate</div>`;
        if (!isChild && !isTheme && PU.moveToTheme) {
            items += `<div class="pu-ctx-item" data-testid="pu-ctx-move-theme" onclick="PU.themes.closeContextMenu(); PU.moveToTheme.open('${ePath}')">&#8593; Move to Theme</div>`;
        }

        // ext_text_max setting for theme blocks
        if (isTheme) {
            const prompt = PU.helpers.getActivePrompt();
            const block = prompt ? PU.blocks.findBlockByPath(prompt.text, path) : null;
            const currentMax = (block && block.ext_text_max) || 0;
            items += `<div class="pu-ctx-item pu-ctx-inline-field" data-testid="pu-ctx-ext-max" onclick="event.stopPropagation()">
                <span>Max texts</span>
                <input type="number" min="0" value="${currentMax}" data-testid="pu-ctx-ext-max-input"
                       onclick="event.stopPropagation()"
                       onchange="PU.actions.updateExtTextMax('${ePath}', this.value)">
                <span class="pu-ctx-field-hint">0 = all</span>
            </div>`;
        }

        items += '<div class="pu-ctx-divider"></div>';

        items += `<div class="pu-ctx-item" onclick="PU.themes.moveBlock('${ePath}', 'up')">&#8593; Move Up</div>`;
        items += `<div class="pu-ctx-item" onclick="PU.themes.moveBlock('${ePath}', 'down')">&#8595; Move Down</div>`;
        items += `<div class="pu-ctx-item" onclick="PU.themes.duplicateBlock('${ePath}')">&#9776; Duplicate</div>`;

        // Nesting: Add Child / Insert Theme as Child (replaces hover-only nest buttons on touch)
        if (!isChild) {
            items += `<div class="pu-ctx-item" data-testid="pu-ctx-add-child" onclick="PU.themes.closeContextMenu(); PU.actions.addNestedBlock('${ePath}')">&#8627; Add Child</div>`;
            items += `<div class="pu-ctx-item" data-testid="pu-ctx-insert-theme" onclick="PU.themes.closeContextMenu(); PU.themes.addThemeAsChild('${ePath}')">&#128230; Insert Theme as Child</div>`;
        }

        items += '<div class="pu-ctx-divider"></div>';

        if (isTheme) {
            items += `<div class="pu-ctx-item" onclick="PU.themes.dissolve('${ePath}')">&#9881; Dissolve into Blocks</div>`;
        }

        items += `<div class="pu-ctx-item" onclick="PU.themes.openSaveModal('${ePath}')">&#128190; Save as Theme</div>`;

        items += '<div class="pu-ctx-divider"></div>';
        items += `<div class="pu-ctx-item danger" onclick="PU.themes._deleteFromMenu('${ePath}')">&#128465; Delete</div>`;

        cm.innerHTML = items;
        document.body.appendChild(cm);

        // Position: anchor to the ⋯ button if it triggered the event,
        // placing the menu's top-right corner at the button's bottom-right.
        const btn = event.target.closest('.block-more');
        const cmRect = cm.getBoundingClientRect();

        if (btn) {
            const btnRect = btn.getBoundingClientRect();
            // Top-right of menu aligns to bottom-right of button
            let left = btnRect.right - cmRect.width;
            let top = btnRect.bottom + 4;

            // Keep within viewport
            if (left < 8) left = 8;
            if (top + cmRect.height > window.innerHeight) {
                // Flip above the button if not enough space below
                top = btnRect.top - cmRect.height - 4;
                if (top < 8) top = 8;
            }
            cm.style.left = left + 'px';
            cm.style.top = top + 'px';
        } else {
            // Fallback: position at click coordinates
            cm.style.left = event.clientX + 'px';
            cm.style.top = event.clientY + 'px';

            // Keep within viewport
            const rect = cm.getBoundingClientRect();
            if (rect.right > window.innerWidth) {
                cm.style.left = (window.innerWidth - rect.width - 8) + 'px';
            }
            if (rect.bottom > window.innerHeight) {
                cm.style.top = (window.innerHeight - rect.height - 8) + 'px';
            }
        }
    },

    closeContextMenu() {
        // Remove active mark from source block
        const prev = document.querySelector('.pu-block.pu-ctx-active');
        if (prev) prev.classList.remove('pu-ctx-active');

        PU.state.themes.contextMenu = { visible: false, path: null, isTheme: false };
        const cm = document.getElementById('pu-theme-context-menu');
        if (cm) cm.remove();
    },

    _deleteFromMenu(path) {
        PU.themes.closeContextMenu();
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        PU.blocks.deleteBlockAtPath(prompt.text, path);
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.state.selectedBlockPath = null;
        PU.actions.showToast('Block deleted', 'success');
    },

    moveBlock(path, direction) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const parts = path.split('.');
        const idx = parseInt(parts[parts.length - 1], 10);
        const newIdx = direction === 'up' ? idx - 1 : idx + 1;

        // Find parent array
        let arr = prompt.text;
        if (parts.length > 1) {
            const parentPath = parts.slice(0, -1).join('.');
            const parent = PU.blocks.findBlockByPath(prompt.text, parentPath);
            if (parent && parent.after) arr = parent.after;
            else return;
        }

        if (newIdx < 0 || newIdx >= arr.length) {
            PU.themes.closeContextMenu();
            return;
        }

        [arr[idx], arr[newIdx]] = [arr[newIdx], arr[idx]];
        PU.themes.closeContextMenu();
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
    },

    duplicateBlock(path) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const parts = path.split('.');
        const idx = parseInt(parts[parts.length - 1], 10);

        let arr = prompt.text;
        if (parts.length > 1) {
            const parentPath = parts.slice(0, -1).join('.');
            const parent = PU.blocks.findBlockByPath(prompt.text, parentPath);
            if (parent && parent.after) arr = parent.after;
            else return;
        }

        const clone = PU.helpers.deepClone(arr[idx]);
        arr.splice(idx + 1, 0, clone);
        PU.themes.closeContextMenu();
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.actions.showToast('Block duplicated', 'success');
    },

    // ── Feature 3b: Save as Theme ──

    openSaveModal(path) {
        PU.overlay.dismissAll();
        PU.state.themes.saveModal = { visible: true, blockPath: path };
        PU.themes._renderSaveModal(path);
        PU.overlay.showOverlay();
    },

    _renderSaveModal(path) {
        const modal = document.querySelector('[data-testid="pu-theme-save-modal"]');
        if (!modal) return;

        // Populate folder selector from extension tree
        const folderSelect = document.querySelector('[data-testid="pu-theme-save-folder"]');
        if (folderSelect) {
            const folders = [''];
            const walkTree = (node, prefix) => {
                for (const [key, value] of Object.entries(node)) {
                    if (key === '_files') continue;
                    const folderPath = prefix ? `${prefix}/${key}` : key;
                    folders.push(folderPath);
                    walkTree(value, folderPath);
                }
            };
            walkTree(PU.state.globalExtensions.tree, '');
            folderSelect.innerHTML = folders.map(f =>
                `<option value="${PU.blocks.escapeAttr(f)}">${f || '(root)'}</option>`
            ).join('');
        }

        // Build preview of what will be saved
        const preview = document.querySelector('[data-testid="pu-theme-save-preview"]');
        if (preview) {
            const prompt = PU.helpers.getActivePrompt();
            const block = prompt ? PU.blocks.findBlockByPath(prompt.text, path) : null;
            if (block) {
                const extData = PU.themes._buildExtensionData(block, prompt);
                const textCount = extData.text ? extData.text.length : 0;
                const wcCount = extData.wildcards ? extData.wildcards.length : 0;
                preview.textContent = `${textCount} text entries, ${wcCount} wildcards`;
            } else {
                preview.textContent = 'No block data';
            }
        }

        // Auto-fill name from block path
        const nameInput = document.querySelector('[data-testid="pu-theme-save-name"]');
        if (nameInput) {
            const prompt = PU.helpers.getActivePrompt();
            const block = prompt ? PU.blocks.findBlockByPath(prompt.text, path) : null;
            if (block && 'ext_text' in block) {
                nameInput.value = block.ext_text.split('/').pop() + '-copy';
            } else {
                nameInput.value = `block-${path.replace(/\./g, '-')}`;
            }
        }

        modal.style.display = 'flex';
    },

    _buildExtensionData(block, prompt) {
        const result = { text: [], wildcards: [] };

        // Collect text content from the block subtree
        const collectText = (b) => {
            if ('content' in b && b.content) {
                result.text.push(b.content);
            }
            if ('ext_text' in b) {
                result.text.push(`__ext:${b.ext_text}__`);
            }
            if (b.after) {
                b.after.forEach(child => collectText(child));
            }
        };
        collectText(block);

        // Collect wildcards referenced in the text
        const allText = result.text.join(' ');
        const wcNames = PU.blocks.detectWildcards(allText);
        const wcLookup = PU.helpers.getWildcardLookup();

        for (const name of wcNames) {
            if (wcLookup[name]) {
                result.wildcards.push({ name, text: wcLookup[name] });
            }
        }

        return result;
    },

    async confirmSave() {
        const nameInput = document.querySelector('[data-testid="pu-theme-save-name"]');
        const folderSelect = document.querySelector('[data-testid="pu-theme-save-folder"]');
        if (!nameInput || !folderSelect) return;

        const name = nameInput.value.trim();
        const folder = folderSelect.value;
        if (!name) {
            PU.actions.showToast('Name required', 'error');
            return;
        }

        // Validate name
        if (!/^[a-zA-Z0-9_-]+$/.test(name)) {
            PU.actions.showToast('Name can only contain letters, numbers, hyphens, underscores', 'error');
            return;
        }

        const path = PU.state.themes.saveModal.blockPath;
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        const extData = PU.themes._buildExtensionData(block, prompt);
        const savePath = folder ? `${folder}/${name}` : name;

        try {
            await PU.api.post('/api/pu/extension/save', {
                path: savePath,
                data: extData
            });
            PU.themes.closeSaveModal();
            PU.actions.showToast(`Saved as theme: ${name}`, 'success');
            await PU.api.loadExtensions(); // Refresh tree
        } catch (e) {
            PU.actions.showToast(`Save failed: ${e.message}`, 'error');
        }
    },

    closeSaveModal() {
        PU.state.themes.saveModal = { visible: false, blockPath: null };
        const modal = document.querySelector('[data-testid="pu-theme-save-modal"]');
        if (modal) modal.style.display = 'none';
    },

    // ── Feature 4: Dissolve into Blocks ──

    async dissolve(path) {
        PU.overlay.dismissPopovers();

        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block || !('ext_text' in block)) return;

        const extName = block.ext_text;
        let extData;
        try {
            extData = await PU.api.loadExtension(extName);
        } catch (e) {
            PU.actions.showToast(`Failed to load theme: ${e.message}`, 'error');
            return;
        }

        // Build content blocks from ext text entries
        const textEntries = [];
        for (const [key, val] of Object.entries(extData)) {
            if (key === 'text' || /^text\d+$/.test(key)) {
                const items = Array.isArray(val) ? val : [val];
                items.forEach(t => textEntries.push({ content: String(t) }));
            }
        }

        // Copy wildcards to prompt (skip duplicates)
        const existingWcNames = new Set((prompt.wildcards || []).map(w => w.name));
        if (!prompt.wildcards) prompt.wildcards = [];
        for (const wc of (extData.wildcards || [])) {
            if (wc.name && !existingWcNames.has(wc.name)) {
                prompt.wildcards.push(PU.helpers.deepClone(wc));
                existingWcNames.add(wc.name);
            }
        }

        // Replace the ext_text block with inline content blocks
        PU.blocks.updateBlockAtPath(prompt.text, path, (arr, idx) => {
            if (textEntries.length === 0) {
                arr[idx] = { content: '' };
                return;
            }
            // First entry replaces the ext_text block
            const first = textEntries[0];
            // Remaining entries become children
            if (textEntries.length > 1) {
                first.after = textEntries.slice(1);
            }
            arr[idx] = first;
        });

        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.rightPanel.render();
        const shortName = extName.split('/').pop();
        PU.actions.showToast(`Dissolved "${shortName}" into blocks`, 'success');
    },

    // ── Feature 5: Source Pill Dropdown ──

    openSourceDropdown(event, path) {
        event.stopPropagation();
        PU.overlay.dismissAll();

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return;
        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        const currentSource = ('ext_text' in block) ? block.ext_text : 'content';
        const state = PU.state.themes.sourceDropdown;
        state.visible = true;
        state.path = path;
        state.currentSource = currentSource;

        const allThemes = PU.themes._getAllThemes();
        const anchor = event.target.closest('[data-has-source]');
        PU.themes._renderSourceDropdown(anchor, currentSource, allThemes);
        PU.overlay.showOverlay();
    },

    _getAllThemes() {
        const tree = PU.state.globalExtensions.tree;
        if (!tree || Object.keys(tree).length === 0) return [];

        const results = [];
        const walk = (node, folderPath) => {
            if (node._files) {
                for (const file of node._files) {
                    const id = folderPath ? `${folderPath}/${file.id}` : file.id;
                    results.push({
                        id,
                        name: file.id,
                        folder: folderPath || '',
                        textCount: file.textCount || 0,
                        wildcardCount: file.wildcardCount || 0
                    });
                }
            }
            for (const key of Object.keys(node)) {
                if (key === '_files') continue;
                const childFolder = folderPath ? `${folderPath}/${key}` : key;
                walk(node[key], childFolder);
            }
        };
        walk(tree, '');
        return results;
    },

    _renderSourceDropdown(anchor, currentSource, allThemes) {
        const existing = document.getElementById('pu-source-dropdown');
        if (existing) existing.remove();

        const dd = document.createElement('div');
        dd.id = 'pu-source-dropdown';
        dd.setAttribute('data-testid', 'pu-source-dropdown');

        let html = '';

        // "content" option
        const isContent = (currentSource === 'content');
        html += `<div class="pu-source-item${isContent ? ' active' : ''}" data-testid="pu-source-item-content" onclick="PU.themes.selectSource('content')">`;
        html += `<span><span class="pu-source-check">\u2713</span>content</span>`;
        html += `</div>`;

        if (allThemes.length > 0) {
            html += '<div class="pu-source-divider"></div>';

            // Group by folder
            const folders = {};
            for (const theme of allThemes) {
                const folder = theme.folder || '';
                if (!folders[folder]) folders[folder] = [];
                folders[folder].push(theme);
            }

            for (const [folder, themes] of Object.entries(folders)) {
                if (folder) {
                    html += `<div class="pu-source-folder-header">${PU.blocks.escapeHtml(folder.toUpperCase())}</div>`;
                }
                for (const theme of themes) {
                    const isActive = (currentSource === theme.id);
                    const eId = PU.blocks.escapeAttr(theme.id);
                    const eName = PU.blocks.escapeHtml(theme.name);
                    html += `<div class="pu-source-item${isActive ? ' active' : ''}" data-testid="pu-source-item-${PU.blocks.escapeAttr(theme.name)}" onclick="PU.themes.selectSource('${eId}')">`;
                    html += `<span><span class="pu-source-check">\u2713</span>${eName}</span>`;
                    if (theme.textCount > 0) {
                        html += `<span class="pu-source-badge">(${theme.textCount})</span>`;
                    }
                    html += `</div>`;
                }
            }
        }

        dd.innerHTML = html;
        document.body.appendChild(dd);

        // Position below anchor
        if (anchor) {
            const rect = anchor.getBoundingClientRect();
            dd.style.left = rect.left + 'px';
            dd.style.top = (rect.bottom + 4) + 'px';

            // Keep within viewport
            const ddRect = dd.getBoundingClientRect();
            if (ddRect.right > window.innerWidth) {
                dd.style.left = (window.innerWidth - ddRect.width - 8) + 'px';
            }
            if (ddRect.bottom > window.innerHeight) {
                dd.style.top = (rect.top - ddRect.height - 4) + 'px';
            }
        }
    },

    selectSource(sourceId) {
        const path = PU.state.themes.sourceDropdown.path;
        const currentSource = PU.state.themes.sourceDropdown.currentSource;
        if (!path || sourceId === currentSource) {
            PU.themes.closeSourceDropdown();
            PU.overlay.hideOverlay();
            return;
        }

        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        if (sourceId === 'content') {
            // Switch ext_text -> content
            delete block.ext_text;
            delete block.ext_text_max;
            block.content = '';
        } else if ('content' in block) {
            // Switch content -> ext_text
            delete block.content;
            block.ext_text = sourceId;
        } else {
            // Switch ext_text -> different ext_text
            block.ext_text = sourceId;
        }

        PU.themes.closeSourceDropdown();
        PU.overlay.hideOverlay();
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.editor.updateHeaderSaveState();
        const shortName = sourceId === 'content' ? 'content' : sourceId.split('/').pop();
        PU.actions.showToast(`Source: ${shortName}`, 'success');
    },

    closeSourceDropdown() {
        PU.state.themes.sourceDropdown = { visible: false, path: null, currentSource: null };
        const dd = document.getElementById('pu-source-dropdown');
        if (dd) dd.remove();
        PU.themes._hideDiffPopover();
    }
};

// Register theme overlays
PU.overlay.registerPopover('contextMenu', () => PU.themes.closeContextMenu());
PU.overlay.registerPopover('swapDropdown', () => PU.themes.closeSwapDropdown());
PU.overlay.registerPopover('sourceDropdown', () => PU.themes.closeSourceDropdown());
PU.overlay.registerModal('saveModal', () => PU.themes.closeSaveModal());
