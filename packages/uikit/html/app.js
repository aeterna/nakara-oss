// aeterna_uikit NUI runtime — renders panels, menus, prompts, progress, skill checks and key hints.
// Uses textContent only (never innerHTML/outerHTML).

const panelLayer = document.getElementById('panel-layer');
const promptLayer = document.getElementById('prompt-layer');
const skillLayer = document.getElementById('skill-layer');
const progressLayer = document.getElementById('progress-layer');
const hintsLayer = document.getElementById('hints-layer');

let locale = {
    'uikit.menu.title': 'Menu',
    'uikit.confirm.ok': 'Confirm',
    'uikit.confirm.cancel': 'Cancel',
    'uikit.input.submit': 'Submit',
    'uikit.progress.cancel': 'Cancel',
    'uikit.skill.title': 'Skill check',
    'uikit.skill.bind': 'Space',
    'uikit.key.unbound': 'Unbound',
    'uikit.close': 'Close',
};

let currentPanel = null;
let blockElements = new Map();
let blockState = new Map();
let progressTimer = null;
let skillState = null;

function postCallback(name, payload) {
    fetch('https://aeterna_uikit/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {}),
    }).catch(() => {});
}

function clearChildren(el) {
    while (el.firstChild) {
        el.removeChild(el.firstChild);
    }
}

function applyThemeOverride(href) {
    const existing = document.getElementById('aeterna-theme-override');
    if (typeof href === 'string' && href.startsWith('nui://') && href.endsWith('.css')) {
        if (existing) {
            existing.setAttribute('href', href);
        } else {
            const link = document.createElement('link');
            link.id = 'aeterna-theme-override';
            link.rel = 'stylesheet';
            link.setAttribute('href', href);
            document.head.appendChild(link);
        }
    } else if (existing) {
        existing.remove();
    }
}

function createCloseButton(onClick) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'close-btn';
    btn.setAttribute('aria-label', locale['uikit.close'] || 'Close');
    const icon = window.AeternaUikitIcons.create('x', 16);
    if (icon) {
        btn.appendChild(icon);
    } else {
        btn.textContent = '×';
    }
    btn.addEventListener('click', onClick);
    return btn;
}

function collectPanelValues() {
    const out = {};
    for (const [id, st] of blockState.entries()) {
        if (st.type === 'field') {
            if (st.input === 'number') {
                if (st.control.value !== '') {
                    const n = Number(st.control.value);
                    if (!Number.isNaN(n)) {
                        out[id] = n;
                    }
                }
            } else {
                out[id] = String(st.control.value || '');
            }
        } else if (st.type === 'toggle') {
            out[id] = st.checked === true;
        } else if (st.type === 'select') {
            out[id] = String(st.control.value || '');
        }
    }
    return out;
}

function renderListItems(container, items, onPick) {
    clearChildren(container);
    if (!Array.isArray(items)) return;
    for (let i = 0; i < items.length; i++) {
        const item = items[i];
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'list-item';
        btn.disabled = item.disabled === true;

        const main = document.createElement('span');
        main.className = 'list-item-main';

        if (item.icon) {
            const iconWrap = document.createElement('span');
            iconWrap.className = 'list-item-icon';
            const svg = window.AeternaUikitIcons.create(item.icon, 18);
            if (svg) iconWrap.appendChild(svg);
            main.appendChild(iconWrap);
        }

        const lbl = document.createElement('span');
        lbl.className = 'list-item-label';
        lbl.textContent = String(item.label || '');
        main.appendChild(lbl);
        btn.appendChild(main);

        if (item.meta) {
            const meta = document.createElement('span');
            meta.className = 'list-item-meta';
            meta.textContent = String(item.meta);
            btn.appendChild(meta);
        }

        btn.addEventListener('click', () => {
            if (!btn.disabled) onPick(item);
        });
        container.appendChild(btn);
    }
}

function renderButtonsRow(container, items, onAction) {
    clearChildren(container);
    if (!Array.isArray(items)) return;
    for (let i = 0; i < items.length; i++) {
        const item = items[i];
        const variant = item.variant === 'primary' || item.variant === 'danger' ? item.variant : 'secondary';
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'btn btn-' + variant;
        btn.disabled = item.disabled === true;

        if (item.icon) {
            const svg = window.AeternaUikitIcons.create(item.icon, 16);
            if (svg) btn.appendChild(svg);
        }

        const span = document.createElement('span');
        span.textContent = String(item.label || '');
        btn.appendChild(span);

        btn.addEventListener('click', () => {
            if (!btn.disabled) onAction(item.id);
        });
        container.appendChild(btn);
    }
}

function buildBlockNode(block, panelId) {
    const btype = block.type;
    if (btype === 'text') {
        const p = document.createElement('p');
        p.className = 'block-text';
        p.textContent = String(block.label || '');
        blockElements.set(block.id, { type: 'text', root: p, labelEl: p });
        return p;
    }

    if (btype === 'divider') {
        const hr = document.createElement('hr');
        hr.className = 'block-divider';
        blockElements.set(block.id, { type: 'divider', root: hr });
        return hr;
    }

    if (btype === 'list') {
        const wrap = document.createElement('div');
        wrap.className = 'list-group';
        let labelEl = null;
        if (block.label) {
            labelEl = document.createElement('div');
            labelEl.className = 'block-label';
            labelEl.textContent = String(block.label);
            wrap.appendChild(labelEl);
        }
        const itemsWrap = document.createElement('div');
        itemsWrap.className = 'list-group';
        const triggerPick = (item) => {
            postCallback('panelAction', {
                panelId,
                action: item.id,
                values: collectPanelValues(),
            });
        };
        renderListItems(itemsWrap, block.items || [], triggerPick);
        wrap.appendChild(itemsWrap);
        blockElements.set(block.id, {
            type: 'list',
            root: wrap,
            labelEl,
            itemsWrap,
            triggerPick,
        });
        return wrap;
    }

    if (btype === 'field') {
        const wrap = document.createElement('div');
        wrap.className = 'field-group';
        const labelEl = document.createElement('label');
        labelEl.className = 'block-label';
        labelEl.textContent = String(block.label || '');
        wrap.appendChild(labelEl);

        const input = document.createElement('input');
        input.className = 'field-input';
        input.type = block.input === 'number' ? 'number' : 'text';
        if (block.input === 'number') {
            if (typeof block.min === 'number') input.min = String(block.min);
            if (typeof block.max === 'number') input.max = String(block.max);
            input.value = block.value !== undefined && block.value !== null ? String(block.value) : '';
        } else {
            input.maxLength = typeof block.maxLen === 'number' ? block.maxLen : 60;
            input.value = typeof block.value === 'string' ? block.value : '';
        }
        if (block.placeholder) {
            input.placeholder = String(block.placeholder);
        }
        input.disabled = block.disabled === true;
        wrap.appendChild(input);

        blockState.set(block.id, { type: 'field', input: block.input || 'text', control: input });
        blockElements.set(block.id, { type: 'field', root: wrap, labelEl, control: input });
        return wrap;
    }

    if (btype === 'toggle') {
        const row = document.createElement('div');
        row.className = 'toggle-row';
        const labelEl = document.createElement('span');
        labelEl.className = 'block-label';
        labelEl.textContent = String(block.label || '');
        row.appendChild(labelEl);

        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'toggle-btn';
        btn.setAttribute('role', 'switch');
        const initChecked = block.value === true;
        btn.setAttribute('aria-checked', initChecked ? 'true' : 'false');
        btn.disabled = block.disabled === true;

        const thumb = document.createElement('span');
        thumb.className = 'toggle-thumb';
        btn.appendChild(thumb);

        const stateObj = { type: 'toggle', checked: initChecked, control: btn };
        btn.addEventListener('click', () => {
            if (btn.disabled) return;
            stateObj.checked = !stateObj.checked;
            btn.setAttribute('aria-checked', stateObj.checked ? 'true' : 'false');
        });
        row.appendChild(btn);

        blockState.set(block.id, stateObj);
        blockElements.set(block.id, { type: 'toggle', root: row, labelEl, control: btn, stateObj });
        return row;
    }

    if (btype === 'select') {
        const wrap = document.createElement('div');
        wrap.className = 'field-group';
        const labelEl = document.createElement('label');
        labelEl.className = 'block-label';
        labelEl.textContent = String(block.label || '');
        wrap.appendChild(labelEl);

        const select = document.createElement('select');
        select.className = 'select-input';
        const opts = Array.isArray(block.options) ? block.options : [];
        for (let i = 0; i < opts.length; i++) {
            const opt = document.createElement('option');
            opt.value = String(opts[i].id);
            opt.textContent = String(opts[i].label || opts[i].id);
            select.appendChild(opt);
        }
        if (block.value !== undefined) {
            select.value = String(block.value);
        }
        select.disabled = block.disabled === true;
        wrap.appendChild(select);

        blockState.set(block.id, { type: 'select', control: select });
        blockElements.set(block.id, { type: 'select', root: wrap, labelEl, control: select });
        return wrap;
    }

    if (btype === 'progress') {
        const wrap = document.createElement('div');
        wrap.className = 'progress-block';
        const header = document.createElement('div');
        header.className = 'progress-header';
        const labelEl = document.createElement('span');
        labelEl.textContent = String(block.label || '');
        const pctEl = document.createElement('span');
        const clamped = Math.max(0, Math.min(1, Number(block.value) || 0));
        pctEl.textContent = Math.round(clamped * 100) + '%';
        header.appendChild(labelEl);
        header.appendChild(pctEl);
        wrap.appendChild(header);

        const track = document.createElement('div');
        track.className = 'progress-track';
        const fill = document.createElement('div');
        fill.className = 'progress-fill';
        fill.style.width = (clamped * 100) + '%';
        track.appendChild(fill);
        wrap.appendChild(track);

        blockElements.set(block.id, { type: 'progress', root: wrap, labelEl, pctEl, fill });
        return wrap;
    }

    if (btype === 'buttons') {
        const row = document.createElement('div');
        row.className = 'buttons-row';
        const triggerBtn = (actionId) => {
            postCallback('panelAction', {
                panelId,
                action: actionId,
                values: collectPanelValues(),
            });
        };
        renderButtonsRow(row, block.items || [], triggerBtn);
        blockElements.set(block.id, { type: 'buttons', root: row, itemsWrap: row, triggerBtn });
        return row;
    }

    return null;
}

function openPanel(panel) {
    currentPanel = panel;
    blockElements = new Map();
    blockState = new Map();
    clearChildren(panelLayer);

    const size = panel.size === 'sm' || panel.size === 'lg' ? panel.size : 'md';
    const card = document.createElement('div');
    card.className = 'card card-' + size;

    const header = document.createElement('div');
    header.className = 'card-header';
    const titleGroup = document.createElement('div');
    titleGroup.className = 'card-title-group';

    const titleEl = document.createElement('h2');
    titleEl.className = 'card-title';
    titleEl.textContent = String(panel.title || '');
    titleGroup.appendChild(titleEl);

    if (panel.subtitle) {
        const subEl = document.createElement('p');
        subEl.className = 'card-subtitle';
        subEl.textContent = String(panel.subtitle);
        titleGroup.appendChild(subEl);
    }

    header.appendChild(titleGroup);
    header.appendChild(createCloseButton(() => {
        postCallback('panelAction', {
            panelId: panel.panelId,
            action: '__close',
            values: {},
        });
    }));
    card.appendChild(header);

    const body = document.createElement('div');
    body.className = 'card-body';

    if (panel.kind === 'menu') {
        const listWrap = document.createElement('div');
        listWrap.className = 'list-group';
        const entries = Array.isArray(panel.entries) ? panel.entries : [];
        renderListItems(listWrap, entries, (entry) => {
            postCallback('panelAction', {
                panelId: '__menu',
                action: entry.id,
                owner: entry.owner,
                id: entry.id,
            });
        });
        body.appendChild(listWrap);
    } else if (Array.isArray(panel.blocks)) {
        for (let i = 0; i < panel.blocks.length; i++) {
            const node = buildBlockNode(panel.blocks[i], panel.panelId);
            if (node) body.appendChild(node);
        }
    }

    card.appendChild(body);
    panelLayer.appendChild(card);
    panelLayer.classList.remove('hidden');

    const firstFocusable = card.querySelector('button, input, select');
    if (firstFocusable) firstFocusable.focus();
}

function updatePanel(panelId, patch) {
    if (!currentPanel || currentPanel.panelId !== panelId) return;
    if (!patch || typeof patch.blocks !== 'object') return;

    for (const [blockId, partial] of Object.entries(patch.blocks)) {
        const ref = blockElements.get(blockId);
        if (!ref || !partial) continue;

        if (partial.label !== undefined && ref.labelEl) {
            ref.labelEl.textContent = String(partial.label);
        }
        if (partial.disabled !== undefined && ref.control) {
            ref.control.disabled = partial.disabled === true;
        }
        if (partial.value !== undefined) {
            if (ref.type === 'field' || ref.type === 'select') {
                ref.control.value = String(partial.value);
            } else if (ref.type === 'toggle' && ref.stateObj) {
                ref.stateObj.checked = partial.value === true;
                ref.control.setAttribute('aria-checked', ref.stateObj.checked ? 'true' : 'false');
            } else if (ref.type === 'progress') {
                const clamped = Math.max(0, Math.min(1, Number(partial.value) || 0));
                ref.fill.style.width = (clamped * 100) + '%';
                ref.pctEl.textContent = Math.round(clamped * 100) + '%';
            }
        }
        if (partial.items !== undefined) {
            if (ref.type === 'list' && ref.itemsWrap) {
                renderListItems(ref.itemsWrap, partial.items, ref.triggerPick);
            } else if (ref.type === 'buttons' && ref.itemsWrap) {
                renderButtonsRow(ref.itemsWrap, partial.items, ref.triggerBtn);
            }
        }
    }
}

function closePanel() {
    currentPanel = null;
    blockElements.clear();
    blockState.clear();
    clearChildren(panelLayer);
    panelLayer.classList.add('hidden');
}

function openConfirmPrompt(prompt) {
    clearChildren(promptLayer);
    const card = document.createElement('div');
    card.className = 'card card-sm';

    const header = document.createElement('div');
    header.className = 'card-header';
    const titleEl = document.createElement('h2');
    titleEl.className = 'card-title';
    titleEl.textContent = String(prompt.title || '');
    header.appendChild(titleEl);
    header.appendChild(createCloseButton(() => {
        clearChildren(promptLayer);
        promptLayer.classList.add('hidden');
        postCallback('promptResult', { kind: 'confirm', value: false });
    }));
    card.appendChild(header);

    if (prompt.body) {
        const bodyEl = document.createElement('p');
        bodyEl.className = 'block-text';
        bodyEl.textContent = String(prompt.body);
        card.appendChild(bodyEl);
    }

    const actions = document.createElement('div');
    actions.className = 'buttons-row';

    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.className = 'btn btn-secondary';
    cancelBtn.textContent = String(prompt.cancel || locale['uikit.confirm.cancel']);
    cancelBtn.addEventListener('click', () => {
        clearChildren(promptLayer);
        promptLayer.classList.add('hidden');
        postCallback('promptResult', { kind: 'confirm', value: false });
    });

    const okBtn = document.createElement('button');
    okBtn.type = 'button';
    okBtn.className = 'btn ' + (prompt.danger ? 'btn-danger' : 'btn-primary');
    okBtn.textContent = String(prompt.confirm || locale['uikit.confirm.ok']);
    okBtn.addEventListener('click', () => {
        clearChildren(promptLayer);
        promptLayer.classList.add('hidden');
        postCallback('promptResult', { kind: 'confirm', value: true });
    });

    actions.appendChild(cancelBtn);
    actions.appendChild(okBtn);
    card.appendChild(actions);

    promptLayer.appendChild(card);
    promptLayer.classList.remove('hidden');
    okBtn.focus();
}

function openInputPrompt(prompt) {
    clearChildren(promptLayer);
    const card = document.createElement('div');
    card.className = 'card card-sm';

    const header = document.createElement('div');
    header.className = 'card-header';
    const titleEl = document.createElement('h2');
    titleEl.className = 'card-title';
    titleEl.textContent = String(prompt.title || '');
    header.appendChild(titleEl);
    header.appendChild(createCloseButton(() => {
        clearChildren(promptLayer);
        promptLayer.classList.add('hidden');
        postCallback('promptResult', { kind: 'input', value: null });
    }));
    card.appendChild(header);

    const body = document.createElement('div');
    body.className = 'card-body';
    const controls = [];
    const fields = Array.isArray(prompt.fields) ? prompt.fields : [];

    for (let i = 0; i < fields.length; i++) {
        const f = fields[i];
        const wrap = document.createElement('div');
        wrap.className = 'field-group';
        const lbl = document.createElement('label');
        lbl.className = 'block-label';
        lbl.textContent = String(f.label || '');
        wrap.appendChild(lbl);

        const inp = document.createElement('input');
        inp.className = 'field-input';
        inp.type = f.input === 'number' ? 'number' : 'text';
        if (f.input === 'number') {
            if (typeof f.min === 'number') inp.min = String(f.min);
            if (typeof f.max === 'number') inp.max = String(f.max);
            inp.value = f.value !== undefined && f.value !== null ? String(f.value) : '';
        } else {
            inp.maxLength = typeof f.maxLen === 'number' ? f.maxLen : 60;
            inp.value = typeof f.value === 'string' ? f.value : '';
        }
        if (f.placeholder) inp.placeholder = String(f.placeholder);
        wrap.appendChild(inp);
        body.appendChild(wrap);
        controls.push({ id: f.id, inputKind: f.input || 'text', el: inp });
    }
    card.appendChild(body);

    const actions = document.createElement('div');
    actions.className = 'buttons-row';

    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.className = 'btn btn-secondary';
    cancelBtn.textContent = String(prompt.cancel || locale['uikit.confirm.cancel']);
    cancelBtn.addEventListener('click', () => {
        clearChildren(promptLayer);
        promptLayer.classList.add('hidden');
        postCallback('promptResult', { kind: 'input', value: null });
    });

    const submitBtn = document.createElement('button');
    submitBtn.type = 'button';
    submitBtn.className = 'btn btn-primary';
    submitBtn.textContent = String(prompt.submit || locale['uikit.input.submit']);
    submitBtn.addEventListener('click', () => {
        const values = {};
        for (let i = 0; i < controls.length; i++) {
            const c = controls[i];
            if (c.inputKind === 'number') {
                if (c.el.value !== '') {
                    const n = Number(c.el.value);
                    if (!Number.isNaN(n)) {
                        values[c.id] = n;
                    }
                }
            } else {
                values[c.id] = String(c.el.value || '');
            }
        }
        clearChildren(promptLayer);
        promptLayer.classList.add('hidden');
        postCallback('promptResult', { kind: 'input', value: values });
    });

    actions.appendChild(cancelBtn);
    actions.appendChild(submitBtn);
    card.appendChild(actions);

    promptLayer.appendChild(card);
    promptLayer.classList.remove('hidden');
    if (controls.length > 0) controls[0].el.focus();
}

function updateProgressPrompt(prompt) {
    if (progressTimer) {
        clearInterval(progressTimer);
        progressTimer = null;
    }
    clearChildren(progressLayer);
    if (!prompt || prompt.active === false) {
        progressLayer.classList.add('hidden');
        return;
    }

    const card = document.createElement('div');
    card.className = 'progress-prompt-card';

    const header = document.createElement('div');
    header.className = 'progress-header';
    const lbl = document.createElement('span');
    lbl.textContent = String(prompt.label || '');
    const pct = document.createElement('span');
    pct.textContent = '0%';
    header.appendChild(lbl);
    header.appendChild(pct);
    card.appendChild(header);

    const track = document.createElement('div');
    track.className = 'progress-track';
    const fill = document.createElement('div');
    fill.className = 'progress-fill';
    fill.style.width = '0%';
    track.appendChild(fill);
    card.appendChild(track);

    progressLayer.appendChild(card);
    progressLayer.classList.remove('hidden');

    const duration = Math.max(300, Number(prompt.duration) || 1000);
    const start = performance.now();
    progressTimer = setInterval(() => {
        const elapsed = performance.now() - start;
        const ratio = Math.min(1, elapsed / duration);
        fill.style.width = (ratio * 100) + '%';
        pct.textContent = Math.round(ratio * 100) + '%';
        if (ratio >= 1) {
            clearInterval(progressTimer);
            progressTimer = null;
        }
    }, 30);
}

function handleSkillMessage(msg) {
    if (msg.action === 'hit' && skillState) {
        skillState.hit();
        return;
    }
    const prompt = msg.prompt;
    if (skillState && skillState.raf) {
        cancelAnimationFrame(skillState.raf);
    }
    skillState = null;
    clearChildren(skillLayer);
    if (!prompt || prompt.active === false) {
        skillLayer.classList.add('hidden');
        return;
    }

    const diff = prompt.difficulty || 'medium';
    const zoneWidth = diff === 'easy' ? 24 : diff === 'hard' ? 10 : 16;
    const speed = diff === 'easy' ? 0.09 : diff === 'hard' ? 0.18 : 0.13;
    const totalRounds = Math.max(1, Math.min(5, Number(prompt.rounds) || 1));

    const card = document.createElement('div');
    card.className = 'skill-card';

    const header = document.createElement('div');
    header.className = 'skill-header';
    const titleEl = document.createElement('span');
    titleEl.textContent = String(prompt.title || locale['uikit.skill.title']);
    const bindEl = document.createElement('span');
    bindEl.className = 'hint-key';
    bindEl.textContent = String(prompt.bind || locale['uikit.skill.bind']);
    header.appendChild(titleEl);
    header.appendChild(bindEl);
    card.appendChild(header);

    const track = document.createElement('div');
    track.className = 'skill-track';
    const zone = document.createElement('div');
    zone.className = 'skill-zone';
    const marker = document.createElement('div');
    marker.className = 'skill-marker';
    track.appendChild(zone);
    track.appendChild(marker);
    card.appendChild(track);

    skillLayer.appendChild(card);
    skillLayer.classList.remove('hidden');

    let round = 1;
    let pos = 0;
    let dir = 1;
    let zoneStart = 35;
    let lastTs = performance.now();

    function setupRound() {
        pos = 0;
        dir = 1;
        zoneStart = 25 + ((round * 17) % (65 - zoneWidth));
        zone.style.left = zoneStart + '%';
        zone.style.width = zoneWidth + '%';
        marker.style.left = '0%';
    }

    function finishSkill(passed) {
        if (!skillState) return;
        if (skillState.raf) cancelAnimationFrame(skillState.raf);
        skillState = null;
        clearChildren(skillLayer);
        skillLayer.classList.add('hidden');
        postCallback('promptResult', { kind: 'skill', value: passed });
    }

    function step(now) {
        if (!skillState) return;
        const dt = now - lastTs;
        lastTs = now;
        pos += dir * speed * dt;
        if (pos >= 100) {
            pos = 100;
            dir = -1;
        } else if (pos <= 0) {
            pos = 0;
            dir = 1;
        }
        marker.style.left = pos + '%';
        skillState.raf = requestAnimationFrame(step);
    }

    skillState = {
        raf: null,
        hit() {
            if (pos >= zoneStart && pos <= (zoneStart + zoneWidth)) {
                if (round >= totalRounds) {
                    finishSkill(true);
                } else {
                    round += 1;
                    setupRound();
                }
            } else {
                finishSkill(false);
            }
        },
    };

    setupRound();
    skillState.raf = requestAnimationFrame(step);
}

function showHints(hints) {
    clearChildren(hintsLayer);
    if (!Array.isArray(hints) || hints.length === 0) {
        hintsLayer.classList.add('hidden');
        return;
    }
    for (let i = 0; i < hints.length; i++) {
        const h = hints[i];
        const row = document.createElement('div');
        row.className = 'hint-row';
        const keyEl = document.createElement('span');
        keyEl.className = 'hint-key';
        keyEl.textContent = String(h.bind || locale['uikit.key.unbound']);
        const lblEl = document.createElement('span');
        lblEl.className = 'hint-label';
        lblEl.textContent = String(h.label || '');
        row.appendChild(keyEl);
        row.appendChild(lblEl);
        hintsLayer.appendChild(row);
    }
    hintsLayer.classList.remove('hidden');
}

function clearHints() {
    clearChildren(hintsLayer);
    hintsLayer.classList.add('hidden');
}

window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg.type !== 'string') return;

    if (msg.type === 'aeterna:theme') {
        applyThemeOverride(msg.href);
    } else if (msg.type === 'locale' && msg.strings && typeof msg.strings === 'object') {
        locale = { ...locale, ...msg.strings };
    } else if (msg.type === 'panel:open' && msg.panel) {
        openPanel(msg.panel);
    } else if (msg.type === 'panel:update') {
        updatePanel(msg.panelId, msg.patch);
    } else if (msg.type === 'panel:close') {
        if (msg.panelId === '__prompt') {
            clearChildren(promptLayer);
            promptLayer.classList.add('hidden');
        } else {
            closePanel();
        }
    } else if (msg.type === 'prompt:confirm' && msg.prompt) {
        openConfirmPrompt(msg.prompt);
    } else if (msg.type === 'prompt:input' && msg.prompt) {
        openInputPrompt(msg.prompt);
    } else if (msg.type === 'prompt:progress') {
        updateProgressPrompt(msg.prompt);
    } else if (msg.type === 'prompt:skill') {
        handleSkillMessage(msg);
    } else if (msg.type === 'hints:show') {
        showHints(msg.hints);
    } else if (msg.type === 'hints:clear') {
        clearHints();
    }
});

window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        event.preventDefault();
        postCallback('escape', {});
    }
});
