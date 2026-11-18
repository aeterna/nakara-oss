// aeterna_notify NUI runtime — renders toasts, announcement banners, and the MOTD card.
// Uses textContent only (never innerHTML/outerHTML).

const toastStack = document.getElementById('toast-stack');
const announceLayer = document.getElementById('announce-layer');
const motdLayer = document.getElementById('motd-layer');

let locale = {
    'notify.motd.dismiss': "Don't show again",
    'notify.motd.continue': 'Continue',
    'notify.announce.title': 'Announcement',
    'notify.announce.by': 'By {name}',
    'notify.announce.console': 'Console',
};

const DEFAULT_TYPE_ICON = {
    info: 'info',
    success: 'check',
    warning: 'alert-triangle',
    error: 'x',
};

let activeToasts = [];
let maxVisibleToasts = 4;
let defaultCorner = 'top-left';
let toastLayoutPlace = null;
let announceLayoutPlace = null;
let announceHideTimer = null;
let motdVisible = false;

function postCallback(name, payload) {
    fetch('https://aeterna_notify/' + name, {
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

function applyToastStackPosition() {
    toastStack.classList.remove('pos-top-left', 'pos-top-right', 'pos-bottom-left', 'pos-bottom-right', 'stack-up');
    if (toastLayoutPlace && typeof toastLayoutPlace === 'object') {
        const x = Number(toastLayoutPlace.x) || 0;
        const y = Number(toastLayoutPlace.y) || 0;
        const ax = Number(toastLayoutPlace.ax) || 0;
        const ay = Number(toastLayoutPlace.ay) || 0;
        const scale = Number(toastLayoutPlace.scale) || 1;
        toastStack.style.top = (y * 100) + '%';
        toastStack.style.left = (x * 100) + '%';
        toastStack.style.right = 'auto';
        toastStack.style.bottom = 'auto';
        toastStack.style.transformOrigin = (ax * 100) + '% ' + (ay * 100) + '%';
        toastStack.style.transform = 'translate(' + (-ax * 100) + '%, ' + (-ay * 100) + '%) scale(' + scale + ')';
        if (ay === 1) {
            toastStack.classList.add('stack-up');
        }
    } else {
        toastStack.style.top = '';
        toastStack.style.left = '';
        toastStack.style.right = '';
        toastStack.style.bottom = '';
        toastStack.style.transformOrigin = '';
        toastStack.style.transform = '';
        const corner = ['top-left', 'top-right', 'bottom-left', 'bottom-right'].includes(defaultCorner)
            ? defaultCorner
            : 'top-left';
        toastStack.classList.add('pos-' + corner);
    }
}

function applyAnnouncePosition() {
    announceLayer.classList.remove('pos-announce-default');
    if (announceLayoutPlace && typeof announceLayoutPlace === 'object') {
        const x = Number(announceLayoutPlace.x) || 0;
        const y = Number(announceLayoutPlace.y) || 0;
        const ax = Number(announceLayoutPlace.ax) || 0;
        const ay = Number(announceLayoutPlace.ay) || 0;
        const scale = Number(announceLayoutPlace.scale) || 1;
        announceLayer.style.top = (y * 100) + '%';
        announceLayer.style.left = (x * 100) + '%';
        announceLayer.style.right = 'auto';
        announceLayer.style.bottom = 'auto';
        announceLayer.style.transformOrigin = (ax * 100) + '% ' + (ay * 100) + '%';
        announceLayer.style.transform = 'translate(' + (-ax * 100) + '%, ' + (-ay * 100) + '%) scale(' + scale + ')';
    } else {
        announceLayer.style.top = '';
        announceLayer.style.left = '';
        announceLayer.style.right = '';
        announceLayer.style.bottom = '';
        announceLayer.style.transformOrigin = '';
        announceLayer.style.transform = '';
        announceLayer.classList.add('pos-announce-default');
    }
}

function populateToastNode(card, toast) {
    clearChildren(card);
    const kind = ['info', 'success', 'warning', 'error'].includes(toast.type) ? toast.type : 'info';
    card.className = 'toast-card toast-' + kind;

    const iconName = (toast.icon && window.AeternaNotifyIcons.has(toast.icon))
        ? toast.icon
        : DEFAULT_TYPE_ICON[kind];
    const iconWrap = document.createElement('span');
    iconWrap.className = 'toast-icon';
    const svg = window.AeternaNotifyIcons.create(iconName, 18);
    if (svg) iconWrap.appendChild(svg);
    card.appendChild(iconWrap);

    const content = document.createElement('div');
    content.className = 'toast-content';

    const titleEl = document.createElement('div');
    titleEl.className = 'toast-title';
    titleEl.textContent = String(toast.title || '');
    content.appendChild(titleEl);

    if (toast.description) {
        const descEl = document.createElement('div');
        descEl.className = 'toast-description';
        descEl.textContent = String(toast.description);
        content.appendChild(descEl);
    }

    card.appendChild(content);
}

function removeToastById(id) {
    for (let i = 0; i < activeToasts.length; i++) {
        if (activeToasts[i].id === id) {
            const entry = activeToasts[i];
            if (entry.timer) clearTimeout(entry.timer);
            if (entry.node && entry.node.parentNode) {
                entry.node.parentNode.removeChild(entry.node);
            }
            activeToasts.splice(i, 1);
            return;
        }
    }
}

function addOrReplaceToast(msg) {
    const toast = msg.toast;
    if (!toast || typeof toast !== 'object') return;
    if (typeof msg.max === 'number' && msg.max >= 1) {
        maxVisibleToasts = msg.max;
    }
    if (typeof msg.position === 'string') {
        defaultCorner = msg.position;
    }
    if (msg.place !== undefined) {
        toastLayoutPlace = msg.place;
    }
    applyToastStackPosition();

    const id = String(toast.id || ('t_' + Date.now()));
    const duration = Math.max(1000, Math.min(15000, Number(toast.duration) || 4000));

    for (let i = 0; i < activeToasts.length; i++) {
        if (activeToasts[i].id === id) {
            const existing = activeToasts[i];
            if (existing.timer) clearTimeout(existing.timer);
            populateToastNode(existing.node, toast);
            existing.timer = setTimeout(() => removeToastById(id), duration);
            return;
        }
    }

    const card = document.createElement('div');
    populateToastNode(card, toast);
    toastStack.appendChild(card);

    const timer = setTimeout(() => removeToastById(id), duration);
    activeToasts.push({ id, node: card, timer });

    while (activeToasts.length > maxVisibleToasts) {
        const oldest = activeToasts.shift();
        if (oldest.timer) clearTimeout(oldest.timer);
        if (oldest.node && oldest.node.parentNode) {
            oldest.node.parentNode.removeChild(oldest.node);
        }
    }
}

function clearToasts(id) {
    if (typeof id === 'string' && id !== '') {
        removeToastById(id);
        return;
    }
    for (let i = 0; i < activeToasts.length; i++) {
        if (activeToasts[i].timer) clearTimeout(activeToasts[i].timer);
    }
    activeToasts = [];
    clearChildren(toastStack);
}

function formatByText(by) {
    const tpl = String(locale['notify.announce.by'] || 'By {name}');
    if (tpl.includes('{name}')) {
        return tpl.replace('{name}', String(by));
    }
    return tpl + ' ' + String(by);
}

function showAnnouncement(msg) {
    const ann = msg.announce;
    if (!ann || typeof ann !== 'object') return;
    if (msg.place !== undefined) {
        announceLayoutPlace = msg.place;
    }
    applyAnnouncePosition();

    if (announceHideTimer) {
        clearTimeout(announceHideTimer);
        announceHideTimer = null;
    }
    clearChildren(announceLayer);

    const header = document.createElement('div');
    header.className = 'announce-header';

    const titleEl = document.createElement('div');
    titleEl.className = 'announce-title';
    titleEl.textContent = String(ann.title || locale['notify.announce.title'] || 'Announcement');
    header.appendChild(titleEl);

    if (ann.by) {
        const byEl = document.createElement('div');
        byEl.className = 'announce-by';
        byEl.textContent = formatByText(ann.by);
        header.appendChild(byEl);
    }

    announceLayer.appendChild(header);

    if (ann.body) {
        const bodyEl = document.createElement('div');
        bodyEl.className = 'announce-body';
        bodyEl.textContent = String(ann.body);
        announceLayer.appendChild(bodyEl);
    }

    announceLayer.classList.remove('hidden');

    const duration = Math.max(3000, Math.min(30000, Number(ann.duration) || 8000));
    announceHideTimer = setTimeout(() => {
        announceHideTimer = null;
        clearChildren(announceLayer);
        announceLayer.classList.add('hidden');
    }, duration);
}

function showMotd(motd) {
    if (!motd || typeof motd !== 'object') return;
    clearChildren(motdLayer);
    motdVisible = true;

    const card = document.createElement('div');
    card.className = 'motd-card';

    const header = document.createElement('div');
    header.className = 'motd-header';

    const titleGroup = document.createElement('div');
    titleGroup.className = 'motd-title-group';

    if (motd.eyebrow) {
        const eyeEl = document.createElement('div');
        eyeEl.className = 'motd-eyebrow';
        eyeEl.textContent = String(motd.eyebrow);
        titleGroup.appendChild(eyeEl);
    }

    const titleEl = document.createElement('h2');
    titleEl.className = 'motd-title';
    titleEl.textContent = String(motd.title || '');
    titleGroup.appendChild(titleEl);
    header.appendChild(titleGroup);

    const closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'close-btn';
    closeBtn.setAttribute('aria-label', String(locale['notify.motd.continue'] || 'Continue'));
    const xIcon = window.AeternaNotifyIcons.create('x', 16);
    if (xIcon) {
        closeBtn.appendChild(xIcon);
    } else {
        closeBtn.textContent = '×';
    }
    closeBtn.addEventListener('click', () => {
        hideMotd();
        postCallback('motdClose', { dismiss: false });
    });
    header.appendChild(closeBtn);
    card.appendChild(header);

    const linesWrap = document.createElement('div');
    linesWrap.className = 'motd-lines';
    const lines = Array.isArray(motd.lines) ? motd.lines : [];
    for (let i = 0; i < lines.length; i++) {
        const p = document.createElement('p');
        p.className = 'motd-line';
        p.textContent = String(lines[i] || '');
        linesWrap.appendChild(p);
    }
    card.appendChild(linesWrap);

    const actions = document.createElement('div');
    actions.className = 'motd-actions';

    const allowDismiss = !motd.buttons || motd.buttons.dismiss !== false;
    if (allowDismiss) {
        const dismissBtn = document.createElement('button');
        dismissBtn.type = 'button';
        dismissBtn.className = 'btn btn-secondary';
        dismissBtn.textContent = String(locale['notify.motd.dismiss'] || "Don't show again");
        dismissBtn.addEventListener('click', () => {
            hideMotd();
            postCallback('motdClose', { dismiss: true });
        });
        actions.appendChild(dismissBtn);
    }

    const continueBtn = document.createElement('button');
    continueBtn.type = 'button';
    continueBtn.className = 'btn btn-primary';
    continueBtn.textContent = String(locale['notify.motd.continue'] || 'Continue');
    continueBtn.addEventListener('click', () => {
        hideMotd();
        postCallback('motdClose', { dismiss: false });
    });
    actions.appendChild(continueBtn);

    card.appendChild(actions);
    motdLayer.appendChild(card);
    motdLayer.classList.remove('hidden');
    continueBtn.focus();
}

function hideMotd() {
    motdVisible = false;
    clearChildren(motdLayer);
    motdLayer.classList.add('hidden');
}

window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg.type !== 'string') return;

    if (msg.type === 'aeterna:theme') {
        applyThemeOverride(msg.href);
    } else if (msg.type === 'locale' && msg.strings && typeof msg.strings === 'object') {
        locale = { ...locale, ...msg.strings };
    } else if (msg.type === 'toast:add') {
        addOrReplaceToast(msg);
    } else if (msg.type === 'toast:clear') {
        clearToasts(msg.id);
    } else if (msg.type === 'announce:show') {
        showAnnouncement(msg);
    } else if (msg.type === 'motd:show' && msg.motd) {
        showMotd(msg.motd);
    } else if (msg.type === 'motd:hide') {
        hideMotd();
    } else if (msg.type === 'layout:apply') {
        if (typeof msg.position === 'string') {
            defaultCorner = msg.position;
        }
        if (msg.id === 'toasts') {
            toastLayoutPlace = msg.place || null;
            applyToastStackPosition();
        } else if (msg.id === 'announce') {
            announceLayoutPlace = msg.place || null;
            applyAnnouncePosition();
        }
    }
});

window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && motdVisible) {
        event.preventDefault();
        hideMotd();
        postCallback('escape', {});
    }
});
