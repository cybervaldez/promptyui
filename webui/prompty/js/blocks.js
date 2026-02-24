/**
 * PromptyUI - Blocks
 *
 * Block rendering and management for content and ext_text blocks.
 */

PU.blocks = {
    /**
     * Render a block (content or ext_text)
     */
    renderBlock(item, path, depth = 0, resolutions, meta = {}) {
        const isSelected = PU.state.selectedBlockPath === path;
        const pathId = path.replace(/\./g, '-');
        const isChild = depth > 0;
        const hasChildren = item.after && item.after.length > 0;

        let html = `
            <div class="pu-block ${isSelected ? 'selected' : ''}${isChild ? ' pu-block-child' : ''}${hasChildren ? ' pu-has-children' : ''}"
                 data-testid="pu-block-${pathId}"
                 data-depth="${depth}"
                 data-path="${path}">`;

        const viz = PU.state.previewMode.visualizer;

        // Path divider for child blocks in animated modes (sits above block-body, like a diagram edge label)
        // In compact mode, path is rendered as inline badge inside content instead
        if (isChild && viz !== 'compact') {
            const divSrcSuffix = PU.blocks._renderSourceSuffix(item);
            const divSrcType = PU.blocks._getSourceType(item);
            html += `<div class="pu-path-divider" data-testid="pu-path-divider-${pathId}"><span class="pu-path-label" data-testid="pu-block-path-${pathId}" data-has-source data-source-type="${divSrcType}" onclick="event.stopPropagation(); PU.themes.openSourceDropdown(event, '${PU.blocks.escapeAttr(path)}')"><span class="pu-child-arrow">\u21B3</span>${path}${divSrcSuffix}</span><button class="pu-inline-action pu-path-delete" data-testid="pu-block-delete-btn-${pathId}" tabindex="-1" onclick="event.stopPropagation(); PU.actions.deleteBlock('${path}')" title="Delete block"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/></svg></button></div>`;
        }

        // Body wrapper: contains header/path + content + toolbar (not children)
        html += `<div class="pu-block-body">`;

        if (isChild) {
            // Path rendered in pu-path-divider (animated) or inline badge (compact) — no separate element here
        } else {
            // Root blocks: headerless compact (like children, no header bar)
            if (viz !== 'compact') {
                // Animated root: path divider without child arrow
                const divSrcSuffix = PU.blocks._renderSourceSuffix(item);
                const divSrcType = PU.blocks._getSourceType(item);
                html += `<div class="pu-path-divider pu-root-divider" data-testid="pu-path-divider-${pathId}">
                    <span class="pu-path-label" data-testid="pu-block-path-${pathId}"
                        data-has-source data-source-type="${divSrcType}"
                        onclick="event.stopPropagation(); PU.themes.openSourceDropdown(event, '${PU.blocks.escapeAttr(path)}')">${path}${divSrcSuffix}</span>
                    <button class="pu-inline-action pu-path-delete" data-testid="pu-block-delete-btn-${pathId}" tabindex="-1"
                        onclick="event.stopPropagation(); PU.actions.deleteBlock('${path}')" title="Delete block">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/></svg>
                    </button></div>`;
            }
            // Compact root: path hint rendered inline inside content (see renderContentBlock/renderExtTextBlock)
        }

        const resolution = resolutions ? resolutions.get(path) : null;

        if ('content' in item) {
            html += PU.blocks.renderContentBlock(item, path, pathId, resolution, depth, meta);
        } else if ('ext_text' in item) {
            html += PU.blocks.renderExtTextBlock(item, path, pathId, resolution, depth, meta);
        }

        // Right-edge actions are now rendered inside .pu-block-content (see renderContentBlock/renderExtTextBlock)

        html += `</div>`; // close .pu-block-body

        // Render nested children (after)
        if (item.after && item.after.length > 0) {
            html += `<div class="pu-block-children">`;
            item.after.forEach((child, idx) => {
                const childPath = `${path}.${idx}`;
                html += PU.blocks.renderBlock(child, childPath, depth + 1, resolutions, {
                    isLast: idx === item.after.length - 1,
                    siblingCount: item.after.length
                });
            });
            html += `</div>`;
        }

        // Nest button at bottom of block (visible on hover) — root blocks only
        if (!isChild) {
            html += `<div class="pu-nest-action"><button class="pu-nest-btn" data-testid="pu-nest-btn-${pathId}" onclick="PU.actions.addNestedBlock('${path}')" title="Add nested block">+ Add Child</button><button class="pu-nest-btn pu-nest-theme-btn" data-testid="pu-nest-theme-btn-${pathId}" onclick="PU.themes.addThemeAsChild('${path}', this)" title="Insert theme as child">+ Insert Theme</button></div>`;
        }

        html += `</div>`;

        return html;
    },

    /**
     * Render inline nest connector button for leaf blocks (no children)
     * Shows ── + NEST inline after text, in the same position as ──▾ on parent blocks
     */
    _renderNestConnector(path, pathId) {
        return `<button class="pu-nest-connector" data-testid="pu-nest-connector-${pathId}" onclick="event.stopPropagation(); PU.actions.addNestedBlock('${path}')" title="Add nested child block"><span class="pu-nest-connector-line"></span><span class="pu-nest-connector-plus">+</span><span class="pu-nest-connector-label">NEST</span></button>`;
    },

    /**
     * Render source suffix — inline separator + source label + arrow for path badges.
     * Returns inner HTML to be appended inside a path element (pu-block-path, pu-path-label, pu-child-path-hint).
     */
    _renderSourceSuffix(item) {
        if ('ext_text' in item) {
            const extName = item.ext_text || '';
            const shortName = PU.blocks.escapeHtml(extName.split('/').pop() || extName);
            return `<span class="pu-path-source-sep">&middot;</span><span class="pu-path-source" data-source-type="theme">${shortName}</span><span class="pu-path-source-arrow">&#9662;</span>`;
        }
        return `<span class="pu-path-source-sep">&middot;</span><span class="pu-path-source" data-source-type="content">content</span><span class="pu-path-source-arrow">&#9662;</span>`;
    },

    /** Get source type string for data attributes */
    _getSourceType(item) {
        return ('ext_text' in item) ? 'theme' : 'content';
    },

    /**
     * Render inline dice button that flows after content text (hover-only, animated modes only)
     */
    _renderInlineDice(pathId) {
        const viz = PU.state.previewMode.visualizer;
        if (viz === 'compact') return '';
        return `<span class="pu-inline-actions"><button class="pu-inline-action pu-inline-dice pu-viz-dice-btn" data-testid="pu-viz-dice-btn-${pathId}" tabindex="-1" title="Re-roll wildcards"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8.5" cy="8.5" r="1.2"/><circle cx="15.5" cy="8.5" r="1.2"/><circle cx="8.5" cy="15.5" r="1.2"/><circle cx="15.5" cy="15.5" r="1.2"/></svg></button></span>`;
    },

    /**
     * Render right-edge horizontal actions for compact mode (pencil + annotate + delete)
     */
    _renderInlineCompactActions(path, pathId, isChild = false, item = null, isExtText = false) {
        const viz = PU.state.previewMode.visualizer;
        if (viz !== 'compact') return '';
        const hasAnn = item && item.annotations && Object.keys(item.annotations).length > 0;
        const moveBtn = (!isChild && !isExtText) ? `<button class="pu-inline-action pu-inline-move" data-testid="pu-block-move-btn-${pathId}" tabindex="-1" onclick="event.stopPropagation(); PU.moveToTheme.open('${path}')" title="Move block to reusable theme"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg></button>` : '';
        const annotateBtn = `<button class="pu-inline-action pu-inline-annotate${hasAnn ? ' has-annotations' : ''}" data-testid="pu-block-annotate-btn-${pathId}" tabindex="-1" onclick="event.stopPropagation(); PU.annotations.toggleEditor('${path}')" title="Annotate block"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="12" height="12"><path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/></svg></button>`;
        const deleteBtn = isChild ? '' : `<button class="pu-inline-action pu-inline-delete" data-testid="pu-block-delete-btn-${pathId}" tabindex="-1" onclick="event.stopPropagation(); PU.actions.deleteBlock('${path}')" title="Delete block"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/></svg></button>`;
        const moreBtn = `<button class="pu-inline-action block-more" onclick="event.stopPropagation(); PU.themes.openContextMenu(event, '${path}', ${isExtText})" data-testid="pu-block-more-${pathId}" tabindex="-1" title="More actions">&#8943;</button>`;
        return `<div class="pu-compact-right-actions"><button class="pu-inline-action pu-inline-edit" data-testid="pu-block-edit-btn-${pathId}" tabindex="-1" onclick="event.stopPropagation(); PU.actions.selectBlock('${path}'); PU.focus.enter('${path}')" title="Edit block"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.83 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg></button>${annotateBtn}${moveBtn}${deleteBtn}${moreBtn}</div>`;
    },

    /**
     * Render right-edge actions (pencil always; annotate; delete only for root blocks; move for eligible content blocks)
     */
    _renderRightEdgeActions(path, pathId, isChild = false, canMove = false, item = null) {
        const isExtText = item && 'ext_text' in item;
        const moveBtn = canMove ? `<button class="pu-inline-action pu-inline-move" data-testid="pu-block-move-btn-${pathId}" tabindex="-1" onclick="event.stopPropagation(); PU.moveToTheme.open('${path}')" title="Move block to reusable theme"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg></button>` : '';
        const hasAnn = item && item.annotations && Object.keys(item.annotations).length > 0;
        const annotateBtn = `<button class="pu-inline-action pu-inline-annotate${hasAnn ? ' has-annotations' : ''}" data-testid="pu-block-annotate-btn-${pathId}" tabindex="-1" onclick="event.stopPropagation(); PU.annotations.toggleEditor('${path}')" title="Annotate block"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/></svg></button>`;
        const deleteBtn = isChild ? '' : `<button class="pu-inline-action pu-inline-delete" data-testid="pu-block-delete-btn-${pathId}" tabindex="-1" onclick="event.stopPropagation(); PU.actions.deleteBlock('${path}')" title="Delete block"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/></svg></button>`;
        const moreBtn = `<button class="pu-inline-action block-more" onclick="event.stopPropagation(); PU.themes.openContextMenu(event, '${path}', ${!!isExtText})" data-testid="pu-block-more-${pathId}" tabindex="-1" title="More actions">&#8943;</button>`;
        return `<div class="pu-right-edge-actions">${moveBtn}<button class="pu-inline-action pu-inline-edit" data-testid="pu-block-edit-btn-${pathId}" tabindex="-1" onclick="event.stopPropagation(); PU.actions.selectBlock('${path}'); PU.focus.enter('${path}')" title="Edit block"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.83 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg></button>${annotateBtn}${deleteBtn}${moreBtn}</div>`;
    },

    /**
     * Render content input block with resolved text and inline dropdowns
     */
    renderContentBlock(item, path, pathId, resolution, depth = 0, meta = {}) {
        const content = item.content || '';
        const viz = PU.state.previewMode.visualizer;
        const vizClass = viz !== 'compact' ? ' pu-block-visualizer' : '';
        const inlineDice = PU.blocks._renderInlineDice(pathId);
        const isChild = depth > 0;
        const inlineCompact = PU.blocks._renderInlineCompactActions(path, pathId, isChild, item, false);
        const hasChildren = item.after && item.after.length > 0;
        const parentConnector = hasChildren
            ? '<span class="pu-parent-connector"><span class="pu-parent-connector-line"></span><span class="pu-parent-connector-arrow">&#9662;</span></span>'
            : '';
        const nestConnector = !hasChildren ? PU.blocks._renderNestConnector(path, pathId) : '';

        // Tree connector for compact mode child blocks (demo-style ├── / └──)
        const treeConnector = (isChild && viz === 'compact')
            ? `<span class="pu-tree-connector" data-testid="pu-tree-connector-${pathId}">${meta.isLast ? '\u2514\u2500\u2500 ' : '\u251C\u2500\u2500 '}</span>`
            : '';
        // Path badge for compact mode blocks (after tree connector) — source integrated
        // Roots also get inline path hints in compact mode (headerless design)
        const compactSrcSuffix = (viz === 'compact') ? PU.blocks._renderSourceSuffix(item) : '';
        const compactSrcType = (viz === 'compact') ? PU.blocks._getSourceType(item) : '';
        const pathTestId = isChild ? `pu-child-path-hint-${pathId}` : `pu-block-path-${pathId}`;
        const inlinePathHint = (viz === 'compact')
            ? `<span class="pu-child-path-hint" data-testid="${pathTestId}" data-has-source data-source-type="${compactSrcType}" onclick="event.stopPropagation(); PU.themes.openSourceDropdown(event, '${PU.blocks.escapeAttr(path)}')">${path}${compactSrcSuffix}</span>`
            : '';

        // Right-edge actions (animated modes only) — inside content div for proper centering
        const canMove = !isChild; // Root content blocks can be moved to theme (parents too — children stay attached)
        const rightEdge = (viz !== 'compact') ? PU.blocks._renderRightEdgeActions(path, pathId, isChild, canMove, item) : '';
        const annotationBadge = PU.blocks._renderAnnotationBadge(item, path, pathId);

        if (resolution) {
            return `
                <div class="pu-block-content" data-testid="pu-block-input-${pathId}" data-path="${path}">
                    <div class="pu-resolved-text${vizClass}">${treeConnector}${inlinePathHint}${resolution.resolvedHtml}${annotationBadge}${inlineDice}${parentConnector}${nestConnector}</div>
                    ${inlineCompact}
                    ${rightEdge}
                </div>
            `;
        }

        // Fallback: show escaped raw text (loading state or no resolution)
        return `
            <div class="pu-block-content" data-testid="pu-block-input-${pathId}" data-path="${path}">
                <div class="pu-resolved-text">${treeConnector}${inlinePathHint}${PU.blocks.escapeHtml(content)}${annotationBadge}${inlineDice}${parentConnector}${nestConnector}</div>
                ${inlineCompact}
                ${rightEdge}
            </div>
        `;
    },

    /**
     * Render ext_text reference block (theme block)
     */
    renderExtTextBlock(item, path, pathId, resolution, depth = 0, meta = {}) {
        const extName = item.ext_text || '';
        const viz = PU.state.previewMode.visualizer;
        const vizClass = viz !== 'compact' ? ' pu-block-visualizer' : '';
        const isChild = depth > 0;
        const isExtText = true;

        const resolvedHtml = resolution ? resolution.resolvedHtml : '';
        const accumulatedHtml = resolution ? PU.blocks.renderAccumulatedText(resolution) : '';
        const annotationBadge = PU.blocks._renderAnnotationBadge(item, path, pathId);

        if (viz === 'compact') {
            const treeConnector = isChild
                ? `<span class="pu-tree-connector" data-testid="pu-tree-connector-${pathId}">${meta.isLast ? '\u2514\u2500\u2500 ' : '\u251C\u2500\u2500 '}</span>`
                : '';
            // Roots also get inline path hints in compact mode (headerless design)
            const extSrcSuffix = PU.blocks._renderSourceSuffix(item);
            const extSrcType = PU.blocks._getSourceType(item);
            const extPathTestId = isChild ? `pu-child-path-hint-${pathId}` : `pu-block-path-${pathId}`;
            const inlinePathHint = `<span class="pu-child-path-hint" data-testid="${extPathTestId}" data-has-source data-source-type="${extSrcType}" onclick="event.stopPropagation(); PU.themes.openSourceDropdown(event, '${PU.blocks.escapeAttr(path)}')">${path}${extSrcSuffix}</span>`;
            const inlineCompact = PU.blocks._renderInlineCompactActions(path, pathId, isChild, item, isExtText);
            const hasChildren = item.after && item.after.length > 0;
            const parentConnector = hasChildren
                ? '<span class="pu-parent-connector"><span class="pu-parent-connector-line"></span><span class="pu-parent-connector-arrow">&#9662;</span></span>'
                : '';
            const nestConnector = !hasChildren ? PU.blocks._renderNestConnector(path, pathId) : '';

            return `
                <div class="pu-block-content pu-theme-block" data-testid="pu-block-input-${pathId}" data-path="${path}">
                    <div class="pu-resolved-text">${treeConnector}${inlinePathHint}${resolvedHtml}${annotationBadge}${parentConnector}${nestConnector}</div>
                    ${inlineCompact}
                    ${accumulatedHtml}
                </div>
            `;
        }

        // Animated modes
        const rightEdge = PU.blocks._renderRightEdgeActions(path, pathId, isChild, false, item);
        const hasChildren = item.after && item.after.length > 0;
        const parentConnector = hasChildren
            ? '<span class="pu-parent-connector"><span class="pu-parent-connector-line"></span><span class="pu-parent-connector-arrow">&#9662;</span></span>'
            : '';
        const nestConnector = !hasChildren ? PU.blocks._renderNestConnector(path, pathId) : '';

        return `
            <div class="pu-block-content pu-theme-block" data-testid="pu-block-input-${pathId}" data-path="${path}">
                <div class="pu-resolved-text${vizClass}">${resolvedHtml}${annotationBadge}${parentConnector}${nestConnector}</div>
                ${accumulatedHtml}
                ${rightEdge}
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
     * Render resolved text with inline wildcard visualizer.
     * Converts {{wc:value}} markers to mode-specific HTML structures.
     * Modes: compact, typewriter (v4b), reel (v1a2), stack (v1b), ticker (v1a1)
     */
    renderResolvedTextWithDropdowns(resolvedText, wildcardDropdowns, path) {
        if (!resolvedText) return '';

        const viz = PU.state.previewMode.visualizer;

        // First, HTML-escape while preserving markers
        let html = PU.preview.escapeHtmlPreservingMarkers(resolvedText);

        // Build wildcard lookup from dropdowns
        const wcLookup = {};
        if (wildcardDropdowns) {
            for (const dd of wildcardDropdowns) {
                wcLookup[dd.name] = dd;
            }
        }

        // Replace {{wc:value}} markers based on visualizer mode
        html = html.replace(/\{\{([^:]+):([^}]+)\}\}/g, (match, wcName, value) => {
            const dd = wcLookup[wcName];
            const values = dd ? dd.values : [value];
            const valIdx = values.indexOf(value);
            const currentIdx = valIdx !== -1 ? valIdx : (dd ? dd.currentIndex % values.length : 0);
            const valuesJson = PU.blocks.escapeAttr(JSON.stringify(values));
            const eName = PU.blocks.escapeAttr(wcName);

            if (viz === 'compact') {
                return `<span class="pu-wc-text-value" data-wc="${eName}" data-values="${valuesJson}" data-value="${PU.blocks.escapeAttr(value)}">${PU.blocks.escapeHtml(value)}</span>`;
            }

            if (viz === 'stack') {
                return PU.blocks._renderStackHtml(eName, values, currentIdx);
            }
            if (viz === 'typewriter') {
                return `<span class="pu-wc-typewriter" data-wc="${eName}" data-values="${valuesJson}" data-current-idx="${currentIdx}" data-value="${PU.blocks.escapeAttr(value)}"><span class="pu-wc-tw-placeholder">${PU.blocks.escapeHtml(wcName)}</span><span class="pu-wc-tw-text"></span><span class="pu-wc-tw-cursor"></span></span>`;
            }
            if (viz === 'reel') {
                return `<span class="pu-wc-reel" data-wc="${eName}" data-values="${valuesJson}" data-current-idx="${currentIdx}" data-value="${PU.blocks.escapeAttr(value)}"><span class="pu-wc-reel-label">${PU.blocks.escapeHtml(wcName)}</span><span class="pu-wc-reel-window"><span class="pu-wc-reel-track"></span></span></span>`;
            }
            if (viz === 'ticker') {
                return `<span class="pu-wc-ticker" data-wc="${eName}" data-values="${valuesJson}" data-current-idx="${currentIdx}" data-value="${PU.blocks.escapeAttr(value)}"><span class="pu-wc-ticker-label">${PU.blocks.escapeHtml(wcName)}</span><span class="pu-wc-ticker-track"></span></span>`;
            }

            return `<span class="pu-wc-resolved-pill">${PU.blocks.escapeHtml(value)}</span>`;
        });

        return html;
    },

    /**
     * Generate Stack (v1b Step Reel) HTML — all values visible vertically, center highlighted
     */
    _renderStackHtml(escapedName, values, currentIdx) {
        const VISIBLE_RADIUS = 2;
        const displayCount = Math.min(2 * VISIBLE_RADIUS + 1, Math.max(values.length, 1));
        const halfDisplay = Math.floor(displayCount / 2);
        const valuesJson = PU.blocks.escapeAttr(JSON.stringify(values));

        let html = `<span class="pu-wc-stack" data-wc="${escapedName}" data-values="${valuesJson}" data-center="${currentIdx}">`;
        for (let i = 0; i < displayCount; i++) {
            const offset = i - halfDisplay;
            const valueIdx = ((currentIdx + offset) % values.length + values.length) % values.length;
            const dist = Math.abs(offset);
            let cls = 'pu-wc-stack-item';
            if (dist === 0) cls += ' center';
            else if (dist === 1) cls += ' near';
            else cls += ' far';
            html += `<span class="${cls}" data-offset="${offset}">${PU.blocks.escapeHtml(values[valueIdx])}</span>`;
        }
        html += '</span>';
        return html;
    },

    /**
     * Visualizer animation timer tracking and lifecycle
     */
    _vizTimers: [],
    _vizIntroKey: null,
    _vizIntroBusy: false,
    _vizAnimating: false,
    _vizCursorTimer: null,

    cleanupVisualizerAnimations() {
        if (PU.blocks._vizTimers) {
            for (const id of PU.blocks._vizTimers) {
                clearTimeout(id);
            }
        }
        PU.blocks._vizTimers = [];
        PU.blocks._vizAnimating = false;
        // Clean up cursor auto-hide timer
        if (PU.blocks._vizCursorTimer) {
            clearTimeout(PU.blocks._vizCursorTimer);
            PU.blocks._vizCursorTimer = null;
        }
        // Clean up connector intro classes from interrupted intros
        document.querySelectorAll('.pu-parent-connector.pu-connector-intro').forEach(c => {
            c.classList.remove('pu-connector-intro', 'pu-connector-visible');
        });
    },

    _scheduleTimer(fn, delay) {
        if (!PU.blocks._vizTimers) PU.blocks._vizTimers = [];
        const id = setTimeout(fn, delay);
        PU.blocks._vizTimers.push(id);
        return id;
    },

    /** Schedule cursor auto-hide: removes 'active' from all typewriter elements after 0.3s */
    _scheduleCursorHide() {
        const CURSOR_HIDE_DELAY = 750;
        if (PU.blocks._vizCursorTimer) clearTimeout(PU.blocks._vizCursorTimer);
        PU.blocks._vizCursorTimer = setTimeout(() => {
            document.querySelectorAll('.pu-wc-typewriter.active').forEach(el => {
                el.classList.remove('active');
            });
            PU.blocks._vizCursorTimer = null;
        }, CURSOR_HIDE_DELAY);
    },

    /**
     * In-place typewriter animation for a single element.
     * Erases current text then types new text char-by-char.
     * @param {Element} el - The .pu-wc-typewriter element
     * @param {string} newValue - New text to type
     * @param {Function} [callback] - Called after typing completes
     */
    _typewriterAnimateEl(el, newValue, callback) {
        const TYPE_SPEED = 70;
        const textEl = el.querySelector('.pu-wc-tw-text');
        const placeholderEl = el.querySelector('.pu-wc-tw-placeholder');
        if (!textEl) { if (callback) callback(); return; }

        // Show cursor, remove settled
        el.classList.add('active');
        el.classList.remove('settled');
        if (placeholderEl) placeholderEl.classList.add('hidden');

        // Erase current text first
        const currentText = textEl.textContent || '';
        let eraseIdx = currentText.length;

        function eraseNext() {
            if (eraseIdx > 0) {
                eraseIdx--;
                textEl.textContent = currentText.slice(0, eraseIdx);
                PU.blocks._scheduleTimer(eraseNext, TYPE_SPEED / 2);
            } else {
                // Then type new text
                let typeIdx = 0;
                function typeNext() {
                    typeIdx++;
                    if (typeIdx <= newValue.length) {
                        textEl.textContent = newValue.slice(0, typeIdx);
                        PU.blocks._scheduleTimer(typeNext, TYPE_SPEED);
                    } else {
                        el.classList.add('settled');
                        // Update data attributes to reflect new value
                        el.dataset.value = newValue;
                        const values = JSON.parse(el.dataset.values || '[]');
                        const newIdx = values.indexOf(newValue);
                        if (newIdx !== -1) el.dataset.currentIdx = newIdx;
                        if (callback) callback();
                    }
                }
                typeNext();
            }
        }
        eraseNext();
    },

    initVisualizerAnimations() {
        PU.blocks.cleanupVisualizerAnimations();
        const viz = PU.state.previewMode.visualizer;

        if (viz === 'compact') {
            PU.blocks._initClickableWildcards();
            return;
        }

        const key = `${PU.state.activePromptId}:${viz}`;
        const isIntro = (PU.blocks._vizIntroKey !== key);

        if (viz === 'stack') PU.blocks._initStack();
        if (viz === 'typewriter') PU.blocks._initTypewriter(isIntro);
        if (viz === 'reel') PU.blocks._initReel(isIntro);
        if (viz === 'ticker') PU.blocks._initTicker(isIntro);

        PU.blocks._initClickableWildcards();
        PU.blocks._initDiceButtons(isIntro);
        PU.blocks._vizIntroKey = key;
    },

    /** Shared: make all wildcard widgets clickable to cycle values */
    _initClickableWildcards() {
        const viz = PU.state.previewMode.visualizer;

        // Non-stack modes: click picks random new value and pins it (per-block)
        document.querySelectorAll('.pu-wc-typewriter, .pu-wc-reel, .pu-wc-ticker, .pu-wc-text-value').forEach(el => {
            el.addEventListener('click', (e) => {
                e.stopPropagation();
                if (PU.blocks._vizIntroBusy) return;
                const blockEl = el.closest('.pu-block[data-path]');
                const blockPath = blockEl ? blockEl.dataset.path : null;
                if (!blockPath) return;
                const wcName = el.dataset.wc;
                const values = JSON.parse(el.dataset.values || '[]');
                const currentValue = el.dataset.value;
                if (!wcName || values.length === 0) return;
                const others = values.filter(v => v !== currentValue);
                const newValue = others.length > 0
                    ? others[Math.floor(Math.random() * others.length)]
                    : values[Math.floor(Math.random() * values.length)];

                // Typewriter: animate in-place instead of re-rendering
                if (viz === 'typewriter' && el.classList.contains('pu-wc-typewriter')) {
                    if (PU.blocks._vizAnimating) return;
                    PU.blocks._vizAnimating = true;
                    if (!PU.state.previewMode.selectedWildcards[blockPath])
                        PU.state.previewMode.selectedWildcards[blockPath] = {};
                    PU.state.previewMode.selectedWildcards[blockPath][wcName] = newValue;
                    // Remove active from all other typewriter elements
                    document.querySelectorAll('.pu-wc-typewriter.active').forEach(other => {
                        if (other !== el) other.classList.remove('active');
                    });
                    PU.blocks._typewriterAnimateEl(el, newValue, () => {
                        PU.blocks._vizAnimating = false;
                        PU.blocks._scheduleCursorHide();
                    });
                    return;
                }

                PU.preview.selectWildcardValue(wcName, newValue, blockPath);
            });
        });

        // Stack: click pins the specific clicked item's value (per-block)
        document.querySelectorAll('.pu-wc-stack').forEach(container => {
            const blockEl = container.closest('.pu-block[data-path]');
            const blockPath = blockEl ? blockEl.dataset.path : null;
            const wcName = container.dataset.wc;
            const values = JSON.parse(container.dataset.values || '[]');
            const centerIdx = parseInt(container.dataset.center) || 0;
            container.querySelectorAll('.pu-wc-stack-item').forEach(item => {
                item.addEventListener('click', (e) => {
                    e.stopPropagation();
                    if (PU.blocks._vizIntroBusy) return;
                    if (!blockPath) return;
                    const offset = parseInt(item.dataset.offset) || 0;
                    const valueIdx = ((centerIdx + offset) % values.length + values.length) % values.length;
                    PU.preview.selectWildcardValue(wcName, values[valueIdx], blockPath);
                });
            });
        });
    },

    /** Shared: dice button re-rolls wildcards scoped to its own block */
    _initDiceButtons(isIntro) {
        const viz = PU.state.previewMode.visualizer;

        document.querySelectorAll('.pu-viz-dice-btn').forEach(btn => {
            if (isIntro) btn.disabled = true;
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                if (PU.blocks._vizIntroBusy) return;
                // Scope to this block's content only (not children)
                const body = btn.closest('.pu-block-body');
                const blockContent = body ? body.querySelector('.pu-block-content') : null;

                // Typewriter: animate all wildcards in block sequentially
                if (viz === 'typewriter' && blockContent) {
                    PU.blocks._rerollBlockTypewriter(blockContent);
                    return;
                }

                PU.blocks._rerollBlockWildcards(blockContent);
            });
        });
    },

    async _rerollBlockWildcards(scopeEl) {
        if (!scopeEl) return;
        const blockEl = scopeEl.closest('.pu-block[data-path]');
        const blockPath = blockEl ? blockEl.dataset.path : null;
        if (!blockPath) return;
        if (!PU.state.previewMode.selectedWildcards[blockPath])
            PU.state.previewMode.selectedWildcards[blockPath] = {};
        const seen = new Set();
        // Only query wildcards within the scoped content element
        scopeEl.querySelectorAll('[data-wc][data-values]').forEach(el => {
            const wcName = el.dataset.wc;
            if (seen.has(wcName)) return;
            seen.add(wcName);
            const values = JSON.parse(el.dataset.values || '[]');
            if (values.length === 0) return;
            const newValue = values[Math.floor(Math.random() * values.length)];
            PU.state.previewMode.selectedWildcards[blockPath][wcName] = newValue;
        });
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

    /** Typewriter-specific dice reroll: animate all wildcards in block sequentially */
    _rerollBlockTypewriter(scopeEl) {
        if (!scopeEl || PU.blocks._vizAnimating) return;
        const blockEl = scopeEl.closest('.pu-block[data-path]');
        const blockPath = blockEl ? blockEl.dataset.path : null;
        if (!blockPath) return;
        PU.blocks._vizAnimating = true;
        const PAUSE_BETWEEN = 200;
        const els = Array.from(scopeEl.querySelectorAll('.pu-wc-typewriter'));
        if (els.length === 0) { PU.blocks._vizAnimating = false; return; }

        if (!PU.state.previewMode.selectedWildcards[blockPath])
            PU.state.previewMode.selectedWildcards[blockPath] = {};
        // Pick new random values for each wildcard
        const rerolls = [];
        els.forEach(el => {
            const wcName = el.dataset.wc;
            const values = JSON.parse(el.dataset.values || '[]');
            if (!wcName || values.length === 0) return;
            const newValue = values[Math.floor(Math.random() * values.length)];
            PU.state.previewMode.selectedWildcards[blockPath][wcName] = newValue;
            rerolls.push({ el, newValue });
        });
        if (rerolls.length === 0) { PU.blocks._vizAnimating = false; return; }

        // Remove active from all typewriter elements first
        document.querySelectorAll('.pu-wc-typewriter.active').forEach(el => el.classList.remove('active'));

        // Animate sequentially: erase + retype each wildcard, cursor moves along
        let chain = Promise.resolve();
        rerolls.forEach(({ el, newValue }, idx) => {
            chain = chain.then(() => new Promise(resolve => {
                // Move cursor to this element
                if (idx > 0) rerolls[idx - 1].el.classList.remove('active');
                PU.blocks._typewriterAnimateEl(el, newValue, () => {
                    PU.blocks._scheduleTimer(resolve, PAUSE_BETWEEN);
                });
            }));
        });

        // After all done, schedule cursor auto-hide
        chain.then(() => {
            PU.blocks._vizAnimating = false;
            PU.blocks._scheduleCursorHide();
        });
    },

    /** Stack: static layout, click handling done by _initClickableWildcards */
    _initStack() {
        // Stack HTML is rendered statically by _renderStackHtml.
        // Click handling is done by _initClickableWildcards.
    },

    /**
     * Group wildcard DOM elements by their containing block's data-depth.
     * Returns sorted array of depth layers, each containing block entries
     * with their wildcard elements and connector reference.
     * Also includes .pu-has-children blocks with no wildcards (static-text parents)
     * so the connector bridge still fires for them.
     */
    _groupWidgetsByDepth(selector) {
        const els = Array.from(document.querySelectorAll(selector));
        // Map: blockEl → { depth, blockEl, widgets[], connector }
        const blockMap = new Map();

        els.forEach(el => {
            const blockEl = el.closest('.pu-block');
            if (!blockEl) return;
            const depth = parseInt(blockEl.dataset.depth) || 0;
            if (!blockMap.has(blockEl)) {
                const body = blockEl.querySelector(':scope > .pu-block-body');
                const connector = body ? body.querySelector('.pu-parent-connector') : null;
                blockMap.set(blockEl, { depth, blockEl, widgets: [], connector });
            }
            blockMap.get(blockEl).widgets.push(el);
        });

        // Also include .pu-has-children blocks that have no wildcards for this selector
        // (static-text parents) so connector bridge still fires
        document.querySelectorAll('.pu-has-children').forEach(blockEl => {
            if (blockMap.has(blockEl)) return;
            const body = blockEl.querySelector(':scope > .pu-block-body');
            const connector = body ? body.querySelector('.pu-parent-connector') : null;
            if (!connector) return;
            const depth = parseInt(blockEl.dataset.depth) || 0;
            blockMap.set(blockEl, { depth, blockEl, widgets: [], connector });
        });

        // Group by depth
        const depthGroups = new Map();
        for (const entry of blockMap.values()) {
            if (!depthGroups.has(entry.depth)) depthGroups.set(entry.depth, []);
            depthGroups.get(entry.depth).push(entry);
        }

        // Sort by depth ascending, return array of layers
        return Array.from(depthGroups.entries())
            .sort((a, b) => a[0] - b[0])
            .map(([depth, blocks]) => ({ depth, blocks }));
    },

    /**
     * Generic orchestrator: animate depth layers sequentially.
     * - Within each layer, calls animateBlock() for each block with 80ms cascade stagger
     * - After all blocks at a depth finish, calls animateConnector() on each block's connector
     * - Waits 300ms for connector animation, then proceeds to next depth
     * - Calls onAllDone after deepest layer completes
     *
     * @param {Array} layers - from _groupWidgetsByDepth
     * @param {Function} animateBlock - (blockEntry) => durationMs. Animates widgets in one block.
     * @param {Function} animateConnector - (connectorEl) => void. Triggers connector fade-in.
     * @param {Function} onAllDone - Called after all depths complete.
     */
    _cascadeByDepth(layers, animateBlock, animateConnector, onAllDone) {
        const CASCADE_STAGGER = 80;
        const CONNECTOR_WAIT = 300;

        function processLayer(layerIdx) {
            if (layerIdx >= layers.length) {
                if (onAllDone) onAllDone();
                return;
            }

            const layer = layers[layerIdx];
            const blocks = layer.blocks;
            let maxFinishTime = 0;

            blocks.forEach((blockEntry, i) => {
                const staggerDelay = i * CASCADE_STAGGER;
                PU.blocks._scheduleTimer(() => {
                    const duration = animateBlock(blockEntry);
                    const finishTime = staggerDelay + duration;
                    if (finishTime > maxFinishTime) maxFinishTime = finishTime;
                }, staggerDelay);
            });

            // After all blocks at this depth finish, animate connectors then next layer
            const waitForBlocks = (blocks.length - 1) * CASCADE_STAGGER +
                (blocks.length > 0 ? animateBlock.estimatedDuration || 0 : 0);

            // Use the max estimated time for the layer
            PU.blocks._scheduleTimer(() => {
                // Animate connectors for blocks that have children
                let hasConnectors = false;
                blocks.forEach(blockEntry => {
                    if (blockEntry.connector) {
                        hasConnectors = true;
                        animateConnector(blockEntry.connector);
                    }
                });

                if (hasConnectors) {
                    PU.blocks._scheduleTimer(() => processLayer(layerIdx + 1), CONNECTOR_WAIT);
                } else {
                    processLayer(layerIdx + 1);
                }
            }, waitForBlocks);
        }

        processLayer(0);
    },

    /** Typewriter: sequential char-by-char fill on intro, instant on re-render */
    _initTypewriter(isIntro) {
        const els = Array.from(document.querySelectorAll('.pu-wc-typewriter'));
        if (els.length === 0) return;

        // Build element → wildcard data map
        const wcDataMap = new Map();
        els.forEach(el => {
            const wc = {
                el,
                values: JSON.parse(el.dataset.values || '[]'),
                valueIndex: parseInt(el.dataset.currentIdx) || 0,
                textEl: el.querySelector('.pu-wc-tw-text'),
                placeholderEl: el.querySelector('.pu-wc-tw-placeholder'),
            };
            // Lock min-width from placeholder
            wc.el.style.minWidth = wc.el.offsetWidth + 'px';
            wcDataMap.set(el, wc);
        });

        if (!isIntro) {
            // Non-intro: show values immediately
            wcDataMap.forEach(wc => {
                const text = wc.values[wc.valueIndex] || '';
                if (wc.placeholderEl) wc.placeholderEl.classList.add('hidden');
                wc.textEl.textContent = text;
                wc.el.classList.add('settled');
            });
            return;
        }

        // Intro: hierarchy-aware sequential typing — no pause between wildcards
        // so it feels like one continuous typing session hopping between fields
        PU.blocks._vizIntroBusy = true;
        const TYPE_SPEED = 70;
        const PAUSE_BETWEEN = 0;
        const INTRO_DELAY = 1400;

        // Initial state: placeholders visible, text empty
        wcDataMap.forEach(wc => {
            if (wc.placeholderEl) wc.placeholderEl.classList.remove('hidden');
            wc.textEl.textContent = '';
            wc.el.classList.remove('active', 'settled');
        });

        function typeValue(wc, text, callback) {
            if (wc.placeholderEl) wc.placeholderEl.classList.add('hidden');
            wc.el.classList.remove('settled');
            let ci = 0;
            function next() {
                ci++;
                if (ci <= text.length) {
                    wc.textEl.textContent = text.slice(0, ci);
                    PU.blocks._scheduleTimer(next, TYPE_SPEED);
                } else {
                    wc.el.classList.add('settled');
                    callback();
                }
            }
            next();
        }

        // Estimate typing duration for a block's wildcards (sequential within block)
        function estimateBlockDuration(blockEntry) {
            let total = 0;
            blockEntry.widgets.forEach(el => {
                const wc = wcDataMap.get(el);
                if (!wc) return;
                const text = wc.values[wc.valueIndex] || '';
                total += text.length * TYPE_SPEED + PAUSE_BETWEEN;
            });
            return total;
        }

        const layers = PU.blocks._groupWidgetsByDepth('.pu-wc-typewriter');

        // animateBlock: type wildcards within one block sequentially, return duration
        // Cursor (active class) stays on the last wildcard of the block
        function animateBlock(blockEntry) {
            const widgets = blockEntry.widgets;
            if (widgets.length === 0) return 0;

            // Collect valid wildcards for this block
            const blockWcs = [];
            widgets.forEach(el => {
                const wc = wcDataMap.get(el);
                if (!wc) return;
                const text = wc.values[wc.valueIndex] || '';
                if (!text) return;
                blockWcs.push({ wc, text });
            });
            if (blockWcs.length === 0) return 0;

            let duration = 0;
            let chain = Promise.resolve();

            blockWcs.forEach(({ wc, text }, idx) => {
                duration += text.length * TYPE_SPEED + PAUSE_BETWEEN;
                chain = chain.then(() => new Promise(resolve => {
                    // Remove active from previous wildcard in this block
                    if (idx > 0) blockWcs[idx - 1].wc.el.classList.remove('active');
                    wc.el.classList.add('active');
                    typeValue(wc, text, () => {
                        PU.blocks._scheduleTimer(resolve, PAUSE_BETWEEN);
                    });
                }));
            });

            return duration;
        }

        // Estimate max block duration for cascade timing
        let maxBlockDuration = 0;
        layers.forEach(layer => {
            layer.blocks.forEach(blockEntry => {
                const d = estimateBlockDuration(blockEntry);
                if (d > maxBlockDuration) maxBlockDuration = d;
            });
        });
        animateBlock.estimatedDuration = maxBlockDuration;

        function animateConnector(connectorEl) {
            connectorEl.classList.add('pu-connector-intro');
            // Force reflow so transition triggers
            connectorEl.offsetHeight;
            connectorEl.classList.add('pu-connector-visible');
        }

        function onAllDone() {
            PU.blocks._vizIntroBusy = false;
            document.querySelectorAll('.pu-viz-dice-btn').forEach(btn => btn.disabled = false);
            // Remove connector intro classes, restoring hover-only behavior
            document.querySelectorAll('.pu-parent-connector.pu-connector-intro').forEach(c => {
                c.classList.remove('pu-connector-intro', 'pu-connector-visible');
            });
            // Auto-hide cursor after 2s
            PU.blocks._scheduleCursorHide();
        }

        PU.blocks._scheduleTimer(() => {
            PU.blocks._cascadeByDepth(layers, animateBlock, animateConnector, onAllDone);
        }, INTRO_DELAY);
    },

    /** Ticker: scroll-in on intro, static on re-render */
    _initTicker(isIntro) {
        const els = Array.from(document.querySelectorAll('.pu-wc-ticker'));
        if (els.length === 0) return;

        const SCROLL_DURATION = 800;

        // Build element → prepared data map
        const tickerDataMap = new Map();

        els.forEach(el => {
            const values = JSON.parse(el.dataset.values || '[]');
            if (values.length === 0) return;
            const track = el.querySelector('.pu-wc-ticker-track');
            const label = el.querySelector('.pu-wc-ticker-label');
            const currentIdx = parseInt(el.dataset.currentIdx) || 0;

            if (isIntro) {
                // Intro: prepend wildcard name as first track item, then 2x value copies
                const nameItem = document.createElement('span');
                nameItem.className = 'pu-wc-ticker-item pu-wc-ticker-name';
                nameItem.textContent = el.dataset.wc;
                track.appendChild(nameItem);
                for (let r = 0; r < 2; r++) {
                    values.forEach(val => {
                        const item = document.createElement('span');
                        item.className = 'pu-wc-ticker-item';
                        item.textContent = val;
                        track.appendChild(item);
                    });
                }
            } else {
                // Non-intro: just values, no name prefix
                values.forEach(val => {
                    const item = document.createElement('span');
                    item.className = 'pu-wc-ticker-item';
                    item.textContent = val;
                    track.appendChild(item);
                });
            }

            const itemH = track.querySelector('.pu-wc-ticker-item').getBoundingClientRect().height;
            el.style.height = itemH + 'px';

            tickerDataMap.set(el, { el, track, label, values, currentIdx, itemH });

            if (!isIntro) {
                // Hide label, show track at final position
                if (label) label.style.display = 'none';
                track.style.transition = 'none';
                track.style.transform = `translateY(-${currentIdx * itemH}px)`;
            } else {
                // Intro: show label initially, track starts at name item (position 0)
                if (label) label.style.display = 'none';
                track.style.transition = 'none';
                track.style.transform = 'translateY(0)';
            }
        });

        if (!isIntro) return;

        // Intro: hierarchy-aware scroll cascade
        PU.blocks._vizIntroBusy = true;

        const layers = PU.blocks._groupWidgetsByDepth('.pu-wc-ticker');

        function animateBlock(blockEntry) {
            blockEntry.widgets.forEach(widgetEl => {
                const data = tickerDataMap.get(widgetEl);
                if (!data) return;
                // +1 offset for the prepended wildcard name item
                const targetPos = 1 + data.values.length + data.currentIdx;
                data.track.style.transition = `transform ${SCROLL_DURATION}ms cubic-bezier(0.4, 0, 0.2, 1)`;
                data.track.style.transform = `translateY(-${targetPos * data.itemH}px)`;
            });
            return SCROLL_DURATION;
        }
        animateBlock.estimatedDuration = SCROLL_DURATION;

        function animateConnector(connectorEl) {
            connectorEl.classList.add('pu-connector-intro');
            connectorEl.offsetHeight;
            connectorEl.classList.add('pu-connector-visible');
        }

        function onAllDone() {
            PU.blocks._vizIntroBusy = false;
            document.querySelectorAll('.pu-viz-dice-btn').forEach(btn => btn.disabled = false);
            document.querySelectorAll('.pu-parent-connector.pu-connector-intro').forEach(c => {
                c.classList.remove('pu-connector-intro', 'pu-connector-visible');
            });
        }

        PU.blocks._scheduleTimer(() => {
            PU.blocks._cascadeByDepth(layers, animateBlock, animateConnector, onAllDone);
        }, 1000);
    },

    /** Reel: label shrinks + value fades in on intro, static on re-render */
    _initReel(isIntro) {
        const els = Array.from(document.querySelectorAll('.pu-wc-reel'));
        if (els.length === 0) return;

        const LABEL_ANIM = 600;
        const TRACK_FADE_DELAY = 100;
        const REEL_DURATION = LABEL_ANIM + TRACK_FADE_DELAY + 400; // ~1100ms

        // Build element → prepared data map
        const reelDataMap = new Map();

        els.forEach(el => {
            const values = JSON.parse(el.dataset.values || '[]');
            if (values.length === 0) return;
            const label = el.querySelector('.pu-wc-reel-label');
            const windowEl = el.querySelector('.pu-wc-reel-window');
            const track = el.querySelector('.pu-wc-reel-track');
            const currentIdx = parseInt(el.dataset.currentIdx) || 0;

            // Populate track items
            values.forEach(val => {
                const item = document.createElement('span');
                item.className = 'pu-wc-reel-item';
                item.textContent = val;
                track.appendChild(item);
            });

            const itemH = track.querySelector('.pu-wc-reel-item').getBoundingClientRect().height;
            el.style.height = itemH + 'px';

            // Min-width from label text
            const ctx = document.createElement('canvas').getContext('2d');
            ctx.font = getComputedStyle(label).font;
            el.style.minWidth = Math.ceil(ctx.measureText(label.textContent).width) + 'px';
            windowEl.style.height = itemH + 'px';
            label.style.lineHeight = itemH + 'px';

            const targetY = -(itemH / 2 + 6);
            track.style.transform = `translateY(-${currentIdx * itemH}px)`;

            reelDataMap.set(el, { el, label, track, targetY });

            if (!isIntro) {
                // Non-intro: immediately show final state
                label.style.transition = 'none';
                label.style.transform = `translateY(${targetY}px) scale(0.55)`;
                track.classList.add('visible');
            }
        });

        if (!isIntro) return;

        // Intro: hierarchy-aware label shrink + track fade cascade
        PU.blocks._vizIntroBusy = true;

        const layers = PU.blocks._groupWidgetsByDepth('.pu-wc-reel');

        function animateBlock(blockEntry) {
            blockEntry.widgets.forEach(widgetEl => {
                const data = reelDataMap.get(widgetEl);
                if (!data) return;
                data.label.style.transform = `translateY(${data.targetY}px) scale(0.55)`;
                PU.blocks._scheduleTimer(() => {
                    data.track.classList.add('visible');
                }, LABEL_ANIM + TRACK_FADE_DELAY);
            });
            return REEL_DURATION;
        }
        animateBlock.estimatedDuration = REEL_DURATION;

        function animateConnector(connectorEl) {
            connectorEl.classList.add('pu-connector-intro');
            connectorEl.offsetHeight;
            connectorEl.classList.add('pu-connector-visible');
        }

        function onAllDone() {
            PU.blocks._vizIntroBusy = false;
            document.querySelectorAll('.pu-viz-dice-btn').forEach(btn => btn.disabled = false);
            document.querySelectorAll('.pu-parent-connector.pu-connector-intro').forEach(c => {
                c.classList.remove('pu-connector-intro', 'pu-connector-visible');
            });
        }

        PU.blocks._scheduleTimer(() => {
            PU.blocks._cascadeByDepth(layers, animateBlock, animateConnector, onAllDone);
        }, 1200);
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
    // =========================================================================
    // ANNOTATION CRUD HELPERS
    // =========================================================================

    /**
     * Get annotations for a block at path
     * @returns {Object|null}
     */
    getAnnotations(textArray, path) {
        const block = PU.blocks.findBlockByPath(textArray, path);
        if (!block) return null;
        return block.annotations || null;
    },

    /**
     * Set annotations (replace entire dict) for a block at path
     */
    setAnnotations(textArray, path, annotations) {
        const block = PU.blocks.findBlockByPath(textArray, path);
        if (!block) return;
        if (annotations && Object.keys(annotations).length > 0) {
            block.annotations = annotations;
        } else {
            delete block.annotations;
        }
    },

    /**
     * Set a single annotation key/value
     */
    setAnnotation(textArray, path, key, value) {
        const block = PU.blocks.findBlockByPath(textArray, path);
        if (!block) return;
        if (!block.annotations) block.annotations = {};
        block.annotations[key] = value;
    },

    /**
     * Remove a single annotation key; cleans up if empty
     */
    removeAnnotation(textArray, path, key) {
        const block = PU.blocks.findBlockByPath(textArray, path);
        if (!block || !block.annotations) return;
        delete block.annotations[key];
        if (Object.keys(block.annotations).length === 0) {
            delete block.annotations;
        }
    },

    /**
     * Check if block has annotations
     * @returns {boolean}
     */
    hasAnnotations(textArray, path) {
        const block = PU.blocks.findBlockByPath(textArray, path);
        return !!(block && block.annotations && Object.keys(block.annotations).length > 0);
    },

    /**
     * Render annotation badge (small purple tag icon with count)
     */
    _renderAnnotationBadge(item, path, pathId) {
        const ann = item.annotations;
        if (!ann || Object.keys(ann).length === 0) return '';
        const count = Object.keys(ann).length;
        return `<span class="pu-annotation-badge" data-testid="pu-ann-badge-${pathId}" title="${count} annotation${count !== 1 ? 's' : ''}" onclick="event.stopPropagation(); PU.annotations.toggleEditor('${path}')"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="12" height="12"><path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/></svg><span class="pu-ann-count">${count}</span></span>`;
    },

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
