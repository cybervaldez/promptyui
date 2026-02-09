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

        // Load extensions first (needed for dropdown population)
        await PU.inspector.init();

        // Then load jobs (which may select a job and populate dropdowns)
        await PU.sidebar.init();

        // Update header
        PU.actions.updateHeader();

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
        const mode = params.get('mode');
        const composition = params.get('composition');
        const wcMax = params.get('wc_max');
        const extText = params.get('ext_text');

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
            }
        }

        // Set wc_max from URL if provided
        if (wcMax) {
            const wcMaxVal = parseInt(wcMax, 10);
            if (!isNaN(wcMaxVal) && wcMaxVal >= 0) {
                PU.state.previewMode.extWildcardsMax = wcMaxVal;
            }
        }

        // Set ext_text from URL if provided
        if (extText) {
            const extTextVal = parseInt(extText, 10);
            if (!isNaN(extTextVal) && extTextVal >= 1) {
                PU.state.previewMode.extTextMax = extTextVal;
            }
        }

        // Enter preview mode if specified in URL
        if (mode === 'preview') {
            // Will enter after init when prompt is loaded
            PU.state.previewMode.pendingActivation = true;
        }

        if (modal === 'export') {
            // Will open after init
            setTimeout(() => PU.export.open(), 500);
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
        if (PU.state.previewMode.active) {
            params.set('mode', 'preview');
            params.set('composition', PU.state.previewMode.compositionId);
            // Include wc_max if non-default (default is 0)
            if (PU.state.previewMode.extWildcardsMax > 0) {
                params.set('wc_max', PU.state.previewMode.extWildcardsMax);
            }
            // Include ext_text if non-default (default is 1)
            if (PU.state.previewMode.extTextMax !== 1) {
                params.set('ext_text', PU.state.previewMode.extTextMax);
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
            activeJobEl.textContent = PU.state.activeJobId || 'No job selected';
        }
    },

    // ============================================
    // Section Toggle Actions
    // ============================================

    toggleSection(section) {
        PU.state.ui.sectionsCollapsed[section] = !PU.state.ui.sectionsCollapsed[section];

        const toggle = document.querySelector(`[data-testid="pu-jobs-toggle"]`);
        if (toggle) {
            toggle.classList.toggle('collapsed', PU.state.ui.sectionsCollapsed[section]);
        }

        PU.helpers.saveUIState();
    },

    toggleDefaults() {
        PU.state.ui.sectionsCollapsed.defaults = !PU.state.ui.sectionsCollapsed.defaults;

        const form = document.querySelector('[data-testid="pu-defaults-form"]');
        if (form) {
            form.classList.toggle('collapsed', PU.state.ui.sectionsCollapsed.defaults);
        }
    },

    // ============================================
    // Extension Actions (Right Inspector Only)
    // ============================================

    filterInspectorExtensions(value) {
        PU.state.ui.inspectorExtensionFilter = value;
        PU.inspector.renderExtensionsTree();
    },

    selectExtension(path) {
        PU.inspector.selectExtFile(path);
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

        // Auto-select first prompt if none selected
        const job = PU.state.jobs[jobId];
        if (job && job.prompts && job.prompts.length > 0) {
            const firstPromptId = typeof job.prompts[0] === 'string'
                ? job.prompts[0]
                : job.prompts[0].id;

            if (!PU.state.activePromptId) {
                PU.state.activePromptId = firstPromptId;
            }
        }

        // Update UI
        PU.actions.updateHeader();
        PU.sidebar.renderJobs();

        if (PU.state.activePromptId) {
            await PU.editor.showPrompt(jobId, PU.state.activePromptId);
        }

        if (updateUrl) {
            PU.actions.updateUrl();
        }

        PU.helpers.saveUIState();
    },

    async selectPrompt(jobId, promptId) {
        // Ensure job is selected
        if (PU.state.activeJobId !== jobId) {
            await PU.actions.selectJob(jobId, false);
        }

        PU.state.activePromptId = promptId;
        PU.state.selectedBlockPath = null;

        // Update UI
        PU.sidebar.updateActiveStates();
        await PU.editor.showPrompt(jobId, promptId);
        PU.inspector.showOverview();

        PU.actions.updateUrl();
        PU.helpers.saveUIState();
    },

    selectDefaults(jobId) {
        PU.actions.selectJob(jobId);
        // Scroll to defaults toolbar
        const toolbar = document.querySelector('[data-testid="pu-defaults-toolbar"]');
        if (toolbar) {
            toolbar.scrollIntoView({ behavior: 'smooth' });
        }
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

        // Update inspector
        const prompt = PU.helpers.getActivePrompt();
        if (prompt) {
            const blockData = PU.blocks.findBlockByPath(prompt.text || [], path);
            if (blockData && 'content' in blockData) {
                const wildcards = PU.blocks.detectWildcards(blockData.content);
                PU.inspector.updateWildcardsContext(wildcards, prompt.wildcards || []);
            } else if (blockData && 'ext_text' in blockData) {
                // Show ext_text context
                PU.inspector.selectExtFile(`${prompt.ext || 'defaults'}/${blockData.ext_text}`);
            }
        }
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
    // Preview Actions
    // ============================================

    showPreviewForBlock(path) {
        PU.preview.show(path);
    },

    previewAllVariations() {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !prompt.text || prompt.text.length === 0) {
            PU.actions.showToast('No content to preview', 'error');
            return;
        }

        // Preview first block
        PU.preview.show('0');
    },

    closePreview() {
        PU.preview.hide();
    },

    /**
     * Toggle between edit mode and preview mode (checkpoint list)
     */
    togglePreviewMode() {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) {
            PU.actions.showToast('No prompt selected', 'error');
            return;
        }

        PU.preview.togglePreviewMode();
    },

    copyAllVariations() {
        PU.preview.copyAll();
    },

    showAllVariations() {
        PU.preview.showAll();
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

    // ============================================
    // Misc Actions
    // ============================================

    toggleAddMenu(show) {
        const menu = document.querySelector('.pu-add-menu');
        if (menu) {
            if (show === undefined) {
                menu.style.display = menu.style.display === 'none' ? 'block' : 'none';
            } else {
                menu.style.display = show ? 'block' : 'none';
            }
        }
    },

    insertExtText(extId) {
        const prompt = PU.editor.getModifiedPrompt();
        if (!prompt) {
            PU.actions.showToast('No prompt selected', 'error');
            return;
        }

        if (!Array.isArray(prompt.text)) {
            prompt.text = [];
        }

        prompt.text.push({ ext_text: extId });

        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
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
// Initialize on DOM ready
// ============================================
document.addEventListener('DOMContentLoaded', () => {
    PU.actions.init();
});

// Close dropdowns when clicking outside
document.addEventListener('click', (e) => {
    // Close add menu
    if (!e.target.closest('.pu-add-root-dropdown')) {
        PU.actions.toggleAddMenu(false);
    }

    // Close preview when clicking outside
    if (PU.state.preview.visible && !e.target.closest('.pu-preview-popup') && !e.target.closest('.pu-content-input')) {
        // Don't close if clicking another input (preview will switch)
        if (!e.target.classList.contains('pu-content-input')) {
            PU.preview.hide();
        }
    }

    // Close extension picker when clicking outside
    if (PU.state.extPickerCallback && !e.target.closest('.pu-ext-picker-popup') && !e.target.closest('.pu-add-menu')) {
        PU.inspector.closeExtPicker();
    }
});

// Handle escape key
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (PU.state.extPickerCallback) {
            PU.inspector.closeExtPicker();
        } else if (PU.state.exportModal.visible) {
            PU.export.close();
        } else if (PU.state.preview.visible) {
            PU.preview.hide();
        } else if (PU.state.previewMode.active) {
            PU.preview.exitPreviewMode();
        }
    }
});
