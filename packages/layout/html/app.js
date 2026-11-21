// aeterna_layout NUI runtime — stand-in boxes, live drag with 100 ms throttle, grid snap,
// keyboard nudging/scaling, inspector panel and toolbar; 0.2: drag grid, snap step and preset selects,
// export / import box, screen size reports. Uses textContent only (never innerHTML).

const layoutRoot = document.getElementById('layout-root');
const canvasLayer = document.getElementById('canvas-layer');
const emptyBanner = document.getElementById('empty-banner');
const inspectorPanel = document.getElementById('inspector-panel');
const toolbarPanel = document.getElementById('toolbar-panel');
const confirmLayer = document.getElementById('confirm-layer');
const gridLayer = document.getElementById('grid-layer');
const shareLayer = document.getElementById('share-layer');

const DRAG_THROTTLE_MS = 100;
const SCREEN_REPORT_MS = 150;
const MAX_IMPORT_BYTES = 8192;

let locale = {
    'layout.menu.entry': 'Edit HUD layout',
    'layout.key.edit': 'Edit HUD layout',
    'layout.editor.title': 'HUD layout',
    'layout.editor.snap': 'Grid snap',
    'layout.editor.reset': 'Reset this',
    'layout.editor.resetAll': 'Reset all',
    'layout.editor.resetAllConfirm': 'Reset all elements to default positions?',
    'layout.editor.hide': 'Hide',
    'layout.editor.show': 'Show',
    'layout.editor.scale': 'Scale',
    'layout.editor.cancel': 'Cancel',
    'layout.editor.done': 'Done',
    'layout.editor.doneHint': 'Press Enter to confirm',
    'layout.editor.empty': 'No movable HUD elements registered',
    'layout.editor.preset': 'Preset',
    'layout.editor.snapOff': 'Off',
    'layout.menu.share': 'Export / import',
    'layout.export.title': 'Export layout',
    'layout.export.hint': 'Press Ctrl+C to copy this text.',
    'layout.import.title': 'Import layout',
    'layout.import.apply': 'Import',
    'layout.import.ok': 'Layout imported. Press Done to keep it.',
};

let isOpen = false;
let elements = [];
let selectedKey = null;
let snapStep = 8;
let snapSteps = [8, 16, 32];
let presetList = [];
let scaleConfig = { min: 0.5, max: 2.0, step: 0.05 };
let dragState = null;
let confirmOpen = false;
let shareOpen = false;
let shareStatusEl = null;
const boxNodes = new Map();

function postCallback(name, payload) {
    fetch('https://aeterna_layout/' + name, {
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

function applyThemeOverride(href, preset) {
    const root = document.documentElement;
    if (typeof href !== 'string' || href === '') {
        const known = preset === 'paper' || preset === 'night-market' || preset === 'asphalt';
        root.setAttribute('data-preset', known ? preset : 'asphalt');
    } else {
        root.removeAttribute('data-preset');
    }
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

function elementKey(el) {
    return el.owner + '/' + el.id;
}

function getSelectedElement() {
    if (!selectedKey) return null;
    for (let i = 0; i < elements.length; i++) {
        if (elementKey(elements[i]) === selectedKey) {
            return elements[i];
        }
    }
    return null;
}

function placeToPixels(el, screenW, screenH) {
    const sw = el.w * el.scale;
    const sh = el.h * el.scale;
    const left = el.x * screenW - el.ax * sw;
    const top = el.y * screenH - el.ay * sh;
    return { left, top, sw, sh };
}

function chooseAnchorAxis(pos, span) {
    const frac = span > 0 ? pos / span : 0;
    if (frac < 1 / 3) return 0;
    if (frac <= 2 / 3) return 0.5;
    return 1;
}

function utf8Bytes(text) {
    return new TextEncoder().encode(text).length;
}

function showGrid(visible) {
    if (visible && snapStep > 0) {
        gridLayer.style.backgroundSize = snapStep + 'px ' + snapStep + 'px';
        gridLayer.classList.remove('hidden');
    } else {
        gridLayer.classList.add('hidden');
    }
}

function dropToPlace(rawLeft, rawTop, w, h, scale, screenW, screenH, useSnap) {
    let left = rawLeft;
    let top = rawTop;
    if (useSnap && snapStep > 0) {
        left = Math.round(left / snapStep) * snapStep;
        top = Math.round(top / snapStep) * snapStep;
    }
    const sw = w * scale;
    const sh = h * scale;
    const maxLeft = Math.max(0, screenW - sw);
    const maxTop = Math.max(0, screenH - sh);
    const cLeft = Math.min(maxLeft, Math.max(0, left));
    const cTop = Math.min(maxTop, Math.max(0, top));
    const ax = chooseAnchorAxis(cLeft + sw * 0.5, screenW);
    const ay = chooseAnchorAxis(cTop + sh * 0.5, screenH);
    const x = screenW > 0 ? Math.min(1, Math.max(0, (cLeft + ax * sw) / screenW)) : 0;
    const y = screenH > 0 ? Math.min(1, Math.max(0, (cTop + ay * sh) / screenH)) : 0;
    return { x, y, ax, ay, scale };
}

function sendMoved(el) {
    postCallback('moved', {
        owner: el.owner,
        id: el.id,
        x: el.x,
        y: el.y,
        ax: el.ax,
        ay: el.ay,
        scale: el.scale,
    });
}

function updateBoxNode(el) {
    const key = elementKey(el);
    const entry = boxNodes.get(key);
    if (!entry) return;
    const screenW = window.innerWidth || 1920;
    const screenH = window.innerHeight || 1080;
    const { left, top, sw, sh } = placeToPixels(el, screenW, screenH);

    entry.box.style.left = Math.round(left) + 'px';
    entry.box.style.top = Math.round(top) + 'px';
    entry.box.style.width = Math.round(sw) + 'px';
    entry.box.style.height = Math.round(sh) + 'px';
    entry.box.classList.toggle('selected', key === selectedKey);
    entry.box.classList.toggle('is-hidden', el.hidden === true);
    entry.metaEl.textContent = Math.round(el.scale * 100) + '%';
}

function selectElement(key, focusDom) {
    selectedKey = key;
    for (let i = 0; i < elements.length; i++) {
        updateBoxNode(elements[i]);
    }
    renderInspector();
    if (focusDom && key && boxNodes.has(key)) {
        boxNodes.get(key).box.focus();
    }
}

function changeScale(el, delta) {
    if (!el || el.scalable === false) return;
    const rawNext = el.scale + delta;
    const stepped = Math.round(rawNext / scaleConfig.step) * scaleConfig.step;
    const nextScale = Number(Math.min(scaleConfig.max, Math.max(scaleConfig.min, stepped)).toFixed(2));
    if (nextScale === el.scale) return;

    const screenW = window.innerWidth || 1920;
    const screenH = window.innerHeight || 1080;
    const { left, top } = placeToPixels(el, screenW, screenH);
    const nextPlace = dropToPlace(left, top, el.w, el.h, nextScale, screenW, screenH, false);
    el.x = nextPlace.x;
    el.y = nextPlace.y;
    el.ax = nextPlace.ax;
    el.ay = nextPlace.ay;
    el.scale = nextScale;

    updateBoxNode(el);
    renderInspector();
    sendMoved(el);
}

function renderInspector() {
    clearChildren(inspectorPanel);
    const el = getSelectedElement();
    if (!el) {
        inspectorPanel.classList.add('hidden');
        return;
    }

    const titleEl = document.createElement('span');
    titleEl.className = 'inspector-title';
    titleEl.textContent = String(el.label || el.id);
    inspectorPanel.appendChild(titleEl);

    if (el.scalable !== false) {
        const scaleWrap = document.createElement('div');
        scaleWrap.className = 'scale-group';

        const scaleLbl = document.createElement('span');
        scaleLbl.className = 'scale-label';
        scaleLbl.textContent = String(locale['layout.editor.scale'] || 'Scale');
        scaleWrap.appendChild(scaleLbl);

        const minusBtn = document.createElement('button');
        minusBtn.type = 'button';
        minusBtn.className = 'btn btn-icon';
        minusBtn.disabled = el.scale <= scaleConfig.min;
        const minusIcon = window.AeternaLayoutIcons.create('minus', 14);
        if (minusIcon) minusBtn.appendChild(minusIcon);
        else minusBtn.textContent = '-';
        minusBtn.addEventListener('click', () => changeScale(el, -scaleConfig.step));
        scaleWrap.appendChild(minusBtn);

        const valEl = document.createElement('span');
        valEl.className = 'scale-value';
        valEl.textContent = Math.round(el.scale * 100) + '%';
        scaleWrap.appendChild(valEl);

        const plusBtn = document.createElement('button');
        plusBtn.type = 'button';
        plusBtn.className = 'btn btn-icon';
        plusBtn.disabled = el.scale >= scaleConfig.max;
        const plusIcon = window.AeternaLayoutIcons.create('plus', 14);
        if (plusIcon) plusBtn.appendChild(plusIcon);
        else plusBtn.textContent = '+';
        plusBtn.addEventListener('click', () => changeScale(el, scaleConfig.step));
        scaleWrap.appendChild(plusBtn);

        inspectorPanel.appendChild(scaleWrap);
    }

    const resetBtn = document.createElement('button');
    resetBtn.type = 'button';
    resetBtn.className = 'btn';
    resetBtn.textContent = String(locale['layout.editor.reset'] || 'Reset this');
    resetBtn.addEventListener('click', () => {
        postCallback('reset', { owner: el.owner, id: el.id });
    });
    inspectorPanel.appendChild(resetBtn);

    if (el.hideable === true) {
        const hideBtn = document.createElement('button');
        hideBtn.type = 'button';
        hideBtn.className = 'btn';
        hideBtn.textContent = String(
            el.hidden
                ? (locale['layout.editor.show'] || 'Show')
                : (locale['layout.editor.hide'] || 'Hide')
        );
        hideBtn.addEventListener('click', () => {
            el.hidden = !el.hidden;
            updateBoxNode(el);
            renderInspector();
            postCallback('hide', {
                owner: el.owner,
                id: el.id,
                hidden: el.hidden,
            });
        });
        inspectorPanel.appendChild(hideBtn);
    }

    inspectorPanel.classList.remove('hidden');
}

function openResetAllConfirm() {
    confirmOpen = true;
    clearChildren(confirmLayer);

    const card = document.createElement('div');
    card.className = 'confirm-card';

    const text = document.createElement('p');
    text.className = 'confirm-text';
    text.textContent = String(locale['layout.editor.resetAllConfirm'] || 'Reset all elements to default positions?');
    card.appendChild(text);

    const actions = document.createElement('div');
    actions.className = 'confirm-actions';

    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.className = 'btn';
    cancelBtn.textContent = String(locale['layout.editor.cancel'] || 'Cancel');
    cancelBtn.addEventListener('click', () => {
        closeResetAllConfirm();
    });

    const confirmBtn = document.createElement('button');
    confirmBtn.type = 'button';
    confirmBtn.className = 'btn btn-danger';
    confirmBtn.textContent = String(locale['layout.editor.resetAll'] || 'Reset all');
    confirmBtn.addEventListener('click', () => {
        closeResetAllConfirm();
        postCallback('reset', {});
    });

    actions.appendChild(cancelBtn);
    actions.appendChild(confirmBtn);
    card.appendChild(actions);

    confirmLayer.appendChild(card);
    confirmLayer.classList.remove('hidden');
    confirmBtn.focus();
}

function closeResetAllConfirm() {
    confirmOpen = false;
    clearChildren(confirmLayer);
    confirmLayer.classList.add('hidden');
}

function createSelect(labelText) {
    const wrap = document.createElement('label');
    wrap.className = 'select-group';
    const lbl = document.createElement('span');
    lbl.className = 'select-label';
    lbl.textContent = labelText;
    wrap.appendChild(lbl);
    const select = document.createElement('select');
    select.className = 'select';
    wrap.appendChild(select);
    return { wrap, select };
}

function openShare(text) {
    shareOpen = true;
    clearChildren(shareLayer);

    const card = document.createElement('div');
    card.className = 'share-card';

    const head = document.createElement('div');
    head.className = 'share-head';
    const title = document.createElement('h2');
    title.className = 'share-title';
    title.textContent = String(locale['layout.export.title'] || 'Export layout');
    head.appendChild(title);
    const closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'btn btn-icon';
    closeBtn.setAttribute('aria-label', String(locale['layout.editor.cancel'] || 'Cancel'));
    const xIcon = window.AeternaLayoutIcons.create('x', 14);
    if (xIcon) closeBtn.appendChild(xIcon);
    else closeBtn.textContent = 'x';
    closeBtn.addEventListener('click', () => closeShare());
    head.appendChild(closeBtn);
    card.appendChild(head);

    const hint = document.createElement('p');
    hint.className = 'share-hint';
    hint.textContent = String(locale['layout.export.hint'] || '');
    card.appendChild(hint);

    const exportBox = document.createElement('textarea');
    exportBox.className = 'share-text';
    exportBox.readOnly = true;
    exportBox.rows = 3;
    exportBox.spellcheck = false;
    exportBox.value = String(text || '');
    card.appendChild(exportBox);

    const importTitle = document.createElement('h2');
    importTitle.className = 'share-title';
    importTitle.textContent = String(locale['layout.import.title'] || 'Import layout');
    card.appendChild(importTitle);

    const importBox = document.createElement('textarea');
    importBox.className = 'share-text';
    importBox.rows = 3;
    importBox.spellcheck = false;
    importBox.maxLength = MAX_IMPORT_BYTES;
    card.appendChild(importBox);

    const foot = document.createElement('div');
    foot.className = 'share-foot';
    shareStatusEl = document.createElement('p');
    shareStatusEl.className = 'share-status';
    shareStatusEl.setAttribute('role', 'status');
    foot.appendChild(shareStatusEl);
    const applyBtn = document.createElement('button');
    applyBtn.type = 'button';
    applyBtn.className = 'btn btn-primary';
    applyBtn.textContent = String(locale['layout.import.apply'] || 'Import');
    applyBtn.addEventListener('click', () => {
        const value = importBox.value.trim();
        if (value === '' || utf8Bytes(value) > MAX_IMPORT_BYTES) return;
        postCallback('import', { text: value });
    });
    foot.appendChild(applyBtn);
    card.appendChild(foot);

    shareLayer.appendChild(card);
    shareLayer.classList.remove('hidden');
    exportBox.focus();
    exportBox.select();
}

function closeShare() {
    shareOpen = false;
    shareStatusEl = null;
    clearChildren(shareLayer);
    shareLayer.classList.add('hidden');
}

function showImportResult(msg) {
    if (!shareStatusEl) return;
    shareStatusEl.classList.toggle('is-error', msg.ok !== true);
    shareStatusEl.textContent = msg.ok === true
        ? String(locale['layout.import.ok'] || '')
        : String(msg.error || '');
}

function applyClamp(msg) {
    if (!msg.place || typeof msg.place !== 'object') return;
    const key = String(msg.owner) + '/' + String(msg.id);
    for (let i = 0; i < elements.length; i++) {
        const el = elements[i];
        if (elementKey(el) !== key) continue;
        if (dragState && dragState.el === el) return;
        el.x = Number(msg.place.x) || 0;
        el.y = Number(msg.place.y) || 0;
        el.ax = Number(msg.place.ax) || 0;
        el.ay = Number(msg.place.ay) || 0;
        el.scale = Number(msg.place.scale) || 1;
        updateBoxNode(el);
        if (key === selectedKey) renderInspector();
        return;
    }
}

let screenTimer = null;
function reportScreen() {
    const w = Math.round(window.innerWidth);
    const h = Math.round(window.innerHeight);
    if (w < 1 || h < 1 || w > 16384 || h > 16384) return;
    postCallback('screen', { w, h });
}

function renderToolbar() {
    clearChildren(toolbarPanel);

    const titleWrap = document.createElement('div');
    titleWrap.className = 'toolbar-title';
    const iconSpan = document.createElement('span');
    iconSpan.className = 'toolbar-title-icon';
    const slidersIcon = window.AeternaLayoutIcons.create('sliders', 16);
    if (slidersIcon) iconSpan.appendChild(slidersIcon);
    titleWrap.appendChild(iconSpan);

    const titleText = document.createElement('span');
    titleText.textContent = String(locale['layout.editor.title'] || 'HUD layout');
    titleWrap.appendChild(titleText);
    toolbarPanel.appendChild(titleWrap);

    const actions = document.createElement('div');
    actions.className = 'toolbar-actions';

    if (presetList.length > 0) {
        const presetSelect = createSelect(String(locale['layout.editor.preset'] || 'Preset'));
        const placeholder = document.createElement('option');
        placeholder.value = '';
        placeholder.textContent = String(locale['layout.editor.preset'] || 'Preset');
        presetSelect.select.appendChild(placeholder);
        for (let i = 0; i < presetList.length; i++) {
            const opt = document.createElement('option');
            opt.value = presetList[i].name;
            opt.textContent = presetList[i].label;
            presetSelect.select.appendChild(opt);
        }
        presetSelect.select.value = '';
        presetSelect.select.addEventListener('change', () => {
            const name = presetSelect.select.value;
            presetSelect.select.value = '';
            if (name) postCallback('preset', { name });
        });
        actions.appendChild(presetSelect.wrap);
    }

    const snapSelect = createSelect(String(locale['layout.editor.snap'] || 'Grid snap'));
    const steps = [0].concat(snapSteps);
    for (let i = 0; i < steps.length; i++) {
        const opt = document.createElement('option');
        opt.value = String(steps[i]);
        opt.textContent = steps[i] === 0 ? String(locale['layout.editor.snapOff'] || 'Off') : steps[i] + ' px';
        snapSelect.select.appendChild(opt);
    }
    snapSelect.select.value = String(snapStep);
    snapSelect.select.addEventListener('change', () => {
        const step = Number(snapSelect.select.value);
        if (steps.indexOf(step) === -1) return;
        snapStep = step;
        postCallback('snap', { step });
    });
    actions.appendChild(snapSelect.wrap);

    const resetAllBtn = document.createElement('button');
    resetAllBtn.type = 'button';
    resetAllBtn.className = 'btn';
    resetAllBtn.textContent = String(locale['layout.editor.resetAll'] || 'Reset all');
    resetAllBtn.addEventListener('click', () => {
        openResetAllConfirm();
    });
    actions.appendChild(resetAllBtn);

    const shareBtn = document.createElement('button');
    shareBtn.type = 'button';
    shareBtn.className = 'btn';
    shareBtn.textContent = String(locale['layout.menu.share'] || 'Export / import');
    shareBtn.addEventListener('click', () => {
        postCallback('exportOpen', {});
    });
    actions.appendChild(shareBtn);

    const cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.className = 'btn';
    cancelBtn.textContent = String(locale['layout.editor.cancel'] || 'Cancel');
    cancelBtn.addEventListener('click', () => {
        postCallback('cancel', {});
    });
    actions.appendChild(cancelBtn);

    const doneBtn = document.createElement('button');
    doneBtn.type = 'button';
    doneBtn.className = 'btn btn-primary';
    doneBtn.title = String(locale['layout.editor.doneHint'] || 'Press Enter to confirm');
    const checkIcon = window.AeternaLayoutIcons.create('check', 15);
    if (checkIcon) doneBtn.appendChild(checkIcon);
    const doneSpan = document.createElement('span');
    doneSpan.textContent = String(locale['layout.editor.done'] || 'Done');
    doneBtn.appendChild(doneSpan);
    doneBtn.addEventListener('click', () => {
        postCallback('done', {});
    });
    actions.appendChild(doneBtn);

    toolbarPanel.appendChild(actions);
}

function renderCanvas() {
    clearChildren(canvasLayer);
    boxNodes.clear();

    if (elements.length === 0) {
        emptyBanner.textContent = String(locale['layout.editor.empty'] || 'No movable HUD elements registered');
        emptyBanner.classList.remove('hidden');
        selectedKey = null;
        renderInspector();
        return;
    }

    emptyBanner.classList.add('hidden');
    if (!selectedKey || !getSelectedElement()) {
        selectedKey = elementKey(elements[0]);
    }

    for (let i = 0; i < elements.length; i++) {
        const el = elements[i];
        const key = elementKey(el);

        const box = document.createElement('div');
        box.className = 'standin-box';
        box.tabIndex = 0;
        box.setAttribute('role', 'button');
        box.setAttribute('aria-label', String(el.label || el.id));

        const lbl = document.createElement('span');
        lbl.className = 'standin-label';
        lbl.textContent = String(el.label || el.id);
        box.appendChild(lbl);

        const meta = document.createElement('span');
        meta.className = 'standin-meta';
        meta.textContent = Math.round(el.scale * 100) + '%';
        box.appendChild(meta);

        box.addEventListener('pointerdown', (ev) => {
            if (ev.button !== 0) return;
            ev.preventDefault();
            selectElement(key, false);
            const screenW = window.innerWidth || 1920;
            const screenH = window.innerHeight || 1080;
            const { left, top } = placeToPixels(el, screenW, screenH);
            dragState = {
                el,
                box,
                offsetX: ev.clientX - left,
                offsetY: ev.clientY - top,
                lastSentAt: 0,
            };
            box.classList.add('dragging');
            showGrid(!ev.shiftKey);
        });

        box.addEventListener('focus', () => {
            if (selectedKey !== key) {
                selectElement(key, false);
            }
        });

        canvasLayer.appendChild(box);
        boxNodes.set(key, { box, labelEl: lbl, metaEl: meta });
        updateBoxNode(el);
    }

    renderInspector();
}

window.addEventListener('pointermove', (ev) => {
    if (!isOpen || !dragState) return;
    const { el } = dragState;
    const screenW = window.innerWidth || 1920;
    const screenH = window.innerHeight || 1080;
    const rawLeft = ev.clientX - dragState.offsetX;
    const rawTop = ev.clientY - dragState.offsetY;
    const useSnap = snapStep > 0 && !ev.shiftKey;
    showGrid(useSnap);
    const next = dropToPlace(rawLeft, rawTop, el.w, el.h, el.scale, screenW, screenH, useSnap);

    el.x = next.x;
    el.y = next.y;
    el.ax = next.ax;
    el.ay = next.ay;
    updateBoxNode(el);

    const now = performance.now();
    if (now - dragState.lastSentAt >= DRAG_THROTTLE_MS) {
        dragState.lastSentAt = now;
        sendMoved(el);
    }
});

window.addEventListener('pointerup', (ev) => {
    if (!isOpen || !dragState) return;
    const { el, box } = dragState;
    box.classList.remove('dragging');
    const screenW = window.innerWidth || 1920;
    const screenH = window.innerHeight || 1080;
    const rawLeft = ev.clientX - dragState.offsetX;
    const rawTop = ev.clientY - dragState.offsetY;
    const useSnap = snapStep > 0 && !ev.shiftKey;
    showGrid(false);
    const next = dropToPlace(rawLeft, rawTop, el.w, el.h, el.scale, screenW, screenH, useSnap);

    el.x = next.x;
    el.y = next.y;
    el.ax = next.ax;
    el.ay = next.ay;
    dragState = null;
    updateBoxNode(el);
    sendMoved(el);
});

window.addEventListener('resize', () => {
    if (screenTimer !== null) clearTimeout(screenTimer);
    screenTimer = setTimeout(() => {
        screenTimer = null;
        reportScreen();
    }, SCREEN_REPORT_MS);
    if (!isOpen) return;
    for (let i = 0; i < elements.length; i++) {
        updateBoxNode(elements[i]);
    }
});

window.addEventListener('keydown', (ev) => {
    if (!isOpen) return;

    if (ev.key === 'Escape') {
        ev.preventDefault();
        if (confirmOpen) {
            closeResetAllConfirm();
            return;
        }
        if (shareOpen) {
            closeShare();
            return;
        }
        postCallback('cancel', {});
        return;
    }

    if (confirmOpen || shareOpen) return;

    const focused = document.activeElement;
    if (focused && focused.tagName === 'SELECT') return;

    if (ev.key === 'Enter') {
        const toolbarButtonFocused = !!(focused && focused.tagName === 'BUTTON' && toolbarPanel.contains(focused));
        if (!toolbarButtonFocused) {
            ev.preventDefault();
            postCallback('done', {});
            return;
        }
    }

    if (ev.key === 'Tab' && elements.length > 0) {
        ev.preventDefault();
        let idx = 0;
        for (let i = 0; i < elements.length; i++) {
            if (elementKey(elements[i]) === selectedKey) {
                idx = i;
                break;
            }
        }
        const dir = ev.shiftKey ? -1 : 1;
        const nextIdx = (idx + dir + elements.length) % elements.length;
        selectElement(elementKey(elements[nextIdx]), true);
        return;
    }

    const el = getSelectedElement();
    if (!el) return;

    if (ev.key === 'ArrowLeft' || ev.key === 'ArrowRight' || ev.key === 'ArrowUp' || ev.key === 'ArrowDown') {
        ev.preventDefault();
        const step = ev.shiftKey ? 10 : 1;
        const dx = ev.key === 'ArrowLeft' ? -step : ev.key === 'ArrowRight' ? step : 0;
        const dy = ev.key === 'ArrowUp' ? -step : ev.key === 'ArrowDown' ? step : 0;
        const screenW = window.innerWidth || 1920;
        const screenH = window.innerHeight || 1080;
        const { left, top } = placeToPixels(el, screenW, screenH);
        const next = dropToPlace(left + dx, top + dy, el.w, el.h, el.scale, screenW, screenH, false);
        el.x = next.x;
        el.y = next.y;
        el.ax = next.ax;
        el.ay = next.ay;
        updateBoxNode(el);
        sendMoved(el);
        return;
    }

    if (ev.key === '+' || ev.key === '=') {
        ev.preventDefault();
        changeScale(el, scaleConfig.step);
        return;
    }

    if (ev.key === '-' || ev.key === '_') {
        ev.preventDefault();
        changeScale(el, -scaleConfig.step);
    }
});

function openEditor(msg) {
    const refresh = isOpen;
    isOpen = true;
    dragState = null;
    showGrid(false);
    closeResetAllConfirm();
    if (!refresh) closeShare();

    if (Array.isArray(msg.snapSteps)) {
        snapSteps = msg.snapSteps.filter((v) => Number.isInteger(v) && v > 0);
    }
    if (typeof msg.snap === 'number' && msg.snap >= 0) {
        snapStep = msg.snap;
    }
    if (msg.scale && typeof msg.scale === 'object') {
        scaleConfig = {
            min: typeof msg.scale.min === 'number' ? msg.scale.min : 0.5,
            max: typeof msg.scale.max === 'number' ? msg.scale.max : 2.0,
            step: typeof msg.scale.step === 'number' ? msg.scale.step : 0.05,
        };
    }

    const rawElements = Array.isArray(msg.elements) ? msg.elements : [];
    elements = rawElements.map((item) => ({
        owner: String(item.owner || ''),
        id: String(item.id || ''),
        label: String(item.label || item.id || ''),
        w: Number(item.w) || 100,
        h: Number(item.h) || 50,
        x: Number(item.x) || 0,
        y: Number(item.y) || 0,
        ax: Number(item.ax) || 0,
        ay: Number(item.ay) || 0,
        scale: Number(item.scale) || 1.0,
        hidden: item.hidden === true,
        scalable: item.scalable !== false,
        hideable: item.hideable === true,
    }));

    renderToolbar();
    renderCanvas();
    layoutRoot.classList.remove('hidden');
}

function closeEditor() {
    isOpen = false;
    dragState = null;
    elements = [];
    selectedKey = null;
    presetList = [];
    showGrid(false);
    closeResetAllConfirm();
    closeShare();
    clearChildren(canvasLayer);
    clearChildren(inspectorPanel);
    clearChildren(toolbarPanel);
    boxNodes.clear();
    layoutRoot.classList.add('hidden');
}

window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg.type !== 'string') return;

    if (msg.type === 'aeterna:theme') {
        applyThemeOverride(msg.href, msg.preset);
    } else if (msg.type === 'locale' && msg.strings && typeof msg.strings === 'object') {
        locale = { ...locale, ...msg.strings };
        if (isOpen) {
            renderToolbar();
            renderCanvas();
        }
    } else if (msg.type === 'editor:open') {
        openEditor(msg);
    } else if (msg.type === 'editor:close') {
        closeEditor();
    } else if (msg.type === 'editor:clamp') {
        if (isOpen) applyClamp(msg);
    } else if (msg.type === 'editor:presets') {
        presetList = (Array.isArray(msg.list) ? msg.list : [])
            .filter((p) => p && typeof p.name === 'string')
            .map((p) => ({ name: p.name, label: String(p.label || p.name) }));
        if (isOpen) renderToolbar();
    } else if (msg.type === 'export:show') {
        if (isOpen) openShare(msg.text);
    } else if (msg.type === 'import:result') {
        showImportResult(msg);
    }
});

reportScreen();
