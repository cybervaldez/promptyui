/**
 * PromptyUI - State Management
 *
 * Central state store for the PromptyUI application.
 * All state changes should go through PU.actions.
 */

const PU = window.PU || {};

/**
 * Overlay Registry — central dismiss-all for popups, modals, panels.
 * Every overlay registers its close function. Openers call dismissAll()
 * before showing themselves to enforce mutual exclusion.
 *
 * Two layers:
 *   popover — lightweight (context menu, swap dropdown, add menu, etc.)
 *   modal   — heavyweight (move-to-theme, save-as-theme, export, ext picker, focus)
 *
 * dismissAll() closes everything. dismissPopovers() closes only the popover layer.
 */
PU.overlay = {
    _popovers: [],   // [{name, close}]
    _modals: [],      // [{name, close}]

    /** Register a popover-layer overlay. */
    registerPopover(name, closeFn) {
        PU.overlay._popovers.push({ name, close: closeFn });
    },

    /** Register a modal-layer overlay. */
    registerModal(name, closeFn) {
        PU.overlay._modals.push({ name, close: closeFn });
    },

    /** Show the popup backdrop overlay. */
    showOverlay() {
        const el = document.querySelector('[data-testid="pu-popup-overlay"]');
        if (el) el.classList.add('visible');
    },

    /** Hide the popup backdrop overlay and clear sticky hover state. */
    hideOverlay() {
        const el = document.querySelector('[data-testid="pu-popup-overlay"]');
        if (el) el.classList.remove('visible');

        // Clear lingering context-active marks
        document.querySelectorAll('.pu-ctx-active').forEach(b => b.classList.remove('pu-ctx-active'));

        // Absorb the dismiss click: block pointer-events on the editor
        // so the click/touch-end doesn't bleed through to a block behind
        // the overlay, which would immediately trigger a new hover state.
        const blocks = document.querySelector('[data-testid="pu-blocks-container"]');
        if (blocks) {
            blocks.style.pointerEvents = 'none';
            setTimeout(() => { blocks.style.pointerEvents = ''; }, 80);
        }
    },

    /** Close all popovers (lightweight overlays). */
    dismissPopovers() {
        for (const entry of PU.overlay._popovers) {
            entry.close();
        }
        PU.overlay.hideOverlay();
    },

    /** Close everything — popovers + modals + responsive panels on mobile. */
    dismissAll() {
        PU.overlay.dismissPopovers();
        for (const entry of PU.overlay._modals) {
            entry.close();
        }
    }
};

/**
 * Application State
 */
PU.state = {
    // Global extensions (loaded once, cached)
    globalExtensions: {
        tree: {},
        loaded: false
    },

    // All jobs (loaded from jobs/ folder)
    jobs: {},
    jobsLoaded: false,

    // Currently active job and prompt
    activeJobId: null,
    activePromptId: null,

    // Currently selected block path
    selectedBlockPath: null,

    // Modified job data (in-memory edits)
    modifiedJobs: {},

    // UI state
    ui: {
        sectionsCollapsed: {
            jobs: false,
            defaults: false
        },
        jobsExpanded: {},
        outputFooterCollapsed: false,
        outputLabelMode: 'none',
        outputGroupBy: null,
        outputGroupCollapsed: {},
        outputFilters: {},
        outputFilterCollapsed: {},
        rpSectionsCollapsed: {},   // (deprecated — kept for compat)
        rightPanelCollapsed: false,
        leftSidebarCollapsed: false
    },

    // Preview state
    preview: {
        activeWildcard: null   // wildcard name at cursor, or null
    },

    // Focus mode state (zen editing overlay)
    focusMode: {
        active: false,
        blockPath: null,         // e.g. "0", "0.1"
        quillInstance: null,     // Transient Quill (not in PU.quill.instances)
        enterTimestamp: 0,       // Debounce guard
        pendingPath: null,       // URL-restored path, consumed after render
        draft: false,            // True when editing a not-yet-materialized block
        draftMaterialized: false, // True after first keystroke materializes the draft
        draftParentPath: null    // Parent path for nested draft blocks
    },

    // Build Composition panel state
    buildComposition: {
        visible: false,
        operations: [],              // Available build hook (operation) file names
        activeOperation: null,       // Currently selected operation (build hook) name
        activeOperationData: null,   // Loaded operation (build hook) YAML content
        generating: false            // Loading state for Export button
    },

    // Export modal state
    exportModal: {
        visible: false,
        yaml: '',
        validation: {
            valid: true,
            warnings: [],
            errors: []
        }
    },

    // Autocomplete cache (for wildcard dropdown)
    autocompleteCache: {
        extWildcardNames: [],  // [{name, source}] from scoped extensions
        loaded: false,
        loading: false,
        extScope: null         // ext scope string (invalidate on change)
    },

    // Theme management UI state
    themes: {
        swapDropdown: { visible: false, path: null, currentTheme: null },
        diffPopover: { visible: false, targetTheme: null, diffData: null },
        contextMenu: { visible: false, path: null, isTheme: false },
        saveModal: { visible: false, blockPath: null },
        moveToThemeModal: { visible: false, blockPath: null, blockIndex: null },
        pushToThemePopover: { visible: false, wildcardName: null },
        sourceDropdown: { visible: false, path: null, currentSource: null }
    },

    // Preview/resolution state (odometer + wildcard selections)
    previewMode: {
        compositionId: 99,    // Default composition ID
        extTextMax: 1,        // Bucket size limit for ext_text (user-controlled)
        extTextCount: 1,      // Actual ext_text count (computed from loaded data)
        wildcardsMax: 0,      // 0 = use actual wildcard counts, >0 = override all wildcard counts
        visualizer: 'compact',  // Wildcard display style: compact | typewriter | reel | stack | ticker
        selectedWildcards: {},  // Per-block wildcard overrides: { blockPath: { wcName: value } }
        lockedValues: {},       // Locked wildcard values: { wcName: ["val1", "val2"] }
        focusedWildcards: [],   // Wildcard names for multi-focus mode (bulb toggle, OR union)
        _extTextCache: {},    // Cached ext_text API data: { "scope/name": data }
        _sessionBaseline: null // Snapshot of persisted session state (for dirty detection)
    }
};

/**
 * State Helpers
 */
PU.helpers = {
    /**
     * Get the current job data (modified or original)
     */
    getActiveJob() {
        const jobId = PU.state.activeJobId;
        if (!jobId) return null;

        // Check for modified version first
        if (PU.state.modifiedJobs[jobId]) {
            return PU.state.modifiedJobs[jobId];
        }

        // Return original (explicit null if not found)
        const job = PU.state.jobs[jobId];
        if (!job) {
            return null;
        }
        return job;
    },

    /**
     * Get the current prompt data
     */
    getActivePrompt() {
        const job = PU.helpers.getActiveJob();
        if (!job || !PU.state.activePromptId) return null;

        const prompts = job.prompts || [];

        // Handle both string prompts (from list API) and object prompts (from full load)
        for (const p of prompts) {
            if (typeof p === 'string') {
                // Just ID - means full job not loaded yet
                continue;
            }
            if (p.id === PU.state.activePromptId) {
                return p;
            }
        }
        return null;
    },

    /**
     * Mark job as modified
     */
    markJobModified(jobId, data) {
        PU.state.modifiedJobs[jobId] = data;
    },

    /**
     * Check if job has unsaved changes
     */
    isJobModified(jobId) {
        return !!PU.state.modifiedJobs[jobId];
    },

    /**
     * Save state to localStorage
     */
    saveUIState() {
        const uiState = {
            activeJobId: PU.state.activeJobId,
            activePromptId: PU.state.activePromptId,
            jobsExpanded: PU.state.ui.jobsExpanded,
            sectionsCollapsed: PU.state.ui.sectionsCollapsed,
            outputFooterCollapsed: PU.state.ui.outputFooterCollapsed,
            outputLabelMode: PU.state.ui.outputLabelMode,
            rightPanelCollapsed: PU.state.ui.rightPanelCollapsed,
            leftSidebarCollapsed: PU.state.ui.leftSidebarCollapsed
        };
        localStorage.setItem('pu_ui_state', JSON.stringify(uiState));
    },

    /**
     * Load state from localStorage
     */
    loadUIState() {
        try {
            const saved = localStorage.getItem('pu_ui_state');
            if (saved) {
                const state = JSON.parse(saved);
                PU.state.activeJobId = state.activeJobId || null;
                PU.state.activePromptId = state.activePromptId || null;
                PU.state.ui.jobsExpanded = state.jobsExpanded || {};
                PU.state.ui.sectionsCollapsed = state.sectionsCollapsed || {};
                PU.state.ui.outputFooterCollapsed = state.outputFooterCollapsed || false;
                PU.state.ui.outputLabelMode = state.outputLabelMode || 'none';
                PU.state.ui.rightPanelCollapsed = state.rightPanelCollapsed || false;
                PU.state.ui.leftSidebarCollapsed = state.leftSidebarCollapsed || false;
            }
        } catch (e) {
            console.warn('Failed to load UI state:', e);
        }
    },

    /**
     * Deep clone an object
     */
    deepClone(obj) {
        return JSON.parse(JSON.stringify(obj));
    },

    /**
     * Get wildcard lookup map from active prompt
     * Returns { wildcardName: [value1, value2, ...], ... }
     */
    getWildcardLookup() {
        const prompt = PU.helpers.getActivePrompt();
        if (!prompt) return {};

        const lookup = {};
        (prompt.wildcards || []).forEach(wc => {
            if (wc.name) {
                lookup[wc.name] = Array.isArray(wc.text) ? wc.text : [wc.text];
            }
        });
        return lookup;
    },

    /**
     * Load wildcard names from scoped extensions (async, cached)
     * Walks the extension tree under the prompt's ext scope,
     * loads files with wildcardCount > 0, extracts wildcard names.
     */
    async loadExtensionWildcardNames() {
        const prompt = PU.helpers.getActivePrompt();
        const job = PU.helpers.getActiveJob();
        // Empty string ext scope means "walk entire extension tree root" — valid when no scope is configured
        const extScope = (prompt && prompt.ext) || (job && job.defaults && job.defaults.ext) || '';
        const cache = PU.state.autocompleteCache;

        // Return cached if scope hasn't changed
        if (cache.loaded && cache.extScope === extScope) {
            return cache.extWildcardNames;
        }

        // Prevent concurrent loads
        if (cache.loading) return cache.extWildcardNames;
        cache.loading = true;

        try {
            const tree = PU.state.globalExtensions.tree;
            if (!tree || Object.keys(tree).length === 0) {
                cache.extWildcardNames = [];
                cache.loaded = true;
                cache.extScope = extScope;
                cache.loading = false;
                return [];
            }

            // Find the scoped subtree
            const scopeParts = extScope ? extScope.split('/').filter(Boolean) : [];
            let subtree = tree;
            for (const part of scopeParts) {
                if (subtree && subtree[part]) {
                    subtree = subtree[part];
                } else {
                    subtree = null;
                    break;
                }
            }

            if (!subtree) {
                cache.extWildcardNames = [];
                cache.loaded = true;
                cache.extScope = extScope;
                cache.loading = false;
                return [];
            }

            // Collect files with wildcardCount > 0
            const filePaths = [];
            const walkTree = (node, pathPrefix) => {
                if (node._files) {
                    for (const file of node._files) {
                        if (file.wildcardCount > 0) {
                            const fullPath = pathPrefix ? `${pathPrefix}/${file.name}` : file.name;
                            filePaths.push(fullPath);
                        }
                    }
                }
                for (const key of Object.keys(node)) {
                    if (key === '_files') continue;
                    walkTree(node[key], pathPrefix ? `${pathPrefix}/${key}` : key);
                }
            };
            walkTree(subtree, extScope);

            // Load each file and extract wildcard names
            const results = [];
            const failedPaths = [];
            for (const path of filePaths) {
                try {
                    const ext = await PU.api.loadExtension(path);
                    if (ext && ext.wildcards) {
                        for (const wc of ext.wildcards) {
                            if (wc.name) {
                                results.push({ name: wc.name, source: path });
                            }
                        }
                    }
                } catch (e) {
                    failedPaths.push(path);
                    console.warn('Failed to load extension for autocomplete:', path, e);
                }
            }

            cache.extWildcardNames = results;
            cache.loaded = true;
            cache.extScope = extScope;
            cache.loading = false;
            return results;
        } catch (e) {
            console.error('loadExtensionWildcardNames failed:', e);
            PU.actions.showToast('Failed to load extension wildcards', 'error');
            cache.loading = false;
            return [];
        }
    },

    /**
     * Get unified autocomplete items from local + extension wildcards
     * Returns [{name, source, defined, preview}]
     */
    getAutocompleteItems() {
        const items = [];
        const seen = new Set();

        // Local wildcards (from prompt definition)
        const lookup = PU.helpers.getWildcardLookup();
        for (const [name, values] of Object.entries(lookup)) {
            const preview = values.slice(0, 3).join(', ') + (values.length > 3 ? ` +${values.length - 3}` : '');
            items.push({ name, source: 'local', defined: true, preview });
            seen.add(name);
        }

        // Extension wildcards (from cache)
        const cache = PU.state.autocompleteCache;
        for (const ext of cache.extWildcardNames) {
            if (!seen.has(ext.name)) {
                items.push({ name: ext.name, source: ext.source, defined: false, preview: '' });
                seen.add(ext.name);
            }
        }

        // If cache not loaded, trigger async load
        if (!cache.loaded && !cache.loading) {
            PU.helpers.loadExtensionWildcardNames().then(() => {
                if (PU.quill._autocompleteOpen) {
                    PU.quill.refreshAutocomplete();
                }
            });
        }

        return items;
    },

    async getExtensionWildcardValues(wildcardName) {
        const cache = PU.state.autocompleteCache;
        if (!cache.loaded) await PU.helpers.loadExtensionWildcardNames();
        const extItem = cache.extWildcardNames.find(e => e.name === wildcardName);
        if (!extItem) return [];
        try {
            const ext = await PU.api.loadExtension(extItem.source);
            const wc = (ext.wildcards || []).find(w => w.name === wildcardName);
            return wc ? (Array.isArray(wc.text) ? wc.text : [wc.text]) : [];
        } catch (e) {
            console.warn(`Failed to load extension wildcard values for "${wildcardName}":`, e);
            return [];
        }
    }
};

/**
 * API Helpers
 */
PU.api = {
    /**
     * Load operations (build hooks) list for a job
     */
    async loadOperations(jobId) {
        const data = await PU.api.get(`/api/pu/job/${encodeURIComponent(jobId)}/operations`);
        return data.operations || [];
    },

    /**
     * Load single operation content
     */
    async loadOperation(jobId, opName) {
        return PU.api.get(`/api/pu/job/${encodeURIComponent(jobId)}/operation/${encodeURIComponent(opName)}`);
    },

    /**
     * Save operation content
     */
    async saveOperation(jobId, opName, mappings) {
        return PU.api.post(`/api/pu/job/${encodeURIComponent(jobId)}/operation/${encodeURIComponent(opName)}`, { mappings });
    },

    /**
     * Load session state for a job
     */
    async loadSession(jobId) {
        return PU.api.get(`/api/pu/job/${encodeURIComponent(jobId)}/session`);
    },

    /**
     * Save session state for a prompt
     */
    async saveSession(jobId, promptId, data) {
        return PU.api.post(`/api/pu/job/${encodeURIComponent(jobId)}/session`, { prompt_id: promptId, data });
    },

    /**
     * Make GET request
     */
    async get(endpoint) {
        const response = await fetch(endpoint);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        return response.json();
    },

    /**
     * Make POST request
     */
    async post(endpoint, data) {
        const response = await fetch(endpoint, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        return response.json();
    },

    /**
     * Load all jobs
     */
    async loadJobs() {
        const data = await PU.api.get('/api/pu/jobs');
        if (!data.jobs) {
            console.error('API response missing jobs field:', data);
            PU.state.jobs = {};
        } else {
            PU.state.jobs = data.jobs;
        }
        PU.state.jobsLoaded = true;
        return PU.state.jobs;
    },

    /**
     * Load single job details
     */
    async loadJob(jobId) {
        const data = await PU.api.get(`/api/pu/job/${encodeURIComponent(jobId)}`);
        if (data.valid) {
            PU.state.jobs[jobId] = data;
        }
        return data;
    },

    /**
     * Load extensions tree
     */
    async loadExtensions() {
        const data = await PU.api.get('/api/pu/extensions');
        if (!data.tree) {
            console.error('API response missing tree field:', data);
            PU.state.globalExtensions.tree = {};
        } else {
            PU.state.globalExtensions.tree = data.tree;
        }
        PU.state.globalExtensions.loaded = true;
        return PU.state.globalExtensions.tree;
    },

    /**
     * Load extension content
     */
    async loadExtension(path) {
        return PU.api.get(`/api/pu/extension/${encodeURIComponent(path)}`);
    },

    /**
     * Preview variations
     */
    async previewVariations(params) {
        return PU.api.post('/api/pu/preview', params);
    },

    /**
     * Validate job
     */
    async validateJob(jobId) {
        return PU.api.post('/api/pu/validate', { job_id: jobId });
    },

    /**
     * Export job
     */
    async exportJob(jobId, options = {}) {
        return PU.api.post('/api/pu/export', {
            job_id: jobId,
            ...options
        });
    }
};

// Make PU globally available
window.PU = PU;
