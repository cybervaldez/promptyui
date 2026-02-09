/**
 * PromptyUI - Inspector
 *
 * Right sidebar panel showing context-aware information:
 * - Global extensions tree (top)
 * - Local context based on selection (bottom)
 */

PU.inspector = {
    /**
     * Initialize inspector
     */
    async init() {
        // Load extensions first (needed for the extensions tree)
        await PU.inspector.loadExtensions();
        PU.inspector.showOverview();
    },

    /**
     * Load extensions from API
     */
    async loadExtensions() {
        const container = document.querySelector('[data-testid="pu-inspector-ext-tree"]');
        if (!container) return;

        try {
            await PU.api.loadExtensions();
            PU.inspector.renderExtensionsTree();
        } catch (e) {
            container.innerHTML = `<div class="pu-tree-item error">Failed to load extensions</div>`;
            console.error('Failed to load extensions:', e);
        }
    },

    /**
     * Render mini extensions tree in inspector
     */
    renderExtensionsTree() {
        const container = document.querySelector('[data-testid="pu-inspector-ext-tree"]');
        if (!container) return;

        const tree = PU.state.globalExtensions.tree;
        const filter = PU.state.ui.inspectorExtensionFilter.toLowerCase();

        container.innerHTML = PU.inspector.renderExtTree(tree, '', filter);
    },

    /**
     * Render extension tree node
     */
    renderExtTree(node, path, filter) {
        let html = '';

        // Render folders
        for (const [key, value] of Object.entries(node)) {
            if (key === '_files') continue;

            const folderPath = path ? `${path}/${key}` : key;

            // Check if matches filter
            if (filter && !key.toLowerCase().includes(filter) && !PU.sidebar.folderMatchesFilter(value, filter)) {
                continue;
            }

            html += `
                <div class="pu-tree-item" onclick="PU.inspector.toggleExtFolder('${folderPath}')">
                    <span class="pu-tree-icon">&#128194;</span>
                    <span class="pu-tree-label">${key}</span>
                </div>
            `;

            // Always expanded in inspector for now
            html += `<div class="pu-tree-children">`;
            html += PU.inspector.renderExtTree(value, folderPath, filter);
            html += `</div>`;
        }

        // Render files
        const files = node._files || [];
        for (const file of files) {
            if (filter && !file.file.toLowerCase().includes(filter)) {
                continue;
            }

            const filePath = path ? `${path}/${file.file}` : file.file;

            html += `
                <div class="pu-tree-item" onclick="PU.inspector.selectExtFile('${filePath}')"
                     draggable="true"
                     ondragstart="PU.inspector.dragExtFile(event, '${file.id}')">
                    <span class="pu-tree-icon">&#128196;</span>
                    <span class="pu-tree-label">${file.id || file.file.replace('.yaml', '')}</span>
                </div>
            `;
        }

        return html;
    },

    /**
     * Toggle extension folder in inspector
     */
    toggleExtFolder(path) {
        // For now, just log - could add expand/collapse
        console.log('Toggle ext folder:', path);
    },

    /**
     * Select extension file for preview
     */
    async selectExtFile(path) {
        try {
            const data = await PU.api.loadExtension(path.replace('.yaml', ''));
            PU.inspector.showExtensionDetails(data, path);
        } catch (e) {
            console.error('Failed to load extension:', path, e);
            PU.actions.showToast(`Failed to load extension: ${e.message}`, 'error');
        }
    },

    /**
     * Drag extension file (for drag-and-drop to editor)
     */
    dragExtFile(event, extId) {
        event.dataTransfer.setData('text/plain', extId);
        event.dataTransfer.setData('application/x-pu-ext', extId);
    },

    /**
     * Show extension details in context panel
     */
    showExtensionDetails(data, path) {
        const container = document.querySelector('[data-testid="pu-inspector-context"]');
        if (!container) return;

        const textItems = [];
        for (const [key, value] of Object.entries(data)) {
            if (key === 'text' || /^text\d+$/.test(key)) {
                if (Array.isArray(value)) {
                    textItems.push(...value);
                } else if (typeof value === 'string') {
                    textItems.push(value);
                }
            }
        }

        const wildcards = data.wildcards || [];

        let html = `
            <div class="pu-wildcard-section">
                <div class="pu-wildcard-header">Extension: ${data.id || path}</div>
                <div style="font-size: 12px; color: var(--pu-text-muted); margin-bottom: 12px;">
                    ${textItems.length} text items, ${wildcards.length} wildcards
                </div>
        `;

        // Text items preview
        if (textItems.length > 0) {
            html += `
                <div class="pu-wildcard-header" style="margin-top: 12px;">Text Items</div>
            `;
            textItems.slice(0, 5).forEach((item, idx) => {
                html += `
                    <div class="pu-wildcard-value" style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">
                        ${idx + 1}. ${item.substring(0, 60)}${item.length > 60 ? '...' : ''}
                    </div>
                `;
            });
            if (textItems.length > 5) {
                html += `<div class="pu-wildcard-value">... and ${textItems.length - 5} more</div>`;
            }
        }

        // Wildcards
        if (wildcards.length > 0) {
            html += `
                <div class="pu-wildcard-header" style="margin-top: 12px;">Wildcards</div>
            `;
            wildcards.forEach(wc => {
                const values = Array.isArray(wc.text) ? wc.text : [wc.text];
                html += `
                    <div class="pu-wildcard-item">
                        <div class="pu-wildcard-name">
                            <span class="pu-wildcard-label">__${wc.name}__</span>
                            <span class="pu-wildcard-count">(${values.length})</span>
                        </div>
                    </div>
                `;
            });
        }

        html += `
                <button class="pu-btn pu-btn-small pu-btn-full" style="margin-top: 12px;"
                        onclick="PU.actions.insertExtText('${data.id}')">
                    Insert as ext_text
                </button>
            </div>
        `;

        container.innerHTML = html;
    },

    /**
     * Show wildcards context (when content block selected)
     */
    updateWildcardsContext(usedWildcards, promptWildcards) {
        const container = document.querySelector('[data-testid="pu-inspector-context"]');
        if (!container) return;

        // Build wildcard lookup from prompt
        const wildcardLookup = {};
        (promptWildcards || []).forEach(wc => {
            if (wc.name) {
                wildcardLookup[wc.name] = Array.isArray(wc.text) ? wc.text : [wc.text];
            }
        });

        let html = '';

        // Used wildcards
        if (usedWildcards.length > 0) {
            html += `
                <div class="pu-wildcard-section">
                    <div class="pu-wildcard-header">Used in this text (${usedWildcards.length})</div>
            `;

            usedWildcards.forEach(wcName => {
                const values = wildcardLookup[wcName] || [];
                const isDefined = values.length > 0;

                html += `
                    <div class="pu-wildcard-item" data-testid="pu-inspector-wc-${wcName}">
                        <div class="pu-wildcard-name" onclick="PU.inspector.toggleWildcard('${wcName}')">
                            <span class="pu-wildcard-label ${!isDefined ? 'undefined' : ''}">__${wcName}__</span>
                            <span class="pu-wildcard-count">${isDefined ? `(${values.length})` : '(undefined)'}</span>
                        </div>
                        <div class="pu-wildcard-values" data-testid="pu-inspector-wc-values-${wcName}">
                            ${values.map(v => `<div class="pu-wildcard-value">${v}</div>`).join('')}
                            ${isDefined ? `
                                <button class="pu-btn pu-btn-small" data-testid="pu-inspector-add-value-${wcName}"
                                        onclick="PU.inspector.addWildcardValue('${wcName}')">+ Add value</button>
                            ` : `
                                <button class="pu-btn pu-btn-small"
                                        onclick="PU.inspector.defineWildcard('${wcName}')">Define wildcard</button>
                            `}
                        </div>
                    </div>
                `;
            });

            html += `</div>`;
        }

        // Available wildcards (defined but not used in current text)
        const availableWildcards = Object.keys(wildcardLookup).filter(wc => !usedWildcards.includes(wc));
        if (availableWildcards.length > 0) {
            html += `
                <div class="pu-wildcard-section">
                    <div class="pu-wildcard-header">Available to insert (${availableWildcards.length})</div>
            `;

            availableWildcards.forEach(wcName => {
                const values = wildcardLookup[wcName];
                html += `
                    <div class="pu-wildcard-item">
                        <div class="pu-wildcard-name" onclick="PU.inspector.toggleWildcard('${wcName}')">
                            <span class="pu-wildcard-label">__${wcName}__</span>
                            <span class="pu-wildcard-count">(${values.length})</span>
                        </div>
                        <div class="pu-wildcard-values">
                            ${values.slice(0, 3).map(v => `<div class="pu-wildcard-value">${v}</div>`).join('')}
                            ${values.length > 3 ? `<div class="pu-wildcard-value">... ${values.length - 3} more</div>` : ''}
                            <button class="pu-btn pu-btn-small"
                                    onclick="PU.inspector.insertWildcard('${wcName}')">Insert at cursor</button>
                        </div>
                    </div>
                `;
            });

            html += `</div>`;
        }

        // Add new wildcard button
        html += `
            <div style="margin-top: 16px;">
                <button class="pu-btn pu-btn-full" onclick="PU.inspector.defineNewWildcard()">
                    + Define New Wildcard
                </button>
            </div>
        `;

        container.innerHTML = html || `
            <div class="pu-inspector-empty">
                <p>No wildcards in this text. Use __name__ syntax to add wildcards.</p>
            </div>
        `;
    },

    /**
     * Show prompt overview (no block selected)
     */
    showOverview() {
        const container = document.querySelector('[data-testid="pu-inspector-context"]');
        if (!container) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            container.innerHTML = `
                <div class="pu-inspector-empty">
                    <p>Select a block to see wildcards and context</p>
                </div>
            `;
            return;
        }

        const wildcards = prompt.wildcards || [];
        const textItems = prompt.text || [];

        // Count items
        let blockCount = 0;
        let maxDepth = 0;

        function countBlocks(items, depth = 0) {
            if (!Array.isArray(items)) return;
            for (const item of items) {
                blockCount++;
                maxDepth = Math.max(maxDepth, depth);
                if (item.after) {
                    countBlocks(item.after, depth + 1);
                }
            }
        }

        countBlocks(textItems);

        let html = `
            <div class="pu-wildcard-section">
                <div class="pu-wildcard-header">Prompt Overview</div>
                <div style="font-size: 12px; color: var(--pu-text-secondary); margin-bottom: 16px;">
                    <div>&#128202; Total blocks: ${blockCount}</div>
                    <div>&#128202; Max depth: ${maxDepth} levels</div>
                    <div>&#128202; Wildcards defined: ${wildcards.length}</div>
                </div>
            </div>
        `;

        // All wildcards
        if (wildcards.length > 0) {
            html += `
                <div class="pu-wildcard-section">
                    <div class="pu-wildcard-header">All Wildcards (${wildcards.length})</div>
            `;

            wildcards.forEach(wc => {
                const values = Array.isArray(wc.text) ? wc.text : [wc.text];
                html += `
                    <div class="pu-wildcard-item">
                        <div class="pu-wildcard-name" onclick="PU.inspector.toggleWildcard('${wc.name}')">
                            <span class="pu-wildcard-label">__${wc.name}__</span>
                            <span class="pu-wildcard-count">(${values.length})</span>
                        </div>
                        <div class="pu-wildcard-values">
                            ${values.map(v => `<div class="pu-wildcard-value">${v}</div>`).join('')}
                        </div>
                    </div>
                `;
            });

            html += `</div>`;
        }

        container.innerHTML = html;
    },

    /**
     * Toggle wildcard values visibility
     */
    toggleWildcard(wcName) {
        const valuesEl = document.querySelector(`[data-testid="pu-inspector-wc-values-${wcName}"]`);
        if (valuesEl) {
            valuesEl.classList.toggle('expanded');
        }
    },

    /**
     * Add value to existing wildcard
     */
    addWildcardValue(wcName) {
        const value = prompt(`Enter new value for __${wcName}__:`);
        if (!value) return;

        const promptData = PU.editor.getModifiedPrompt();
        if (!promptData) return;

        const wildcard = (promptData.wildcards || []).find(wc => wc.name === wcName);
        if (wildcard) {
            if (!Array.isArray(wildcard.text)) {
                wildcard.text = [wildcard.text];
            }
            wildcard.text.push(value);
        }

        // Refresh context
        const block = PU.blocks.findBlockByPath(promptData.text || [], PU.state.selectedBlockPath || '0');
        if (block && block.content) {
            const usedWildcards = PU.blocks.detectWildcards(block.content);
            PU.inspector.updateWildcardsContext(usedWildcards, promptData.wildcards || []);
        }
    },

    /**
     * Define a new wildcard
     */
    defineWildcard(wcName) {
        const value = prompt(`Enter first value for __${wcName}__:`);
        if (!value) return;

        const promptData = PU.editor.getModifiedPrompt();
        if (!promptData) return;

        if (!promptData.wildcards) {
            promptData.wildcards = [];
        }

        promptData.wildcards.push({
            name: wcName,
            text: [value]
        });

        // Refresh context
        const block = PU.blocks.findBlockByPath(promptData.text || [], PU.state.selectedBlockPath || '0');
        if (block && block.content) {
            const usedWildcards = PU.blocks.detectWildcards(block.content);
            PU.inspector.updateWildcardsContext(usedWildcards, promptData.wildcards || []);
        }
    },

    /**
     * Define a completely new wildcard
     */
    defineNewWildcard() {
        const name = prompt('Enter wildcard name (without __):');
        if (!name) return;

        const value = prompt(`Enter first value for __${name}__:`);
        if (!value) return;

        const promptData = PU.editor.getModifiedPrompt();
        if (!promptData) return;

        if (!promptData.wildcards) {
            promptData.wildcards = [];
        }

        promptData.wildcards.push({
            name: name,
            text: [value]
        });

        PU.actions.showToast(`Created wildcard __${name}__`, 'success');

        // Refresh context
        PU.inspector.showOverview();
    },

    /**
     * Insert wildcard at cursor in active input
     */
    insertWildcard(wcName) {
        const activeInput = document.querySelector('.pu-content-input:focus');
        if (!activeInput) {
            PU.actions.showToast('Click on a content input first', 'error');
            return;
        }

        const start = activeInput.selectionStart;
        const end = activeInput.selectionEnd;
        const text = activeInput.value;
        const insertion = `__${wcName}__`;

        activeInput.value = text.slice(0, start) + insertion + text.slice(end);
        activeInput.selectionStart = activeInput.selectionEnd = start + insertion.length;

        // Trigger input event
        activeInput.dispatchEvent(new Event('input'));
    },

    /**
     * Show extension picker popup
     */
    showExtensionPicker(onSelect) {
        PU.state.extPickerCallback = onSelect;
        const popup = document.querySelector('[data-testid="pu-ext-picker-popup"]');
        const tree = document.querySelector('[data-testid="pu-ext-picker-tree"]');
        const searchInput = document.querySelector('[data-testid="pu-ext-picker-search"]');

        // Clear search
        if (searchInput) searchInput.value = '';

        // Render tree with picker mode
        tree.innerHTML = PU.inspector.renderExtTreeForPicker(
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
        tree.innerHTML = PU.inspector.renderExtTreeForPicker(
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
        PU.inspector.closeExtPicker();
    },

    /**
     * Render extension tree for picker (click selects instead of showing details)
     */
    renderExtTreeForPicker(node, path, filter = '') {
        let html = '';

        // Render folders
        for (const [key, value] of Object.entries(node)) {
            if (key === '_files') continue;

            const folderPath = path ? `${path}/${key}` : key;

            // Check if matches filter
            if (filter && !key.toLowerCase().includes(filter) && !PU.inspector.folderMatchesPickerFilter(value, filter)) {
                continue;
            }

            html += `
                <div class="pu-tree-item pu-picker-folder">
                    <span class="pu-tree-icon">&#128194;</span>
                    <span class="pu-tree-label">${key}</span>
                </div>
            `;

            // Always expanded in picker
            html += `<div class="pu-tree-children">`;
            html += PU.inspector.renderExtTreeForPicker(value, folderPath, filter);
            html += `</div>`;
        }

        // Render files
        const files = node._files || [];
        for (const file of files) {
            const fileId = file.id || file.file.replace('.yaml', '');

            if (filter && !fileId.toLowerCase().includes(filter)) {
                continue;
            }

            // Count texts and wildcards for display
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
                     onclick="PU.inspector.selectExtForPicker('${fileId}')">
                    <span class="pu-tree-icon">&#128196;</span>
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
        // Check files in this folder
        const files = node._files || [];
        for (const file of files) {
            const fileId = file.id || file.file.replace('.yaml', '');
            if (fileId.toLowerCase().includes(filter)) {
                return true;
            }
        }

        // Check subfolders
        for (const [key, value] of Object.entries(node)) {
            if (key === '_files') continue;
            if (key.toLowerCase().includes(filter)) return true;
            if (PU.inspector.folderMatchesPickerFilter(value, filter)) return true;
        }

        return false;
    }
};
