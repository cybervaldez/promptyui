/**
 * PromptyUI - Sampler Gallery
 *
 * Grid view of sampled compositions resolved to their final text.
 * Uses PU.preview.buildMultiCompositionOutputs() to sample and resolve.
 */

PU.gallery = {
    open() {
        PU.buildMenu.close();
        PU.overlay.dismissAll();
        const modal = document.querySelector('[data-testid="pu-gallery-modal"]');
        if (!modal) return;
        PU.state.gallery = PU.state.gallery || { visible: false };
        PU.state.gallery.visible = true;
        modal.style.display = 'flex';
        PU.gallery.render();
    },

    close() {
        const modal = document.querySelector('[data-testid="pu-gallery-modal"]');
        if (!modal) return;
        if (PU.state.gallery) PU.state.gallery.visible = false;
        modal.style.display = 'none';
    },

    refresh() {
        PU.gallery.render();
    },

    async render() {
        const body = document.querySelector('[data-testid="pu-gallery-body"]');
        const status = document.querySelector('[data-testid="pu-gallery-status"]');
        if (!body) return;

        const prompt = PU.helpers.getActivePrompt();
        if (!prompt || !Array.isArray(prompt.text) || prompt.text.length === 0) {
            body.innerHTML = '<div class="pu-gallery-empty">No prompt selected</div>';
            if (status) status.textContent = '';
            return;
        }

        body.innerHTML = '<div class="pu-gallery-empty">Sampling compositions...</div>';

        const textItems = prompt.text;
        const primaryRes = await PU.preview.buildBlockResolutions(textItems, {
            skipOdometerUpdate: true,
            ignoreOverrides: true
        });

        const { outputs, total } = await PU.preview.buildMultiCompositionOutputs(
            textItems, primaryRes, 30
        );

        if (outputs.length === 0) {
            body.innerHTML = '<div class="pu-gallery-empty">No compositions to display</div>';
            if (status) status.textContent = '';
            return;
        }

        const cards = outputs.map((out, i) => {
            const labelHtml = out.wcDetails
                ? out.wcDetails.map(d =>
                    `<span class="pu-gallery-wc-tag">${PU.blocks.escapeHtml(d.name)}=${PU.blocks.escapeHtml(d.value)}</span>`
                  ).join('')
                : `<span class="pu-gallery-wc-tag">${PU.blocks.escapeHtml(out.label)}</span>`;

            const escapedLabel = PU.blocks.escapeHtml(out.label);

            return `<div class="pu-gallery-card" data-testid="pu-gallery-card-${i}"
                         data-label="${escapedLabel}"
                         onclick="PU.gallery.selectCard(${i}, this.dataset.label)">
                <div class="pu-gallery-card-label">${labelHtml}</div>
                <div class="pu-gallery-card-text" data-testid="pu-gallery-card-text-${i}">${PU.blocks.escapeHtml(out.text)}</div>
            </div>`;
        }).join('');

        body.innerHTML = `<div class="pu-gallery-grid" data-testid="pu-gallery-grid">${cards}</div>`;

        if (status) {
            status.textContent = `${outputs.length} of ${total.toLocaleString()} compositions`;
        }
    },

    /** Click a card to navigate to that composition */
    selectCard(index, label) {
        const { wildcardCounts, extTextCount, wcNames } = PU.shared.getCompositionParams();

        // Label format is "idx.idx.idx" — parse back to dimension indices
        const parts = label.split('.').map(Number);

        const hasExt = extTextCount > 1;
        const extIdx = hasExt ? parts[0] : 0;
        const dimValues = hasExt ? parts.slice(1) : parts;

        // Reverse the compositionToIndices mapping to get compId
        // Odometer: ext_text is outermost (slowest), wildcards alphabetical (fastest on right)
        const sortedNames = [...wcNames].sort();
        let compId = 0;
        let multiplier = 1;

        for (let i = sortedNames.length - 1; i >= 0; i--) {
            const idx = dimValues[i] || 0;
            compId += idx * multiplier;
            multiplier *= (wildcardCounts[sortedNames[i]] || 1);
        }
        if (hasExt) {
            compId += extIdx * multiplier;
        }

        PU.state.previewMode.compositionId = compId;
        PU.preview.clearStaleBlockOverrides();
        PU.actions.updateUrl();

        PU.gallery.close();
        PU.editor.renderBlocks(PU.state.activeJobId, PU.state.activePromptId);
        PU.rightPanel.render();

        PU.actions.showToast(`Jumped to composition ${compId}`, 'info');
    }
};
