/**
 * PromptyUI - Main Entry Point
 *
 * Initializes the application and defines action handlers.
 */

/**
 * Actions - UI event handlers
 */
PU.actions = {
    /**
     * Initialize the application
     */
    async init() {
        // Load saved UI state
        PU.helpers.loadUIState();

        // Load URL parameters
        PU.actions.parseUrlParams();

        // Initialize editor mode (restore persisted mode before first render)
        PU.editorMode.init();

        // Load extensions first (needed for dropdown population)
        await PU.rightPanel.init();

        // Suppress transitions during initial collapsed state restore
        const sidebar = document.querySelector('[data-testid="pu-sidebar"]');
        const rightPanel = document.querySelector('[data-testid="pu-right-panel"]');
        if (sidebar) sidebar.style.transition = 'none';
        if (rightPanel) rightPanel.style.transition = 'none';

        // Apply persisted collapsed states (instant, no animation)
        PU.rightPanel.applyCollapsedState();
        PU.sidebar.applyCollapsedState();

        // Force reflow so collapsed state commits with transition: none
        void document.body.offsetHeight;

        // Re-enable transitions after paint
        requestAnimationFrame(() => requestAnimationFrame(() => {
            if (sidebar) sidebar.style.transition = '';
            if (rightPanel) rightPanel.style.transition = '';
        }));

        // Show loading skeleton while jobs load
        PU.sidebar.showLoadingSkeleton();

        // Then load jobs (which may select a job and populate dropdowns)
        await PU.sidebar.init();

        // Remove skeleton and check layout
        PU.sidebar.hideLoadingSkeleton();

        if (!PU.state.activeJobId) {
            // No job selected — expand sidebar to fill screen.
            // Editor + right panel are hidden via CSS data-layout="no-job".
            PU.actions.setExpandedLayout(true);
            // Clear any persisted collapsed state so the sidebar is visible
            if (PU.state.ui.leftSidebarCollapsed) {
                PU.sidebar.expand();
            }
        }

        // Restore focus mode from URL (blocks are rendered after sidebar.init)
        if (PU.state.focusMode.pendingPath) {
            const focusPath = PU.state.focusMode.pendingPath;
            PU.state.focusMode.pendingPath = null;
            const prompt = PU.helpers.getActivePrompt();
            if (prompt && Array.isArray(prompt.text) && prompt.text.length > 0) {
                const block = PU.blocks.findBlockByPath(prompt.text, focusPath);
                if (block && 'content' in block) {
                    // Exact path exists — regular enter
                    PU.focus.enter(focusPath);
                } else {
                    // Block doesn't exist — check if parent does (draft restore)
                    const parts = focusPath.split('.');
                    if (parts.length > 1) {
                        const parentPath = parts.slice(0, -1).join('.');
                        const parent = PU.blocks.findBlockByPath(prompt.text, parentPath);
                        if (parent && 'content' in parent) {
                            PU.focus.enter(focusPath, { draft: true, parentPath: parentPath });
                        }
                    }
                }
            }
        }

        // Re-trigger preview rendering if deep-linked to preview mode
        // (blocks are now loaded after sidebar.init, so renderPreview has data)
        if (PU.state.ui.editorMode === 'preview') {
            PU.editorMode.renderPreview();
            PU.editorMode.renderSidebarPreview();
            PU.rightPanel.renderOpsSection();
        }

        // Sync URL after init — clears stale params (e.g. focus path that failed to restore)
        PU.actions.updateUrl();

        // Update header
        PU.actions.updateHeader();

        // Init global dropdown close handler (once)
        PU.preview.initDropdownCloseHandler();

        // Init responsive panel behavior
        PU.responsive.init();

        console.log('PromptyUI initialized');
    },

    /**
     * Parse URL parameters
     */
    parseUrlParams() {
        const params = new URLSearchParams(window.location.search);

        const jobId = params.get('job');
        const promptId = params.get('prompt');
        const modal = params.get('modal');
        const composition = params.get('composition');
        const extText = params.get('ext_text');
        const viz = params.get('viz');

        if (jobId) {
            PU.state.activeJobId = jobId;
            PU.state.ui.jobsExpanded[jobId] = true;
        }

        if (promptId) {
            PU.state.activePromptId = promptId;
        }

        // Set composition from URL if provided
        if (composition) {
            const compId = parseInt(composition, 10);
            if (!isNaN(compId) && compId >= 0) {
                PU.state.previewMode.compositionId = compId;
                PU.state.previewMode._compositionFromUrl = true;
            }
        }

        // Set ext_text from URL if provided
        if (extText) {
            const extTextVal = parseInt(extText, 10);
            if (!isNaN(extTextVal) && extTextVal >= 1) {
                PU.state.previewMode.extTextMax = extTextVal;
            }
        }

        // Set visualizer from URL if provided
        if (viz && ['compact', 'typewriter', 'reel', 'stack', 'ticker'].includes(viz)) {
            PU.state.previewMode.visualizer = viz;
            const vizSelect = document.querySelector('[data-testid="pu-editor-visualizer"]');
            if (vizSelect) vizSelect.value = viz;
        }

        // Set editor mode from URL if provided
        const editorMode = params.get('editorMode');
        if (editorMode && ['write', 'preview', 'review'].includes(editorMode)) {
            PU.state.ui.editorMode = editorMode;
            PU.state.ui.editorLayers = { ...PU.editorMode.PRESETS[editorMode] };
        }

        // Set preview depth from URL if provided
        const depth = params.get('depth');
        if (depth) {
            const depthVal = parseInt(depth, 10);
            if (!isNaN(depthVal) && depthVal >= 1) {
                PU.state.previewMode.previewDepth = depthVal;
            }
        }

        // Set right panel tab from URL (Review mode only)
        const rightTab = params.get('rightTab');
        if (rightTab && ['wildcards', 'annotations'].includes(rightTab)) {
            PU.state.ui.rightPanelTab = rightTab;
        }

        const focusPath = params.get('focus');
        if (focusPath && /^[0-9]+(\.[0-9]+)*$/.test(focusPath)) {
            PU.state.focusMode.pendingPath = focusPath;
        }

        if (modal === 'export') {
            // Will open after init
            setTimeout(() => PU.export.open(), 500);
        } else if (modal === 'focus') {
            // modal=focus opens focus mode; uses focus param for path, defaults to "0"
            if (!PU.state.focusMode.pendingPath) {
                PU.state.focusMode.pendingPath = '0';
            }
        }
    },

    /**
     * Update URL with current state
     */
    updateUrl() {
        const params = new URLSearchParams();

        if (PU.state.activeJobId) {
            params.set('job', PU.state.activeJobId);
        }
        if (PU.state.activePromptId) {
            params.set('prompt', PU.state.activePromptId);
        }
        if (PU.state.activePromptId) {
            params.set('composition', PU.state.previewMode.compositionId);
            if (PU.state.previewMode.extTextMax !== 1) {
                params.set('ext_text', PU.state.previewMode.extTextMax);
            }
            if (PU.state.previewMode.visualizer !== 'compact') {
                params.set('viz', PU.state.previewMode.visualizer);
            }
            if (PU.state.focusMode.active && PU.state.focusMode.blockPath) {
                params.set('modal', 'focus');
                params.set('focus', PU.state.focusMode.blockPath);
            }
            if (PU.state.ui.editorMode !== 'write') {
                params.set('editorMode', PU.state.ui.editorMode);
            }
            if (PU.state.ui.editorMode === 'preview' && PU.state.previewMode.previewDepth !== null) {
                params.set('depth', PU.state.previewMode.previewDepth);
            }
            if (PU.state.ui.editorMode === 'review' && PU.state.ui.rightPanelTab !== 'wildcards') {
                params.set('rightTab', PU.state.ui.rightPanelTab);
            }
        }

        const newUrl = params.toString() ? `?${params.toString()}` : '/';
        window.history.replaceState({}, '', newUrl);
    },

    /**
     * Update header with active job
     */
    updateHeader() {
        const activeJobEl = document.querySelector('[data-testid="pu-header-active-job"]');
        if (activeJobEl) {
            if (PU.state.activeJobId && PU.state.activePromptId) {
                activeJobEl.textContent = `${PU.state.activeJobId} / ${PU.state.activePromptId}`;
            } else {
                activeJobEl.textContent = PU.state.activeJobId || 'No job selected';
            }
        }
    },

    /**
     * Toggle expanded sidebar layout (no job selected).
     */
    setExpandedLayout(expanded) {
        const main = document.querySelector('.pu-main');
        if (!main) return;
        if (expanded) {
            main.dataset.layout = 'no-job';
        } else {
            delete main.dataset.layout;
            // Force sidebar visible — collapsed state may have been
            // persisted while no-job CSS was masking it
            if (PU.state.ui.leftSidebarCollapsed) {
                PU.sidebar.expand();
            }
        }
    },

    // ============================================
    // Section Toggle Actions
    // ============================================

    toggleSection(section) {
        PU.state.ui.sectionsCollapsed[section] = !PU.state.ui.sectionsCollapsed[section];
        PU.helpers.saveUIState();
    },

    // ============================================
    // Extension Actions (Right Inspector Only)
    // ============================================

    selectExtension(path) {
        // Placeholder for extension selection if needed
    },

    // ============================================
    // Job Actions
    // ============================================

    toggleJobExpand(jobId) {
        PU.state.ui.jobsExpanded[jobId] = !PU.state.ui.jobsExpanded[jobId];
        PU.sidebar.renderJobs();
        PU.helpers.saveUIState();
    },

    toggleJobSection(jobId, section) {
        // Could expand/collapse prompt list, etc.
        console.log('Toggle job section:', jobId, section);
    },

    async selectJob(jobId, updateUrl = true) {
        // Collapse expanded sidebar layout when a job is selected
        PU.actions.setExpandedLayout(false);

        // On mobile, auto-close sidebar overlay after selecting a job
        if (PU.responsive && PU.responsive.isMobile()) {
            PU.responsive.closePanel('pu-sidebar');
        }

        // Check if full job details are loaded (prompts should be objects, not strings)
        const existingJob = PU.state.jobs[jobId];
        const needsFullLoad = !existingJob ||
            !existingJob.prompts ||
            (existingJob.prompts.length > 0 && typeof existingJob.prompts[0] === 'string');

        if (needsFullLoad) {
            if (existingJob && existingJob.valid === false) {
                // Invalid job - show error
                PU.actions.showToast(`Job '${jobId}' has errors: ${existingJob.error}`, 'error');
                return;
            }

            try {
                await PU.api.loadJob(jobId);
            } catch (e) {
                console.error('Failed to load job:', jobId, e);
                PU.actions.showToast(`Failed to load job: ${e.message}`, 'error');
                return;
            }
        }

        PU.state.activeJobId = jobId;
        PU.state.ui.jobsExpanded[jobId] = true;

        // Auto-select first prompt if none selected or current prompt doesn't belong to this job
        const job = PU.state.jobs[jobId];
        if (job && job.prompts && job.prompts.length > 0) {
            const firstPromptId = typeof job.prompts[0] === 'string'
                ? job.prompts[0]
                : job.prompts[0].id;

            const currentPromptInJob = PU.state.activePromptId && job.prompts.some(p =>
                (typeof p === 'string' ? p : p.id) === PU.state.activePromptId
            );

            if (!PU.state.activePromptId || !currentPromptInJob) {
                PU.state.activePromptId = firstPromptId;
            }
        }

        // Clear transient preview state on job switch
        PU.state.previewMode.lockedValues = {};
        PU.state.previewMode.focusedWildcards = [];
        PU.state.previewMode.selectedWildcards = {};

        // Update UI
        PU.actions.updateHeader();
        PU.sidebar.renderJobs();

        // Apply prompt-level wildcards_max (kept for build-composition export)
        if (PU.state.activePromptId) {
            const p = PU.helpers.getActivePrompt();
            const j = PU.state.jobs[jobId];
            PU.state.previewMode.wildcardsMax = p?.wildcards_max ?? j?.defaults?.wildcards_max ?? 0;
        }

        // Load operations (build hooks) for this job
        await PU.rightPanel.loadOperations();

        // Load session state (initial load — set baseline, hydrate non-URL fields)
        if (PU.state.activePromptId) {
            await PU.rightPanel.loadSession();
        }

        if (PU.state.activePromptId) {
            await PU.editor.showPrompt(jobId, PU.state.activePromptId);
            PU.rightPanel.render();
        } else {
            // No prompts in this job — show no-prompts CTA
            PU.editor.showNoPromptsState();
        }

        if (updateUrl) {
            PU.actions.updateUrl();
        }

        PU.helpers.saveUIState();
    },

    async selectPrompt(jobId, promptId) {
        if (PU.state.focusMode.active) PU.focus.exit();

        // Ensure job is selected
        if (PU.state.activeJobId !== jobId) {
            await PU.actions.selectJob(jobId, false);
        }

        PU.state.activePromptId = promptId;
        PU.state.selectedBlockPath = null;

        // Apply prompt-level wildcards_max (or fall back to job defaults)
        const activePrompt = PU.helpers.getActivePrompt();
        const activeJob = PU.helpers.getActiveJob();
        PU.state.previewMode.wildcardsMax = activePrompt?.wildcards_max ?? activeJob?.defaults?.wildcards_max ?? 0;

        // Clear transient preview state on prompt change
        PU.state.previewMode.lockedValues = {};
        PU.state.previewMode.focusedWildcards = [];
        PU.state.previewMode.selectedWildcards = {};
        PU.state.previewMode.shortlist = [];

        // Hide focus banner if visible (stale bulb focus from previous prompt)
        PU.rightPanel._removeFocus();

        // Invalidate autocomplete cache on prompt switch
        PU.state.autocompleteCache.loaded = false;
        PU.state.autocompleteCache.extWildcardNames = [];

        // Load session state (restores composition, locks, overrides, active operation)
        await PU.rightPanel.loadSession();

        // Update UI
        PU.sidebar.updateActiveStates();
        PU.actions.updateHeader();
        await PU.editor.showPrompt(jobId, promptId);
        PU.rightPanel.render();

        PU.actions.updateUrl();
        PU.helpers.saveUIState();
    },

    createNewJob() {
        const jobId = prompt('Enter new job name:');
        if (!jobId) return;

        // Validate job name (alphanumeric and hyphens only)
        if (!/^[a-zA-Z0-9-]+$/.test(jobId)) {
            PU.actions.showToast('Job name can only contain letters, numbers, and hyphens', 'error');
            return;
        }

        // Check if already exists
        if (PU.state.jobs[jobId]) {
            PU.actions.showToast('Job already exists', 'error');
            return;
        }

        // Create new job in state
        PU.state.jobs[jobId] = {
            valid: true,
            defaults: {
                seed: 42,
                trigger_delimiter: ', ',
                prompts_delimiter: ', ',
                ext: 'defaults'
            },
            prompts: [],
            loras: []
        };

        // Mark as modified (needs to be saved)
        PU.state.modifiedJobs[jobId] = PU.helpers.deepClone(PU.state.jobs[jobId]);

        // Update UI
        PU.sidebar.renderJobs();
        PU.actions.selectJob(jobId);

        PU.actions.showToast(`Created new job '${jobId}'`, 'success');
    },

    async createNewPrompt(jobId) {
        if (!jobId) jobId = PU.state.activeJobId;
        if (!jobId) return;

        const job = PU.state.jobs[jobId];
        if (!job) return;

        const promptId = prompt('Enter prompt name:');
        if (!promptId) return;

        // Validate prompt name (letters, numbers, hyphens, underscores)
        if (!/^[a-zA-Z0-9-_]+$/.test(promptId)) {
            PU.actions.showToast('Prompt name can only contain letters, numbers, hyphens, and underscores', 'error');
            return;
        }

        // Check for duplicates
        const prompts = job.prompts || [];
        if (prompts.some(p => (typeof p === 'string' ? p : p.id) === promptId)) {
            PU.actions.showToast('Prompt already exists in this job', 'error');
            return;
        }

        // Create new prompt skeleton
        const newPrompt = { id: promptId, text: [], wildcards: [] };

        // Ensure modified job exists
        if (!PU.state.modifiedJobs[jobId]) {
            PU.state.modifiedJobs[jobId] = PU.helpers.deepClone(PU.state.jobs[jobId]);
        }

        // Add to both original and modified state
        job.prompts.push(newPrompt);
        PU.state.modifiedJobs[jobId].prompts.push(PU.helpers.deepClone(newPrompt));

        // Select the new prompt (renders editor + right panel)
        await PU.actions.selectPrompt(jobId, promptId);

        // Update sidebar to show the new prompt
        PU.sidebar.renderJobs();

        // Open focus overlay in draft mode for the first block
        // (toast suppressed — overlay opening is sufficient confirmation)
        PU.editor.addBlock('content');
    },

    // ============================================
    // Block Actions
    // ============================================

    selectBlock(path) {
        PU.state.selectedBlockPath = path;

        // Update block highlight
        document.querySelectorAll('.pu-block.selected').forEach(el => {
            el.classList.remove('selected');
        });

        const block = document.querySelector(`[data-path="${path}"]`);
        if (block) {
            block.classList.add('selected');
        }

        // Update right panel
        PU.rightPanel.render();
    },

    toggleBlock(path) {
        // Could expand/collapse block children
        console.log('Toggle block:', path);
    },

    updateBlockContent(path, content) {
        PU.editor.updateBlockContent(path, content);
    },

    updateExtTextMax(path, value) {
        PU.editor.updateExtTextMax(path, value);
    },

    addBlock(type) {
        PU.editor.addBlock(type);
    },

    addNestedBlock(parentPath) {
        PU.editor.addNestedBlock(parentPath);
    },

    deleteBlock(path) {
        PU.editor.deleteBlock(path);
    },

    onBlockBlur(path) {
        // Could hide preview or save state
    },

    // ============================================
    // Defaults Actions
    // ============================================

    updateDefaults(key, value) {
        PU.editor.updateDefaults(key, value);
    },

    // ============================================
    // Export Actions
    // ============================================

    openExportModal() {
        PU.export.open();
    },

    closeExportModal() {
        PU.export.close();
    },

    confirmExport() {
        PU.export.confirm();
    },

    /**
     * Show inline "Copied to Clipboard" feedback on a copy button, then revert.
     */
    _showCopiedFeedback(btn) {
        if (!btn) return;
        if (btn._copiedTimer) clearTimeout(btn._copiedTimer);
        const original = btn._originalCopyHTML || btn.innerHTML;
        btn._originalCopyHTML = original;
        btn.classList.add('pu-copied');
        btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" width="12" height="12"><polyline points="20 6 9 17 4 12"/></svg> Copied to Clipboard';
        btn._copiedTimer = setTimeout(() => {
            btn.classList.remove('pu-copied');
            btn.innerHTML = original;
            btn._copiedTimer = null;
            btn._originalCopyHTML = null;
        }, 2000);
    },

    // ============================================
    // Misc Actions
    // ============================================

    toggleAddMenu(show) {
        const menu = document.querySelector('.pu-add-menu');
        if (menu) {
            if (show === undefined) {
                const opening = menu.style.display === 'none';
                menu.style.display = opening ? 'block' : 'none';
                if (opening) PU.overlay.showOverlay();
            } else {
                menu.style.display = show ? 'block' : 'none';
                if (show) PU.overlay.showOverlay();
            }
        }
    },

    async insertExtText(extId) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) {
            PU.actions.showToast('No prompt selected', 'error');
            return;
        }

        if (!Array.isArray(prompt.text)) {
            prompt.text = [];
        }

        prompt.text.push({ ext_text: extId });

        await PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.actions.showToast(`Added ext_text: ${extId}`, 'success');
    },

    showHelp() {
        alert(`PromptyUI Help

Keyboard-free workflow:
- Click jobs in sidebar to select
- Click prompts to edit
- Text inputs are always editable
- Preview appears on focus
- Drag extensions to editor

Tips:
- Use __name__ syntax for wildcards
- Define wildcards in inspector panel
- Export saves to jobs/{id}/jobs.yaml

Need more help? Check docs/creating_jobs.md`);
    },

    showToast(message, type = 'info') {
        const container = document.querySelector('[data-testid="pu-toast-container"]');
        if (!container) return;

        const toast = document.createElement('div');
        toast.className = `pu-toast ${type}`;
        toast.textContent = message;

        container.appendChild(toast);

        // Remove after 3 seconds
        setTimeout(() => {
            toast.remove();
        }, 3000);
    }
};

// ============================================
// Responsive panel management (mobile/tablet)
// ============================================
PU.responsive = {
    _mobileQuery: null,
    _tabletQuery: null,

    /** True when viewport is mobile (<768px). */
    isMobile() {
        return PU.responsive._mobileQuery?.matches ?? false;
    },

    /** True when viewport is tablet (768-1024px). */
    isTablet() {
        return PU.responsive._tabletQuery?.matches ?? false;
    },

    /** True when either panel should use overlay behavior. */
    isOverlay() {
        return PU.responsive.isMobile() || PU.responsive.isTablet();
    },

    /** Initialize matchMedia listeners and touch gestures. */
    init() {
        PU.responsive._mobileQuery = window.matchMedia('(max-width: 767px)');
        PU.responsive._tabletQuery = window.matchMedia('(min-width: 768px) and (max-width: 1024px)');

        // Wire backdrop click
        const backdrop = document.querySelector('[data-testid="pu-backdrop"]');
        if (backdrop) {
            backdrop.addEventListener('click', () => {
                PU.responsive.closePanels();
            });
        }

        // Wire popup overlay click (dismiss all popups)
        const popupOverlay = document.querySelector('[data-testid="pu-popup-overlay"]');
        if (popupOverlay) {
            popupOverlay.addEventListener('click', () => {
                PU.overlay.dismissAll();
            });
        }

    },

    /** Open a panel as overlay (adds pu-panel-open + shows backdrop). */
    openPanel(panelTestId) {
        const panel = document.querySelector(`[data-testid="${panelTestId}"]`);
        if (!panel) return;
        panel.classList.add('pu-panel-open');
        PU.responsive._showBackdrop();
    },

    /** Close a specific panel overlay. */
    closePanel(panelTestId) {
        const panel = document.querySelector(`[data-testid="${panelTestId}"]`);
        if (!panel) return;
        panel.classList.remove('pu-panel-open');
        // Hide backdrop only if no panels are open
        if (!document.querySelector('.pu-panel-open')) {
            PU.responsive._hideBackdrop();
        }
    },

    /** Close all overlay panels. */
    closePanels() {
        document.querySelectorAll('.pu-panel-open').forEach(el => {
            el.classList.remove('pu-panel-open');
        });
        PU.responsive._hideBackdrop();
    },

    _showBackdrop() {
        const backdrop = document.querySelector('[data-testid="pu-backdrop"]');
        if (backdrop) backdrop.classList.add('visible');
    },

    _hideBackdrop() {
        const backdrop = document.querySelector('[data-testid="pu-backdrop"]');
        if (backdrop) backdrop.classList.remove('visible');
    }
};

// ============================================
// Initialize on DOM ready
// ============================================
document.addEventListener('DOMContentLoaded', () => {
    PU.actions.init();
});

// Register add menu as a popover overlay
PU.overlay.registerPopover('addMenu', () => PU.actions.toggleAddMenu(false));

// Close dropdowns when clicking outside
document.addEventListener('click', (e) => {
    // Close autocomplete when clicking outside
    if (PU.quill._autocompleteOpen && !e.target.closest('.pu-autocomplete-menu') && !e.target.closest('.ql-editor')) {
        PU.quill.closeAutocomplete();
    }

    // Close add menu
    if (!e.target.closest('.pu-add-root-dropdown')) {
        PU.actions.toggleAddMenu(false);
    }

    // Close extension picker when clicking outside
    if (PU.state.extPickerCallback && !e.target.closest('.pu-ext-picker-popup') && !e.target.closest('.pu-add-menu')) {
        PU.inspector.closeExtPicker();
    }

    // Close theme swap dropdown when clicking outside
    if (PU.state.themes.swapDropdown.visible &&
        !e.target.closest('#pu-theme-swap-dropdown') &&
        !e.target.closest('.pu-theme-label')) {
        PU.themes.closeSwapDropdown();
    }

    // Close theme context menu when clicking outside
    if (PU.state.themes.contextMenu.visible &&
        !e.target.closest('#pu-theme-context-menu') &&
        !e.target.closest('.block-more')) {
        PU.themes.closeContextMenu();
    }

    // Close move-to-theme modal on overlay click
    if (PU.state.themes.moveToThemeModal.visible &&
        e.target.matches('[data-testid="pu-move-to-theme-modal"]')) {
        PU.moveToTheme.close();
    }
});

// Handle keyboard shortcuts
document.addEventListener('keydown', (e) => {
    // Cmd/Ctrl+S — save prompt
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        PU.editor.savePrompt();
        return;
    }

    // [ — toggle left sidebar (skip if typing in input/textarea/contenteditable)
    if (e.key === '[' && !e.ctrlKey && !e.metaKey && !e.altKey) {
        const tag = (e.target.tagName || '').toLowerCase();
        const editable = e.target.isContentEditable;
        if (tag !== 'input' && tag !== 'textarea' && !editable) {
            e.preventDefault();
            PU.sidebar.togglePanel();
            return;
        }
    }

    // ] — toggle right panel (skip if typing in input/textarea/contenteditable)
    if (e.key === ']' && !e.ctrlKey && !e.metaKey && !e.altKey) {
        const tag = (e.target.tagName || '').toLowerCase();
        const editable = e.target.isContentEditable;
        if (tag !== 'input' && tag !== 'textarea' && !editable) {
            e.preventDefault();
            PU.rightPanel.togglePanel();
            return;
        }
    }

    if (e.key === 'Escape') {
        if (PU.state.themes.swapDropdown.visible) {
            PU.themes.closeSwapDropdown();
        } else if (PU.state.themes.contextMenu.visible) {
            PU.themes.closeContextMenu();
        } else if (PU.state.themes.moveToThemeModal.visible) {
            PU.moveToTheme.close();
        } else if (PU.state.themes.saveModal.visible) {
            PU.themes.closeSaveModal();
        } else if (PU.quill._autocompleteOpen) {
            PU.quill.closeAutocomplete();
        } else if (PU.state.focusMode && PU.state.focusMode.active) {
            PU.focus.exit();
        } else if (PU.state.extPickerCallback) {
            PU.inspector.closeExtPicker();
        } else if (PU.state.exportModal.visible) {
            PU.export.close();
        }
    }
});

