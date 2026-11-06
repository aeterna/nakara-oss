// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory(root);
    else (root.Rongroi = root.Rongroi || {}).screens = Object.assign(root.Rongroi.screens || {}, { settings: factory(root) });
}(typeof globalThis !== 'undefined' ? globalThis : this, function (root) {
    'use strict';
    var BACKENDS = ['auto', 'kvp', 'file'];
    function isObject(value) {
        return value !== null && typeof value === 'object' && !Array.isArray(value);
    }
    function viewModel(data) {
        var source = isObject(data) ? data : {};
        var values = isObject(source.settings) ? source.settings
            : (isObject(source.values) ? source.values : source);
        var retention = typeof values.retentionDays === 'number' && isFinite(values.retentionDays)
            ? values.retentionDays : 30;
        var backend = BACKENDS.indexOf(values.backendOverride) !== -1 ? values.backendOverride : 'auto';
        return {
            screen: 'settings',
            fields: [
                { name: 'publicOrigin', type: 'text', value: typeof values.publicOrigin === 'string' ? values.publicOrigin : '' },
                { name: 'retentionDays', type: 'number', value: retention, min: 1, max: 365, step: 1 },
                { name: 'backendOverride', type: 'select', value: backend, options: BACKENDS.slice() },
                { name: 'uploadPageEnabled', type: 'toggle', value: values.uploadPageEnabled === true },
            ],
            rotation: {
                confirming: source.confirmRotation === true
                    || (isObject(source.rotation) && source.rotation.confirming === true),
            },
            reason: typeof source.reason === 'string' && source.reason.length > 0 ? source.reason : null,
            corrupt: Array.isArray(values.corrupt) ? values.corrupt.filter(function (name) {
                return typeof name === 'string';
            }) : [],
        };
    }
    function el(tag, className, value) {
        var node = document.createElement(tag);
        if (className) node.className = className;
        if (value !== undefined) node.textContent = value;
        return node;
    }
    function labelFor(strings, name) {
        return isObject(strings.fields) && typeof strings.fields[name] === 'string' ? strings.fields[name] : name;
    }
    function optionLabel(strings, field, option) {
        var group = isObject(strings.options) ? strings.options[field] : null;
        return isObject(group) && typeof group[option] === 'string' ? group[option] : option;
    }
    function reasonText(strings, code) {
        if (typeof code !== 'string') return '';
        var reasons = isObject(strings.reasons) ? strings.reasons : {};
        if (Object.prototype.hasOwnProperty.call(reasons, code)) return reasons[code];
        return typeof strings.unknownError === 'string' ? strings.unknownError : '';
    }
    function addField(form, field, strings) {
        var wrap = el('div', 'field field-' + field.name);
        var id = 'rongroi-settings-' + field.name;
        var control, label;
        if (field.type === 'toggle') {
            var row = el('div', 'toggle');
            control = el('input', 'toggle-input');
            control.type = 'checkbox';
            control.id = id;
            control.name = field.name;
            control.checked = field.value === true;
            label = el('label', 'toggle-label', labelFor(strings, field.name));
            label.htmlFor = id;
            row.appendChild(control);
            row.appendChild(label);
            wrap.appendChild(row);
        } else {
            label = el('label', 'field-label', labelFor(strings, field.name));
            label.htmlFor = id;
            wrap.appendChild(label);
            if (field.type === 'select') {
                control = el('select', 'control');
                control.id = id;
                control.name = field.name;
                field.options.forEach(function (option) {
                    var item = el('option', '', optionLabel(strings, field.name, option));
                    item.value = option;
                    if (option === field.value) item.selected = true;
                    control.appendChild(item);
                });
            } else {
                control = el('input', 'control');
                control.id = id;
                control.name = field.name;
                control.type = field.type === 'number' ? 'number' : 'text';
                control.value = String(field.value);
                if (field.type === 'number') {
                    control.min = String(field.min);
                    control.max = String(field.max);
                    control.step = String(field.step);
                }
            }
            wrap.appendChild(control);
        }
        form.appendChild(wrap);
    }
    function collect(form, model) {
        var patch = {};
        model.fields.forEach(function (field) {
            var node = form.elements[field.name];
            if (!node) return;
            if (field.type === 'toggle') {
                patch[field.name] = node.checked === true;
            } else if (field.type === 'number') {
                if (String(node.value).trim() === '') return;
                var number = Number(node.value);
                if (isFinite(number)) patch[field.name] = number;
            } else {
                patch[field.name] = node.value;
            }
        });
        return patch;
    }
    function call(name, data) {
        var shell = root && root.Rongroi && root.Rongroi.shell;
        if (shell && typeof shell.call === 'function') return shell.call(name, data);
        return Promise.resolve();
    }
    function addDeletePlayer(form, strings) {
        var wrap = el('div', 'field field-delete-player');
        var id = 'rongroi-settings-delete-identifier';
        var label = el('label', 'field-label', strings.deletePlayerLabel || 'Player identifier');
        label.htmlFor = id;
        var input = el('input', 'control');
        input.type = 'text';
        input.id = id;
        input.name = 'deleteIdentifier';
        wrap.appendChild(label);
        wrap.appendChild(input);
        var actions = el('div', 'form-actions');
        var button = el('button', 'button danger', strings.deletePlayer || 'Delete player data');
        button.type = 'button';
        var confirm = null;
        function removeConfirm() {
            if (!confirm) return;
            if (confirm.parentNode) confirm.parentNode.removeChild(confirm);
            confirm = null;
        }
        button.addEventListener('click', function () {
            if (confirm) return;
            var identifier = String(input.value).trim();
            if (identifier === '') return;
            confirm = el('div', 'confirm');
            confirm.appendChild(el('p', 'confirm-text',
                strings.deletePlayerConfirmHint || 'This removes every case and report for that player. This cannot be undone.'));
            var yes = el('button', 'button danger', strings.deletePlayerConfirm || 'Delete player data');
            yes.type = 'button';
            yes.addEventListener('click', function () {
                call('deletePlayer', { identifier: identifier });
                removeConfirm();
            });
            var no = el('button', 'button secondary', strings.deletePlayerCancel || 'Cancel');
            no.type = 'button';
            no.addEventListener('click', removeConfirm);
            confirm.appendChild(yes);
            confirm.appendChild(no);
            wrap.appendChild(confirm);
        });
        actions.appendChild(button);
        wrap.appendChild(actions);
        form.appendChild(wrap);
    }
    function render(target, data, strings) {
        var model = viewModel(data), t = isObject(strings) ? strings : {};
        target.textContent = '';
        target.appendChild(el('h1', '', t.title || 'Settings'));
        if (typeof t.hint === 'string' && t.hint.length > 0) target.appendChild(el('p', 'hint', t.hint));
        if (model.reason) target.appendChild(el('p', 'reason', reasonText(t, model.reason)));
        if (model.corrupt.length > 0 && typeof t.corrupt === 'string') {
            target.appendChild(el('p', 'notice', t.corrupt.replace('{count}', String(model.corrupt.length))));
        }
        var form = el('form', 'form settings-form');
        form.setAttribute('novalidate', 'novalidate');
        model.fields.forEach(function (field) { addField(form, field, t); });
        var confirm = null;
        function removeConfirm() {
            if (!confirm) return;
            if (confirm.parentNode) confirm.parentNode.removeChild(confirm);
            confirm = null;
        }
        function showConfirm() {
            if (confirm) return;
            confirm = el('div', 'confirm');
            confirm.appendChild(el('p', 'confirm-text', t.rotateConfirmHint || 'Open pairing codes stop working.'));
            var yes = el('button', 'button danger', t.rotateConfirm || 'Rotate key');
            yes.type = 'button';
            yes.addEventListener('click', function () { call('rotateKey', {}); removeConfirm(); });
            var no = el('button', 'button secondary', t.rotateCancel || 'Cancel');
            no.type = 'button';
            no.addEventListener('click', removeConfirm);
            confirm.appendChild(yes);
            confirm.appendChild(no);
            form.appendChild(confirm);
        }
        var actions = el('div', 'form-actions');
        var save = el('button', 'button primary', t.save || 'Save settings');
        save.type = 'submit';
        actions.appendChild(save);
        var rotate = el('button', 'button secondary', t.rotate || 'Rotate key');
        rotate.type = 'button';
        rotate.addEventListener('click', showConfirm);
        actions.appendChild(rotate);
        form.appendChild(actions);
        form.addEventListener('submit', function (event) {
            event.preventDefault();
            call('saveSettings', collect(form, model));
        });
        addDeletePlayer(form, t);
        target.appendChild(form);
        if (model.rotation.confirming) showConfirm();
    }
    return { viewModel: viewModel, render: render };
}));
