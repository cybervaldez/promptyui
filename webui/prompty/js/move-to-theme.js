/**
 * PromptyUI - Move to Theme
 *
 * Moves a content block from the prompt to an ext/ theme file.
 * The block becomes an ext_text reference. Wildcards are COPIED
 * to the theme (local copies stay in the prompt).
 */

PU.moveToTheme = {

    /**
     * Open the move-to-theme modal for a given block path.
     */
    open(blockPath) {
        const jobId = PU.state.activeJobId;
        const promptId = PU.state.activePromptId;
        if (!jobId || !promptId) {
            PU.actions.showToast('No prompt selected', 'error');
            return;
        }

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text)) {
            PU.actions.showToast('Prompt has no text blocks', 'error');
            return;
        }

        const analysis = PU.moveToTheme._analyzeBlock(blockPath, prompt);
        if (!analysis) {
            PU.actions.showToast('Block not found or not eligible', 'error');
            return;
        }

        PU.state.themes.moveToThemeModal = {
            visible: true,
            blockPath: blockPath,
            blockIndex: analysis.blockIndex
        };

        PU.moveToTheme._renderModal(analysis, prompt);

        const modal = document.querySelector('[data-testid="pu-move-to-theme-modal"]');
        if (modal) modal.style.display = 'flex';
    },

    /**
     * Analyze a block for the modal: extract content, wildcards, shared status.
     */
    _analyzeBlock(blockPath, prompt) {
        const blocks = prompt.text;
        const block = PU.blocks.findBlockByPath(blocks, blockPath);
        if (!block || !('content' in block)) return null;
        if ('ext_text' in block) return null;
        if (block.after && block.after.length > 0) return null;

        const content = block.content || '';
        const blockIndex = parseInt(blockPath.split('.')[0], 10);

        // Detect wildcards in this block's text
        const wcNames = PU.blocks.detectWildcards(content);

        // Collect text from OTHER blocks to find shared wildcards
        const otherText = [];
        const collectText = (items, excludeIdx) => {
            items.forEach((item, i) => {
                if (i === excludeIdx && items === blocks) return;
                if (item.content) otherText.push(item.content);
                if (item.after) {
                    item.after.forEach(child => {
                        if (child.content) otherText.push(child.content);
                        if (child.after) collectText(child.after, -1);
                    });
                }
            });
        };
        collectText(blocks, blockIndex);
        const otherWcNames = new Set(PU.blocks.detectWildcards(otherText.join(' ')));

        // Build wildcard info with shared detection
        const wcLookup = PU.helpers.getWildcardLookup();
        const wildcards = wcNames.map(name => ({
            name,
            count: wcLookup[name] ? wcLookup[name].length : 0,
            shared: otherWcNames.has(name),
            checked: !otherWcNames.has(name)
        }));

        return { content, blockIndex, wildcards };
    },

    /**
     * Render the modal body with block preview, theme input, scope radios, wildcards.
     */
    _renderModal(analysis, prompt) {
        const body = document.querySelector('[data-testid="pu-mtt-body"]');
        if (!body) return;

        const jobId = PU.state.activeJobId;
        const job = PU.helpers.getActiveJob();
        const extPrefix = (prompt.ext || (job && job.defaults && job.defaults.ext) || '') + '/';

        // Highlight wildcards in preview text
        const highlightedText = PU.blocks.escapeHtml(analysis.content)
            .replace(/__([a-zA-Z0-9_-]+)__/g, '<span class="pu-wc-highlight">__$1__</span>');

        let html = '';

        // 1. Block preview
        html += `
            <label class="pu-mtt-section-label">Moving this block:</label>
            <div class="pu-mtt-preview" data-testid="pu-mtt-preview">
                ${highlightedText}
                <span class="pu-mtt-block-index">block ${analysis.blockIndex}</span>
            </div>`;

        // 2. Theme name input
        html += `
            <div class="pu-mtt-input-group">
                <label class="pu-mtt-section-label" for="mtt-theme-name">Theme name</label>
                <input type="text"
                       id="mtt-theme-name"
                       data-testid="pu-mtt-theme-name"
                       value="${PU.blocks.escapeAttr(extPrefix)}"
                       placeholder="e.g., ${PU.blocks.escapeAttr(extPrefix)}my-theme">
                <div class="pu-mtt-path-hint" data-testid="pu-mtt-path-hint">
                    ext/${PU.blocks.escapeHtml(extPrefix)}
                </div>
            </div>`;

        // 3. Scope radios
        html += `
            <div class="pu-mtt-scope" data-testid="pu-mtt-scope">
                <label class="pu-radio">
                    <input type="radio" name="mtt-scope" value="shared" checked>
                    Shared
                    <span class="scope-path">ext/<span id="mtt-shared-path">${PU.blocks.escapeHtml(extPrefix)}</span></span>
                </label>
                <label class="pu-radio">
                    <input type="radio" name="mtt-scope" value="fork">
                    Job-scoped copy
                    <span class="scope-path">ext/${PU.blocks.escapeHtml(jobId)}/<span id="mtt-fork-path">${PU.blocks.escapeHtml(extPrefix)}</span></span>
                </label>
            </div>`;

        // 4. Wildcards section
        if (analysis.wildcards.length > 0) {
            const hasWarnings = analysis.wildcards.some(w => w.shared);
            const wcExpanded = hasWarnings;
            const checkedWcs = analysis.wildcards.filter(w => w.checked);
            const summaryText = checkedWcs.length > 0
                ? `${checkedWcs.length} bundled (${checkedWcs.map(w => w.name).join(', ')})`
                : 'none bundled';

            html += `<div class="pu-mtt-wildcards" data-testid="pu-mtt-wildcards">`;
            html += `
                <div class="pu-mtt-wc-toggle" data-testid="pu-mtt-wc-toggle">
                    <span class="pu-mtt-chevron ${wcExpanded ? 'expanded' : ''}" id="mtt-wc-chevron">&#9654;</span>
                    <span>Bundled wildcards</span>
                    <span class="pu-mtt-wc-summary" id="mtt-wc-summary">${summaryText}</span>
                </div>`;

            html += `<div class="pu-mtt-wc-list" id="mtt-wc-list" style="display: ${wcExpanded ? 'block' : 'none'}">`;
            analysis.wildcards.forEach(wc => {
                const eName = PU.blocks.escapeAttr(wc.name);
                html += `
                    <div class="pu-mtt-wc-item">
                        <input type="checkbox"
                               id="mtt-wc-${eName}"
                               data-testid="pu-mtt-wc-${eName}"
                               data-wc-name="${eName}"
                               ${wc.checked ? 'checked' : ''}
                               ${wc.shared ? 'disabled' : ''}>
                        <label for="mtt-wc-${eName}">
                            <span class="pu-mtt-wc-name">${PU.blocks.escapeHtml(wc.name)}</span>
                            <span class="pu-mtt-wc-count">(${wc.count} values)</span>
                            ${wc.shared ? '<span class="pu-mtt-wc-shared">stays local</span>' : ''}
                        </label>
                    </div>`;
            });
            html += `</div>`;

            // Warning for shared wildcards
            if (hasWarnings) {
                const sharedNames = analysis.wildcards.filter(w => w.shared).map(w => w.name);
                html += `
                    <div class="pu-export-validation-item warning" data-testid="pu-mtt-shared-warning">
                        <span>&#9888;</span>
                        <span>${sharedNames.map(n => `<strong>${PU.blocks.escapeHtml(n)}</strong>`).join(', ')} also used in other blocks &mdash; will stay local only</span>
                    </div>`;
            }

            html += `</div>`;
        }

        body.innerHTML = html;

        // Bind events after render
        PU.moveToTheme._bindEvents(jobId);
    },

    /**
     * Bind input/radio/toggle events after modal render.
     */
    _bindEvents(jobId) {
        // Theme name input → update path hint
        const input = document.getElementById('mtt-theme-name');
        if (input) {
            input.addEventListener('input', () => PU.moveToTheme._updatePathHint(jobId));
        }

        // Scope radios → update path hint
        document.querySelectorAll('input[name="mtt-scope"]').forEach(radio => {
            radio.addEventListener('change', () => PU.moveToTheme._updatePathHint(jobId));
        });

        // Wildcard toggle
        const toggle = document.querySelector('[data-testid="pu-mtt-wc-toggle"]');
        if (toggle) {
            toggle.addEventListener('click', () => {
                const list = document.getElementById('mtt-wc-list');
                const chevron = document.getElementById('mtt-wc-chevron');
                if (list) {
                    const show = list.style.display === 'none';
                    list.style.display = show ? 'block' : 'none';
                    if (chevron) chevron.classList.toggle('expanded', show);
                }
            });
        }

        // Wildcard checkboxes → update summary
        document.querySelectorAll('.pu-mtt-wc-item input[type="checkbox"]').forEach(cb => {
            cb.addEventListener('change', () => PU.moveToTheme._updateWcSummary());
        });
    },

    /**
     * Update the path hint below the theme name input.
     */
    _updatePathHint(jobId) {
        const input = document.getElementById('mtt-theme-name');
        const hint = document.querySelector('[data-testid="pu-mtt-path-hint"]');
        const sharedPath = document.getElementById('mtt-shared-path');
        const forkPath = document.getElementById('mtt-fork-path');
        const scope = document.querySelector('input[name="mtt-scope"]:checked');

        if (!input || !hint) return;
        const val = input.value || '';

        if (sharedPath) sharedPath.textContent = val;
        if (forkPath) forkPath.textContent = val;

        if (scope && scope.value === 'fork') {
            hint.textContent = `ext/${jobId}/${val}`;
        } else {
            hint.textContent = `ext/${val}`;
        }
    },

    /**
     * Update the wildcard summary text.
     */
    _updateWcSummary() {
        const summary = document.getElementById('mtt-wc-summary');
        if (!summary) return;

        const checked = document.querySelectorAll('.pu-mtt-wc-item input[type="checkbox"]:checked');
        const names = Array.from(checked).map(cb => cb.dataset.wcName);

        summary.textContent = names.length > 0
            ? `${names.length} bundled (${names.join(', ')})`
            : 'none bundled';
    },

    /**
     * Confirm and execute the move-to-theme operation.
     */
    async confirm() {
        const jobId = PU.state.activeJobId;
        const promptId = PU.state.activePromptId;
        if (!jobId || !promptId) return;

        const input = document.getElementById('mtt-theme-name');
        if (!input || !input.value.trim()) {
            PU.actions.showToast('Theme name required', 'error');
            return;
        }

        const themePath = input.value.trim();

        // Validate theme path
        if (!/^[a-zA-Z0-9_\-/]+$/.test(themePath)) {
            PU.actions.showToast('Invalid characters in theme name', 'error');
            return;
        }

        // Trailing slash check
        if (themePath.endsWith('/')) {
            PU.actions.showToast('Theme name cannot end with /', 'error');
            return;
        }

        const scope = document.querySelector('input[name="mtt-scope"]:checked');
        const fork = scope ? scope.value === 'fork' : false;

        // Collect selected wildcard names
        const wildcardNames = [];
        document.querySelectorAll('.pu-mtt-wc-item input[type="checkbox"]:checked').forEach(cb => {
            if (cb.dataset.wcName) wildcardNames.push(cb.dataset.wcName);
        });

        const blockIndex = PU.state.themes.moveToThemeModal.blockIndex;

        // Disable confirm button during request
        const confirmBtn = document.querySelector('[data-testid="pu-mtt-confirm-btn"]');
        if (confirmBtn) {
            confirmBtn.disabled = true;
            confirmBtn.textContent = 'Moving...';
        }

        try {
            const result = await PU.api.post('/api/pu/move-to-theme', {
                job_id: jobId,
                prompt_id: promptId,
                block_index: blockIndex,
                theme_path: themePath,
                fork: fork,
                wildcard_names: wildcardNames
            });

            if (result.success) {
                PU.moveToTheme.close();

                // Show warnings in toast if any
                let msg = `Moved to ${result.theme_file}`;
                if (result.warnings && result.warnings.length > 0) {
                    msg += ` (${result.warnings.join('; ')})`;
                }
                PU.actions.showToast(msg, 'success');

                // Reload job data to pick up the changes
                await PU.api.loadJob(jobId);

                // Clear modified state so we use the fresh server data
                delete PU.state.modifiedJobs[jobId];

                // Reload extensions tree (new theme file was created)
                await PU.api.loadExtensions();

                // Re-render blocks and right panel
                await PU.editor.renderBlocks(jobId, promptId);
                PU.rightPanel.render();
            } else {
                PU.actions.showToast(result.error || 'Move failed', 'error');
            }
        } catch (e) {
            PU.actions.showToast(`Move failed: ${e.message}`, 'error');
        } finally {
            if (confirmBtn) {
                confirmBtn.disabled = false;
                confirmBtn.textContent = 'Move';
            }
        }
    },

    /**
     * Close the modal and reset state.
     */
    close() {
        PU.state.themes.moveToThemeModal = { visible: false, blockPath: null, blockIndex: null };
        const modal = document.querySelector('[data-testid="pu-move-to-theme-modal"]');
        if (modal) modal.style.display = 'none';
    }
};
