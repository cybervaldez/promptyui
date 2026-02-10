/**
 * PromptyUI - Sidebar
 *
 * Renders and manages the left sidebar with:
 * - Jobs tree (extensions are in the right inspector)
 */

PU.sidebar = {
    /**
     * Initialize sidebar
     */
    async init() {
        await PU.sidebar.loadJobs();
    },

    /**
     * Load and render jobs
     */
    async loadJobs() {
        const container = document.querySelector('[data-testid="pu-jobs-tree"]');
        if (!container) return;

        try {
            await PU.api.loadJobs();
            PU.sidebar.renderJobs();

            // Update jobs count
            const count = Object.keys(PU.state.jobs).length;
            const countEl = document.querySelector('[data-testid="pu-jobs-count"]');
            if (countEl) {
                countEl.textContent = `(${count})`;
            }

            // Restore last active job if any
            if (PU.state.activeJobId && PU.state.jobs[PU.state.activeJobId]) {
                await PU.actions.selectJob(PU.state.activeJobId, false);
            }
        } catch (e) {
            container.innerHTML = `<div class="pu-tree-item error">Failed to load jobs</div>`;
            console.error('Failed to load jobs:', e);
        }
    },

    /**
     * Render jobs tree
     */
    renderJobs() {
        const container = document.querySelector('[data-testid="pu-jobs-tree"]');
        if (!container) return;

        const jobs = PU.state.jobs;
        let html = '';

        for (const [jobId, jobData] of Object.entries(jobs)) {
            const isExpanded = PU.state.ui.jobsExpanded[jobId];
            const isActive = jobId === PU.state.activeJobId;
            const isValid = jobData.valid !== false;

            html += `
                <div class="pu-tree-item ${isActive ? 'active' : ''} ${!isValid ? 'error' : ''}"
                     data-testid="pu-job-${jobId}">
                    <span class="pu-tree-toggle ${isExpanded ? 'expanded' : ''}"
                          data-testid="pu-job-toggle-${jobId}"
                          onclick="event.stopPropagation(); PU.actions.toggleJobExpand('${jobId}')">&#9654;</span>
                    <span class="pu-tree-label" onclick="PU.actions.selectJob('${jobId}')">${jobId}</span>
                    ${!isValid ? `<span class="pu-tree-badge" data-testid="pu-job-error-${jobId}" title="${jobData.error || 'Invalid'}">&#9888;</span>` : ''}
                </div>
            `;

            if (isExpanded && isValid) {
                html += `<div class="pu-tree-children">`;

                // Prompts
                const prompts = jobData.prompts || [];
                if (prompts.length > 0) {
                    html += `
                        <div class="pu-tree-item" onclick="PU.actions.toggleJobSection('${jobId}', 'prompts')">
                            <span class="pu-tree-toggle">&#9654;</span>
                            <span class="pu-tree-label">Prompts</span>
                            <span class="pu-tree-badge">${prompts.length}</span>
                        </div>
                    `;

                    for (const prompt of prompts) {
                        // Handle both string IDs and object prompts
                        const promptId = typeof prompt === 'string' ? prompt : prompt.id;
                        const isPromptActive = promptId === PU.state.activePromptId && jobId === PU.state.activeJobId;
                        html += `
                            <div class="pu-tree-children">
                                <div class="pu-tree-item ${isPromptActive ? 'active' : ''}"
                                     data-testid="pu-prompt-${jobId}-${promptId}"
                                     onclick="PU.actions.selectPrompt('${jobId}', '${promptId}')">
                                    <span class="pu-tree-toggle" style="visibility: hidden;">&#9654;</span>
                                    <span class="pu-tree-label">${promptId}</span>
                                </div>
                            </div>
                        `;
                    }
                }

                // LoRAs
                const loras = jobData.loras || [];
                if (loras.length > 0) {
                    html += `
                        <div class="pu-tree-item">
                            <span class="pu-tree-toggle" style="visibility: hidden;">&#9654;</span>
                            <span class="pu-tree-label">LoRAs</span>
                            <span class="pu-tree-badge">${loras.length}</span>
                        </div>
                    `;
                }

                // Defaults
                html += `
                    <div class="pu-tree-item" data-testid="pu-defaults-${jobId}"
                         onclick="PU.actions.selectDefaults('${jobId}')">
                        <span class="pu-tree-toggle" style="visibility: hidden;">&#9654;</span>
                        <span class="pu-tree-label">Defaults</span>
                    </div>
                `;

                html += `</div>`;
            }
        }

        container.innerHTML = html || '<div class="pu-tree-item">No jobs found</div>';
    },

    /**
     * Update active states in sidebar
     */
    updateActiveStates() {
        // Remove all active states
        document.querySelectorAll('.pu-sidebar .pu-tree-item.active').forEach(el => {
            el.classList.remove('active');
        });

        // Add active state to current job
        if (PU.state.activeJobId) {
            const jobEl = document.querySelector(`[data-testid="pu-job-${PU.state.activeJobId}"]`);
            if (jobEl) {
                jobEl.classList.add('active');
            }

            // Add active state to current prompt
            if (PU.state.activePromptId) {
                const promptEl = document.querySelector(`[data-testid="pu-prompt-${PU.state.activeJobId}-${PU.state.activePromptId}"]`);
                if (promptEl) {
                    promptEl.classList.add('active');
                }
            }
        }
    },

    /**
     * Check if folder or children match filter (used by inspector)
     */
    folderMatchesFilter(node, filter) {
        if (!filter) return true;

        // Check files
        const files = node._files || [];
        for (const file of files) {
            if (file.file.toLowerCase().includes(filter) || file.id.toLowerCase().includes(filter)) {
                return true;
            }
        }

        // Check subfolders recursively
        for (const [key, value] of Object.entries(node)) {
            if (key === '_files') continue;
            if (key.toLowerCase().includes(filter)) return true;
            if (PU.sidebar.folderMatchesFilter(value, filter)) return true;
        }

        return false;
    }
};
