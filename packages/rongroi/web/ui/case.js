// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
(function (root, factory) {
    'use strict';
    if (typeof module === 'object' && module.exports) module.exports = factory();
    else (root.Rongroi = root.Rongroi || {}).screens = Object.assign(root.Rongroi.screens || {}, { case: factory() });
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    'use strict';

    var THIN = '\u2009';
    var CASE_STATE_KEYS = { opened: 'stateOpened', received: 'stateReceived', expired: 'stateExpired', declined: 'stateDeclined' };
    var FINDING_STATE_KEYS = { found: 'findingFound', not_found: 'findingNotFound', unmeasured: 'findingUnmeasured', unknown: 'findingUnknown' };
    var ORIGIN_KEYS = { connect: 'originConnect', saved_file: 'originSavedFile' };

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

    function groupsOf(value) {
        var text = textOf(value).replace(/\s+/g, '');
        var groups = [];
        for (var i = 0; i < text.length; i += 4) groups.push(text.slice(i, i + 4));
        return groups;
    }

    function hashOf(source) {
        var raw = source.visualHash;
        if (!isObject(raw) && typeof raw !== 'string') raw = source.visual_hash;
        var recorded = typeof raw === 'string' ? raw : (isObject(raw) && typeof raw.recorded === 'string' ? raw.recorded : null);
        var recomputed = isObject(raw) && typeof raw.recomputed === 'string' ? raw.recomputed : null;
        var equal = isObject(raw) && typeof raw.equal === 'boolean' ? raw.equal : null;
        var groups = groupsOf(recorded);
        return { recorded: recorded, recomputed: recomputed, equal: equal, groups: groups, grouped: groups.join(THIN) };
    }

    function factsOf(source) {
        return {
            openedBy: member(source.facts, 'openedBy'),
            openedAt: member(source.facts, 'openedAt'),
            ticketState: member(source.facts, 'ticketState'),
            receivedAt: member(source.facts, 'receivedAt'),
            uploaderAddress: member(source.facts, 'uploaderAddress'),
            connectAddress: member(source.facts, 'connectAddress'),
        };
    }

    function selfAssertedOf(source) {
        return {
            official_build: member(source.selfAsserted, 'official_build'),
            producer: member(source.selfAsserted, 'producer'),
            rongroi_version: member(source.selfAsserted, 'rongroi_version'),
            issued_at: member(source.selfAsserted, 'issued_at'),
            expires_at: member(source.selfAsserted, 'expires_at'),
        };
    }

    function policyOf(source) {
        var collectors = member(source.policy, 'collectors');
        var elevation = member(source.policy, 'elevation');
        return {
            profile: member(source.policy, 'profile'),
            collectors: Array.isArray(collectors) ? collectors.slice() : [],
            elevation: typeof elevation === 'boolean' ? elevation : null,
            serverName: member(source.policy, 'serverName'),
        };
    }

    function viewModel(data) {
        var source = isObject(data) ? data : {};
        var envelopeCaseId = member(source, 'caseId');
        if (isObject(source.case)) source = source.case;
        var caseId = member(source, 'caseId');
        if (caseId === null) caseId = envelopeCaseId;
        return {
            screen: 'case',
            built: true,
            caseId: caseId,
            state: typeof source.state === 'string' ? source.state : 'unknown',
            origin: typeof source.origin === 'string' ? source.origin : 'connect',
            fixedLineKey: typeof source.fixedLineKey === 'string' ? source.fixedLineKey : 'rongroi.case.fixedLine',
            facts: factsOf(source),
            selfAsserted: selfAssertedOf(source),
            policy: policyOf(source),
            findings: Array.isArray(source.findings) ? source.findings.slice() : [],
            visualHash: hashOf(source),
        };
    }

    function callShell(root, name, payload) {
        var doc = root && root.ownerDocument;
        var win = doc && doc.defaultView ? doc.defaultView : (typeof globalThis !== 'undefined' ? globalThis : null);
        var shell = win && win.Rongroi && win.Rongroi.shell;
        if (shell && typeof shell.call === 'function') shell.call(name, payload);
    }

    function renderActions(root, model, strings) {
        var actions = el('div', 'form-actions');
        var back = el('button', 'button secondary', strings.back || 'Back');
        back.type = 'button';
        back.addEventListener('click', function () { callShell(root, 'back', {}); });
        actions.appendChild(back);

        var remove = el('button', 'button danger', strings.deleteCase || 'Delete case');
        remove.type = 'button';
        var confirm = null;
        function removeConfirm() {
            if (!confirm) return;
            if (confirm.parentNode) confirm.parentNode.removeChild(confirm);
            confirm = null;
        }
        remove.addEventListener('click', function () {
            if (confirm) return;
            confirm = el('div', 'confirm');
            confirm.appendChild(el('p', 'confirm-text',
                strings.deleteConfirmHint || 'This removes the case and its report. This cannot be undone.'));
            var yes = el('button', 'button danger', strings.deleteConfirm || 'Delete case');
            yes.type = 'button';
            yes.addEventListener('click', function () {
                callShell(root, 'deleteCase', { caseId: model.caseId });
                removeConfirm();
            });
            var no = el('button', 'button secondary', strings.deleteCancel || 'Cancel');
            no.type = 'button';
            no.addEventListener('click', removeConfirm);
            confirm.appendChild(yes);
            confirm.appendChild(no);
            root.appendChild(confirm);
        });
        actions.appendChild(remove);
        root.appendChild(actions);
    }

    function wordFor(table, name, strings, fallback) { var key = table[name]; return key && strings[key] ? strings[key] : fallback; }
    function caseState(model, strings) { return wordFor(CASE_STATE_KEYS, model.state, strings, strings.stateUnknown || 'Unknown'); }
    function findingState(state, strings) { var name = typeof state === 'string' ? state : 'unknown'; return wordFor(FINDING_STATE_KEYS, name, strings, strings.findingUnknown || 'Unknown'); }
    function originWord(model, strings) { var key = ORIGIN_KEYS[model.origin]; return key && strings[key] ? strings[key] : textOf(model.origin); }

    function hashFact(model, strings) {
        if (model.visualHash.equal === true) return strings.hashEqual || 'The recomputed hash equals the recorded value.';
        if (model.visualHash.equal === false) return strings.hashNotEqual || 'The recomputed hash does not equal the recorded value.';
        return strings.hashUnknown || 'The hash could not be compared.';
    }

    function timeText(value) {
        if (value === null || value === undefined || value === '') return '';
        if (typeof value === 'number' && isFinite(value)) {
            var date = new Date(value);
            if (!isNaN(date.getTime())) return date.toISOString();
        }
        return String(value);
    }

    function producerText(value) {
        if (typeof value === 'string') return value;
        if (!isObject(value)) return '';
        var parts = [];
        if (typeof value.name === 'string' && value.name) parts.push(value.name);
        if (typeof value.version === 'string' && value.version) parts.push(value.version);
        return parts.join(' ');
    }

    function yesNo(value, strings) {
        if (value === true) return strings.yes || 'Yes';
        if (value === false) return strings.no || 'No';
        return '';
    }

    function addFact(list, label, value) {
        list.appendChild(el('dt', '', label));
        list.appendChild(el('dd', '', value));
    }

    function section(title) {
        var node = el('section', 'case-section');
        node.appendChild(el('h2', '', title));
        return node;
    }

    function findingsTable(findings, strings) {
        var table = el('table', 'findings');
        var head = el('thead');
        var headRow = el('tr');
        var columns = [
            strings.columnRule || 'Rule', strings.columnCollector || 'Collector',
            strings.columnStrength || 'Strength', strings.columnState || 'State',
            strings.columnReason || 'Reason',
        ];
        for (var c = 0; c < columns.length; c += 1) {
            var th = el('th', '', columns[c]);
            th.scope = 'col';
            headRow.appendChild(th);
        }
        head.appendChild(headRow);
        table.appendChild(head);
        var body = el('tbody');
        for (var r = 0; r < findings.length; r += 1) {
            var row = findings[r];
            var cells = [
                textOf(member(row, 'rule_id')), textOf(member(row, 'collector')),
                textOf(member(row, 'strength')), findingState(member(row, 'state'), strings),
                textOf(member(row, 'reason')),
            ];
            var tr = el('tr');
            for (var i = 0; i < cells.length; i += 1) tr.appendChild(el('td', i === 3 ? 'cell-state' : '', cells[i]));
            body.appendChild(tr);
        }
        table.appendChild(body);
        return table;
    }

    function render(root, data, strings) {
        var model = viewModel(data);
        var t = strings || {};
        setText(root, '');
        root.appendChild(el('h1', '', t.title || 'Case'));
        var stateLine = el('p', 'case-state');
        setText(stateLine, (t.stateLabel || 'State') + ': ' + caseState(model, t));
        root.appendChild(stateLine);

        var hashSection = el('section', 'case-hash');
        var hash = el('div', 'visual-hash' + (model.visualHash.grouped ? '' : ' is-empty'),
            model.visualHash.grouped || (t.hashMissing || 'No hash recorded.'));
        hash.setAttribute('role', 'textbox');
        hash.setAttribute('aria-readonly', 'true');
        hash.setAttribute('aria-label', t.hashLabel || 'Visual hash');
        hash.tabIndex = 0;
        hashSection.appendChild(hash);
        hashSection.appendChild(el('p', 'hash-fact', hashFact(model, t)));
        hashSection.appendChild(el('p', 'fixed-line', t.fixedLine || 'This shows what was uploaded with this case\'s code.'));
        root.appendChild(hashSection);

        var factsSection = section(t.factsTitle || 'Facts');
        var facts = el('dl', 'fact-list');
        addFact(facts, t.openedBy || 'Opened by', textOf(model.facts.openedBy));
        addFact(facts, t.openedAt || 'Opened at', timeText(model.facts.openedAt));
        addFact(facts, t.ticketState || 'Ticket state', textOf(model.facts.ticketState));
        addFact(facts, t.receivedAt || 'Received at',
            model.facts.receivedAt === null ? (t.notYet || 'Not yet') : timeText(model.facts.receivedAt));
        addFact(facts, t.uploaderAddress || 'Uploader address', textOf(model.facts.uploaderAddress));
        addFact(facts, t.connectAddress || 'Connect address', textOf(model.facts.connectAddress));
        addFact(facts, t.originLabel || 'Origin', originWord(model, t));
        factsSection.appendChild(facts);
        root.appendChild(factsSection);

        var policySection = section(t.policyTitle || 'Policy');
        var policy = el('dl', 'fact-list');
        addFact(policy, t.profile || 'Profile', textOf(model.policy.profile));
        addFact(policy, t.collectors || 'Collectors', model.policy.collectors.join(', '));
        addFact(policy, t.elevation || 'Elevation', yesNo(model.policy.elevation, t));
        addFact(policy, t.serverName || 'Server name', textOf(model.policy.serverName));
        policySection.appendChild(policy);
        root.appendChild(policySection);

        var saysSection = section(t.reportSaysTitle || 'The report says');
        var says = el('dl', 'fact-list');
        addFact(says, t.officialBuild || 'Official build', yesNo(model.selfAsserted.official_build, t));
        addFact(says, t.producer || 'Producer', producerText(model.selfAsserted.producer));
        addFact(says, t.rongroiVersion || 'Rongroi version', textOf(model.selfAsserted.rongroi_version));
        addFact(says, t.issuedAt || 'Issued at', textOf(model.selfAsserted.issued_at));
        addFact(says, t.expiresAt || 'Expires at', textOf(model.selfAsserted.expires_at));
        saysSection.appendChild(says);
        root.appendChild(saysSection);

        var findingsSection = section(t.findingsTitle || 'Findings');
        if (model.findings.length === 0) findingsSection.appendChild(el('p', 'empty', t.findingsEmpty || 'No findings in this report.'));
        else findingsSection.appendChild(findingsTable(model.findings, t));
        root.appendChild(findingsSection);

        renderActions(root, model, t);
    }

    return { viewModel: viewModel, render: render };
}));
