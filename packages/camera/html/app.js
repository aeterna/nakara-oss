// aeterna_camera NUI: the viewfinder overlay (counter, key hints) and the gallery (grid, full view, delete confirm).
// Lua owns the photo list and re-checks every id. Text is set with textContent, images with img.src only.
'use strict';

const RESOURCE = 'aeterna_camera';
const BASE_HEIGHT = 1080;
const ID_RE = /^[0-9a-f]{32}$/;
const Icons = window.AeternaCameraIcons;

const el = (id) => document.getElementById(id);
const vfEl = el('vf');
const vfCounter = el('vf-counter');
const vfHints = el('vf-hints');
const galleryEl = el('gallery');
const titleEl = el('gallery-title');
const backBtn = el('gallery-back');
const closeBtn = el('gallery-close');
const gridEl = el('gallery-grid');
const emptyEl = el('gallery-empty');
const emptyLabel = el('gallery-empty-label');
const viewEl = el('gallery-view');
const photoEl = el('gallery-photo');
const actionsEl = el('gallery-actions');
const deleteBtn = el('gallery-delete');
const confirmEl = el('gallery-confirm');
const confirmText = el('gallery-confirm-text');
const confirmCancel = el('gallery-confirm-cancel');
const confirmDelete = el('gallery-confirm-delete');

let locale = {
    'camera.app.gallery': 'Gallery',
    'camera.hint.shutter': 'Photo',
    'camera.hint.switch': 'Switch camera',
    'camera.hint.close': 'Close',
    'camera.gallery.empty': 'No photos yet',
    'camera.gallery.delete': 'Delete',
    'camera.gallery.delete_confirm': 'Delete this photo?',
    'camera.gallery.cancel': 'Cancel',
};

const state = {
    gallery: false,
    base: '',
    items: [],
    viewing: null,
    confirming: false,
};

function post(name, payload) {
    return fetch('https://' + RESOURCE + '/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {}),
    }).then((r) => r.json()).catch(() => ({}));
}

function clearChildren(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
}

function setIcon(node, name, size) {
    clearChildren(node);
    const svg = Icons.create(name, size);
    if (svg) node.appendChild(svg);
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

function applyScale() {
    const s = window.innerHeight > 0 ? Math.min(1.5, window.innerHeight / BASE_HEIGHT) : 1;
    galleryEl.style.setProperty('--s', String(s));
}

function applyLocale() {
    titleEl.textContent = locale['camera.app.gallery'];
    emptyLabel.textContent = locale['camera.gallery.empty'];
    deleteBtn.textContent = locale['camera.gallery.delete'];
    confirmText.textContent = locale['camera.gallery.delete_confirm'];
    confirmCancel.textContent = locale['camera.gallery.cancel'];
    confirmDelete.textContent = locale['camera.gallery.delete'];
    closeBtn.setAttribute('aria-label', locale['camera.hint.close']);
    backBtn.setAttribute('aria-label', locale['camera.app.gallery']);
}

// Viewfinder overlay

function renderHints(hints) {
    clearChildren(vfHints);
    if (!Array.isArray(hints)) return;
    for (const h of hints.slice(0, 3)) {
        if (!h || typeof h !== 'object') continue;
        const row = document.createElement('div');
        row.className = 'hint-row';
        const key = document.createElement('span');
        key.className = 'hint-key';
        key.textContent = typeof h.bind === 'string' ? h.bind : '';
        const label = document.createElement('span');
        label.className = 'hint-label';
        label.textContent = typeof h.label === 'string' ? h.label : '';
        row.appendChild(key);
        row.appendChild(label);
        vfHints.appendChild(row);
    }
}

function showViewfinder(msg) {
    const count = Number.isInteger(msg.count) ? msg.count : 0;
    const cap = Number.isInteger(msg.cap) ? msg.cap : 0;
    vfCounter.textContent = count + ' / ' + cap;
    renderHints(msg.hints);
    vfEl.classList.remove('hidden');
}

// Gallery

function photoUrl(id) {
    return state.base + id + '.jpg';
}

function renderGrid() {
    clearChildren(gridEl);
    const empty = state.items.length === 0;
    emptyEl.classList.toggle('hidden', !empty);
    gridEl.classList.toggle('hidden', empty);
    for (const item of state.items) {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'thumb';
        if (state.base) {
            const img = document.createElement('img');
            img.loading = 'lazy';
            img.alt = '';
            img.src = photoUrl(item.id);
            btn.appendChild(img);
        }
        btn.addEventListener('click', () => openPhoto(item.id));
        gridEl.appendChild(btn);
    }
}

function showGrid() {
    state.viewing = null;
    state.confirming = false;
    viewEl.classList.add('hidden');
    backBtn.classList.add('hidden');
    photoEl.removeAttribute('src');
    renderGrid();
}

function openPhoto(id) {
    if (!ID_RE.test(id)) return;
    post('open', { id }).then((res) => {
        if (!res || res.ok !== true || !state.gallery) return;
        state.viewing = id;
        state.confirming = false;
        if (state.base) photoEl.src = photoUrl(id);
        confirmEl.classList.add('hidden');
        actionsEl.classList.remove('hidden');
        viewEl.classList.remove('hidden');
        backBtn.classList.remove('hidden');
        deleteBtn.focus();
    });
}

function askDelete() {
    if (!state.viewing) return;
    state.confirming = true;
    actionsEl.classList.add('hidden');
    confirmEl.classList.remove('hidden');
    confirmCancel.focus();
}

function cancelDelete() {
    state.confirming = false;
    confirmEl.classList.add('hidden');
    actionsEl.classList.remove('hidden');
    deleteBtn.focus();
}

function doDelete() {
    const id = state.viewing;
    if (!id) return;
    post('delete', { id }).then((res) => {
        if (res && res.ok === true) cancelDelete();
    });
}

function showGallery(msg) {
    const items = Array.isArray(msg.items) ? msg.items.filter((it) => it && ID_RE.test(it.id)) : [];
    state.items = items;
    state.base = typeof msg.base === 'string' && /^http:\/\/[^/\s]+\/aeterna_camera\/p\/$/.test(msg.base) ? msg.base : '';
    state.gallery = true;
    applyScale();
    galleryEl.classList.remove('hidden');
    showGrid();
    closeBtn.focus();
}

function removeItem(id) {
    state.items = state.items.filter((it) => it.id !== id);
    if (state.viewing === id) showGrid();
    else renderGrid();
}

function hideGallery() {
    state.gallery = false;
    state.items = [];
    state.viewing = null;
    galleryEl.classList.add('hidden');
    clearChildren(gridEl);
    photoEl.removeAttribute('src');
}

// Escape: confirm row = Cancel; full view = back to the grid; grid or viewfinder = close.
function onEscape() {
    if (state.gallery && state.confirming) cancelDelete();
    else if (state.gallery && state.viewing) showGrid();
    else post('escape', {});
}

setIcon(closeBtn, 'x', 18);
setIcon(backBtn, 'chevron-left', 18);
setIcon(el('gallery-empty-icon'), 'image', 32);
applyLocale();
closeBtn.addEventListener('click', () => post('close', {}));
backBtn.addEventListener('click', showGrid);
deleteBtn.addEventListener('click', askDelete);
confirmCancel.addEventListener('click', cancelDelete);
confirmDelete.addEventListener('click', doDelete);
window.addEventListener('resize', applyScale);

window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        event.preventDefault();
        onEscape();
    }
});

window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== 'object') return;
    switch (msg.type) {
    case 'aeterna:theme':
        applyTheme(msg);
        break;
    case 'locale':
        if (msg.strings && typeof msg.strings === 'object') {
            for (const k of Object.keys(locale)) {
                if (typeof msg.strings[k] === 'string') locale[k] = msg.strings[k];
            }
            applyLocale();
        }
        break;
    case 'vf:show':
        showViewfinder(msg);
        break;
    case 'vf:hide':
        vfEl.classList.add('hidden');
        break;
    case 'vf:mode':
        vfEl.dataset.mode = msg.mode === 'selfie' ? 'selfie' : 'back';
        break;
    case 'gallery:show':
        showGallery(msg);
        break;
    case 'gallery:removed':
        if (typeof msg.id === 'string') removeItem(msg.id);
        break;
    case 'gallery:hide':
        hideGallery();
        break;
    default:
        break;
    }
});
