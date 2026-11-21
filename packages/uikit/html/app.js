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
    'uikit.search.placeholder': 'Search',
    'uikit.search.none': 'Nothing matches',
    'uikit.table.empty': 'No rows',
    'uikit.tabs.label': 'Sections',
};

let currentPanel = null;
let blockElements = new Map();
let blockState = new Map();
let progressTimer = null;
let skillState = null;
let tabsState = null;
let paused = false; // 0.2: a focus overlay from another resource pauses uikit; the page ignores input
const exitTimers = new Map();

// Returns false (and sends nothing) while paused, so callers keep their card on screen.
function postCallback(name, payload) {
    if (paused) return false;
    fetch('https://aeterna_uikit/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {}),
    }).catch(() => {});
    return true;
}

function setPaused(flag) {
    paused = flag === true;
    document.getElementById('uikit-root').classList.toggle('uikit-paused', paused);
    if (skillState) {
        if (paused) skillState.pause();
        else skillState.resume();
    }
}

// While paused, keys and clicks never reach a control (typing, toggles, slider, tabs, ESC).
for (const kind of ['keydown', 'mousedown', 'click']) {
    window.addEventListener(kind, (event) => {
        if (!paused) return;
        event.preventDefault();
        event.stopImmediatePropagation();
    }, true);
}

function answerPrompt(kind, value) {
    if (!postCallback('promptResult', { kind, value })) return;
    closePrompt();
}

function clearChildren(el) {
    while (el.firstChild) {
        el.removeChild(el.firstChild);
    }
}

// Motion (0.2): cards enter with a fade and an 8 px rise over --enter and leave with a fade over --fast.
// Under prefers-reduced-motion theme.css sets both to 0ms and style.css drops the rise.
function cssMs(name) {
    const raw = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    const n = parseFloat(raw);
    if (Number.isNaN(n)) return 0;
    return raw.endsWith('ms') ? n : n * 1000;
}

function cancelExit(layer) {
    const t = exitTimers.get(layer);
    if (t) {
        clearTimeout(t);
        exitTimers.delete(layer);
    }
}

function showLayerCard(layer, card) {
    cancelExit(layer);
    clearChildren(layer);
    card.classList.add('motion-enter');
    layer.appendChild(card);
    layer.classList.remove('hidden');
    void card.offsetWidth; // commit the start state so the transition runs
    card.classList.remove('motion-enter');
}

// The answer is never held back: callers post their callback first, then hide.
function hideLayer(layer, animate) {
    cancelExit(layer);
    const card = layer.firstElementChild;
    const ms = animate && card ? cssMs('--fast') : 0;
    if (ms <= 0) {
        clearChildren(layer);
        layer.classList.add('hidden');
        return;
    }
    card.classList.add('motion-exit');
    card.setAttribute('aria-hidden', 'true');
    exitTimers.set(layer, setTimeout(() => {
        exitTimers.delete(layer);
        clearChildren(layer);
        layer.classList.add('hidden');
    }, ms));
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
        } else if (st.type === 'slider' || st.type === 'tabs') {
            out[id] = st.value;
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

function buildEmptyState(opt, action, onAction) {
    const wrap = document.createElement('div');
    wrap.className = 'empty-state';
    if (opt.icon) {
        const svg = window.AeternaUikitIcons.create(opt.icon, 24);
        if (svg) {
            const iconWrap = document.createElement('span');
            iconWrap.className = 'empty-icon';
            iconWrap.appendChild(svg);
            wrap.appendChild(iconWrap);
        }
    }
    const labelEl = document.createElement('p');
    labelEl.className = 'empty-label';
    labelEl.textContent = String(opt.label || '');
    wrap.appendChild(labelEl);
    let bodyEl = null;
    if (opt.body) {
        bodyEl = document.createElement('p');
        bodyEl.className = 'empty-body';
        bodyEl.textContent = String(opt.body);
        wrap.appendChild(bodyEl);
    }
    let control = null;
    if (action && action.id) {
        control = document.createElement('button');
        control.type = 'button';
        control.className = 'btn btn-secondary';
        control.textContent = String(action.label || '');
        control.addEventListener('click', () => {
            if (!control.disabled) onAction(action.id);
        });
        wrap.appendChild(control);
    }
    return { root: wrap, labelEl, bodyEl, control };
}

function matchesQuery(item, query) {
    if (!query) return true;
    const label = String(item.label || '').toLowerCase();
    const meta = String(item.meta || '').toLowerCase();
    return label.includes(query) || meta.includes(query);
}

// List items filtered by the search box, with the empty state when nothing is left to show.
function refreshList(ref) {
    const items = Array.isArray(ref.items) ? ref.items : [];
    const query = ref.query.trim().toLowerCase();
    const shown = items.filter((item) => matchesQuery(item, query));
    renderListItems(ref.itemsWrap, shown, ref.triggerPick);
    clearChildren(ref.emptyWrap);
    if (shown.length === 0) {
        let opt = ref.empty;
        if (items.length > 0 && !opt) opt = { label: locale['uikit.search.none'] };
        if (opt) ref.emptyWrap.appendChild(buildEmptyState(opt).root);
    }
}

function renderTable(ref) {
    clearChildren(ref.tbody);
    clearChildren(ref.emptyWrap);
    const rows = Array.isArray(ref.rows) ? ref.rows : [];
    ref.table.classList.toggle('hidden', rows.length === 0);
    if (rows.length === 0) {
        const opt = ref.empty || { label: locale['uikit.table.empty'] };
        ref.emptyWrap.appendChild(buildEmptyState(opt).root);
        return;
    }
    for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        const tr = document.createElement('tr');
        tr.className = 'table-row';
        const cells = row.cells && typeof row.cells === 'object' ? row.cells : {};
        for (let c = 0; c < ref.columns.length; c++) {
            const col = ref.columns[c];
            const td = document.createElement('td');
            td.className = col.align === 'end' ? 'cell-end' : 'cell-start';
            const v = cells[col.id];
            td.textContent = v === undefined || v === null ? '' : String(v);
            tr.appendChild(td);
        }
        if (ref.selectable) {
            const disabled = row.disabled === true;
            tr.classList.add('table-row-selectable');
            tr.setAttribute('role', 'button');
            tr.tabIndex = disabled ? -1 : 0;
            if (disabled) tr.setAttribute('aria-disabled', 'true');
            const pick = () => {
                if (!disabled) ref.triggerPick(row.id);
            };
            tr.addEventListener('click', pick);
            tr.addEventListener('keydown', (event) => {
                if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault();
                    pick();
                }
            });
        }
        ref.tbody.appendChild(tr);
    }
}

// Blocks with `tab` show only while that tab is active; a newly shown block fades in over --fast.
function applyTabVisibility() {
    if (!tabsState) return;
    for (const ref of blockElements.values()) {
        if (!ref.tab) continue;
        const show = ref.tab === tabsState.value;
        const wasHidden = ref.root.classList.contains('hidden');
        ref.root.classList.toggle('hidden', !show);
        if (show && wasHidden) {
            ref.root.classList.remove('tab-in');
            void ref.root.offsetWidth;
            ref.root.classList.add('tab-in');
        }
    }
}

function buildSlider(block) {
    const min = Number(block.min);
    const max = Number(block.max);
    const step = Number(block.step) > 0 ? Number(block.step) : 1;
    const sliderMath = window.AeternaUikitSlider;
    const decimals = Math.min(20, Math.max(sliderMath.decimalsOf(step), sliderMath.decimalsOf(min)));

    const wrap = document.createElement('div');
    wrap.className = 'slider-group';
    const header = document.createElement('div');
    header.className = 'slider-header';
    const labelEl = document.createElement('span');
    labelEl.className = 'block-label';
    labelEl.textContent = String(block.label || '');
    const valueWrap = document.createElement('span');
    valueWrap.className = 'slider-value';
    const valueEl = document.createElement('span');
    valueWrap.appendChild(valueEl);
    if (block.unit) {
        const unitEl = document.createElement('span');
        unitEl.className = 'slider-unit';
        unitEl.textContent = String(block.unit);
        valueWrap.appendChild(unitEl);
    }
    header.appendChild(labelEl);
    header.appendChild(valueWrap);
    wrap.appendChild(header);

    const track = document.createElement('div');
    track.className = 'slider-track';
    track.tabIndex = 0;
    track.setAttribute('role', 'slider');
    track.setAttribute('aria-label', String(block.label || ''));
    track.setAttribute('aria-valuemin', String(min));
    track.setAttribute('aria-valuemax', String(max));
    const fill = document.createElement('div');
    fill.className = 'slider-fill';
    const thumb = document.createElement('div');
    thumb.className = 'slider-thumb';
    track.appendChild(fill);
    track.appendChild(thumb);
    wrap.appendChild(track);

    const state = { type: 'slider', value: min, disabled: false };

    // Snap to the step grid (html/slider-math.js) so what the page sends passes the server re-check.
    function setValue(v) {
        state.value = sliderMath.snap(v, min, max, step);
        const pct = Math.min(100, ((state.value - min) / (max - min)) * 100);
        fill.style.width = pct + '%';
        thumb.style.left = pct + '%';
        const text = state.value.toFixed(decimals);
        valueEl.textContent = text;
        track.setAttribute('aria-valuenow', text);
    }

    function setDisabled(flag) {
        state.disabled = flag === true;
        track.tabIndex = state.disabled ? -1 : 0;
        track.setAttribute('aria-disabled', state.disabled ? 'true' : 'false');
    }

    track.addEventListener('keydown', (event) => {
        if (state.disabled) return;
        const keySteps = { ArrowLeft: -1, ArrowDown: -1, ArrowRight: 1, ArrowUp: 1, PageDown: -10, PageUp: 10 };
        if (keySteps[event.key] !== undefined) {
            setValue(state.value + keySteps[event.key] * step);
        } else if (event.key === 'Home') {
            setValue(min);
        } else if (event.key === 'End') {
            setValue(max);
        } else {
            return;
        }
        event.preventDefault();
    });

    function setFromPointer(clientX) {
        const rect = track.getBoundingClientRect();
        if (rect.width <= 0) return;
        const ratio = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
        setValue(min + ratio * (max - min));
    }

    function onMove(event) {
        setFromPointer(event.clientX);
    }

    function onUp() {
        track.classList.remove('slider-dragging');
        window.removeEventListener('mousemove', onMove);
        window.removeEventListener('mouseup', onUp);
    }

    track.addEventListener('mousedown', (event) => {
        if (state.disabled || event.button !== 0) return;
        track.focus();
        track.classList.add('slider-dragging');
        setFromPointer(event.clientX);
        window.addEventListener('mousemove', onMove);
        window.addEventListener('mouseup', onUp);
    });

    setValue(block.value);
    return { wrap, labelEl, track, state, setValue, setDisabled };
}

function buildTabs(block, panelId) {
    const bar = document.createElement('div');
    bar.className = 'tabs-bar';
    bar.setAttribute('role', 'tablist');
    bar.setAttribute('aria-label', locale['uikit.tabs.label'] || 'Sections');
    const items = Array.isArray(block.items) ? block.items : [];
    const buttons = [];
    const state = { type: 'tabs', value: block.value };

    function select(id, fromUser) {
        if (!items.some((item) => item.id === id)) return;
        const changed = state.value !== id;
        state.value = id;
        for (const btn of buttons) {
            const active = btn.dataset.tab === id;
            btn.setAttribute('aria-selected', active ? 'true' : 'false');
            btn.tabIndex = active ? 0 : -1;
        }
        applyTabVisibility();
        if (fromUser && changed && block.report === true) {
            postCallback('panelAction', { panelId, action: id, values: collectPanelValues() });
        }
    }

    for (let i = 0; i < items.length; i++) {
        const item = items[i];
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'tab-btn';
        btn.setAttribute('role', 'tab');
        btn.dataset.tab = String(item.id);
        if (item.icon) {
            const svg = window.AeternaUikitIcons.create(item.icon, 16);
            if (svg) btn.appendChild(svg);
        }
        const span = document.createElement('span');
        span.textContent = String(item.label || '');
        btn.appendChild(span);
        btn.addEventListener('click', () => select(item.id, true));
        buttons.push(btn);
        bar.appendChild(btn);
    }

    bar.addEventListener('keydown', (event) => {
        const idx = buttons.findIndex((btn) => btn.dataset.tab === state.value);
        let next = -1;
        if (event.key === 'ArrowRight') next = (idx + 1) % buttons.length;
        else if (event.key === 'ArrowLeft') next = (idx - 1 + buttons.length) % buttons.length;
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = buttons.length - 1;
        if (next < 0) return;
        event.preventDefault();
        select(buttons[next].dataset.tab, true);
        buttons[next].focus();
    });

    tabsState = state;
    select(block.value, false);
    return { bar, state, select };
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
        const triggerPick = (item) => {
            postCallback('panelAction', {
                panelId,
                action: item.id,
                values: collectPanelValues(),
            });
        };
        const ref = {
            type: 'list',
            root: wrap,
            labelEl,
            itemsWrap: document.createElement('div'),
            emptyWrap: document.createElement('div'),
            triggerPick,
            items: block.items || [],
            empty: block.empty || null,
            query: '',
        };
        if (block.search) {
            const search = document.createElement('input');
            search.type = 'text';
            search.className = 'field-input list-search';
            search.placeholder = String(block.search.placeholder || locale['uikit.search.placeholder']);
            search.setAttribute('aria-label', search.placeholder);
            search.addEventListener('input', () => {
                ref.query = search.value;
                refreshList(ref);
            });
            wrap.appendChild(search);
        }
        ref.itemsWrap.className = 'list-group';
        wrap.appendChild(ref.itemsWrap);
        wrap.appendChild(ref.emptyWrap);
        refreshList(ref);
        blockElements.set(block.id, ref);
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

    if (btype === 'tabs') {
        const tabs = buildTabs(block, panelId);
        blockState.set(block.id, tabs.state);
        blockElements.set(block.id, { type: 'tabs', root: tabs.bar, select: tabs.select });
        return tabs.bar;
    }

    if (btype === 'slider') {
        const slider = buildSlider(block);
        blockState.set(block.id, slider.state);
        blockElements.set(block.id, {
            type: 'slider',
            root: slider.wrap,
            labelEl: slider.labelEl,
            track: slider.track,
            setValue: slider.setValue,
            setDisabled: slider.setDisabled,
        });
        return slider.wrap;
    }

    if (btype === 'table') {
        const wrap = document.createElement('div');
        wrap.className = 'table-group';
        const table = document.createElement('table');
        table.className = 'data-table';
        const thead = document.createElement('thead');
        const headRow = document.createElement('tr');
        const columns = Array.isArray(block.columns) ? block.columns : [];
        for (let c = 0; c < columns.length; c++) {
            const th = document.createElement('th');
            th.scope = 'col';
            th.className = columns[c].align === 'end' ? 'cell-end' : 'cell-start';
            th.textContent = String(columns[c].label || '');
            headRow.appendChild(th);
        }
        thead.appendChild(headRow);
        table.appendChild(thead);
        const tbody = document.createElement('tbody');
        table.appendChild(tbody);
        wrap.appendChild(table);
        const emptyWrap = document.createElement('div');
        wrap.appendChild(emptyWrap);
        const ref = {
            type: 'table',
            root: wrap,
            table,
            tbody,
            emptyWrap,
            columns,
            rows: block.rows || [],
            empty: block.empty || null,
            selectable: block.selectable === true,
            triggerPick: (rowId) => {
                postCallback('panelAction', { panelId, action: rowId, values: collectPanelValues() });
            },
        };
        renderTable(ref);
        blockElements.set(block.id, ref);
        return wrap;
    }

    if (btype === 'empty') {
        const empty = buildEmptyState(block, block.action, (actionId) => {
            postCallback('panelAction', { panelId, action: actionId, values: collectPanelValues() });
        });
        blockElements.set(block.id, { type: 'empty', root: empty.root, labelEl: empty.labelEl, control: empty.control });
        return empty.root;
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
    tabsState = null;

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
            const block = panel.blocks[i];
            const node = buildBlockNode(block, panel.panelId);
            if (!node) continue;
            const ref = blockElements.get(block.id);
            if (ref && typeof block.tab === 'string') ref.tab = block.tab;
            body.appendChild(node);
        }
        applyTabVisibility();
    }

    card.appendChild(body);
    showLayerCard(panelLayer, card);

    const focusables = card.querySelectorAll('button, input, select, [tabindex="0"]');
    for (const el of focusables) {
        if (el.offsetParent !== null && !el.disabled) {
            el.focus();
            break;
        }
    }
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
        if (partial.disabled !== undefined) {
            if (ref.setDisabled) {
                ref.setDisabled(partial.disabled === true);
            } else if (ref.control) {
                ref.control.disabled = partial.disabled === true;
            }
        }
        if (partial.value !== undefined) {
            if (ref.type === 'tabs') {
                ref.select(String(partial.value), false);
            } else if (ref.type === 'slider') {
                ref.setValue(partial.value);
            } else if (ref.type === 'field' || ref.type === 'select') {
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
        if (partial.empty !== undefined && (ref.type === 'list' || ref.type === 'table')) {
            ref.empty = partial.empty || null;
            if (ref.type === 'table') renderTable(ref);
        }
        if (partial.rows !== undefined && ref.type === 'table') {
            ref.rows = Array.isArray(partial.rows) ? partial.rows : [];
            renderTable(ref);
        }
        if (partial.items !== undefined) {
            if (ref.type === 'list') {
                ref.items = Array.isArray(partial.items) ? partial.items : [];
            } else if (ref.type === 'buttons' && ref.itemsWrap) {
                renderButtonsRow(ref.itemsWrap, partial.items, ref.triggerBtn);
            }
        }
        if (ref.type === 'list' && (partial.items !== undefined || partial.empty !== undefined)) {
            refreshList(ref);
        }
    }
}

// A panel replaced by another swaps without an exit animation.
function closePanel(reason) {
    currentPanel = null;
    tabsState = null;
    blockElements.clear();
    blockState.clear();
    hideLayer(panelLayer, reason !== 'replaced');
}

function closePrompt() {
    hideLayer(promptLayer, true);
}

function openConfirmPrompt(prompt) {
    const card = document.createElement('div');
    card.className = 'card card-sm';

    const header = document.createElement('div');
    header.className = 'card-header';
    const titleEl = document.createElement('h2');
    titleEl.className = 'card-title';
    titleEl.textContent = String(prompt.title || '');
    header.appendChild(titleEl);
    header.appendChild(createCloseButton(() => {
        answerPrompt('confirm', false);
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
        answerPrompt('confirm', false);
    });

    const okBtn = document.createElement('button');
    okBtn.type = 'button';
    okBtn.className = 'btn ' + (prompt.danger ? 'btn-danger' : 'btn-primary');
    okBtn.textContent = String(prompt.confirm || locale['uikit.confirm.ok']);
    okBtn.addEventListener('click', () => {
        answerPrompt('confirm', true);
    });

    actions.appendChild(cancelBtn);
    actions.appendChild(okBtn);
    card.appendChild(actions);

    showLayerCard(promptLayer, card);
    okBtn.focus();
}

function openInputPrompt(prompt) {
    const card = document.createElement('div');
    card.className = 'card card-sm';

    const header = document.createElement('div');
    header.className = 'card-header';
    const titleEl = document.createElement('h2');
    titleEl.className = 'card-title';
    titleEl.textContent = String(prompt.title || '');
    header.appendChild(titleEl);
    header.appendChild(createCloseButton(() => {
        answerPrompt('input', null);
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
        answerPrompt('input', null);
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
        answerPrompt('input', values);
    });

    actions.appendChild(cancelBtn);
    actions.appendChild(submitBtn);
    card.appendChild(actions);

    showLayerCard(promptLayer, card);
    if (controls.length > 0) controls[0].el.focus();
}

function updateProgressPrompt(prompt) {
    if (progressTimer) {
        clearInterval(progressTimer);
        progressTimer = null;
    }
    if (!prompt || prompt.active === false) {
        hideLayer(progressLayer, true);
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

    showLayerCard(progressLayer, card);

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
    if (msg.action === 'hit') {
        if (skillState) skillState.hit();
        return;
    }
    const prompt = msg.prompt;
    if (skillState && skillState.raf) {
        cancelAnimationFrame(skillState.raf);
    }
    skillState = null;
    if (!prompt || prompt.active === false) {
        hideLayer(skillLayer, true);
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

    showLayerCard(skillLayer, card);

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
        postCallback('promptResult', { kind: 'skill', value: passed });
        hideLayer(skillLayer, true);
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

    // While a focus overlay pauses uikit the marker stops where it is and ignores hits.
    skillState = {
        raf: null,
        paused: false,
        pause() {
            if (this.paused) return;
            this.paused = true;
            if (this.raf) cancelAnimationFrame(this.raf);
            this.raf = null;
        },
        resume() {
            if (!this.paused) return;
            this.paused = false;
            lastTs = performance.now();
            this.raf = requestAnimationFrame(step);
        },
        hit() {
            if (this.paused) return;
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
    if (paused) skillState.pause();
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

// Self-tests (0.2): the client test drives the open test panel the way a player would and reports what it saw.
function visibleBlockIds() {
    const out = [];
    for (const [id, ref] of blockElements.entries()) {
        if (!ref.root.classList.contains('hidden')) out.push(id);
    }
    return out;
}

function selftestDrive(msg) {
    if (!currentPanel) return;
    if (msg.op === 'tab') {
        const buttons = panelLayer.querySelectorAll('.tab-btn');
        for (const btn of buttons) {
            if (btn.dataset.tab === String(msg.target)) btn.click();
        }
        postCallback('selftestProbe', { op: 'tab', visible: visibleBlockIds() });
    } else if (msg.op === 'slider') {
        const ref = blockElements.get(String(msg.block));
        let shown = null;
        if (ref && ref.track) {
            ref.track.focus();
            ref.track.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }));
            shown = ref.track.getAttribute('aria-valuenow');
        }
        const press = blockElements.get(String(msg.press));
        const btn = press && press.itemsWrap ? press.itemsWrap.querySelector('button') : null;
        if (btn) btn.click();
        postCallback('selftestProbe', { op: 'slider', shown });
    }
}

window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg.type !== 'string') return;

    if (msg.type === 'aeterna:theme') {
        applyThemeOverride(msg.href);
    } else if (msg.type === 'focus:paused') {
        setPaused(msg.paused === true);
    } else if (msg.type === 'locale' && msg.strings && typeof msg.strings === 'object') {
        locale = { ...locale, ...msg.strings };
    } else if (msg.type === 'panel:open' && msg.panel) {
        openPanel(msg.panel);
    } else if (msg.type === 'panel:update') {
        updatePanel(msg.panelId, msg.patch);
    } else if (msg.type === 'panel:close') {
        if (msg.panelId === '__prompt') {
            closePrompt();
        } else {
            closePanel(msg.reason);
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
    } else if (msg.type === 'selftest:drive') {
        selftestDrive(msg);
    }
});

window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        event.preventDefault();
        postCallback('escape', {});
    }
});
