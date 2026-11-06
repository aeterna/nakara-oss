// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory();
    else (root.Rongroi = root.Rongroi || {}).screens = Object.assign(root.Rongroi.screens || {}, { cases: factory() });
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    'use strict';

    var CASE_STATE_KEYS = { opened: 'stateOpened', received: 'stateReceived', expired: 'stateExpired', declined: 'stateDeclined' };

    function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
    function member(value, name) { return isObject(value) && Object.prototype.hasOwnProperty.call(value, name) ? value[name] : null; }
    function textOf(value) { return value === null || value === undefined ? '' : String(value); }
    function setText(node, value) { node.textContent = textOf(value); return node; }

    function el(tag, className, value) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (value !== undefined) setText(node, value);
        return node;
    }

    function rowOf(entry) {
        var source = isObject(entry) ? entry : {};
        return {
            caseId: member(source, 'caseId'),
            openedBy: member(source, 'openedBy'),
            openedAt: member(source, 'openedAt'),
            state: member(source, 'state'),
            receivedAt: member(source, 'receivedAt'),
            origin: member(source, 'origin'),
        };
    }

    function viewModel(data) {
        var source = isObject(data) ? data : {};
        var list = Array.isArray(data) ? data : (Array.isArray(source.cases) ? source.cases : []);
        return { screen: 'cases', built: true, cases: list.map(rowOf) };
    }

    function stateWord(state, strings) {
        var key = CASE_STATE_KEYS[state];
        return key && strings[key] ? strings[key] : (strings.stateUnknown || 'Unknown');
    }

    function timeText(value) {
        if (value === null || value === undefined || value === '') return '';
        if (typeof value === 'number' && isFinite(value)) {
            var date = new Date(value);
            if (!isNaN(date.getTime())) return date.toISOString();
        }
        return String(value);
    }

    function metaText(row, strings) {
        var parts = [];
        if (row.openedBy !== null) parts.push((strings.listOpenedBy || 'Opened by') + ': ' + textOf(row.openedBy));
        if (row.openedAt !== null) parts.push((strings.listOpenedAt || 'Opened at') + ': ' + timeText(row.openedAt));
        if (row.receivedAt !== null) parts.push((strings.listReceivedAt || 'Received at') + ': ' + timeText(row.receivedAt));
        return parts.join(' · ');
    }

    function callShell(root, name, payload) {
        var doc = root && root.ownerDocument;
        var win = doc && doc.defaultView ? doc.defaultView : (typeof globalThis !== 'undefined' ? globalThis : null);
        var shell = win && win.Rongroi && win.Rongroi.shell;
        if (shell && typeof shell.call === 'function') shell.call(name, payload);
    }

    function render(root, data, strings) {
        var model = viewModel(data);
        var t = strings || {};
        setText(root, '');
        root.appendChild(el('h1', '', t.listTitle || 'Cases'));
        if (model.cases.length === 0) {
            root.appendChild(el('p', 'empty', t.listEmpty || 'No cases yet.'));
            return;
        }
        var list = el('ul', 'case-list');
        for (var i = 0; i < model.cases.length; i += 1) {
            var row = model.cases[i];
            var item = el('li', 'case-row');
            var button = el('button', 'case-row-open');
            button.type = 'button';
            var head = el('span', 'case-row-head');
            head.appendChild(el('span', 'case-row-id', textOf(row.caseId) || (t.caseUnknown || 'Unknown case')));
            head.appendChild(el('span', 'case-row-state', stateWord(row.state, t)));
            button.appendChild(head);
            button.appendChild(el('span', 'case-row-meta', metaText(row, t)));
            button.setAttribute('aria-label', (t.selectCase || 'Open case') + ' ' + textOf(row.caseId));
            button.addEventListener('click', function (row) {
                return function () { callShell(root, 'selectCase', { caseId: row.caseId }); };
            }(row));
            item.appendChild(button);
            list.appendChild(item);
        }
        root.appendChild(list);
    }

    return { viewModel: viewModel, render: render };
}));
