// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory(root);
    else (root.Rongroi = root.Rongroi || {}).screens = Object.assign(root.Rongroi.screens || {}, { policy: factory(root) });
}(typeof globalThis !== 'undefined' ? globalThis : this, function (root) {
    'use strict';
    var THIN = '\u2009', PROFILES = ['posture', 'standard', 'custom'];
    var POSTURE_COLLECTORS = ['posture', 'os_image', 'install_marker', 'defender_exclusion', 'net_config', 'driver_service'];
    var STANDARD_COLLECTORS = [
        'antivirus_product', 'autostart', 'bam', 'defender_exclusion', 'driver_service', 'event_fields',
        'evtx', 'fivem_dir', 'hid_device', 'install_marker', 'net_config', 'os_image', 'pca', 'pci_device',
        'posture', 'prefetch', 'process', 'userassist', 'usn', 'windows_start',
    ];
    function isObject(value) {
        return value !== null && typeof value === 'object' && !Array.isArray(value);
    }
    function uniqueStrings(values) {
        var seen = {};
        return values.filter(function (value) {
            if (typeof value !== 'string' || value.length === 0 || seen[value]) return false;
            seen[value] = true;
            return true;
        });
    }
    function collectorsOf(policy, profile) {
        var list = Array.isArray(policy.required_collectors) ? uniqueStrings(policy.required_collectors) : [];
        if (profile === 'custom') return list;
        if (list.length > 0) return list;
        return profile === 'posture' ? POSTURE_COLLECTORS.slice() : STANDARD_COLLECTORS.slice();
    }
    function hashOf(source, policy) {
        var candidates = [source.policy_hash, source.policyHash, policy.policy_hash];
        for (var i = 0; i < candidates.length; i += 1) {
            if (typeof candidates[i] === 'string' && candidates[i].length > 0) return candidates[i];
        }
        return '';
    }
    function groupsOf(value) {
        var text = String(value || '').replace(/\s+/g, ''), groups = [];
        for (var i = 0; i < text.length; i += 4) groups.push(text.slice(i, i + 4));
        return groups;
    }
    function viewModel(data) {
        var source = isObject(data) ? data : {};
        var policy = isObject(source.policy) ? source.policy : {};
        var profile = typeof policy.profile === 'string' && PROFILES.indexOf(policy.profile) !== -1
            ? policy.profile : 'posture';
        var required = collectorsOf(policy, profile);
        var selectedSet = {};
        required.forEach(function (id) { selectedSet[id] = true; });
        var known = Array.isArray(source.collectors) ? uniqueStrings(source.collectors) : STANDARD_COLLECTORS.slice();
        var seen = {}, ids = [];
        known.concat(required).forEach(function (id) {
            if (seen[id]) return;
            seen[id] = true;
            ids.push(id);
        });
        var serverName = typeof source.serverName === 'string' ? source.serverName
            : (typeof policy.server_name === 'string' ? policy.server_name : '');
        var hash = hashOf(source, policy);
        return {
            screen: 'policy',
            fields: [
                { name: 'profile', type: 'select', value: profile, options: PROFILES.slice() },
                { name: 'required_collectors', type: 'collectors', value: required.slice() },
                { name: 'require_elevation', type: 'toggle', value: policy.require_elevation === true },
                { name: 'serverName', type: 'text', value: serverName },
                { name: 'policy_hash', type: 'hash', value: hash },
            ],
            collectors: ids.map(function (id) {
                return { id: id, selected: selectedSet[id] === true, editable: profile === 'custom' };
            }),
            policyHash: hash,
            groupedHash: groupsOf(hash).join(THIN),
            reason: typeof source.reason === 'string' && source.reason.length > 0 ? source.reason : null,
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
    function addField(form, field, model, strings) {
        var wrap = el('div', 'field field-' + field.name);
        if (field.name === 'required_collectors') {
            wrap.appendChild(el('div', 'field-label', labelFor(strings, field.name)));
            var list = el('div', 'collectors' + (model.fields[0].value === 'custom' ? '' : ' is-disabled'));
            model.collectors.forEach(function (collector) {
                var row = el('label', 'collector');
                var check = el('input', 'collector-input');
                check.type = 'checkbox';
                check.name = 'collector';
                check.value = collector.id;
                check.checked = collector.selected === true;
                check.disabled = collector.editable !== true;
                row.appendChild(check);
                row.appendChild(el('span', 'collector-name', String(collector.id).replace(/_/g, ' ')));
                list.appendChild(row);
            });
            wrap.appendChild(list);
            form.appendChild(wrap);
            return;
        }
        if (field.name === 'policy_hash') {
            wrap.appendChild(el('div', 'field-label', labelFor(strings, field.name)));
            var hash = model.policyHash ? model.groupedHash : (strings.emptyHash || 'No policy hash yet.');
            wrap.appendChild(el('code', 'hash', hash));
            form.appendChild(wrap);
            return;
        }
        var id = 'rongroi-policy-' + field.name;
        if (field.type === 'toggle') {
            var row = el('div', 'toggle');
            var control = el('input', 'toggle-input');
            control.type = 'checkbox';
            control.id = id;
            control.name = field.name;
            control.checked = field.value === true;
            var label = el('label', 'toggle-label', labelFor(strings, field.name));
            label.htmlFor = id;
            row.appendChild(control);
            row.appendChild(label);
            wrap.appendChild(row);
        } else {
            var heading = el('label', 'field-label', labelFor(strings, field.name));
            heading.htmlFor = id;
            wrap.appendChild(heading);
            var input = el(field.type === 'select' ? 'select' : 'input', 'control');
            input.id = id;
            input.name = field.name;
            if (field.type === 'select') {
                field.options.forEach(function (option) {
                    var item = el('option', '', optionLabel(strings, field.name, option));
                    item.value = option;
                    if (option === field.value) item.selected = true;
                    input.appendChild(item);
                });
            } else {
                input.type = 'text';
                input.value = String(field.value);
            }
            wrap.appendChild(input);
        }
        form.appendChild(wrap);
    }
    function collect(form) {
        var profile = form.elements.profile ? form.elements.profile.value : 'posture';
        var policy = {
            profile: profile,
            require_elevation: form.elements.require_elevation
                ? form.elements.require_elevation.checked === true : false,
        };
        if (profile === 'custom') {
            policy.required_collectors = [];
            var inputs = form.querySelectorAll('input[name="collector"]');
            for (var i = 0; i < inputs.length; i += 1) {
                if (inputs[i].checked === true) policy.required_collectors.push(inputs[i].value);
            }
        }
        return { policy: policy, serverName: form.elements.serverName ? form.elements.serverName.value : '' };
    }
    function call(name, data) {
        var shell = root && root.Rongroi && root.Rongroi.shell;
        if (shell && typeof shell.call === 'function') return shell.call(name, data);
        return Promise.resolve();
    }
    function render(target, data, strings) {
        var model = viewModel(data), t = isObject(strings) ? strings : {};
        target.textContent = '';
        target.appendChild(el('h1', '', t.title || 'Policy'));
        if (typeof t.hint === 'string' && t.hint.length > 0) target.appendChild(el('p', 'hint', t.hint));
        if (model.reason) target.appendChild(el('p', 'reason', reasonText(t, model.reason)));
        var form = el('form', 'form policy-form');
        form.setAttribute('novalidate', 'novalidate');
        model.fields.forEach(function (field) { addField(form, field, model, t); });
        var profile = form.elements.profile;
        var list = form.querySelector('.collectors');
        if (profile && list) {
            profile.addEventListener('change', function () {
                var custom = profile.value === 'custom';
                list.className = 'collectors' + (custom ? '' : ' is-disabled');
                var inputs = form.querySelectorAll('input[name="collector"]');
                for (var i = 0; i < inputs.length; i += 1) inputs[i].disabled = !custom;
            });
        }
        var actions = el('div', 'form-actions');
        var save = el('button', 'button primary', t.save || 'Save policy');
        save.type = 'submit';
        actions.appendChild(save);
        form.appendChild(actions);
        form.addEventListener('submit', function (event) {
            event.preventDefault();
            call('savePolicy', collect(form));
        });
        target.appendChild(form);
    }
    return { viewModel: viewModel, render: render };
}));
