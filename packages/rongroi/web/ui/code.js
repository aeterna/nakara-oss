// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory(root);
    else (root.Rongroi = root.Rongroi || {}).screens = Object.assign(root.Rongroi.screens || {}, { code: factory(root) });
}(typeof globalThis !== 'undefined' ? globalThis : this, function (root) {
    'use strict';

    var THIN = '\u2009';
    var timer = null;

    function groupsOf(code) {
        var text = String(code || '').replace(/\s+/g, '');
        var groups = [];
        for (var i = 0; i < text.length; i += 4) groups.push(text.slice(i, i + 4));
        return groups;
    }

    function countdown(seconds) {
        var h = Math.floor(seconds / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        var s = seconds % 60;
        var tail = (m < 10 && h > 0 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
        return h > 0 ? h + ':' + tail : tail;
    }

    function viewModel(data, now) {
        var source = data && typeof data === 'object' ? data : {};
        var code = typeof source.code === 'string' ? source.code.replace(/\s+/g, '') : '';
        var expiresAt = Number(source.expiresAt);
        var clock = typeof now === 'number' && isFinite(now) ? now : 0;
        var hasExpiry = isFinite(expiresAt) && expiresAt > 0;
        var seconds = hasExpiry ? Math.max(0, Math.ceil((expiresAt - clock) / 1000)) : 0;
        var expired = code !== '' && hasExpiry && seconds <= 0;
        var groups = groupsOf(code);
        return {
            code: code,
            groups: groups,
            grouped: groups.join(THIN),
            empty: code === '',
            hasExpiry: hasExpiry,
            seconds: seconds,
            expired: expired,
            countdown: hasExpiry && !expired ? countdown(seconds) : '',
        };
    }

    function el(tag, className, value) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (value !== undefined) node.textContent = value;
        return node;
    }

    function expiryText(model, strings) {
        if (model.expired) return strings.expired || 'This code has expired.';
        return (strings.expiresIn || 'Expires in {time}').replace('{time}', model.countdown);
    }

    function stop() {
        if (timer !== null) {
            clearInterval(timer);
            timer = null;
        }
    }

    function render(root, data, strings) {
        stop();
        var model = viewModel(data, Date.now());
        var t = strings || {};
        root.textContent = '';
        root.appendChild(el('h1', '', t.title || 'Pairing code'));
        if (model.empty) {
            root.appendChild(el('p', 'empty', t.empty || 'No pairing code yet.'));
            root.appendChild(el('p', 'notice', t.onlyPaste || 'Only paste a code you got in this game.'));
            return;
        }
        root.appendChild(el('p', 'hint', t.hint || 'Paste this code into Rongroi Connect.'));
        var block = el('div', 'code' + (model.expired ? ' is-expired' : ''), model.grouped);
        block.setAttribute('role', 'textbox');
        block.setAttribute('aria-readonly', 'true');
        block.setAttribute('aria-label', t.title || 'Pairing code');
        block.tabIndex = 0;
        root.appendChild(block);
        var expiry = null;
        if (model.hasExpiry) {
            expiry = el('p', 'expiry' + (model.expired ? ' is-expired' : ''), expiryText(model, t));
            root.appendChild(expiry);
        }
        var actions = el('div', 'actions');
        var copy = el('button', 'copy', t.copy || 'Copy');
        copy.type = 'button';
        copy.disabled = model.expired;
        copy.addEventListener('click', function () {
            if (!navigator.clipboard || typeof navigator.clipboard.writeText !== 'function') {
                copy.textContent = t.copyFailed || 'Could not copy';
                return;
            }
            navigator.clipboard.writeText(model.code).then(function () {
                copy.textContent = t.copied || 'Copied';
                var shell = root.Rongroi && root.Rongroi.shell;
                if (shell && typeof shell.call === 'function') shell.call('copy', { code: model.code });
            }).catch(function () {
                copy.textContent = t.copyFailed || 'Could not copy';
            });
        });
        actions.appendChild(copy);
        root.appendChild(actions);
        root.appendChild(el('p', 'notice', t.onlyPaste || 'Only paste a code you got in this game.'));
        if (model.hasExpiry && !model.expired) {
            timer = setInterval(function () {
                var next = viewModel(data, Date.now());
                expiry.textContent = expiryText(next, t);
                expiry.className = 'expiry' + (next.expired ? ' is-expired' : '');
                block.className = 'code' + (next.expired ? ' is-expired' : '');
                if (next.expired) {
                    copy.disabled = true;
                    stop();
                }
            }, 1000);
        }
    }

    return { viewModel: viewModel, render: render, destroy: stop };
}));
