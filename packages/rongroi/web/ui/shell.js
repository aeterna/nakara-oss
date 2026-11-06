// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory(root);
    else factory(root);
}(typeof globalThis !== 'undefined' ? globalThis : this, function (root) {
    'use strict';

    var SCREENS = { code: true, cases: true, case: true, settings: true, policy: true, error: true };
    var app = typeof document === 'object' ? document.getElementById('app') : null;
    var screen = typeof document === 'object' ? document.getElementById('screen') : null;
    var active = null;
    var current = null;

    function language() {
        return /^th\b/i.test((typeof navigator === 'object' && navigator.language) || '') ? 'th' : 'en';
    }

    function strings(name) {
        var group = (root.Rongroi && root.Rongroi.strings && root.Rongroi.strings[name]) || {};
        var lang = language();
        return group[lang] || group.en || {};
    }

    function call(name, data) {
        if (typeof GetParentResourceName !== 'function') return Promise.resolve();
        return fetch(`https://${GetParentResourceName()}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data || {}),
        }).catch(function () {});
    }

    function stop() {
        if (current && typeof current.destroy === 'function') current.destroy();
        current = null;
    }

    function hide() {
        active = null;
        stop();
        if (screen) screen.textContent = '';
        if (app) app.hidden = true;
    }

    function el(tag, className, value) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (value !== undefined) node.textContent = value;
        return node;
    }

    function reasonText(t, data) {
        var code = data && typeof data.reason === 'string' ? data.reason : '';
        var reasons = t.reasons || strings('settings').reasons || {};
        if (code && Object.prototype.hasOwnProperty.call(reasons, code)) return reasons[code];
        return t.errorUnknown || 'Unknown error.';
    }

    function renderError(target, data) {
        var t = strings('error');
        target.appendChild(el('h1', '', t.errorTitle || 'Something went wrong'));
        target.appendChild(el('p', 'reason', reasonText(t, data)));
        var actions = el('div', 'actions');
        var back = el('button', 'button secondary', t.errorBack || t.back || 'Back');
        back.type = 'button';
        back.addEventListener('click', function () { call('back', {}); });
        actions.appendChild(back);
        target.appendChild(actions);
    }

    function show(message) {
        if (!message || !SCREENS[message.screen] || !app || !screen) return;
        active = message.screen;
        stop();
        screen.textContent = '';
        app.hidden = false;
        if (active === 'error') {
            renderError(screen, message.data);
            return;
        }
        current = (root.Rongroi && root.Rongroi.screens && root.Rongroi.screens[active]) || null;
        if (current && typeof current.render === 'function') {
            current.render(screen, message.data, strings(active));
            return;
        }
        var p = document.createElement('p');
        p.className = 'empty';
        p.textContent = 'Not built yet.';
        screen.appendChild(p);
    }

    if (typeof root.addEventListener === 'function') {
        root.addEventListener('message', function (event) {
            var message = event.data;
            if (!message || typeof message !== 'object') return;
            if (message.type === 'show') show(message);
            else if (message.type === 'hide') hide();
        });
    }

    if (typeof document === 'object' && typeof document.addEventListener === 'function') {
        document.addEventListener('keydown', function (event) {
            if (event.key !== 'Escape' || !active) return;
            event.preventDefault();
            hide();
            call('close', {});
        });
    }

    root.Rongroi = root.Rongroi || {};
    root.Rongroi.shell = { SCREENS: SCREENS, show: show, hide: hide, call: call };

    return { SCREENS: SCREENS, show: show, hide: hide, call: call };
}));
