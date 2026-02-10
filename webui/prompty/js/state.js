/**
 * PromptyUI - State Management
 *
 * Central state store for the PromptyUI application.
 * All state changes should go through PU.actions.
 */

const PU = window.PU || {};

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
        inspectorExtensionFilter: ''
    },

    // Preview popup state
    preview: {
        visible: false,
        targetPath: null,
        variations: [],
        totalCount: 0,
        loading: false,
        activeWildcard: null   // wildcard name at cursor, or null
    },

    // Focus mode state (zen editing overlay)
    focusMode: {
        active: false,
        blockPath: null,         // e.g. "0", "0.1"
        quillInstance: null,     // Transient Quill (not in PU.quill.instances)
        enterTimestamp: 0        // Debounce guard
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

    // Preview mode state (checkpoint list view)
    previewMode: {
        active: false,
        checkpoints: [],      // All terminal nodes
        compositionId: 99,    // Default composition (matching v4 default)
        extTextMax: 1,        // Bucket size limit for ext_text (user-controlled)
        extTextCount: 1,      // Actual ext_text count (computed from loaded data)
        extWildcardsMax: 0,   // 0 = use actual wildcard counts, >0 = override all wildcard counts
        pendingActivation: false,  // Set by URL parser, activated after prompt loads
        selectedWildcards: {}  // User-selected wildcard overrides: { wildcardName: selectedValue }
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
            sectionsCollapsed: PU.state.ui.sectionsCollapsed
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

            if (failedPaths.length > 0) {
                PU.actions.showToast(
                    `Failed to load ${failedPaths.length} extension file(s) for autocomplete`,
                    'error'
                );
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
