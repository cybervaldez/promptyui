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
        loading: false
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
