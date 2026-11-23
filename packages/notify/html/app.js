// aeterna_notify NUI runtime — renders toasts (0.2: actions, x n count, lifetime bar), announcement and countdown
// banners, and the MOTD card. Uses textContent only (never innerHTML/outerHTML).

const toastStack = document.getElementById('toast-stack');
const announceLayer = document.getElementById('announce-layer');
const countdownLayer = document.getElementById('countdown-layer');
const motdLayer = document.getElementById('motd-layer');

const THEME_PRESETS = ['asphalt', 'paper', 'night-market'];

let locale = {
    'notify.motd.dismiss': "Don't show again",
    'notify.motd.continue': 'Continue',
    'notify.announce.title': 'Announcement',
    'notify.announce.by': 'By {name}',
    'notify.announce.console': 'Console',
    'notify.action.unbound': 'Unbound',
    'notify.countdown.title': 'Countdown',
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
let countdownState = null;

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

// The preset applies only when no owner theme file is set (aeterna_core spec, Theme preset).
function applyTheme(msg) {
    const href = msg.href;
    const hasHref = typeof href === 'string' && href.startsWith('nui://') && href.endsWith('.css');
    applyThemeOverride(href);
    if (!hasHref && THEME_PRESETS.includes(msg.preset)) {
        document.documentElement.setAttribute('data-preset', msg.preset);
    } else {
        document.documentElement.removeAttribute('data-preset');
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

function placeBanner(el) {
    el.classList.remove('pos-announce-default');
    if (announceLayoutPlace && typeof announceLayoutPlace === 'object') {
        const x = Number(announceLayoutPlace.x) || 0;
        const y = Number(announceLayoutPlace.y) || 0;
        const ax = Number(announceLayoutPlace.ax) || 0;
        const ay = Number(announceLayoutPlace.ay) || 0;
        const scale = Number(announceLayoutPlace.scale) || 1;
        el.style.top = (y * 100) + '%';
        el.style.left = (x * 100) + '%';
        el.style.right = 'auto';
        el.style.bottom = 'auto';
        el.style.transformOrigin = (ax * 100) + '% ' + (ay * 100) + '%';
        el.style.transform = 'translate(' + (-ax * 100) + '%, ' + (-ay * 100) + '%) scale(' + scale + ')';
    } else {
        el.style.top = '';
        el.style.left = '';
        el.style.right = '';
        el.style.bottom = '';
        el.style.transformOrigin = '';
        el.style.transform = '';
        el.classList.add('pos-announce-default');
    }
}

function applyAnnouncePosition() {
    placeBanner(announceLayer);
    placeBanner(countdownLayer);
}

function populateToastNode(card, toast, keys) {
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

    const titleRow = document.createElement('div');
    titleRow.className = 'toast-title-row';

    const titleEl = document.createElement('div');
    titleEl.className = 'toast-title';
    titleEl.textContent = String(toast.title || '');
    titleRow.appendChild(titleEl);

    const countEl = document.createElement('span');
    countEl.className = 'toast-count';
    titleRow.appendChild(countEl);
    content.appendChild(titleRow);

    if (toast.description) {
        const descEl = document.createElement('div');
        descEl.className = 'toast-description';
        descEl.textContent = String(toast.description);
        content.appendChild(descEl);
    }

    const actions = Array.isArray(toast.actions) ? toast.actions.slice(0, 2) : [];
    if (actions.length > 0) {
        const row = document.createElement('div');
        row.className = 'toast-actions';
        for (let i = 0; i < actions.length; i++) {
            const action = actions[i];
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'btn toast-action ' + (action.variant === 'primary' ? 'btn-primary' : 'btn-secondary');
            const label = document.createElement('span');
            label.textContent = String(action.label || '');
            btn.appendChild(label);
            const keyEl = document.createElement('span');
            keyEl.className = 'toast-key';
            const keyLabel = Array.isArray(keys) && typeof keys[i] === 'string' && keys[i] !== ''
                ? keys[i]
                : String(locale['notify.action.unbound'] || 'Unbound');
            keyEl.textContent = keyLabel;
            btn.appendChild(keyEl);
            const toastId = String(toast.toastId || '');
            const actionId = String(action.id || '');
            // The toast closes when Lua sends toast:clear after it checked the press.
            btn.addEventListener('click', () => {
                postCallback('toastAction', { toastId, action: actionId });
            });
            row.appendChild(btn);
        }
        content.appendChild(row);
    }

    card.appendChild(content);

    const life = document.createElement('div');
    life.className = 'toast-life';
    card.appendChild(life);
}

function setCount(entry, label) {
    const countEl = entry.node.querySelector('.toast-count');
    if (countEl) countEl.textContent = typeof label === 'string' ? label : '';
}

// Shrinks the bar from full to empty over `duration`; called again to restart it.
function startLifetime(entry) {
    const bar = entry.node.querySelector('.toast-life');
    if (!bar) return;
    if (!entry.lifetime) {
        bar.classList.add('hidden');
        return;
    }
    bar.classList.remove('hidden');
    bar.style.transition = 'none';
    bar.style.transform = 'scaleX(1)';
    void bar.offsetWidth;
    bar.style.transition = 'transform ' + entry.duration + 'ms linear';
    bar.style.transform = 'scaleX(0)';
}

function restartTimer(entry) {
    if (entry.timer) clearTimeout(entry.timer);
    entry.timer = setTimeout(() => removeToastById(entry.id), entry.duration);
    startLifetime(entry);
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
    const lifetime = msg.lifetime !== false;

    for (let i = 0; i < activeToasts.length; i++) {
        if (activeToasts[i].id === id) {
            const existing = activeToasts[i];
            populateToastNode(existing.node, toast, msg.keys);
            existing.duration = duration;
            existing.lifetime = lifetime;
            setCount(existing, toast.countLabel);
            restartTimer(existing);
            return;
        }
    }

    const card = document.createElement('div');
    populateToastNode(card, toast, msg.keys);
    toastStack.appendChild(card);

    const entry = { id, node: card, timer: null, duration, lifetime };
    activeToasts.push(entry);
    setCount(entry, toast.countLabel);
    restartTimer(entry);

    while (activeToasts.length > maxVisibleToasts) {
        const oldest = activeToasts.shift();
        if (oldest.timer) clearTimeout(oldest.timer);
        if (oldest.node && oldest.node.parentNode) {
            oldest.node.parentNode.removeChild(oldest.node);
        }
    }
}

// An identical toast arrived: show the count, keep the place, restart the timer and the bar.
function mergeToast(msg) {
    const id = String(msg.id || '');
    for (let i = 0; i < activeToasts.length; i++) {
        if (activeToasts[i].id === id) {
            setCount(activeToasts[i], msg.countLabel);
            restartTimer(activeToasts[i]);
            return;
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

function hideAnnouncementNow() {
    if (announceHideTimer) {
        clearTimeout(announceHideTimer);
        announceHideTimer = null;
    }
    clearChildren(announceLayer);
    announceLayer.classList.add('hidden');
}

function formatClock(ms) {
    const total = Math.ceil(Math.max(0, Number(ms) || 0) / 1000);
    const mm = Math.floor(total / 60);
    const ss = total % 60;
    return String(mm).padStart(2, '0') + ':' + String(ss).padStart(2, '0');
}

function hideCountdown() {
    if (countdownState) {
        if (countdownState.interval) clearInterval(countdownState.interval);
        if (countdownState.hideTimer) clearTimeout(countdownState.hideTimer);
    }
    countdownState = null;
    clearChildren(countdownLayer);
    countdownLayer.classList.add('hidden');
}

// Counts down locally from the remainingMs the server sent; the server is the clock that ends it.
function showCountdown(msg) {
    const cd = msg.countdown;
    if (!cd || typeof cd !== 'object') return;
    if (msg.place !== undefined) {
        announceLayoutPlace = msg.place;
    }
    hideCountdown();
    hideAnnouncementNow();
    applyAnnouncePosition();

    const header = document.createElement('div');
    header.className = 'announce-header';

    const titleEl = document.createElement('div');
    titleEl.className = 'announce-title';
    titleEl.textContent = String(cd.title || locale['notify.countdown.title'] || 'Countdown');
    header.appendChild(titleEl);

    const clockEl = document.createElement('div');
    clockEl.className = 'countdown-clock';
    header.appendChild(clockEl);
    countdownLayer.appendChild(header);

    if (cd.body) {
        const bodyEl = document.createElement('div');
        bodyEl.className = 'announce-body';
        bodyEl.textContent = String(cd.body);
        countdownLayer.appendChild(bodyEl);
    }

    if (cd.by) {
        const byEl = document.createElement('div');
        byEl.className = 'announce-by';
        byEl.textContent = formatByText(cd.by);
        countdownLayer.appendChild(byEl);
    }

    const remaining = Math.max(0, Number(cd.remainingMs) || 0);
    const showMs = Math.max(0, Math.min(remaining, Number(msg.showMs) || remaining));
    const startedAt = performance.now();
    const render = () => {
        const left = remaining - (performance.now() - startedAt);
        clockEl.textContent = formatClock(left);
    };
    render();
    countdownLayer.classList.remove('hidden');
    countdownState = {
        id: String(cd.countdownId || ''),
        interval: setInterval(render, 250),
        hideTimer: setTimeout(hideCountdown, showMs),
    };
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
            postCallback('motdClose', { dismiss: true });
        });
        actions.appendChild(dismissBtn);
    }

    const continueBtn = document.createElement('button');
    continueBtn.type = 'button';
    continueBtn.className = 'btn btn-primary';
    continueBtn.textContent = String(locale['notify.motd.continue'] || 'Continue');
    continueBtn.addEventListener('click', () => {
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
        applyTheme(msg);
    } else if (msg.type === 'locale' && msg.strings && typeof msg.strings === 'object') {
        locale = { ...locale, ...msg.strings };
    } else if (msg.type === 'toast:add') {
        addOrReplaceToast(msg);
    } else if (msg.type === 'toast:merge') {
        mergeToast(msg);
    } else if (msg.type === 'toast:clear') {
        clearToasts(msg.id);
    } else if (msg.type === 'announce:show') {
        showAnnouncement(msg);
    } else if (msg.type === 'countdown:show') {
        showCountdown(msg);
    } else if (msg.type === 'countdown:hide') {
        if (!countdownState || !msg.countdownId || countdownState.id === msg.countdownId) {
            hideCountdown();
        }
    } else if (msg.type === 'selftest:motion') {
        // the self-test forces the reduced-motion rules for its run (style.css / theme.css .reduce-motion)
        document.documentElement.classList.toggle('reduce-motion', msg.reduce === true);
    } else if (msg.type === 'settings') {
        document.documentElement.setAttribute('data-sound', msg.sound === true ? 'on' : 'off');
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
        postCallback('escape', {});
    }
});
