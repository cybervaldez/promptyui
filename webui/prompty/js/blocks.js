/**
 * PromptyUI - Blocks
 *
 * Block rendering and management for content and ext_text blocks.
 */

PU.blocks = {
    /**
     * Render a block (content or ext_text)
     */
    renderBlock(item, path, depth = 0) {
        const isSelected = PU.state.selectedBlockPath === path;
        const pathId = path.replace(/\./g, '-');

        let html = `
            <div class="pu-block ${isSelected ? 'selected' : ''}"
                 data-testid="pu-block-${pathId}"
                 data-path="${path}">
                <div class="pu-block-header">
                    <span class="pu-block-toggle expanded"
                          onclick="PU.actions.toggleBlock('${path}')">&#9654;</span>
                    <span class="pu-block-path" data-testid="pu-block-path-${pathId}">Path: ${path}</span>
        `;

        if ('content' in item) {
            html += `<span class="pu-block-type">content</span>`;
        } else if ('ext_text' in item) {
            html += `<span class="pu-block-type">ext_text</span>`;
        }

        html += `
                    <div class="pu-block-actions">
                        <button class="pu-block-action" data-testid="pu-block-nest-btn-${pathId}"
                                onclick="PU.actions.addNestedBlock('${path}')"
                                title="Add nested block">+ Nest</button>
                        <button class="pu-block-action delete" data-testid="pu-block-delete-btn-${pathId}"
                                onclick="PU.actions.deleteBlock('${path}')"
                                title="Delete block">&#128465;</button>
                    </div>
                </div>
                <div class="pu-block-content">
        `;

        if ('content' in item) {
            html += PU.blocks.renderContentBlock(item, path, pathId);
        } else if ('ext_text' in item) {
            html += PU.blocks.renderExtTextBlock(item, path, pathId);
        }

        html += `</div>`;

        // Render nested children (after)
        if (item.after && item.after.length > 0) {
            html += `<div class="pu-block-children">`;
            item.after.forEach((child, idx) => {
                const childPath = `${path}.${idx}`;
                html += PU.blocks.renderBlock(child, childPath, depth + 1);
            });
            html += `</div>`;
        }

        html += `</div>`;

        return html;
    },

    /**
     * Render content input block
     */
    renderContentBlock(item, path, pathId) {
        const content = item.content || '';
        const wildcards = PU.blocks.detectWildcards(content);
        const hasWildcards = wildcards.length > 0;

        // Use Quill editor if available, otherwise fallback to textarea
        if (PU.quill && !PU.quill._fallback) {
            return `
                <div class="pu-content-quill" data-testid="pu-block-input-${pathId}" data-path="${path}" data-initial="${PU.blocks.escapeAttr(content)}"></div>
                ${hasWildcards ? `
                    <div class="pu-wc-summary" data-testid="pu-content-wc-summary-${pathId}">
                        ${PU.blocks.renderWildcardSummary(wildcards)}
                    </div>
                ` : `<div class="pu-wc-summary" data-testid="pu-content-wc-summary-${pathId}"></div>`}
            `;
        }

        // Fallback: plain textarea
        const wildcardLookup = PU.helpers.getWildcardLookup();
        return `
            <textarea class="pu-content-input${hasWildcards ? ' pu-content-has-wildcards' : ''}"
                      data-testid="pu-block-input-${pathId}"
                      data-path="${path}"
                      placeholder="Enter content... Use __name__ for template wildcards (replaced at build time)"
                      onfocus="PU.actions.selectBlock('${path}'); PU.actions.showPreviewForBlock('${path}')"
                      oninput="PU.actions.updateBlockContent('${path}', this.value)"
                      onblur="PU.actions.onBlockBlur('${path}')">${PU.blocks.escapeHtml(content)}</textarea>
            ${hasWildcards ? `
                <div class="pu-content-wildcards" data-testid="pu-content-wildcards-${pathId}">
                    ${PU.blocks.renderWildcardChips(wildcards, wildcardLookup)}
                </div>
            ` : ''}
        `;
    },

    /**
     * Render ext_text reference block
     */
    renderExtTextBlock(item, path, pathId) {
        const extName = item.ext_text || '';
        const extMax = item.ext_text_max;

        return `
            <div class="pu-exttext-ref" data-testid="pu-block-exttext-${pathId}"
                 onclick="PU.actions.selectBlock('${path}')">
                <span class="pu-exttext-icon">&#128218;</span>
                <span class="pu-exttext-name">ext_text: ${extName}</span>
                ${extMax !== undefined ? `<span class="pu-exttext-count">(max: ${extMax})</span>` : ''}
            </div>
            <div class="pu-exttext-settings">
                <label>
                    ext_text_max:
                    <input type="number" min="0" value="${extMax || 0}"
                           onchange="PU.actions.updateExtTextMax('${path}', this.value)">
                </label>
            </div>
        `;
    },

    /**
     * Detect wildcards in text
     */
    detectWildcards(text) {
        const matches = text.match(/__([a-zA-Z0-9_-]+)__/g) || [];
        const wildcards = matches.map(m => m.replace(/__/g, ''));
        return [...new Set(wildcards)]; // Unique
    },

    /**
     * Render wildcard chips for edit mode (visual affordance matching Preview Mode)
     */
    renderWildcardChips(wildcards, wildcardLookup) {
        return `
            <div class="pu-edit-wc-legend">
                <span class="pu-edit-wc-legend-label">Template wildcards</span>
                <span class="pu-edit-wc-legend-hint">__name__ syntax → replaced at build time</span>
            </div>
            <div class="pu-edit-wc-chips">
                ${wildcards.map(w => {
                    const values = wildcardLookup[w] || [];
                    const preview = values.slice(0, 3).join(', ');
                    const more = values.length > 3 ? ` +${values.length - 3}` : '';
                    const status = values.length === 0 ? 'undefined' : preview + more;
                    const statusClass = values.length === 0 ? 'pu-edit-wc-undefined' : '';
                    return `<span class="pu-edit-wc-chip ${statusClass}">
                        <span class="pu-edit-wc-chip-name">__${w}__</span>
                        <span class="pu-edit-wc-chip-arrow">&#9656;</span>
                        <span class="pu-edit-wc-chip-values">(${status})</span>
                    </span>`;
                }).join('')}
            </div>
        `;
    },

    /**
     * Render wildcard summary (simplified one-line form for Quill mode)
     */
    renderWildcardSummary(wildcards) {
        if (!wildcards || wildcards.length === 0) return '';
        return `<span class="pu-wc-summary-text">${wildcards.length} wildcard${wildcards.length !== 1 ? 's' : ''}: ${wildcards.join(', ')}</span>`;
    },

    /**
     * Escape HTML
     */
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    },

    /**
     * Escape text for use in HTML attributes
     */
    escapeAttr(text) {
        return (text || '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },

    /**
     * Find block by path in text array
     */
    findBlockByPath(textArray, path) {
        const parts = path.split('.').map(p => parseInt(p, 10));
        let current = textArray;

        for (let i = 0; i < parts.length; i++) {
            const idx = parts[i];

            if (Array.isArray(current)) {
                if (idx >= current.length) return null;
                current = current[idx];
            } else if (current && current.after) {
                if (idx >= current.after.length) return null;
                current = current.after[idx];
            } else {
                return null;
            }
        }

        return current;
    },

    /**
     * Update block at path
     */
    updateBlockAtPath(textArray, path, updater) {
        const parts = path.split('.').map(p => parseInt(p, 10));
        let current = textArray;
        let parent = null;
        let lastIndex = 0;

        for (let i = 0; i < parts.length - 1; i++) {
            const idx = parts[i];

            if (Array.isArray(current)) {
                parent = current;
                lastIndex = idx;
                current = current[idx];
            } else if (current && current.after) {
                parent = current.after;
                lastIndex = idx;
                current = current.after[idx];
            }
        }

        const finalIdx = parts[parts.length - 1];

        if (parts.length === 1) {
            // Root level
            updater(textArray, finalIdx);
        } else if (current && current.after) {
            // Nested level (current block's after array)
            updater(current.after, finalIdx);
        } else if (parent) {
            // Nested level (parent's array)
            if (parent[lastIndex] && parent[lastIndex].after) {
                updater(parent[lastIndex].after, finalIdx);
            }
        }
    },

    /**
     * Delete block at path
     */
    deleteBlockAtPath(textArray, path) {
        const parts = path.split('.').map(p => parseInt(p, 10));

        if (parts.length === 1) {
            // Root level
            textArray.splice(parts[0], 1);
            return;
        }

        // Navigate to parent
        let current = textArray;
        for (let i = 0; i < parts.length - 1; i++) {
            const idx = parts[i];
            if (Array.isArray(current)) {
                current = current[idx];
            } else if (current && current.after) {
                current = current.after[idx];
            }
        }

        // Delete from after array
        if (current && current.after) {
            current.after.splice(parts[parts.length - 1], 1);
        }
    },

    /**
     * Add nested block at path
     */
    addNestedBlockAtPath(textArray, parentPath, blockType) {
        const block = blockType === 'ext_text'
            ? { ext_text: '' }
            : { content: '' };

        if (!parentPath) {
            // Add to root
            textArray.push(block);
            return String(textArray.length - 1);
        }

        const parent = PU.blocks.findBlockByPath(textArray, parentPath);
        if (!parent) return null;

        if (!parent.after) {
            parent.after = [];
        }
        parent.after.push(block);

        return `${parentPath}.${parent.after.length - 1}`;
    }
};
