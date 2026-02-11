/**
 * PromptyUI - Blocks
 *
 * Block rendering and management for content and ext_text blocks.
 */

PU.blocks = {
    /**
     * Render a block (content or ext_text)
     */
    renderBlock(item, path, depth = 0, resolutions) {
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
        `;

        const resolution = resolutions ? resolutions.get(path) : null;

        if ('content' in item) {
            html += PU.blocks.renderContentBlock(item, path, pathId, resolution);
        } else if ('ext_text' in item) {
            html += PU.blocks.renderExtTextBlock(item, path, pathId, resolution);
        }

        // Render nested children (after)
        if (item.after && item.after.length > 0) {
            html += `<div class="pu-block-children">`;
            item.after.forEach((child, idx) => {
                const childPath = `${path}.${idx}`;
                html += PU.blocks.renderBlock(child, childPath, depth + 1, resolutions);
            });
            html += `</div>`;
        }

        html += `</div>`;

        return html;
    },

    /**
     * Render content input block with resolved text and inline dropdowns
     */
    renderContentBlock(item, path, pathId, resolution) {
        const content = item.content || '';
        const accumulatedHtml = resolution ? PU.blocks.renderAccumulatedText(resolution) : '';

        if (resolution) {
            return `
                <div class="pu-block-content pu-block-clickable" data-testid="pu-block-input-${pathId}" data-path="${path}">
                    <div class="pu-block-edit-icon">&#9998;</div>
                    <div class="pu-resolved-text">${resolution.resolvedHtml}</div>
                    ${accumulatedHtml}
                </div>
            `;
        }

        // Fallback: show escaped raw text (loading state or no resolution)
        return `
            <div class="pu-block-content pu-block-clickable" data-testid="pu-block-input-${pathId}" data-path="${path}">
                <div class="pu-block-edit-icon">&#9998;</div>
                <div class="pu-resolved-text">${PU.blocks.escapeHtml(content)}</div>
            </div>
        `;
    },

    /**
     * Render ext_text reference block
     */
    renderExtTextBlock(item, path, pathId, resolution) {
        const extName = item.ext_text || '';
        const extMax = item.ext_text_max;

        const resolvedContent = resolution
            ? `<div class="pu-resolved-text">${resolution.resolvedHtml}</div>`
            : '';
        const accumulatedHtml = resolution ? PU.blocks.renderAccumulatedText(resolution) : '';

        return `
            <div class="pu-block-content">
                <div class="pu-exttext-ref" data-testid="pu-block-exttext-${pathId}"
                     onclick="PU.actions.selectBlock('${path}')">
                    <span class="pu-exttext-icon">&#128218;</span>
                    <span class="pu-exttext-name">ext_text: ${extName}</span>
                    ${extMax !== undefined ? `<span class="pu-exttext-count">(max: ${extMax})</span>` : ''}
                </div>
                ${resolvedContent}
                ${accumulatedHtml}
                <div class="pu-exttext-settings">
                    <label>
                        ext_text_max:
                        <input type="number" min="0" value="${extMax || 0}"
                               onchange="PU.actions.updateExtTextMax('${path}', this.value)">
                    </label>
                </div>
            </div>
        `;
    },

    /**
     * Render accumulated text showing parent (inherited) and current block text.
     * @param {Object} resolution - Resolution object with plainText, parentAccumulatedText
     * @returns {string} HTML string
     */
    renderAccumulatedText(resolution) {
        if (!resolution || !resolution.accumulatedText) return '';

        const inherited = resolution.parentAccumulatedText || '';
        if (!inherited) return '';

        const current = resolution.plainText || '';

        let html = '<div class="pu-accumulated-text">';
        if (inherited) {
            html += `<span class="pu-accumulated-inherited">${PU.blocks.escapeHtml(inherited)}</span>`;
            // Determine separator between inherited and current
            if (current) {
                const seps = [',', ' ', '\n', '\t'];
                const needsSpace = !seps.some(s => inherited.trimEnd().endsWith(s)) &&
                                   !seps.some(s => current.trimStart().startsWith(s));
                if (needsSpace) {
                    html += '<span class="pu-accumulated-inherited"> </span>';
                }
            }
        }
        if (current) {
            html += `<span class="pu-accumulated-current">${PU.blocks.escapeHtml(current)}</span>`;
        }
        html += '</div>';
        return html;
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
     * Render resolved text with inline wildcard dropdowns.
     * Converts {{wc:value}} markers to dropdown spans.
     */
    renderResolvedTextWithDropdowns(resolvedText, wildcardDropdowns, path) {
        if (!resolvedText) return '';

        // First, HTML-escape while preserving markers
        let html = PU.preview.escapeHtmlPreservingMarkers(resolvedText);

        // Replace {{wc:value}} markers with plain styled pills (non-interactive)
        html = html.replace(/\{\{([^:]+):([^}]+)\}\}/g, (match, wcName, value) => {
            return `<span class="pu-wc-resolved-pill">${PU.blocks.escapeHtml(value)}</span>`;
        });

        return html;
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
