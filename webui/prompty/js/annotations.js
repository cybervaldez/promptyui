/**
 * PromptyUI - Annotations
 *
 * Inline annotation editor for block metadata with 3-layer inheritance.
 * Resolution: defaults.annotations → prompt.annotations → block.annotations
 * Null sentinel removes inherited values. Block annotations do NOT cascade to after: children.
 *
 * NAMESPACE SEPARATION (Strategy D):
 * Annotations express USER INTENT ("what to DO" — format, section, quality).
 * Theme metadata (meta) expresses REFERENCE FACTS ("what it IS" — department, level).
 * These are separate namespaces: annotations never merge with or override meta.
 * Hook context receives both: ctx['annotations'] + ctx['meta'].
 * See docs/composition-model.md "Theme Metadata (meta)" for full spec.
 */

PU.annotations = {
    // Track which editors are open (Set of paths)
    _openEditors: new Set(),

    // Registered annotation event handlers: name -> { event, handler }
    _hooks: {},

    // Universal annotation definitions: key → descriptor
    // Universal annotations have built-in UI semantics (custom widgets, inline display).
    // _ prefix signals "the system handles this, not hooks."
    _universals: {
        '_comment': {
            widget: 'textarea',
            label: 'Comment',
            placeholder: 'Add a note about this block...',
            rows: 2,
            showOnCard: true,
        },
        '_priority': {
            widget: 'select',
            label: 'Priority',
            options: ['high', 'medium', 'low'],
            showOnCard: true,
            defaultValue: 'medium',
        },
        '_draft': {
            widget: 'toggle',
            label: 'Draft',
            description: 'Mark as draft',
            showOnCard: true,
        },
        '_token_limit': {
            widget: 'number',
            label: 'Token Limit',
            placeholder: 'e.g. 500',
            showOnCard: false,
            description: 'Token budget for this block',
        },
    },

    /** Valid widget types for universal annotations */
    _validWidgets: ['textarea', 'select', 'toggle', 'async', 'number'],

    /**
     * Register a universal annotation type.
     * Validates the descriptor and logs console warnings for invalid input.
     * Registration proceeds regardless — warn loudly, don't crash.
     * @param {string} key - Annotation key (should start with _)
     * @param {Object} descriptor - { widget, label, placeholder, rows, showOnCard, options, defaultValue, check, autoCheck, cacheTtl, description }
     */
    defineUniversal(key, descriptor) {
        const prefix = `[PU] defineUniversal("${key}")`;
        if (typeof key !== 'string' || !key.startsWith('_')) {
            console.warn(`${prefix}: key should start with "_" (got "${key}")`);
        }
        if (!descriptor || typeof descriptor !== 'object') {
            console.warn(`${prefix}: descriptor must be an object`);
            PU.annotations._universals[key] = descriptor || {};
            return;
        }
        if (!descriptor.widget) {
            console.warn(`${prefix}: missing required field "widget"`);
        } else if (!PU.annotations._validWidgets.includes(descriptor.widget)) {
            console.warn(`${prefix}: unknown widget type "${descriptor.widget}" — valid: ${PU.annotations._validWidgets.join(', ')}`);
        }
        if (descriptor.widget === 'select' && (!Array.isArray(descriptor.options) || descriptor.options.length === 0)) {
            console.warn(`${prefix}: widget "select" requires non-empty "options" array`);
        }
        if (descriptor.widget === 'async' && typeof descriptor.check !== 'function') {
            console.warn(`${prefix}: widget "async" requires "check" function`);
        }
        PU.annotations._universals[key] = descriptor;
    },

    /** Check if an annotation key is a universal annotation */
    isUniversal(key) {
        return PU.annotations._universals.hasOwnProperty(key);
    },

    // =========================================================================
    // TOKEN COUNTING
    // =========================================================================

    /**
     * Approximate token count for a text string.
     * Uses chars/4 heuristic (standard GPT tokenizer approximation).
     * @param {string} text
     * @returns {number}
     */
    computeTokenCount(text) {
        if (!text) return 0;
        return Math.ceil(text.length / 4);
    },

    /**
     * Resolve the effective _token_limit for a block via 3-layer inheritance.
     * Returns null if no _token_limit is set at any level.
     * @param {string} path - Block path
     * @returns {number|null}
     */
    resolveTokenLimit(path) {
        const { computed } = PU.annotations.resolve(path);
        const limit = computed['_token_limit'];
        if (limit === undefined || limit === null) return null;
        const num = Number(limit);
        return isNaN(num) || num <= 0 ? null : num;
    },

    // =========================================================================
    // ASYNC WIDGET
    // =========================================================================

    /** Cache for async check results: "path:key" → { status, message, timestamp } */
    _asyncCache: {},

    /**
     * Run the async check function for a universal annotation with widget: 'async'.
     * Updates the status display inline. Caches results per cacheTtl.
     * @param {string} path - Block path
     * @param {string} key - Annotation key
     */
    async runAsyncCheck(path, key) {
        const desc = PU.annotations._universals[key];
        if (!desc || desc.widget !== 'async' || typeof desc.check !== 'function') {
            console.warn(`[PU] runAsyncCheck: no valid check function for "${key}"`);
            return;
        }

        const cacheKey = `${path}:${key}`;
        const ttl = (desc.cacheTtl || 0) * 1000; // ms

        // Check cache
        if (ttl > 0) {
            const cached = PU.annotations._asyncCache[cacheKey];
            if (cached && (Date.now() - cached.timestamp) < ttl) {
                PU.annotations._updateAsyncStatus(path, key, cached.status, cached.message);
                return;
            }
        }

        // Set running state
        PU.annotations._updateAsyncStatus(path, key, 'running', 'Checking...');

        try {
            const { computed } = PU.annotations.resolve(path);
            const value = computed[key];
            const result = await desc.check(path, value, {
                annotations: computed,
                blockText: PU.annotations._getBlockText(path),
            });

            const status = result && result.status === 'pass' ? 'pass' : 'fail';
            const message = result?.message || (status === 'pass' ? 'Check passed' : 'Check failed');

            PU.annotations._asyncCache[cacheKey] = { status, message, timestamp: Date.now() };
            PU.annotations._updateAsyncStatus(path, key, status, message);
        } catch (err) {
            PU.annotations._updateAsyncStatus(path, key, 'fail', `Error: ${err.message}`);
        }
    },

    /**
     * Update the visual status of an async annotation widget.
     * @param {string} path
     * @param {string} key
     * @param {'pending'|'running'|'pass'|'fail'} status
     * @param {string} message
     */
    _updateAsyncStatus(path, key, status, message) {
        const pathId = path.replace(/\./g, '-');
        // Find the status element by walking async rows for this path
        const rows = document.querySelectorAll(`.pu-ann-async-row[data-ann-key="${key}"]`);
        for (const row of rows) {
            const statusEl = row.querySelector('.pu-ann-async-status');
            if (!statusEl || statusEl.dataset.path !== path) continue;

            const icons = { pending: '&#9679;', running: '&#8987;', pass: '&#10003;', fail: '&#10007;' };
            statusEl.innerHTML = `
                <span class="pu-ann-async-icon ${status}" title="${PU.blocks.escapeAttr(message)}">${icons[status] || icons.pending}</span>
                <span class="pu-ann-async-label">${PU.blocks.escapeHtml(message)}</span>
            `;
        }
    },

    /**
     * Get the resolved block text for async check context.
     * @param {string} path
     * @returns {string}
     */
    _getBlockText(path) {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text)) return '';
        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return '';
        return block.content || '';
    },

    /**
     * Run autoCheck for all async universals on a given path.
     * Called when block content or annotations change.
     * @param {string} path
     */
    autoRunChecks(path) {
        for (const [key, desc] of Object.entries(PU.annotations._universals)) {
            if (desc.widget !== 'async' || !desc.autoCheck) continue;
            const { computed } = PU.annotations.resolve(path);
            if (computed.hasOwnProperty(key)) {
                PU.annotations.runAsyncCheck(path, key);
            }
        }
    },

    // =========================================================================
    // INHERITANCE RESOLUTION
    // =========================================================================

    /**
     * Resolve computed annotations for a block path.
     * Merges: defaults.annotations → prompt.annotations → block.annotations
     * Null values explicitly remove inherited keys.
     *
     * @param {string} path - Block path (e.g. "0", "0.1")
     * @returns {{ computed: Object, sources: Object<string, string>, hasNullOverrides: boolean }}
     *   - computed: final key-value pairs after merge + null removal
     *   - sources: key → 'defaults' | 'prompt' | 'block'
     *   - removed: key → 'defaults' | 'prompt' (source of the removed value)
     *   - hasNullOverrides: true if any null overrides exist on this block
     */
    resolve(path) {
        const job = PU.helpers.getActiveJob();
        const prompt = PU.helpers.getActivePrompt();

        const defaultsAnn = (job && job.defaults && job.defaults.annotations) || {};
        const promptAnn = (prompt && prompt.annotations) || {};

        let blockAnn = {};
        if (prompt && Array.isArray(prompt.text)) {
            const block = PU.blocks.findBlockByPath(prompt.text, path);
            blockAnn = (block && block.annotations) || {};
        }

        // Merge layers: defaults → prompt → block
        const merged = {};
        const sources = {};
        const removed = {};

        for (const [k, v] of Object.entries(defaultsAnn)) {
            merged[k] = v;
            sources[k] = 'defaults';
        }
        for (const [k, v] of Object.entries(promptAnn)) {
            merged[k] = v;
            sources[k] = 'prompt';
        }
        for (const [k, v] of Object.entries(blockAnn)) {
            merged[k] = v;
            sources[k] = 'block';
        }

        // Remove keys with null values (null sentinel = explicit removal)
        const computed = {};
        let hasNullOverrides = false;
        for (const [k, v] of Object.entries(merged)) {
            if (v === null) {
                hasNullOverrides = true;
                // Track what was removed and its original source
                const origSource = Object.prototype.hasOwnProperty.call(promptAnn, k) && promptAnn[k] !== null
                    ? 'prompt'
                    : Object.prototype.hasOwnProperty.call(defaultsAnn, k) ? 'defaults' : null;
                if (origSource) removed[k] = origSource;
            } else {
                computed[k] = v;
            }
        }

        return { computed, sources, removed, hasNullOverrides };
    },

    /**
     * Get computed annotation count for a block (for badge display).
     * @param {string} path
     * @returns {{ count: number, hasNullOverrides: boolean }}
     */
    computedCount(path) {
        const { computed, hasNullOverrides } = PU.annotations.resolve(path);
        // Exclude universal annotations with showOnCard from badge count
        // (they have their own inline visual on the block card)
        let count = 0;
        for (const key of Object.keys(computed)) {
            const desc = PU.annotations._universals[key];
            if (desc && desc.showOnCard) continue;
            count++;
        }
        return { count, hasNullOverrides };
    },

    // =========================================================================
    // EDITOR TOGGLE
    // =========================================================================

    toggleEditor(path) {
        if (PU.annotations._openEditors.has(path)) {
            PU.annotations.closeEditor(path);
        } else {
            PU.annotations.openEditor(path);
        }
    },

    openEditor(path) {
        // Dismiss tooltip immediately when editor opens
        clearTimeout(PU.annotations._tooltipTimeout);
        const tooltip = document.querySelector('[data-testid="pu-ann-tooltip"]');
        if (tooltip) tooltip.style.display = 'none';

        const pathId = path.replace(/\./g, '-');
        const blockEl = document.querySelector(`[data-testid="pu-block-${pathId}"]`);
        if (!blockEl) return;

        const body = blockEl.querySelector(':scope > .pu-block-body');
        if (!body) return;

        // Don't double-insert
        if (body.querySelector('.pu-annotation-editor')) return;

        PU.annotations._openEditors.add(path);

        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        const { computed, sources, removed } = PU.annotations.resolve(path);
        const blockAnn = block.annotations || {};
        const editorHtml = PU.annotations._buildEditorHtml(path, pathId, blockAnn, computed, sources, removed);

        const editorDiv = document.createElement('div');
        editorDiv.className = 'pu-annotation-editor';
        editorDiv.dataset.testid = `pu-ann-editor-${pathId}`;
        editorDiv.innerHTML = editorHtml;
        body.appendChild(editorDiv);

        // Trigger open animation
        requestAnimationFrame(() => {
            editorDiv.classList.add('open');
        });

        PU.annotations.fire('render', { block, path, annotations: computed, containerEl: editorDiv });

        // Auto-run async checks for universals with autoCheck: true
        PU.annotations.autoRunChecks(path);
    },

    closeEditor(path) {
        const pathId = path.replace(/\./g, '-');
        const editorEl = document.querySelector(`[data-testid="pu-ann-editor-${pathId}"]`);
        if (editorEl) {
            editorEl.classList.remove('open');
            editorEl.addEventListener('transitionend', () => editorEl.remove(), { once: true });
            // Fallback removal if transition doesn't fire
            setTimeout(() => { if (editorEl.parentNode) editorEl.remove(); }, 350);
        }
        PU.annotations._openEditors.delete(path);
    },

    // =========================================================================
    // EDITOR HTML (inheritance-aware)
    // =========================================================================

    _buildEditorHtml(path, pathId, blockAnn, computed, sources, removed) {
        let rowsHtml = '';
        let idx = 0;

        // Render computed annotations (inherited + block-owned)
        // Universal keys get custom widgets; standard keys get key/value inputs
        for (const [key, value] of Object.entries(computed)) {
            const source = sources[key] || 'block';
            const isInherited = source !== 'block';
            if (PU.annotations.isUniversal(key)) {
                rowsHtml += PU.annotations._buildUniversalRowHtml(path, pathId, idx, key, String(value), source, isInherited);
            } else {
                rowsHtml += PU.annotations._buildInheritedRowHtml(path, pathId, idx, key, String(value), source, isInherited);
            }
            idx++;
        }

        // Render removed (null override) annotations
        for (const [key, origSource] of Object.entries(removed)) {
            rowsHtml += PU.annotations._buildRemovedRowHtml(path, pathId, idx, key, origSource);
            idx++;
        }

        // Show shortcut buttons for all universals not yet present on this block
        let universalBtns = '';
        for (const [uKey, uDesc] of Object.entries(PU.annotations._universals)) {
            const hasKey = computed.hasOwnProperty(uKey) || removed.hasOwnProperty(uKey);
            if (hasKey) continue;
            const btnLabel = uDesc.label || uKey.replace(/^_/, '');
            const keyId = uKey.replace(/^_/, '');
            universalBtns += `<button class="pu-annotation-add pu-annotation-add-universal" data-testid="pu-ann-add-${keyId}-${pathId}"
                    onclick="event.stopPropagation(); PU.annotations._addUniversal('${path}', '${PU.blocks.escapeAttr(uKey)}')">+ ${PU.blocks.escapeHtml(btnLabel)}</button>`;
        }

        return `
            <div class="pu-annotation-header">
                <span class="pu-annotation-title">Annotations</span>
                <button class="pu-annotation-close" data-testid="pu-ann-close-${pathId}"
                        onclick="event.stopPropagation(); PU.annotations.closeEditor('${path}')">&times;</button>
            </div>
            <div class="pu-annotation-rows" data-testid="pu-ann-rows-${pathId}">
                ${rowsHtml}
            </div>
            <div class="pu-annotation-actions">
                <button class="pu-annotation-add" data-testid="pu-ann-add-${pathId}"
                        onclick="event.stopPropagation(); PU.annotations._addRow('${path}', '${pathId}')">+ Add annotation</button>
                ${universalBtns}
            </div>
        `;
    },

    /** Render a row for a computed annotation (inherited or block-owned) */
    _buildInheritedRowHtml(path, pathId, idx, key, value, source, isInherited) {
        const eKey = PU.blocks.escapeAttr(key);
        const eValue = PU.blocks.escapeAttr(value);
        const sourceClass = isInherited ? ' pu-ann-inherited' : '';
        const sourceBadge = `<span class="pu-ann-source" data-testid="pu-ann-source-${pathId}-${idx}">${source}</span>`;

        if (isInherited) {
            // Inherited: read-only key/value, source badge, remove button (sets null)
            return `
            <div class="pu-annotation-row${sourceClass}" data-ann-key="${eKey}" data-testid="pu-ann-row-${pathId}-${idx}">
                <span class="pu-ann-key pu-ann-readonly">${eKey}</span>
                <span class="pu-ann-value pu-ann-readonly">${eValue}</span>
                ${sourceBadge}
                <button class="pu-ann-remove" data-testid="pu-ann-remove-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._setNull('${path}', '${eKey}')"
                        title="Remove from this block">&times;</button>
            </div>`;
        }

        // Block-owned: editable key/value, source badge, remove button
        return `
            <div class="pu-annotation-row" data-ann-key="${eKey}" data-testid="pu-ann-row-${pathId}-${idx}">
                <input type="text" class="pu-ann-key" value="${eKey}" placeholder="key"
                       data-testid="pu-ann-key-${pathId}-${idx}"
                       onchange="PU.annotations._handleKeyChange('${path}', '${eKey}', this)"
                       onclick="event.stopPropagation()">
                <input type="text" class="pu-ann-value" value="${eValue}" placeholder="value"
                       data-testid="pu-ann-value-${pathId}-${idx}"
                       onchange="PU.annotations._handleValueChange('${path}', '${eKey}', this)"
                       onclick="event.stopPropagation()">
                ${sourceBadge}
                <button class="pu-ann-remove" data-testid="pu-ann-remove-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._removeRow('${path}', '${eKey}')"
                        title="Remove annotation">&times;</button>
            </div>
        `;
    },

    /** Render a row for a null-overridden (removed) inherited annotation */
    _buildRemovedRowHtml(path, pathId, idx, key, origSource) {
        const eKey = PU.blocks.escapeAttr(key);
        return `
            <div class="pu-annotation-row pu-ann-removed" data-ann-key="${eKey}" data-testid="pu-ann-row-${pathId}-${idx}">
                <span class="pu-ann-key pu-ann-readonly pu-ann-strikethrough">${eKey}</span>
                <span class="pu-ann-value pu-ann-readonly pu-ann-strikethrough">removed</span>
                <span class="pu-ann-source">${origSource}</span>
                <button class="pu-ann-restore" data-testid="pu-ann-restore-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._restoreInherited('${path}', '${eKey}')"
                        title="Restore inherited value">restore</button>
            </div>
        `;
    },

    /**
     * Render a row for a universal annotation with a custom widget.
     * Same row position as standard annotations, but the value column uses
     * the widget defined in the universal descriptor (textarea, toggle, select).
     */
    _buildUniversalRowHtml(path, pathId, idx, key, value, source, isInherited) {
        const desc = PU.annotations._universals[key];
        const eKey = PU.blocks.escapeAttr(key);
        const eValue = PU.blocks.escapeAttr(value);
        const sourceClass = isInherited ? ' pu-ann-inherited' : '';
        const sourceBadge = `<span class="pu-ann-source" data-testid="pu-ann-source-${pathId}-${idx}">${source}</span>`;
        const label = desc.label || eKey;

        if (isInherited) {
            // Inherited universal: read-only display
            const displayValue = desc.widget === 'textarea' ? eValue : eValue;
            return `
            <div class="pu-annotation-row pu-ann-universal${sourceClass}" data-ann-key="${eKey}" data-testid="pu-ann-row-${pathId}-${idx}">
                <span class="pu-ann-key pu-ann-readonly pu-ann-universal-label">${PU.blocks.escapeHtml(label)}</span>
                <span class="pu-ann-value pu-ann-readonly">${displayValue}</span>
                ${sourceBadge}
                <button class="pu-ann-remove" data-testid="pu-ann-remove-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._setNull('${path}', '${eKey}')"
                        title="Remove from this block">&times;</button>
            </div>`;
        }

        // Block-owned universal: custom widget
        if (desc.widget === 'textarea') {
            return `
            <div class="pu-annotation-row pu-ann-universal" data-ann-key="${eKey}" data-testid="pu-ann-row-${pathId}-${idx}">
                <span class="pu-ann-key pu-ann-readonly pu-ann-universal-label">${PU.blocks.escapeHtml(label)}</span>
                <textarea class="pu-ann-comment-textarea" data-testid="pu-ann-comment-${pathId}"
                          rows="${desc.rows || 2}" placeholder="${desc.placeholder || ''}"
                          onchange="PU.annotations._handleValueChange('${path}', '${eKey}', this)"
                          oninput="PU.annotations._handleCommentInput('${path}', '${eKey}', this)"
                          onclick="event.stopPropagation()">${eValue}</textarea>
                ${sourceBadge}
                <button class="pu-ann-remove" data-testid="pu-ann-remove-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._removeRow('${path}', '${eKey}')"
                        title="Remove annotation">&times;</button>
            </div>`;
        }

        if (desc.widget === 'select' && desc.options) {
            const optionsHtml = desc.options.map(opt => {
                const sel = opt === value ? ' selected' : '';
                return `<option value="${PU.blocks.escapeAttr(opt)}"${sel}>${PU.blocks.escapeHtml(opt)}</option>`;
            }).join('');
            return `
            <div class="pu-annotation-row pu-ann-universal" data-ann-key="${eKey}" data-testid="pu-ann-row-${pathId}-${idx}">
                <span class="pu-ann-key pu-ann-readonly pu-ann-universal-label">${PU.blocks.escapeHtml(label)}</span>
                <select class="pu-ann-universal-select" data-testid="pu-ann-select-${pathId}-${idx}"
                        onchange="PU.annotations._handleValueChange('${path}', '${eKey}', this)"
                        onclick="event.stopPropagation()">
                    ${optionsHtml}
                </select>
                ${sourceBadge}
                <button class="pu-ann-remove" data-testid="pu-ann-remove-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._removeRow('${path}', '${eKey}')"
                        title="Remove annotation">&times;</button>
            </div>`;
        }

        if (desc.widget === 'toggle') {
            const checked = value === 'true' || value === true ? ' checked' : '';
            return `
            <div class="pu-annotation-row pu-ann-universal" data-ann-key="${eKey}" data-testid="pu-ann-row-${pathId}-${idx}">
                <span class="pu-ann-key pu-ann-readonly pu-ann-universal-label">${PU.blocks.escapeHtml(label)}</span>
                <label class="pu-ann-toggle-wrap">
                    <input type="checkbox" class="pu-ann-toggle" data-testid="pu-ann-toggle-${pathId}-${idx}"${checked}
                           onchange="PU.annotations._handleToggleChange('${path}', '${eKey}', this)"
                           onclick="event.stopPropagation()">
                    <span class="pu-ann-toggle-label">${desc.description || ''}</span>
                </label>
                ${sourceBadge}
                <button class="pu-ann-remove" data-testid="pu-ann-remove-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._removeRow('${path}', '${eKey}')"
                        title="Remove annotation">&times;</button>
            </div>`;
        }

        if (desc.widget === 'async') {
            // Async widget: shows a check status (pending/running/pass/fail)
            // The `check` function is called with (path, value, context) → Promise<{status, message}>
            const statusId = `pu-ann-async-${pathId}-${idx}`;
            return `
            <div class="pu-annotation-row pu-ann-universal pu-ann-async-row" data-ann-key="${eKey}" data-testid="pu-ann-row-${pathId}-${idx}">
                <span class="pu-ann-key pu-ann-readonly pu-ann-universal-label">${PU.blocks.escapeHtml(label)}</span>
                <span class="pu-ann-async-status" data-testid="${statusId}" data-path="${path}" data-key="${eKey}">
                    <span class="pu-ann-async-icon pending" title="Check pending">&#9679;</span>
                    <span class="pu-ann-async-label">pending</span>
                </span>
                <button class="pu-ann-async-run" data-testid="pu-ann-async-run-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations.runAsyncCheck('${path}', '${eKey}')"
                        title="Run check">&#9654;</button>
                ${sourceBadge}
                <button class="pu-ann-remove" data-testid="pu-ann-remove-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._removeRow('${path}', '${eKey}')"
                        title="Remove annotation">&times;</button>
            </div>`;
        }

        if (desc.widget === 'number') {
            return `
            <div class="pu-annotation-row pu-ann-universal" data-ann-key="${eKey}" data-testid="pu-ann-row-${pathId}-${idx}">
                <span class="pu-ann-key pu-ann-readonly pu-ann-universal-label">${PU.blocks.escapeHtml(label)}</span>
                <input type="number" class="pu-ann-number-input" data-testid="pu-ann-number-${pathId}-${idx}"
                       value="${eValue}" placeholder="${desc.placeholder || ''}" min="0" step="1"
                       onchange="PU.annotations._handleValueChange('${path}', '${eKey}', this)"
                       onclick="event.stopPropagation()">
                ${sourceBadge}
                <button class="pu-ann-remove" data-testid="pu-ann-remove-${pathId}-${idx}"
                        onclick="event.stopPropagation(); PU.annotations._removeRow('${path}', '${eKey}')"
                        title="Remove annotation">&times;</button>
            </div>`;
        }

        // Fallback: standard row (unknown widget type)
        console.warn(`[PU] Unknown widget type "${desc.widget}" for annotation "${key}" — rendering as text input`);
        return PU.annotations._buildInheritedRowHtml(path, pathId, idx, key, value, source, isInherited);
    },

    // =========================================================================
    // ROW HANDLERS (key-based instead of index-based for inheritance safety)
    // =========================================================================

    _handleKeyChange(path, oldKey, inputEl) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block || !block.annotations) return;

        const newKey = inputEl.value.trim();
        if (!newKey || newKey === oldKey) return;
        if (!block.annotations.hasOwnProperty(oldKey)) return;

        const value = block.annotations[oldKey];
        // Rebuild preserving order
        const newAnnotations = {};
        for (const [k, v] of Object.entries(block.annotations)) {
            if (k === oldKey) {
                newAnnotations[newKey] = value;
            } else {
                newAnnotations[k] = v;
            }
        }

        block.annotations = newAnnotations;
        PU.annotations._refreshEditor(path);
        PU.annotations._refreshBadge(path);
        PU.annotations.fire('change', { block, path, annotations: block.annotations });
    },

    _handleValueChange(path, key, inputEl) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        let newValue = inputEl.value;

        // Auto-detect types
        if (newValue === 'true') newValue = true;
        else if (newValue === 'false') newValue = false;
        else if (newValue !== '' && !isNaN(Number(newValue))) newValue = Number(newValue);

        if (!block.annotations) block.annotations = {};
        block.annotations[key] = newValue;

        PU.annotations._refreshInlineComment(path);
        PU.annotations.fire('change', { block, path, annotations: block.annotations });
    },

    /** Set a null override to remove an inherited annotation at block level */
    _setNull(path, key) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        if (!block.annotations) block.annotations = {};
        block.annotations[key] = null;

        PU.annotations._refreshEditor(path);
        PU.annotations._refreshBadge(path);
        PU.annotations._refreshInlineComment(path);
        PU.annotations.fire('change', { block, path, annotations: block.annotations });
    },

    /** Restore an inherited annotation by removing the null override */
    _restoreInherited(path, key) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block || !block.annotations) return;

        delete block.annotations[key];
        if (Object.keys(block.annotations).length === 0) {
            delete block.annotations;
        }

        PU.annotations._refreshEditor(path);
        PU.annotations._refreshBadge(path);
        PU.annotations.fire('change', { block, path, annotations: (block.annotations || {}) });
    },

    _addRow(path, pathId) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        if (!block.annotations) block.annotations = {};

        // Find unique key name (skip inherited keys too)
        const { computed } = PU.annotations.resolve(path);
        let keyName = 'key';
        let counter = 1;
        while (block.annotations.hasOwnProperty(keyName) || computed.hasOwnProperty(keyName)) {
            keyName = `key${counter++}`;
        }
        block.annotations[keyName] = '';

        PU.annotations._refreshEditor(path);
        PU.annotations._refreshBadge(path);
        PU.annotations.fire('change', { block, path, annotations: block.annotations });
    },

    _removeRow(path, key) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        PU.blocks.removeAnnotation(prompt.text, path, key);

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        const annotations = (block && block.annotations) || {};

        PU.annotations._refreshEditor(path);
        PU.annotations._refreshBadge(path);
        PU.annotations._refreshInlineComment(path);
        PU.annotations.fire('change', { block, path, annotations });
    },

    /** Add a universal annotation with its default value */
    _addUniversal(path, key) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        if (!block.annotations) block.annotations = {};
        // Use defaultValue from descriptor if available
        const desc = PU.annotations._universals[key];
        const defaultVal = desc && desc.defaultValue !== undefined ? desc.defaultValue : '';
        block.annotations[key] = defaultVal;

        PU.annotations._refreshEditor(path);
        PU.annotations._refreshBadge(path);
        PU.annotations._refreshInlineComment(path);
        PU.annotations.fire('change', { block, path, annotations: block.annotations });
    },

    /** Live update inline comment on the block card as the user types */
    _handleCommentInput(path, key, textareaEl) {
        const desc = PU.annotations._universals[key];
        if (!desc || !desc.showOnCard) return;

        // Update block data immediately for live preview
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;
        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;
        if (!block.annotations) block.annotations = {};
        block.annotations[key] = textareaEl.value;

        PU.annotations._refreshInlineComment(path);
    },

    /** Handle toggle widget change for universal annotations */
    _handleToggleChange(path, key, checkboxEl) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        if (!block.annotations) block.annotations = {};
        block.annotations[key] = checkboxEl.checked;

        PU.annotations._refreshInlineComment(path);
        PU.annotations.fire('change', { block, path, annotations: block.annotations });
    },

    // =========================================================================
    // REFRESH HELPERS
    // =========================================================================

    /** Re-render the editor rows in-place (after inheritance changes) */
    _refreshEditor(path) {
        const pathId = path.replace(/\./g, '-');
        const editorEl = document.querySelector(`[data-testid="pu-ann-editor-${pathId}"]`);
        if (!editorEl) return;

        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;

        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        const { computed, sources, removed } = PU.annotations.resolve(path);
        const blockAnn = block.annotations || {};
        const html = PU.annotations._buildEditorHtml(path, pathId, blockAnn, computed, sources, removed);
        editorEl.innerHTML = html;

        // Check if editor should close (no computed annotations and no block annotations)
        const totalVisible = Object.keys(computed).length + Object.keys(removed).length;
        const blockKeys = Object.keys(blockAnn).length;
        if (totalVisible === 0 && blockKeys === 0) {
            PU.annotations.closeEditor(path);
        }
    },

    /**
     * Refresh all showOnCard universal displays on the block card.
     * Replaces the old comment-only refresh with a generic approach:
     * removes existing inline universals and re-renders them all.
     */
    _refreshInlineComment(path) {
        const pathId = path.replace(/\./g, '-');
        const blockEl = document.querySelector(`[data-testid="pu-block-${pathId}"]`);
        if (!blockEl) return;

        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt || !Array.isArray(prompt.text)) return;
        const block = PU.blocks.findBlockByPath(prompt.text, path);
        if (!block) return;

        const contentEl = blockEl.querySelector('.pu-block-content');
        if (!contentEl) return;

        // Remove existing inline universals (comments + pills container)
        contentEl.querySelectorAll('.pu-block-comment, .pu-block-universal-pills').forEach(el => el.remove());

        // Re-render all showOnCard universals
        const newHtml = PU.blocks._renderShowOnCardUniversals(block, path, pathId);
        if (newHtml) {
            const resolvedEl = contentEl.querySelector('.pu-resolved-text');
            if (resolvedEl) {
                resolvedEl.insertAdjacentHTML('afterend', newHtml);
            }
        }
    },

    _refreshBadge(path) {
        const pathId = path.replace(/\./g, '-');
        const badgeEl = document.querySelector(`[data-testid="pu-ann-badge-${pathId}"]`);
        const annotateBtn = document.querySelector(`[data-testid="pu-block-annotate-btn-${pathId}"]`);

        const { count, hasNullOverrides } = PU.annotations.computedCount(path);

        // Update badge
        if (count > 0) {
            if (badgeEl) {
                const countEl = badgeEl.querySelector('.pu-ann-count');
                if (countEl) countEl.textContent = count;
                // Amber tint for null overrides
                if (hasNullOverrides) {
                    badgeEl.classList.add('has-overrides');
                } else {
                    badgeEl.classList.remove('has-overrides');
                }
            } else {
                // Badge doesn't exist yet; insert it
                const blockEl = document.querySelector(`[data-testid="pu-block-${pathId}"]`);
                if (blockEl) {
                    const resolvedEl = blockEl.querySelector('.pu-resolved-text');
                    if (resolvedEl) {
                        const prompt = PU.editor.getModifiedPrompt();
                        const block = prompt ? PU.blocks.findBlockByPath(prompt.text, path) : null;
                        if (block) {
                            const temp = document.createElement('span');
                            temp.innerHTML = PU.blocks._renderAnnotationBadge(block, path, pathId);
                            if (temp.firstElementChild) {
                                const inlineActions = resolvedEl.querySelector('.pu-inline-actions');
                                if (inlineActions) {
                                    resolvedEl.insertBefore(temp.firstElementChild, inlineActions);
                                } else {
                                    resolvedEl.appendChild(temp.firstElementChild);
                                }
                            }
                        }
                    }
                }
            }
        } else {
            // Remove badge
            if (badgeEl) badgeEl.remove();
        }

        // Update annotate button tint
        if (annotateBtn) {
            if (count > 0) {
                annotateBtn.classList.add('has-annotations');
            } else {
                annotateBtn.classList.remove('has-annotations');
            }
        }
    },

    // =========================================================================
    // ANNOTATION EVENT SYSTEM
    // =========================================================================

    /**
     * Register an annotation event handler
     * @param {string} name - Unique handler name
     * @param {string} event - 'render' | 'select' | 'change' | 'export'
     * @param {Function} handler - (context) => void
     */
    register(name, event, handler) {
        PU.annotations._hooks[name] = { event, handler };
    },

    /**
     * Unregister an annotation event handler
     */
    unregister(name) {
        delete PU.annotations._hooks[name];
    },

    /**
     * Fire an event to all registered annotation handlers
     * @param {string} event - Event name
     * @param {Object} context - { block, path, annotations, containerEl }
     */
    fire(event, context) {
        for (const [name, hook] of Object.entries(PU.annotations._hooks)) {
            if (hook.event === event) {
                try {
                    hook.handler(context);
                } catch (e) {
                    console.warn(`Annotation handler '${name}' error:`, e);
                }
            }
        }
    },

    // =========================================================================
    // BADGE HOVER TOOLTIP
    // =========================================================================

    _tooltipTimeout: null,

    showTooltip(path, badgeEl) {
        clearTimeout(PU.annotations._tooltipTimeout);
        const tooltip = document.querySelector('[data-testid="pu-ann-tooltip"]');
        if (!tooltip) return;

        // No hover tooltip on touch devices — tap goes straight to editor
        if ('ontouchstart' in window) { tooltip.style.display = 'none'; return; }

        // Don't show tooltip when the editor for this block is open
        if (PU.annotations._openEditors.has(path)) {
            tooltip.style.display = 'none';
            return;
        }

        const { computed, sources, removed } = PU.annotations.resolve(path);
        const esc = PU.blocks.escapeHtml;

        let rows = '';
        for (const [key, value] of Object.entries(computed)) {
            // Skip universal annotations with showOnCard (they display inline on the block)
            const uDesc = PU.annotations._universals[key];
            if (uDesc && uDesc.showOnCard) continue;
            const source = sources[key] || 'block';
            rows += `<div class="pu-ann-tooltip-row">
                <span class="pu-ann-tooltip-key">${esc(key)}:</span>
                <span class="pu-ann-tooltip-value">${esc(String(value))}</span>
                <span class="pu-ann-tooltip-source">&larr; ${esc(source)}</span>
            </div>`;
        }
        for (const [key, origSource] of Object.entries(removed)) {
            rows += `<div class="pu-ann-tooltip-row pu-ann-tooltip-removed">
                <span class="pu-ann-tooltip-key pu-ann-strikethrough">${esc(key)}:</span>
                <span class="pu-ann-tooltip-value">(removed)</span>
                <span class="pu-ann-tooltip-source">&larr; ${esc(origSource)}</span>
            </div>`;
        }

        if (!rows) {
            tooltip.style.display = 'none';
            return;
        }

        tooltip.innerHTML = `<div class="pu-ann-tooltip-title">Annotations</div>${rows}`;
        tooltip.style.display = 'block';

        // Position near badge
        const rect = badgeEl.getBoundingClientRect();
        tooltip.style.top = (rect.bottom + 6) + 'px';
        tooltip.style.left = Math.max(8, rect.left - 40) + 'px';
    },

    hideTooltip() {
        PU.annotations._tooltipTimeout = setTimeout(() => {
            const tooltip = document.querySelector('[data-testid="pu-ann-tooltip"]');
            if (tooltip) tooltip.style.display = 'none';
        }, 100);
    },

    // =========================================================================
    // LIVE PROPAGATION (defaults/prompt changes → all blocks)
    // =========================================================================

    /** Refresh all visible block badges and open editors after parent annotation change */
    propagateFromParent() {
        // Refresh all visible badges
        document.querySelectorAll('.pu-annotation-badge').forEach(badge => {
            const testid = badge.dataset.testid || '';
            const match = testid.match(/^pu-ann-badge-(.+)$/);
            if (match) {
                const path = match[1].replace(/-/g, '.');
                PU.annotations._refreshBadge(path);
            }
        });

        // Refresh all open editors
        for (const path of PU.annotations._openEditors) {
            PU.annotations._refreshEditor(path);
        }
    },

    // =========================================================================
    // RESTORE OPEN EDITORS (after DOM rebuild)
    // =========================================================================

    restoreOpenEditors() {
        for (const path of PU.annotations._openEditors) {
            // Re-open editors that were open before re-render
            // Use a microtask to ensure DOM is ready
            setTimeout(() => {
                PU.annotations._openEditors.delete(path); // Remove first so openEditor doesn't skip
                PU.annotations.openEditor(path);
            }, 0);
        }
    }
};
