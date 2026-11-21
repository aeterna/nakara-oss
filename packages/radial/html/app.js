// aeterna_radial NUI: draws the ring, follows the pointer and reports hover / pick / back / escape to Lua.
// Lua owns the slots and re-checks every index; this page only draws. Text is set with textContent only.
'use strict';

const RESOURCE = 'aeterna_radial';
const BASE_HEIGHT = 1080;
const MAX_POSITIONS = 8;

const root = document.getElementById('radial');
const ringEl = document.getElementById('ring');
const centreEl = document.getElementById('centre');
const centreLabel = document.getElementById('centre-label');
const centreSub = document.getElementById('centre-sub');

let locale = {
    'radial.back': 'Back',
    'radial.close': 'Close',
    'radial.denied': 'Action not permitted',
    'radial.empty': 'No actions available',
};

const state = {
    open: false,
    child: false,
    slots: [],
    radius: 150,
    deadZone: 0.35,
    hover: 0,
    denied: false,
    deniedTimer: null,
};

let slotNodes = [];

function post(name, payload) {
    fetch('https://' + RESOURCE + '/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {}),
    }).catch(() => {});
}

function clearChildren(el) {
    while (el.firstChild) el.removeChild(el.firstChild);
}

// Theme: an owner stylesheet (aeterna_theme) wins; otherwise the preset selects tokens in theme.css.
function applyTheme(msg) {
    const href = typeof msg.href === 'string' && msg.href.startsWith('nui://') && msg.href.endsWith('.css') ? msg.href : '';
    let link = document.getElementById('aeterna-theme-override');
    if (href) {
        if (!link) {
            link = document.createElement('link');
            link.id = 'aeterna-theme-override';
            link.rel = 'stylesheet';
            document.head.appendChild(link);
        }
        link.setAttribute('href', href);
        document.documentElement.removeAttribute('data-preset');
    } else {
        if (link) link.remove();
        const preset = typeof msg.preset === 'string' ? msg.preset : 'asphalt';
        document.documentElement.setAttribute('data-preset', preset);
    }
}

function scale() {
    return window.innerHeight > 0 ? window.innerHeight / BASE_HEIGHT : 1;
}

function positions() {
    return Math.max(4, Math.min(MAX_POSITIONS, state.slots.length));
}

// Slot 1 at the top, the rest clockwise; screen y grows downward.
function indexFromPointer(clientX, clientY) {
    const dx = clientX - window.innerWidth / 2;
    const dy = clientY - window.innerHeight / 2;
    const r = state.radius * scale();
    if (Math.hypot(dx, dy) < r * state.deadZone) return { centre: true, index: 0 };
    const step = 360 / positions();
    const angle = ((Math.atan2(dx, -dy) * 180) / Math.PI + 360) % 360;
    const index = Math.floor(((angle + step / 2) % 360) / step) + 1;
    return { centre: false, index: index <= state.slots.length ? index : 0 };
}

function updateCentre() {
    centreEl.classList.toggle('denied', state.denied);
    const hovered = state.hover > 0 ? state.slots[state.hover - 1] : null;
    let label = '';
    if (state.denied) label = locale['radial.denied'];
    else if (hovered) label = hovered.label;
    else if (state.slots.length === 0) label = locale['radial.empty'];
    centreLabel.textContent = label;
    centreSub.textContent = state.child ? locale['radial.back'] : locale['radial.close'];
}

function updateHover() {
    for (let i = 0; i < slotNodes.length; i++) {
        const on = i + 1 === state.hover;
        slotNodes[i].classList.toggle('hover', on);
        slotNodes[i].setAttribute('aria-selected', on ? 'true' : 'false');
    }
    updateCentre();
}

function buildSlot(slot, angle, r) {
    const el = document.createElement('div');
    el.className = 'slot';
    el.style.setProperty('--x', (Math.sin(angle) * r).toFixed(1) + 'px');
    el.style.setProperty('--y', (-Math.cos(angle) * r).toFixed(1) + 'px');
    if (!slot) {
        el.classList.add('empty');
        el.setAttribute('aria-hidden', 'true');
        return el;
    }
    el.setAttribute('role', 'menuitem');
    if (slot.group) {
        el.classList.add('group');
        el.setAttribute('aria-haspopup', 'menu');
    }
    if (typeof slot.icon === 'string') {
        const icon = window.AeternaRadialIcons.create(slot.icon, 22);
        if (icon) el.appendChild(icon);
    }
    const label = document.createElement('span');
    label.className = 'slot-label';
    label.textContent = typeof slot.label === 'string' ? slot.label : '';
    el.appendChild(label);
    return el;
}

function draw() {
    clearChildren(ringEl);
    slotNodes = [];
    const n = positions();
    const r = state.radius;
    root.style.setProperty('--s', String(scale()));
    root.style.setProperty('--r', r + 'px');
    root.style.setProperty('--dz', (r * state.deadZone).toFixed(1) + 'px');
    for (let i = 0; i < n; i++) {
        const slot = i < state.slots.length ? state.slots[i] : null;
        const el = buildSlot(slot, (i * 2 * Math.PI) / n, r);
        ringEl.appendChild(el);
        if (slot) slotNodes.push(el);
    }
    updateHover();
}

function readSlots(list) {
    return Array.isArray(list) ? list.slice(0, MAX_POSITIONS) : [];
}

function showRing(msg, child) {
    state.child = child;
    state.slots = readSlots(msg.slots);
    state.hover = 0;
    if (!child) {
        if (typeof msg.radius === 'number' && msg.radius > 0) state.radius = msg.radius;
        if (typeof msg.deadZone === 'number' && msg.deadZone >= 0 && msg.deadZone < 1) state.deadZone = msg.deadZone;
    }
    draw();
    if (!state.open) {
        state.open = true;
        root.classList.add('open');
        root.setAttribute('aria-hidden', 'false');
    }
}

function closeRing() {
    state.open = false;
    state.slots = [];
    state.hover = 0;
    state.denied = false;
    clearTimeout(state.deniedTimer);
    root.classList.remove('open');
    root.setAttribute('aria-hidden', 'true');
}

function showDenied() {
    state.denied = true;
    updateCentre();
    clearTimeout(state.deniedTimer);
    state.deniedTimer = setTimeout(() => {
        state.denied = false;
        updateCentre();
    }, 1000);
}

function setHover(index, report) {
    if (index === state.hover) return;
    state.hover = index;
    updateHover();
    if (report) post('hover', { index: index });
}

function backOrClose() {
    post(state.child ? 'back' : 'escape', {});
}

document.addEventListener('mousemove', (e) => {
    if (!state.open) return;
    setHover(indexFromPointer(e.clientX, e.clientY).index, true);
});

document.addEventListener('mousedown', (e) => {
    if (!state.open) return;
    if (e.button === 2) {
        post('back', {});
        return;
    }
    if (e.button !== 0) return;
    const hit = indexFromPointer(e.clientX, e.clientY);
    if (hit.centre) backOrClose();
    else if (hit.index > 0) post('pick', { index: hit.index });
});

document.addEventListener('contextmenu', (e) => e.preventDefault());

// Keys reach the page only when it has keyboard focus; in game Lua reads the same keys as controls.
document.addEventListener('keydown', (e) => {
    if (!state.open) return;
    const count = state.slots.length;
    if (e.key === 'Escape') {
        post('escape', {});
    } else if (e.key === 'Backspace') {
        post('back', {});
    } else if ((e.key === 'ArrowRight' || e.key === 'ArrowLeft') && count > 0) {
        const dir = e.key === 'ArrowRight' ? 1 : -1;
        const next = state.hover === 0 ? (dir > 0 ? 1 : count) : ((state.hover - 1 + dir + count) % count) + 1;
        setHover(next, true);
    } else if (e.key === 'Enter' && state.hover > 0) {
        post('pick', { index: state.hover });
    } else {
        return;
    }
    e.preventDefault();
});

window.addEventListener('resize', () => {
    if (state.open) draw();
});

window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== 'object') return;
    switch (msg.type) {
        case 'aeterna:theme':
            applyTheme(msg);
            break;
        case 'locale':
            if (msg.strings && typeof msg.strings === 'object') locale = { ...locale, ...msg.strings };
            break;
        case 'ring:open':
            showRing(msg, false);
            break;
        case 'ring:child':
            showRing(msg, true);
            break;
        case 'ring:hover':
            if (Number.isInteger(msg.index) && msg.index >= 0 && msg.index <= state.slots.length) setHover(msg.index, false);
            break;
        case 'ring:denied':
            showDenied();
            break;
        case 'ring:close':
            closeRing();
            break;
        default:
            break;
    }
});
