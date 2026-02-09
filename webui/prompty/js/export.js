/**
 * PromptyUI - Export
 *
 * Export modal and validation functionality.
 */

PU.export = {
    /**
     * Open export modal
     */
    async open() {
        const jobId = PU.state.activeJobId;
        if (!jobId) {
            PU.actions.showToast('No job selected', 'error');
            return;
        }

        PU.state.exportModal.visible = true;

        const modal = document.querySelector('[data-testid="pu-export-modal"]');
        if (modal) {
            modal.style.display = 'flex';
        }

        // Load validation and YAML preview
        await PU.export.loadPreview();
    },

    /**
     * Load export preview and validation
     */
    async loadPreview() {
        const jobId = PU.state.activeJobId;

        const previewEl = document.querySelector('[data-testid="pu-export-preview"]');
        const validationEl = document.querySelector('[data-testid="pu-export-validation"]');

        if (previewEl) {
            previewEl.innerHTML = '<pre><code>Loading...</code></pre>';
        }

        try {
            // Get YAML preview
            const exportData = await PU.api.exportJob(jobId, { dry_run: true });

            if (previewEl && exportData.yaml) {
                previewEl.innerHTML = `<pre><code>${PU.blocks.escapeHtml(exportData.yaml)}</code></pre>`;
                PU.state.exportModal.yaml = exportData.yaml;
            }

            // Get validation
            const validation = await PU.api.validateJob(jobId);

            PU.state.exportModal.validation = validation;

            if (validationEl) {
                PU.export.renderValidation(validationEl, validation);
            }

        } catch (e) {
            console.error('Failed to load export preview:', e);
            if (previewEl) {
                previewEl.innerHTML = `<pre><code style="color: var(--pu-error);">Error: ${e.message}</code></pre>`;
            }
        }
    },

    /**
     * Render validation messages
     */
    renderValidation(container, validation) {
        let html = '';

        if (validation.errors && validation.errors.length > 0) {
            validation.errors.forEach(err => {
                html += `
                    <div class="pu-export-validation-item error">
                        <span>&#10060;</span> ${PU.blocks.escapeHtml(err)}
                    </div>
                `;
            });
        }

        if (validation.warnings && validation.warnings.length > 0) {
            validation.warnings.forEach(warn => {
                html += `
                    <div class="pu-export-validation-item warning">
                        <span>&#9888;</span> ${PU.blocks.escapeHtml(warn)}
                    </div>
                `;
            });
        }

        if (validation.valid && (!validation.errors || validation.errors.length === 0)) {
            html += `
                <div class="pu-export-validation-item" style="color: var(--pu-success);">
                    <span>&#10004;</span> Validation passed
                </div>
            `;
        }

        container.innerHTML = html;
    },

    /**
     * Close export modal
     */
    close() {
        PU.state.exportModal.visible = false;

        const modal = document.querySelector('[data-testid="pu-export-modal"]');
        if (modal) {
            modal.style.display = 'none';
        }
    },

    /**
     * Confirm and execute export
     */
    async confirm() {
        const jobId = PU.state.activeJobId;
        if (!jobId) {
            PU.actions.showToast('No job selected', 'error');
            return;
        }

        // Check if there are errors
        const validation = PU.state.exportModal.validation;
        if (validation.errors && validation.errors.length > 0) {
            if (!confirm('There are validation errors. Export anyway?')) {
                return;
            }
        }

        // Get export mode
        const saveMode = document.querySelector('[data-testid="pu-export-save-folder"]');
        const saveToFile = saveMode && saveMode.checked;

        if (saveToFile) {
            // Save to jobs folder
            try {
                const result = await PU.api.exportJob(jobId, { save_to_file: true });

                if (result.success) {
                    PU.actions.showToast(`Saved to ${result.path}`, 'success');

                    // Clear modified state
                    delete PU.state.modifiedJobs[jobId];

                    PU.export.close();
                } else {
                    PU.actions.showToast(result.error || 'Export failed', 'error');
                }
            } catch (e) {
                console.error('Export failed:', e);
                PU.actions.showToast('Export failed: ' + e.message, 'error');
            }
        } else {
            // Download as file
            const yaml = PU.state.exportModal.yaml;
            if (!yaml) {
                PU.actions.showToast('No YAML content', 'error');
                return;
            }

            const blob = new Blob([yaml], { type: 'text/yaml' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `${jobId}_jobs.yaml`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);

            PU.actions.showToast('Downloaded jobs.yaml', 'success');
            PU.export.close();
        }
    }
};
