// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
(function (root) {
    'use strict';

    var SCREENS = { code: true, cases: true, case: true, settings: true, policy: true, gate: true };
    var app = document.getElementById('app');
    var screen = document.getElementById('screen');
    if (!app || !screen) return;
    var active = null;
    var module = null;

    function strings(name) {
        var group = (root.Rongroi && root.Rongroi.strings && root.Rongroi.strings[name]) || {};
        var lang = /^th\b/i.test((typeof navigator === 'object' && navigator.language) || '') ? 'th' : 'en';
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
        if (module && typeof module.destroy === 'function') module.destroy();
        module = null;
    }

    function hide() {
        active = null;
        stop();
        screen.textContent = '';
        app.hidden = true;
    }

    function show(message) {
        if (!message || !SCREENS[message.screen]) return;
        active = message.screen;
        stop();
        screen.textContent = '';
        app.hidden = false;
        module = (root.Rongroi && root.Rongroi.screens && root.Rongroi.screens[active]) || null;
        if (module && typeof module.render === 'function') {
            module.render(screen, message.data, strings(active));
            return;
        }
        var p = document.createElement('p');
        p.className = 'empty';
        p.textContent = 'Not built yet.';
        screen.appendChild(p);
    }

    root.addEventListener('message', function (event) {
        var message = event.data;
        if (!message || typeof message !== 'object') return;
        if (message.type === 'show') show(message);
        else if (message.type === 'hide') hide();
    });

    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape' || !active) return;
        event.preventDefault();
        hide();
        call('close', {});
    });

    root.Rongroi = root.Rongroi || {};
    root.Rongroi.shell = { show: show, hide: hide, call: call };
}(typeof globalThis !== 'undefined' ? globalThis : this));
