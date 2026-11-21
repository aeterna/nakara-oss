// app.js -- aeterna_phonekit NUI application.
// Text rendered strictly with textContent; SVG nodes constructed through DOM.
// Plain JavaScript without external dependencies. Chrome 103: no :has(), no container queries.
// 0.2: model frames, lock screen, control centre, cover screen, two panes, keypad models, the exit contract.

(function () {
    'use strict';

    const DL = window.DeviceLayout;

    const rootEl = document.getElementById('phonekit-root');
    const frameEl = document.getElementById('phone-frame');
    const glassEl = document.getElementById('phone-glass');
    const statusEl = document.getElementById('phone-status');
    const contentEl = document.getElementById('pane-main');
    const leftPaneEl = document.getElementById('pane-left');
    const timeEl = document.getElementById('phone-time');
    const liveEl = document.getElementById('phone-live');
    const batteryEl = document.getElementById('phone-battery');
    const batteryFillEl = document.getElementById('phone-battery-fill');
    const batteryPctEl = document.getElementById('phone-battery-pct');
    const batteryChargeEl = document.getElementById('phone-battery-charge');
    const bannerEl = document.getElementById('phone-banner');
    const lockEl = document.getElementById('phone-lock');
    const ccEl = document.getElementById('phone-cc');
    const coverEl = document.getElementById('phone-cover');
    const ringEl = document.getElementById('phone-ring');
    const homeBarEl = document.getElementById('phone-bottom-bar');
    const homeBtn = document.getElementById('phone-home-btn');
    const keysEl = document.getElementById('phone-keys');
    const hardKbEl = document.getElementById('phone-hardkb');

    let locales = {};
    let currentSettings = {
        textSize: 'normal',
        clock24: true,
        hasLayout: false,
    };
    let currentApps = [];
    let enabledBuiltins = { calculator: true, notes: true, contacts: true, settings: true };
    let badges = {};
    let notesData = [];
    let contactsData = [];
    let currentIntents = {};

    // 0.2 shell state
    let device = { model: DL.DEFAULT_MODEL, label: '', fold: null, voice: true, color: null, devices: [], cover: true };
    let battery = { none: true };
    let liveState = null;
    let historyEntries = [];
    let historySeenAt = 0;
    let lockEnabled = false;
    let itemMode = false;
    let locked = false;
    let ccOpen = false;
    let ring = null;
    let pendingCoverApp = null;
    let closeKeyCode = null;
    let paused = false;
    let lastPlace = null;
    let lastPosition = 'bottom-right';
    let keypadIndex = 1;
    let keypadRows = [];
    let calcKeyHandler = null;
    let typingReported = false;

    // Navigation state
    // 'home' | 'calculator' | 'notes' | 'note_edit' | 'contacts' | 'contact_edit' | 'settings' | 'custom_app'
    let currentView = 'home';
    let currentAppId = null;
    let activeEditingNote = null;
    let activeEditingContact = null;
    let activeNoteInputs = null;
    let activeContactInputs = null;

    // App screens from the server, oldest first (the server keeps the same stack, up to 8).
    // entry = { screenId, id, spec: { title, subtitle, blocks, detailOf, detailItem }, values, node, tab }
    let appStack = [];

    function saveCurrentNote() {
        if (!activeNoteInputs || !activeEditingNote) return;
        const note = activeEditingNote;
        const isNew = !note.id;
        const cleanTitle = activeNoteInputs.title.value.trim().substring(0, 60);
        const cleanBody = activeNoteInputs.body.value.trim().substring(0, 2000);

        activeEditingNote = null;
        activeNoteInputs = null;

        if (!cleanTitle && !cleanBody) {
            if (!isNew) {
                const candidate = notesData.filter((n) => n.id !== note.id);
                postNui('builtin:save', { app: 'notes', data: candidate }).then((resp) => {
                    if (resp && resp.ok && resp.list) {
                        notesData = resp.list;
                    } else if (resp && resp.err) {
                        showBanner({ title: resp.err });
                    }
                    if (currentView === 'notes') renderNotesList();
                });
            }
            return;
        }

        const updatedNote = {
            id: note.id || ('n' + Date.now().toString(36)),
            title: cleanTitle || 'Untitled',
            body: cleanBody,
            updatedAt: Math.floor(Date.now() / 1000),
        };

        let updatedList = [];
        let found = false;
        for (let i = 0; i < notesData.length; i++) {
            if (notesData[i].id === updatedNote.id) {
                updatedList.push(updatedNote);
                found = true;
            } else {
                updatedList.push(notesData[i]);
            }
        }
        if (!found) {
            updatedList.unshift(updatedNote);
        }

        postNui('builtin:save', { app: 'notes', data: updatedList }).then((resp) => {
            if (resp && resp.ok && resp.list) {
                notesData = resp.list;
            } else if (resp && resp.err) {
                showBanner({ title: resp.err });
            }
            if (currentView === 'notes') renderNotesList();
        });
    }

    function saveCurrentContact() {
        if (!activeContactInputs || !activeEditingContact) return;
        const contact = activeEditingContact;
        const isNew = !contact.id;
        const cleanName = activeContactInputs.name.value.trim().substring(0, 40);
        const cleanNum = activeContactInputs.number.value.trim().substring(0, 20);

        activeEditingContact = null;
        activeContactInputs = null;

        if (!cleanName && !cleanNum) {
            if (!isNew) {
                const candidate = contactsData.filter((c) => c.id !== contact.id);
                postNui('builtin:save', { app: 'contacts', data: candidate }).then((resp) => {
                    if (resp && resp.ok && resp.list) {
                        contactsData = resp.list;
                    } else if (resp && resp.err) {
                        showBanner({ title: resp.err });
                    }
                    if (currentView === 'contacts') renderContactsList();
                });
            }
            return;
        }

        const updatedContact = {
            id: contact.id || ('c' + Date.now().toString(36)),
            name: cleanName || 'Unnamed',
            number: cleanNum,
        };

        let updatedList = [];
        let found = false;
        for (let i = 0; i < contactsData.length; i++) {
            if (contactsData[i].id === updatedContact.id) {
                updatedList.push(updatedContact);
                found = true;
            } else {
                updatedList.push(contactsData[i]);
            }
        }
        if (!found) {
            updatedList.push(updatedContact);
        }

        postNui('builtin:save', { app: 'contacts', data: updatedList }).then((resp) => {
            if (resp && resp.ok && resp.list) {
                contactsData = resp.list;
            } else if (resp && resp.err) {
                showBanner({ title: resp.err });
            }
            if (currentView === 'contacts') renderContactsList();
        });
    }

    let bannerTimeout = null;
    let clockInterval = null;

    // Helper: NUI callback POST. Resolves to the callback's JSON answer, or null.
    function postNui(event, data) {
        const resource = window.GetParentResourceName ? window.GetParentResourceName() : 'aeterna_phonekit';
        return fetch(`https://${resource}/${event}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).then((resp) => resp.json()).catch(() => null);
    }

    // Helper: Translate locale key
    function t(key, vars) {
        let str = locales[key] || key;
        if (vars) {
            str = str.replace(/\{([A-Za-z0-9_]+)\}/g, (m, k) => (vars[k] !== undefined ? String(vars[k]) : m));
        }
        return str;
    }

    function el(tag, className, text) {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined && text !== null) node.textContent = String(text);
        return node;
    }

    function icon(name, size) {
        return window.PhonekitIcons ? window.PhonekitIcons.create(name, size) : null;
    }

    function emptyNode(node) {
        while (node && node.firstChild) node.removeChild(node.firstChild);
    }

    function isKeypadModel() {
        return DL.isKeypad(device.model);
    }

    let baseServerSeconds = null;
    let baseTimestamp = null;
    let serverDate = null;

    function setServerTime(timeData) {
        if (timeData && typeof timeData.hour === 'number') {
            const h = Number(timeData.hour) || 0;
            const m = Number(timeData.min !== undefined ? timeData.min : timeData.minute) || 0;
            const s = Number(timeData.sec !== undefined ? timeData.sec : timeData.second) || 0;
            baseServerSeconds = ((h * 3600 + m * 60 + s) % 86400 + 86400) % 86400;
            baseTimestamp = Date.now();
            if (typeof timeData.day === 'number' && typeof timeData.month === 'number') {
                serverDate = { day: timeData.day, month: timeData.month };
            }
        }
    }

    function clockText() {
        let hours = 0;
        let minutes = 0;
        if (baseServerSeconds !== null && baseTimestamp !== null) {
            const elapsed = Math.floor((Date.now() - baseTimestamp) / 1000);
            const totalSec = ((baseServerSeconds + elapsed) % 86400 + 86400) % 86400;
            hours = Math.floor(totalSec / 3600);
            minutes = Math.floor((totalSec % 3600) / 60);
        } else {
            const now = new Date();
            hours = now.getHours();
            minutes = now.getMinutes();
        }
        const minStr = String(minutes).padStart(2, '0');
        if (currentSettings.clock24) {
            return `${String(hours).padStart(2, '0')}:${minStr}`;
        }
        const ampm = hours >= 12 ? 'PM' : 'AM';
        let h12 = hours % 12;
        if (h12 === 0) h12 = 12;
        return `${h12}:${minStr} ${ampm}`;
    }

    function dateText() {
        if (serverDate) {
            return `${String(serverDate.day).padStart(2, '0')}/${String(serverDate.month).padStart(2, '0')}`;
        }
        const now = new Date();
        return `${String(now.getDate()).padStart(2, '0')}/${String(now.getMonth() + 1).padStart(2, '0')}`;
    }

    // Update every clock on the phone (status bar, lock screen, cover)
    function updateClock() {
        const txt = clockText();
        if (timeEl) timeEl.textContent = txt;
        document.querySelectorAll('[data-clock]').forEach((node) => { node.textContent = txt; });
        document.querySelectorAll('[data-date]').forEach((node) => { node.textContent = dateText(); });
    }

    function startClock() {
        updateClock();
        if (clockInterval) clearInterval(clockInterval);
        clockInterval = setInterval(updateClock, 1000);
    }

    // Frame size of the held model and fold, its own clamp, and the drawn scale (fit x layout scale).
    function applyPlacement(place, position) {
        if (place !== undefined) lastPlace = place;
        if (position) lastPosition = position;
        const dims = DL.getDimensions(device.model, device.fold);
        frameEl.style.width = `${dims.width}px`;
        frameEl.style.height = `${dims.height}px`;
        const rect = DL.frameRect(lastPlace, lastPosition, dims.width, dims.height, window.innerWidth, window.innerHeight);
        frameEl.style.left = `${rect.x}px`;
        frameEl.style.top = `${rect.y}px`;
        frameEl.style.right = 'auto';
        frameEl.style.bottom = 'auto';
        frameEl.style.transform = `scale(${rect.scale})`;
        frameEl.style.transformOrigin = 'top left';
    }

    // Apply text size setting
    function applySettings(settings) {
        if (settings.textSize === 'large') {
            frameEl.classList.add('phone-large-text');
        } else {
            frameEl.classList.remove('phone-large-text');
        }
        updateClock();
    }

    // Clear the main pane (app screens from the server stay alive in appStack)
    function clearContent() {
        emptyNode(contentEl);
        emptyNode(leftPaneEl);
        leftPaneEl.classList.add('hidden');
        frameEl.classList.remove('two-pane');
    }

    // -------------------------------------------------------------
    // Banner Notification inside phone
    // -------------------------------------------------------------
    function showBanner(banner) {
        if (!bannerEl) return;
        if (bannerTimeout) {
            clearTimeout(bannerTimeout);
            bannerTimeout = null;
        }
        emptyNode(bannerEl);

        const iconBox = el('div', 'phone-banner-icon');
        const iconSvg = icon('bell', 16);
        if (iconSvg) iconBox.appendChild(iconSvg);

        const textBox = el('div', 'phone-banner-text');
        textBox.appendChild(el('div', 'phone-banner-title', banner.title || ''));
        if (banner.body) {
            textBox.appendChild(el('div', 'phone-banner-body', banner.body));
        }

        bannerEl.appendChild(iconBox);
        bannerEl.appendChild(textBox);
        bannerEl.classList.remove('hidden');

        bannerEl.onclick = () => {
            bannerEl.classList.add('hidden');
            if (bannerTimeout) clearTimeout(bannerTimeout);
        };

        bannerTimeout = setTimeout(() => {
            bannerEl.classList.add('hidden');
            bannerTimeout = null;
        }, 4000);
    }

    // -------------------------------------------------------------
    // Navigation
    // -------------------------------------------------------------
    function leaveApp() {
        const top = appStack[appStack.length - 1];
        appStack = [];
        if (top) {
            postNui('action', { screenId: top.screenId, action: '__close', values: {} });
        }
    }

    function goHome() {
        if (currentView === 'note_edit') saveCurrentNote();
        if (currentView === 'contact_edit') saveCurrentContact();
        if (currentView === 'custom_app') leaveApp();
        renderHomeScreen();
    }

    function goBack() {
        if (currentView === 'note_edit') {
            saveCurrentNote();
            renderNotesList();
        } else if (currentView === 'contact_edit') {
            saveCurrentContact();
            renderContactsList();
        } else if (currentView === 'custom_app') {
            const top = appStack[appStack.length - 1];
            if (top && appStack.length > 1) {
                // The server pops its stack and sends the screen under it again (kept here, never rebuilt).
                postNui('back', { screenId: top.screenId });
            } else {
                if (top) postNui('back', { screenId: top.screenId });
                appStack = [];
                renderHomeScreen();
            }
        } else if (currentView === 'calculator' || currentView === 'notes' || currentView === 'contacts' || currentView === 'settings') {
            renderHomeScreen();
        } else if (currentView === 'home') {
            postNui('close', {});
        }
    }

    // -------------------------------------------------------------
    // View: Home Screen (tile grid pages, or a numbered list on keypad models)
    // -------------------------------------------------------------
    function homeTiles() {
        const builtinsList = [
            { id: 'calculator', label: t('phonekit.app.calculator'), icon: 'calculator', order: 10 },
            { id: 'notes', label: t('phonekit.app.notes'), icon: 'file-text', order: 20 },
            { id: 'contacts', label: t('phonekit.app.contacts'), icon: 'users', order: 30 },
            { id: 'settings', label: t('phonekit.app.settings'), icon: 'settings', order: 40 },
        ];
        const allTiles = [];
        builtinsList.forEach((b) => {
            if (b.id === 'settings' || enabledBuiltins[b.id] !== false) {
                allTiles.push({ isBuiltin: true, id: b.id, label: b.label, icon: b.icon, order: b.order });
            }
        });
        currentApps.forEach((a) => {
            if (a.needs === 'voice' && !DL.canMakeCalls(device.model)) return;
            allTiles.push({ isBuiltin: false, owner: a.owner, id: a.id, label: a.label, icon: a.icon, order: Number(a.order) || 100 });
        });
        allTiles.sort((a, b) => {
            if (a.order !== b.order) return a.order - b.order;
            return a.id.localeCompare(b.id);
        });
        return allTiles;
    }

    function openTile(tileData) {
        if (tileData.isBuiltin) {
            if (tileData.id === 'calculator') renderCalculator();
            else if (tileData.id === 'notes') renderNotesList();
            else if (tileData.id === 'contacts') renderContactsList();
            else if (tileData.id === 'settings') renderSettings();
            postNui('tap', { id: tileData.id, owner: '' });
        } else {
            postNui('tap', { id: tileData.id, owner: tileData.owner });
        }
    }

    function badgeOf(id) {
        return Number(badges[id]) || 0;
    }

    function badgeText(count) {
        return count > 99 ? '99+' : String(count);
    }

    function renderHomeScreen() {
        currentView = 'home';
        currentAppId = null;
        calcKeyHandler = null;
        clearContent();

        const tiles = homeTiles();
        if (isKeypadModel()) {
            renderKeypadHome(tiles);
            return;
        }

        const perPage = DL.getTilesPerPage(device.model, device.fold) || 12;
        const pagesEl = el('div', 'home-pages');
        pagesEl.style.setProperty('--per-page', String(perPage));
        let page = null;
        tiles.forEach((tileData, i) => {
            if (i % perPage === 0) {
                page = el('div', 'home-screen');
                pagesEl.appendChild(page);
            }
            const tileBtn = el('button', 'app-tile');
            tileBtn.type = 'button';
            tileBtn.setAttribute('aria-label', tileData.label);

            const iconBox = el('div', 'app-icon-box');
            const iconSvg = icon(tileData.icon, 24);
            if (iconSvg) iconBox.appendChild(iconSvg);

            const count = badgeOf(tileData.id);
            if (count > 0) iconBox.appendChild(el('div', 'app-badge', badgeText(count)));

            tileBtn.appendChild(iconBox);
            tileBtn.appendChild(el('div', 'app-label', tileData.label));
            tileBtn.addEventListener('click', () => { if (!paused) openTile(tileData); });
            page.appendChild(tileBtn);
        });
        contentEl.appendChild(pagesEl);
    }

    function renderKeypadHome(tiles) {
        keypadRows = tiles;
        if (keypadIndex > tiles.length || keypadIndex < 1) keypadIndex = tiles.length > 0 ? 1 : 0;
        const list = el('ol', 'keypad-list');
        tiles.forEach((tileData, i) => {
            const row = el('li', 'keypad-row' + (i + 1 === keypadIndex ? ' is-active' : ''));
            row.appendChild(el('span', 'keypad-row-num', i + 1 === 10 ? '0' : String(i + 1)));
            row.appendChild(el('span', 'keypad-row-label', tileData.label));
            const count = badgeOf(tileData.id);
            if (count > 0) row.appendChild(el('span', 'keypad-row-badge', badgeText(count)));
            row.addEventListener('click', () => { if (!paused) openTile(tileData); });
            list.appendChild(row);
        });
        contentEl.appendChild(list);
    }

    function keypadHomeKey(key) {
        const res = DL.keypadMove(keypadIndex, keypadRows.length, key);
        keypadIndex = res.index;
        if (res.open) {
            openTile(keypadRows[res.open - 1]);
        } else {
            renderHomeScreen();
        }
    }

    // -------------------------------------------------------------
    // View: Calculator App
    // -------------------------------------------------------------
    function renderCalculator() {
        currentView = 'calculator';
        currentAppId = 'calculator';
        clearContent();

        const screen = document.createElement('div');
        screen.className = 'app-screen';

        const header = createHeader(t('phonekit.app.calculator'), null, () => goBack());
        screen.appendChild(header);

        const calcBody = document.createElement('div');
        calcBody.className = 'calc-screen';

        const display = document.createElement('div');
        display.className = 'calc-display';
        display.textContent = '0';
        calcBody.appendChild(display);

        const grid = document.createElement('div');
        grid.className = 'calc-grid';

        let acc = null;
        let op = null;
        let newNum = true;
        let isError = false;

        function formatResult(num) {
            if (typeof num !== 'number' || isNaN(num) || !isFinite(num)) return 'Error';
            if (num === 0) return '0';
            const s = Number(num.toPrecision(10)).toString();
            return s === '-0' ? '0' : s;
        }

        function operate(a, operator, b) {
            if (operator === '+') return a + b;
            if (operator === '-') return a - b;
            if (operator === '*' || operator === '×') return a * b;
            if (operator === '/' || operator === '÷') {
                if (b === 0) return null;
                return a / b;
            }
            return null;
        }

        function handleInput(key) {
            if (isError) {
                if (key === 'C' || key === 'AC' || /^\d$/.test(key)) {
                    isError = false;
                    display.textContent = /^\d$/.test(key) ? key : '0';
                    acc = null;
                    op = null;
                    newNum = /^\d$/.test(key) ? false : true;
                }
                return;
            }

            if (key === 'AC' || key === 'C') {
                if (key === 'C' && !newNum && display.textContent !== '0') {
                    display.textContent = '0';
                    newNum = true;
                } else {
                    display.textContent = '0';
                    acc = null;
                    op = null;
                    newNum = true;
                }
            } else if (/^\d$/.test(key)) {
                if (newNum) {
                    display.textContent = key;
                    newNum = false;
                } else {
                    if (display.textContent === '0') {
                        display.textContent = key;
                    } else if (display.textContent.length < 14) {
                        display.textContent += key;
                    }
                }
            } else if (key === '.') {
                if (newNum) {
                    display.textContent = '0.';
                    newNum = false;
                } else if (!display.textContent.includes('.')) {
                    display.textContent += '.';
                }
            } else if (key === '+/-') {
                const n = Number(display.textContent) || 0;
                display.textContent = formatResult(-n);
            } else if (key === '%') {
                const n = Number(display.textContent) || 0;
                let pct = n / 100;
                if (acc !== null && (op === '+' || op === '-')) {
                    pct = acc * (n / 100);
                }
                display.textContent = formatResult(pct);
            } else if (['+', '-', '×', '÷'].includes(key)) {
                const currentVal = Number(display.textContent) || 0;
                if (acc !== null && !newNum && op !== null) {
                    const res = operate(acc, op, currentVal);
                    if (res === null) {
                        isError = true;
                        display.textContent = 'Error';
                        acc = null;
                        op = null;
                        newNum = true;
                        return;
                    }
                    acc = res;
                    display.textContent = formatResult(res);
                } else {
                    acc = currentVal;
                }
                op = key;
                newNum = true;
            } else if (key === '=') {
                if (op !== null && acc !== null) {
                    const currentVal = Number(display.textContent) || 0;
                    const res = operate(acc, op, currentVal);
                    if (res === null) {
                        isError = true;
                        display.textContent = 'Error';
                    } else {
                        display.textContent = formatResult(res);
                    }
                    acc = null;
                    op = null;
                    newNum = true;
                }
            }
        }

        calcKeyHandler = handleInput;

        const buttons = [
            { k: 'AC', cls: 'calc-btn-fn' },
            { k: '+/-', cls: 'calc-btn-fn' },
            { k: '%', cls: 'calc-btn-fn' },
            { k: '÷', cls: 'calc-btn-op' },
            { k: '7' }, { k: '8' }, { k: '9' },
            { k: '×', cls: 'calc-btn-op' },
            { k: '4' }, { k: '5' }, { k: '6' },
            { k: '-', cls: 'calc-btn-op' },
            { k: '1' }, { k: '2' }, { k: '3' },
            { k: '+', cls: 'calc-btn-op' },
            { k: '0', cls: 'calc-btn-span2' },
            { k: '.' },
            { k: '=', cls: 'calc-btn-op' },
        ];

        for (let i = 0; i < buttons.length; i++) {
            const b = buttons[i];
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'calc-btn' + (b.cls ? ' ' + b.cls : '');
            btn.textContent = b.k;
            btn.addEventListener('click', () => handleInput(b.k));
            grid.appendChild(btn);
        }

        calcBody.appendChild(grid);
        screen.appendChild(calcBody);
        contentEl.appendChild(screen);
    }
    // -------------------------------------------------------------
    // View: Notes App
    // -------------------------------------------------------------
    function renderNotesList() {
        currentView = 'notes';
        currentAppId = 'notes';
        activeEditingNote = null;
        clearContent();

        const screen = document.createElement('div');
        screen.className = 'app-screen';

        const header = createHeader(t('phonekit.app.notes'), null, () => goBack());
        const newBtn = document.createElement('button');
        newBtn.type = 'button';
        newBtn.className = 'app-header-action';
        newBtn.textContent = '+';
        newBtn.setAttribute('aria-label', t('phonekit.notes.new'));
        newBtn.addEventListener('click', () => {
            if (notesData.length >= 50) {
                showBanner({ title: t('phonekit.notes.full') });
                return;
            }
            renderNoteEditor({ id: '', title: '', body: '' });
        });
        header.appendChild(newBtn);
        screen.appendChild(header);

        const body = document.createElement('div');
        body.className = 'app-body';

        if (!notesData || notesData.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'list-empty';
            empty.textContent = t('phonekit.notes.empty');
            body.appendChild(empty);
        } else {
            const stack = document.createElement('div');
            stack.className = 'items-stack';

            for (let i = 0; i < notesData.length; i++) {
                const note = notesData[i];
                const item = document.createElement('div');
                item.className = 'note-item';

                const title = document.createElement('div');
                title.className = 'note-item-title';
                title.textContent = note.title || t('phonekit.notes.new');

                const bodyPreview = document.createElement('div');
                bodyPreview.className = 'note-item-body';
                bodyPreview.textContent = note.body || '';

                item.appendChild(title);
                item.appendChild(bodyPreview);

                item.addEventListener('click', () => {
                    renderNoteEditor(note);
                });

                stack.appendChild(item);
            }
            body.appendChild(stack);
        }

        screen.appendChild(body);
        contentEl.appendChild(screen);
    }

    function renderNoteEditor(note) {
        currentView = 'note_edit';
        activeEditingNote = note;
        clearContent();

        const isNew = !note.id;
        const screen = document.createElement('div');
        screen.className = 'app-screen';

        const header = createHeader(isNew ? t('phonekit.notes.new') : t('phonekit.app.notes'), null, () => {
            goBack();
        });
        screen.appendChild(header);

        const body = document.createElement('div');
        body.className = 'app-body';

        const form = document.createElement('div');
        form.className = 'editor-form';

        const titleInput = document.createElement('input');
        titleInput.type = 'text';
        titleInput.className = 'input-field';
        titleInput.placeholder = t('phonekit.notes.new');
        titleInput.maxLength = 60;
        titleInput.value = note.title || '';

        const bodyInput = document.createElement('textarea');
        bodyInput.className = 'textarea-field';
        bodyInput.placeholder = '...';
        bodyInput.maxLength = 2000;
        bodyInput.value = note.body || '';

        activeNoteInputs = { title: titleInput, body: bodyInput };

        form.appendChild(titleInput);
        form.appendChild(bodyInput);

        if (!isNew) {
            const deleteBtn = document.createElement('button');
            deleteBtn.type = 'button';
            deleteBtn.className = 'btn-danger-outline';
            deleteBtn.textContent = t('phonekit.notes.delete');
            deleteBtn.addEventListener('click', () => {
                activeEditingNote = null;
                activeNoteInputs = null;
                const candidate = notesData.filter((n) => n.id !== note.id);
                postNui('builtin:save', { app: 'notes', data: candidate }).then((resp) => {
                    if (resp && resp.ok && resp.list) {
                        notesData = resp.list;
                    } else if (resp && resp.err) {
                        showBanner({ title: resp.err });
                    }
                    if (currentView === 'notes') renderNotesList();
                });
                renderNotesList();
            });
            form.appendChild(deleteBtn);
        }

        body.appendChild(form);
        screen.appendChild(body);
        contentEl.appendChild(screen);
    }

    // -------------------------------------------------------------
    // View: Contacts App
    // -------------------------------------------------------------
    function renderContactsList() {
        currentView = 'contacts';
        currentAppId = 'contacts';
        activeEditingContact = null;
        clearContent();

        const screen = document.createElement('div');
        screen.className = 'app-screen';

        const header = createHeader(t('phonekit.app.contacts'), null, () => goBack());
        const newBtn = document.createElement('button');
        newBtn.type = 'button';
        newBtn.className = 'app-header-action';
        newBtn.textContent = '+';
        newBtn.setAttribute('aria-label', t('phonekit.contacts.new'));
        newBtn.addEventListener('click', () => {
            if (contactsData.length >= 100) {
                showBanner({ title: t('phonekit.contacts.full') });
                return;
            }
            renderContactEditor({ id: '', name: '', number: '' });
        });
        header.appendChild(newBtn);
        screen.appendChild(header);

        const body = document.createElement('div');
        body.className = 'app-body';

        if (!contactsData || contactsData.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'list-empty';
            empty.textContent = t('phonekit.contacts.empty');
            body.appendChild(empty);
        } else {
            const stack = document.createElement('div');
            stack.className = 'items-stack';

            const sorted = [...contactsData].sort((a, b) => a.name.localeCompare(b.name));

            for (let i = 0; i < sorted.length; i++) {
                const contact = sorted[i];
                const item = document.createElement('div');
                item.className = 'contact-item';

                const name = document.createElement('div');
                name.className = 'contact-item-name';
                name.textContent = contact.name || t('phonekit.contacts.new');

                const num = document.createElement('div');
                num.className = 'contact-item-number';
                num.textContent = contact.number || '';

                item.appendChild(name);
                item.appendChild(num);

                item.addEventListener('click', () => {
                    renderContactEditor(contact);
                });

                stack.appendChild(item);
            }
            body.appendChild(stack);
        }

        screen.appendChild(body);
        contentEl.appendChild(screen);
    }

    function renderContactEditor(contact) {
        currentView = 'contact_edit';
        activeEditingContact = contact;
        clearContent();

        const isNew = !contact.id;
        const screen = document.createElement('div');
        screen.className = 'app-screen';

        const header = createHeader(isNew ? t('phonekit.contacts.new') : t('phonekit.app.contacts'), null, () => {
            goBack();
        });
        screen.appendChild(header);

        const body = document.createElement('div');
        body.className = 'app-body';

        const form = document.createElement('div');
        form.className = 'editor-form';

        const nameInput = document.createElement('input');
        nameInput.type = 'text';
        nameInput.className = 'input-field';
        nameInput.placeholder = t('phonekit.contacts.new');
        nameInput.maxLength = 40;
        nameInput.value = contact.name || '';

        const numInput = document.createElement('input');
        numInput.type = 'text';
        numInput.className = 'input-field';
        numInput.placeholder = '555-0199';
        numInput.maxLength = 20;
        numInput.value = contact.number || '';

        activeContactInputs = { name: nameInput, number: numInput };

        form.appendChild(nameInput);
        form.appendChild(numInput);

        // 0.2 contact intents: Call / Message only when a started app handles that kind.
        if (!isNew && contact.number) {
            const intentRow = document.createElement('div');
            intentRow.className = 'block-buttons-row';
            [['tel', 'phonekit.contacts.call', 'phone'], ['sms', 'phonekit.contacts.message', 'message-circle']].forEach((it) => {
                const handler = currentIntents[it[0]];
                if (!handler || !handler.id) return;
                const btn = document.createElement('button');
                btn.type = 'button';
                btn.className = 'uikit-btn uikit-btn-secondary';
                const icon = window.PhonekitIcons ? window.PhonekitIcons.create(it[2], 14) : null;
                if (icon) btn.appendChild(icon);
                const lbl = document.createElement('span');
                lbl.textContent = t(it[1]);
                btn.appendChild(lbl);
                btn.addEventListener('click', () => {
                    postNui('tap', { id: handler.id, owner: handler.owner, intent: { kind: it[0], number: contact.number } });
                });
                intentRow.appendChild(btn);
            });
            if (intentRow.firstChild) form.appendChild(intentRow);
        }

        if (!isNew) {
            const deleteBtn = document.createElement('button');
            deleteBtn.type = 'button';
            deleteBtn.className = 'btn-danger-outline';
            deleteBtn.textContent = t('phonekit.contacts.delete');
            deleteBtn.addEventListener('click', () => {
                activeEditingContact = null;
                activeContactInputs = null;
                const candidate = contactsData.filter((c) => c.id !== contact.id);
                postNui('builtin:save', { app: 'contacts', data: candidate }).then((resp) => {
                    if (resp && resp.ok && resp.list) {
                        contactsData = resp.list;
                    } else if (resp && resp.err) {
                        showBanner({ title: resp.err });
                    }
                    if (currentView === 'contacts') renderContactsList();
                });
                renderContactsList();
            });
            form.appendChild(deleteBtn);
        }

        body.appendChild(form);
        screen.appendChild(body);
        contentEl.appendChild(screen);
    }

    // -------------------------------------------------------------
    // Settings rows (Settings app and control centre write the same KVP keys)
    // -------------------------------------------------------------
    function buildSettingsRows(body) {
        const textSection = el('div', 'settings-section');
        const textRow = el('div', 'settings-row');
        textRow.appendChild(el('span', 'settings-label', t('phonekit.settings.textSize')));
        const textSegment = el('div', 'segment-control');
        const sizes = [['normal', 'phonekit.settings.normal'], ['large', 'phonekit.settings.large']];
        const segButtons = [];
        sizes.forEach((sz) => {
            const btn = el('button', 'segment-btn' + (currentSettings.textSize === sz[0] ? ' active' : ''), t(sz[1]));
            btn.type = 'button';
            btn.addEventListener('click', () => {
                if (paused) return;
                currentSettings.textSize = sz[0];
                segButtons.forEach((b) => b.classList.remove('active'));
                btn.classList.add('active');
                applySettings(currentSettings);
                postNui('settings', { key: 'textSize', value: sz[0] });
            });
            segButtons.push(btn);
            textSegment.appendChild(btn);
        });
        textRow.appendChild(textSegment);
        textSection.appendChild(textRow);
        body.appendChild(textSection);

        const clockSection = el('div', 'settings-section');
        const clockRow = el('div', 'settings-row');
        clockRow.appendChild(el('span', 'settings-label', t('phonekit.settings.clock24')));
        const switchLabel = el('label', 'toggle-switch');
        const switchInput = document.createElement('input');
        switchInput.type = 'checkbox';
        switchInput.checked = currentSettings.clock24;
        switchInput.setAttribute('aria-label', t('phonekit.settings.clock24'));
        switchInput.addEventListener('change', () => {
            if (paused) { switchInput.checked = currentSettings.clock24; return; }
            currentSettings.clock24 = switchInput.checked;
            updateClock();
            postNui('settings', { key: 'clock24', value: switchInput.checked });
        });
        switchLabel.appendChild(switchInput);
        switchLabel.appendChild(el('span', 'toggle-slider'));
        clockRow.appendChild(switchLabel);
        clockSection.appendChild(clockRow);
        body.appendChild(clockSection);

        // Edit layout (shown only when layout resource is active)
        if (currentSettings.hasLayout) {
            const layoutSection = el('div', 'settings-section');
            const layoutBtn = el('button', 'btn-settings-action');
            layoutBtn.type = 'button';
            const sliderIcon = icon('sliders', 16);
            if (sliderIcon) layoutBtn.appendChild(sliderIcon);
            layoutBtn.appendChild(el('span', null, t('phonekit.settings.layout')));
            layoutBtn.addEventListener('click', () => {
                if (!paused) postNui('settings', { key: 'layout', value: true });
            });
            layoutSection.appendChild(layoutBtn);
            body.appendChild(layoutSection);
        }
    }

    // -------------------------------------------------------------
    // View: Settings App
    // -------------------------------------------------------------
    function renderSettings() {
        currentView = 'settings';
        currentAppId = 'settings';
        calcKeyHandler = null;
        clearContent();

        const screen = el('div', 'app-screen');
        screen.appendChild(createHeader(t('phonekit.app.settings'), null, () => goBack()));
        const body = el('div', 'app-body');
        buildSettingsRows(body);
        screen.appendChild(body);
        contentEl.appendChild(screen);
    }

    // -------------------------------------------------------------
    // View: App screens from the server (showApp), one or two panes
    // -------------------------------------------------------------
    function postAction(entry, action) {
        if (paused) return;
        postNui('action', { screenId: entry.screenId, action, values: entry.values });
    }

    function buildEntryNode(entry) {
        const spec = entry.spec;
        const screen = el('div', 'app-screen');
        screen.setAttribute('data-screen-id', entry.screenId);
        screen.appendChild(createHeader(spec.title, spec.subtitle, () => {
            if (paused) return;
            const top = appStack[appStack.length - 1];
            if (top && top.screenId === entry.screenId) {
                goBack();
            } else {
                // Back on the list pane while a detail sits beside it: close the detail pane.
                if (top) postNui('back', { screenId: top.screenId });
            }
        }));
        const body = el('div', 'app-body');
        const tabsBlock = (spec.blocks || []).find((b) => b && b.type === 'tabs');
        if (tabsBlock && entry.values[tabsBlock.id] === undefined) {
            entry.values[tabsBlock.id] = tabsBlock.value;
        }
        (spec.blocks || []).forEach((b) => {
            const blockEl = createSpecBlock(b, entry);
            if (!blockEl) return;
            if (b.tab) {
                blockEl.setAttribute('data-tab', b.tab);
                if (tabsBlock && entry.values[tabsBlock.id] !== b.tab) blockEl.classList.add('hidden');
            }
            body.appendChild(blockEl);
        });
        screen.appendChild(body);
        entry.node = screen;
        return screen;
    }

    function setPicked(entry, itemId) {
        if (!entry || !entry.node) return;
        entry.node.querySelectorAll('.is-picked').forEach((n) => n.classList.remove('is-picked'));
        if (!itemId) return;
        entry.node.querySelectorAll('[data-item-id]').forEach((n) => {
            if (n.getAttribute('data-item-id') === itemId) n.classList.add('is-picked');
        });
    }

    // Draws the stack in one or two panes. Moving nodes between panes keeps fields; the top screen stays put.
    function layoutPanes() {
        currentView = 'custom_app';
        calcKeyHandler = null;
        const panes = DL.panesFor(appStack, device.model, device.fold);
        const main = appStack[panes.main];
        if (!main) return;
        if (contentEl.firstChild !== main.node || contentEl.childNodes.length !== 1) {
            emptyNode(contentEl);
            contentEl.appendChild(main.node);
        }
        currentAppId = main.id;
        if (panes.left !== undefined) {
            const left = appStack[panes.left];
            if (leftPaneEl.firstChild !== left.node) {
                emptyNode(leftPaneEl);
                leftPaneEl.appendChild(left.node);
            }
            setPicked(left, panes.highlight);
            leftPaneEl.classList.remove('hidden');
            frameEl.classList.add('two-pane');
        } else {
            emptyNode(leftPaneEl);
            leftPaneEl.classList.add('hidden');
            frameEl.classList.remove('two-pane');
        }
    }

    function showAppScreen(data) {
        const existing = appStack.findIndex((e) => e.screenId === data.screenId);
        if (existing >= 0) {
            // Back: the screen is still alive here, never shown again from scratch.
            appStack.length = existing + 1;
        } else {
            const top = appStack[appStack.length - 1];
            if (top && top.id !== data.id) appStack = [];
            const spec = {
                title: data.title, subtitle: data.subtitle, blocks: data.blocks || [],
                detailOf: data.detailOf, detailItem: data.detailItem,
            };
            const under = appStack[appStack.length - 2];
            const top2 = appStack[appStack.length - 1];
            if (spec.detailOf && top2 && top2.spec.detailOf && under && DL.hasDetailTarget(under.spec, spec.detailOf)
                && !DL.hasDetailTarget(top2.spec, spec.detailOf)) {
                appStack.pop();
            }
            const entry = { screenId: data.screenId, id: data.id, spec, values: {} };
            buildEntryNode(entry);
            appStack.push(entry);
            if (appStack.length > 8) appStack.shift();
        }
        layoutPanes();
    }

    function updateAppScreen(screenId, patch) {
        const entry = appStack.find((e) => e.screenId === screenId);
        if (!entry || !patch || !patch.blocks) return;
        Object.keys(patch.blocks).forEach((blockId) => {
            const partial = patch.blocks[blockId];
            if (partial.value !== undefined) entry.values[blockId] = partial.value;
            const b = entry.spec.blocks.find((x) => x.id === blockId);
            if (b) Object.assign(b, partial);
        });
        const old = entry.node;
        const scroll = old ? (old.querySelector('.app-body') || {}).scrollTop : 0;
        buildEntryNode(entry);
        if (old && old.parentNode) old.parentNode.replaceChild(entry.node, old);
        const body = entry.node.querySelector('.app-body');
        if (body && scroll) body.scrollTop = scroll;
        layoutPanes();
    }

    function renderEmptyState(e, extraBtn) {
        const box = el('div', 'block-empty');
        if (e.icon) {
            const ic = icon(e.icon, 24);
            if (ic) box.appendChild(ic);
        }
        box.appendChild(el('div', 'block-empty-label', e.label || ''));
        if (e.body) box.appendChild(el('div', 'block-empty-body', e.body));
        if (extraBtn) box.appendChild(extraBtn);
        return box;
    }

    function createSpecBlock(b, entry) {
        if (!b) return null;
        const values = entry.values;

        if (b.type === 'text') {
            return el('p', 'block-text', b.label || '');
        }

        if (b.type === 'divider') {
            return el('div', 'block-divider');
        }

        if (b.type === 'progress') {
            const box = el('div', 'block-progress-box');
            const head = el('div', 'block-progress-head');
            head.appendChild(el('span', null, b.label || ''));
            head.appendChild(el('span', null, Math.round((b.value || 0) * 100) + '%'));
            const track = el('div', 'block-progress-track');
            const fill = el('div', 'block-progress-fill');
            fill.style.width = Math.max(0, Math.min(100, (b.value || 0) * 100)) + '%';
            track.appendChild(fill);
            box.appendChild(head);
            box.appendChild(track);
            return box;
        }

        if (b.type === 'field') {
            const box = el('div', 'block-field');
            box.appendChild(el('label', 'block-field-label', b.label || ''));
            const inp = document.createElement('input');
            inp.type = b.input === 'number' ? 'number' : 'text';
            inp.className = 'input-field';
            if (b.placeholder) inp.placeholder = b.placeholder;
            if (b.maxLen) inp.maxLength = b.maxLen;
            if (b.disabled) inp.disabled = true;
            const existingVal = values[b.id] !== undefined ? values[b.id] : b.value;
            if (existingVal !== undefined && existingVal !== null) inp.value = existingVal;
            const sync = () => {
                if (b.input === 'number') {
                    if (inp.value.trim() !== '' && !isNaN(Number(inp.value))) {
                        values[b.id] = Number(inp.value);
                    } else {
                        delete values[b.id];
                    }
                } else {
                    values[b.id] = inp.value;
                }
            };
            sync();
            inp.addEventListener('input', sync);
            box.appendChild(inp);
            return box;
        }

        if (b.type === 'toggle') {
            const row = el('div', 'settings-row');
            row.appendChild(el('span', 'settings-label', b.label || ''));
            const switchLabel = el('label', 'toggle-switch');
            const switchInput = document.createElement('input');
            switchInput.type = 'checkbox';
            const existingVal = values[b.id] !== undefined ? values[b.id] : b.value;
            switchInput.checked = existingVal === true;
            if (b.disabled) switchInput.disabled = true;
            values[b.id] = switchInput.checked;
            switchInput.addEventListener('change', () => { values[b.id] = switchInput.checked; });
            switchLabel.appendChild(switchInput);
            switchLabel.appendChild(el('span', 'toggle-slider'));
            row.appendChild(switchLabel);
            return row;
        }

        if (b.type === 'select') {
            const box = el('div', 'block-field');
            box.appendChild(el('label', 'block-field-label', b.label || ''));
            const select = el('select', 'input-field');
            if (b.disabled) select.disabled = true;
            const existingVal = values[b.id] !== undefined ? values[b.id] : b.value;
            (b.options || []).forEach((opt) => {
                const optEl = el('option', null, opt.label);
                optEl.value = opt.id;
                if (opt.id === existingVal) optEl.selected = true;
                select.appendChild(optEl);
            });
            values[b.id] = select.value;
            select.addEventListener('change', () => { values[b.id] = select.value; });
            box.appendChild(select);
            return box;
        }

        if (b.type === 'slider') {
            const box = el('div', 'block-field block-slider');
            const head = el('div', 'block-progress-head');
            head.appendChild(el('span', null, b.label || ''));
            const valueEl = el('span', 'block-slider-value');
            head.appendChild(valueEl);
            const inp = document.createElement('input');
            inp.type = 'range';
            inp.className = 'slider-input';
            inp.min = String(b.min);
            inp.max = String(b.max);
            inp.step = String(b.step);
            inp.setAttribute('aria-label', b.label || '');
            if (b.disabled) inp.disabled = true;
            const start = values[b.id] !== undefined ? values[b.id] : b.value;
            inp.value = String(start);
            const sync = () => {
                values[b.id] = Number(inp.value);
                valueEl.textContent = inp.value + (b.unit ? ` ${b.unit}` : '');
            };
            sync();
            inp.addEventListener('input', sync);
            box.appendChild(head);
            box.appendChild(inp);
            return box;
        }

        if (b.type === 'tabs') {
            const bar = el('div', 'block-tabs');
            bar.setAttribute('role', 'tablist');
            (b.items || []).forEach((it) => {
                const tab = el('button', 'block-tab' + (values[b.id] === it.id ? ' active' : ''));
                tab.type = 'button';
                tab.setAttribute('role', 'tab');
                if (it.icon) {
                    const ic = icon(it.icon, 14);
                    if (ic) tab.appendChild(ic);
                }
                tab.appendChild(el('span', null, it.label));
                tab.addEventListener('click', () => {
                    if (paused) return;
                    values[b.id] = it.id;
                    bar.querySelectorAll('.block-tab').forEach((n) => n.classList.remove('active'));
                    tab.classList.add('active');
                    if (entry.node) {
                        entry.node.querySelectorAll('[data-tab]').forEach((n) => {
                            n.classList.toggle('hidden', n.getAttribute('data-tab') !== it.id);
                        });
                    }
                    if (b.report) postAction(entry, it.id);
                });
                bar.appendChild(tab);
            });
            return bar;
        }

        if (b.type === 'table') {
            const box = el('div', 'block-table');
            const rows = b.rows || [];
            if (rows.length === 0) {
                if (b.empty) box.appendChild(renderEmptyState(b.empty));
                return box;
            }
            const table = el('table', 'block-table-grid');
            const thead = el('thead');
            const hr = el('tr');
            (b.columns || []).forEach((c) => {
                const th = el('th', c.align === 'end' ? 'align-end' : null, c.label);
                hr.appendChild(th);
            });
            thead.appendChild(hr);
            table.appendChild(thead);
            const tbody = el('tbody');
            rows.forEach((r) => {
                const tr = el('tr', (b.selectable ? 'is-selectable' : '') + (r.disabled ? ' disabled' : ''));
                tr.setAttribute('data-item-id', r.id);
                (b.columns || []).forEach((c) => {
                    tr.appendChild(el('td', c.align === 'end' ? 'align-end' : null, (r.cells && r.cells[c.id]) || ''));
                });
                if (b.selectable && !r.disabled) {
                    tr.tabIndex = 0;
                    tr.addEventListener('click', () => postAction(entry, r.id));
                }
                tbody.appendChild(tr);
            });
            table.appendChild(tbody);
            box.appendChild(table);
            return box;
        }

        if (b.type === 'empty') {
            let btn = null;
            if (b.action) {
                btn = el('button', 'uikit-btn uikit-btn-secondary', b.action.label);
                btn.type = 'button';
                btn.addEventListener('click', () => postAction(entry, b.action.id));
            }
            return renderEmptyState(b, btn);
        }

        if (b.type === 'list') {
            const listContainer = el('div', 'uikit-list-box');
            if (b.label) listContainer.appendChild(el('div', 'block-field-label', b.label));
            const itemsBox = el('div', 'uikit-list-items');
            const items = b.items || [];
            const emptyNodeEl = b.empty ? renderEmptyState(b.empty) : el('div', 'hidden');
            const rowsEls = [];
            items.forEach((item) => {
                const itemRow = el('div', 'uikit-list-item' + (item.disabled ? ' disabled' : ''));
                itemRow.setAttribute('data-item-id', item.id);
                if (item.icon) {
                    const iconSvg = icon(item.icon, 16);
                    if (iconSvg) itemRow.appendChild(iconSvg);
                }
                itemRow.appendChild(el('span', 'uikit-list-item-label', item.label || ''));
                if (item.meta) itemRow.appendChild(el('span', 'uikit-list-item-meta', item.meta));
                if (!item.disabled) {
                    itemRow.addEventListener('click', () => postAction(entry, item.id));
                }
                rowsEls.push({ node: itemRow, text: `${item.label || ''} ${item.meta || ''}`.toLowerCase() });
                itemsBox.appendChild(itemRow);
            });
            if (b.search) {
                const search = el('input', 'input-field list-search');
                search.type = 'search';
                search.placeholder = (b.search && b.search.placeholder) || '';
                search.addEventListener('input', () => {
                    const q = search.value.trim().toLowerCase();
                    let shown = 0;
                    rowsEls.forEach((r) => {
                        const hit = q === '' || r.text.indexOf(q) !== -1;
                        r.node.classList.toggle('hidden', !hit);
                        if (hit) shown += 1;
                    });
                    emptyNodeEl.classList.toggle('hidden', shown > 0);
                });
                listContainer.appendChild(search);
            }
            listContainer.appendChild(itemsBox);
            emptyNodeEl.classList.toggle('hidden', items.length > 0);
            listContainer.appendChild(emptyNodeEl);
            return listContainer;
        }

        if (b.type === 'buttons') {
            const row = el('div', 'block-buttons-row');
            (b.items || []).forEach((btn) => {
                const btnEl = el('button', `uikit-btn uikit-btn-${btn.variant || 'secondary'}`);
                btnEl.type = 'button';
                if (btn.disabled) btnEl.disabled = true;
                if (btn.icon) {
                    const iconSvg = icon(btn.icon, 14);
                    if (iconSvg) btnEl.appendChild(iconSvg);
                }
                btnEl.appendChild(el('span', null, btn.label || ''));
                if (!btn.disabled) {
                    btnEl.addEventListener('click', () => postAction(entry, btn.id));
                }
                row.appendChild(btnEl);
            });
            return row;
        }

        return null;
    }

    // Helper: Create standard header
    function createHeader(title, subtitle, onBack) {
        const header = el('div', 'app-header');
        const backBtn = el('button', 'app-header-btn');
        backBtn.type = 'button';
        backBtn.setAttribute('aria-label', t('phonekit.back'));
        const backIcon = icon('chevron-left', 18);
        if (backIcon) backBtn.appendChild(backIcon);
        backBtn.addEventListener('click', onBack);

        const titles = el('div', 'app-header-titles');
        titles.appendChild(el('div', 'app-header-title', title || ''));
        if (subtitle) titles.appendChild(el('div', 'app-header-sub', subtitle));

        header.appendChild(backBtn);
        header.appendChild(titles);
        return header;
    }


    // -------------------------------------------------------------
    // Status bar: time, live pill, battery
    // -------------------------------------------------------------
    function renderStatus() {
        if (liveState && liveState.text) {
            liveEl.textContent = liveState.text;
            liveEl.classList.remove('hidden');
        } else {
            liveEl.textContent = '';
            liveEl.classList.add('hidden');
        }
        if (battery.none) {
            batteryEl.classList.add('hidden');
        } else {
            batteryEl.classList.remove('hidden');
            const pct = Math.max(0, Math.min(100, Number(battery.pct) || 0));
            batteryPctEl.textContent = `${pct}%`;
            batteryFillEl.style.width = `${pct}%`;
            batteryEl.classList.toggle('is-low', pct <= 20 && !battery.charging);
            batteryChargeEl.classList.toggle('hidden', !battery.charging);
            batteryEl.setAttribute('aria-label', battery.charging ? `${pct}% ${t('phonekit.battery.charging')}` : `${pct}%`);
        }
        document.querySelectorAll('[data-battery]').forEach((node) => {
            node.textContent = battery.none ? '' : `${battery.pct}%`;
        });
    }

    // -------------------------------------------------------------
    // Device: model frame, case colour, keypad keys, fold
    // -------------------------------------------------------------
    function applyDevice() {
        frameEl.setAttribute('data-model', device.model);
        frameEl.setAttribute('data-fold', device.fold || 'none');
        frameEl.setAttribute('aria-label', device.label || '');
        if (device.color) {
            frameEl.style.setProperty('--case', device.color);
        } else {
            frameEl.style.removeProperty('--case');
        }
        keysEl.classList.toggle('hidden', !isKeypadModel());
        hardKbEl.classList.toggle('hidden', device.model !== 'qwerty');
        homeBarEl.classList.toggle('hidden', isKeypadModel());
        applyPlacement();
        renderCover();
    }

    function coverShown() {
        return DL.isCoverScreen(device.model, device.fold) && device.cover !== false;
    }

    // Fold or unfold: layout only. The screen on top, its scroll and half-typed text stay.
    let foldTimer = null;
    function applyFold(fold) {
        device.fold = DL.normalizeFold(device.model, fold);
        frameEl.classList.add('is-folding');
        if (foldTimer) clearTimeout(foldTimer);
        foldTimer = setTimeout(() => { frameEl.classList.remove('is-folding'); foldTimer = null; }, 300);
        frameEl.setAttribute('data-fold', device.fold || 'none');
        applyPlacement();
        if (currentView === 'custom_app') {
            layoutPanes();
        } else if (currentView === 'home') {
            // tiles per page change with the book's fold; the home holds no typed text
            renderHomeScreen();
        }
        renderCover();
        renderRing();
        if (!coverShown() && pendingCoverApp) {
            const tile = pendingCoverApp;
            pendingCoverApp = null;
            if (!locked) openTile(tile);
        }
    }

    // -------------------------------------------------------------
    // Waiting items: badges first, then unread history (lock screen and cover)
    // -------------------------------------------------------------
    function waitingItems(limit) {
        const out = [];
        homeTiles().forEach((tile) => {
            const count = badgeOf(tile.id);
            if (count > 0) out.push({ tile, label: tile.label, count });
        });
        historyEntries.forEach((e) => {
            if ((Number(e.at) || 0) > historySeenAt) {
                out.push({ entry: e, label: e.title || '', body: e.description || '', count: Number(e.count) || 1 });
            }
        });
        return out.slice(0, limit);
    }

    // -------------------------------------------------------------
    // Lock screen
    // -------------------------------------------------------------
    function renderLock() {
        emptyNode(lockEl);
        lockEl.classList.toggle('hidden', !locked);
        if (!locked) return;
        lockEl.appendChild(el('div', 'lock-time')).setAttribute('data-clock', '');
        lockEl.appendChild(el('div', 'lock-date')).setAttribute('data-date', '');
        const cards = el('div', 'lock-cards');
        waitingItems(5).forEach((item) => {
            const card = el('button', 'lock-card');
            card.type = 'button';
            card.appendChild(el('span', 'lock-card-label', item.label));
            if (item.body) card.appendChild(el('span', 'lock-card-body', item.body));
            if (item.count > 1 || item.tile) card.appendChild(el('span', 'lock-card-count', item.tile ? badgeText(item.count) : `×${item.count}`));
            card.addEventListener('click', () => {
                if (paused) return;
                unlock();
                if (item.tile) openTile(item.tile);
            });
            cards.appendChild(card);
        });
        lockEl.appendChild(cards);
        if (ring) lockEl.appendChild(ringEl);
        lockEl.appendChild(el('div', 'lock-hint', t(isKeypadModel() ? 'phonekit.lock.hintKeypad' : 'phonekit.lock.hint')));
        updateClock();
    }

    function unlock() {
        if (!locked) return;
        locked = false;
        renderLock();
        renderRing();
    }

    // -------------------------------------------------------------
    // Control centre
    // -------------------------------------------------------------
    function renderHistoryList(container) {
        const head = el('div', 'cc-section-head');
        head.appendChild(el('span', 'cc-section-title', t('phonekit.history.title')));
        const visible = historyEntries.filter((e) => (Number(e.at) || 0) > historySeenAt).slice(0, 20);
        if (visible.length > 0) {
            const clearBtn = el('button', 'cc-clear', t('phonekit.history.clear'));
            clearBtn.type = 'button';
            clearBtn.addEventListener('click', () => {
                if (paused) return;
                let newest = historySeenAt;
                historyEntries.forEach((e) => { newest = Math.max(newest, Number(e.at) || 0); });
                historySeenAt = newest;
                postNui('seen', { at: newest });
                renderCc();
            });
            head.appendChild(clearBtn);
        }
        container.appendChild(head);
        if (visible.length === 0) {
            container.appendChild(el('div', 'list-empty', t('phonekit.history.empty')));
            return;
        }
        const list = el('div', 'cc-history');
        visible.forEach((e) => {
            const row = el('div', 'cc-history-row');
            const iconBox = el('div', 'phone-banner-icon');
            const ic = icon(e.icon || 'bell', 14) || icon('bell', 14);
            if (ic) iconBox.appendChild(ic);
            row.appendChild(iconBox);
            const text = el('div', 'phone-banner-text');
            text.appendChild(el('div', 'phone-banner-title', e.title || ''));
            if (e.description) text.appendChild(el('div', 'phone-banner-body', e.description));
            row.appendChild(text);
            if ((Number(e.count) || 1) > 1) row.appendChild(el('span', 'cc-count', `×${e.count}`));
            list.appendChild(row);
        });
        container.appendChild(list);
    }

    function renderCc() {
        emptyNode(ccEl);
        ccEl.classList.toggle('hidden', !ccOpen);
        if (!ccOpen) return;
        ccEl.appendChild(el('div', 'cc-title', t('phonekit.cc.title')));
        const body = el('div', 'cc-body');
        buildSettingsRows(body);
        if (itemMode && device.devices && device.devices.length > 0) {
            const sec = el('div', 'settings-section');
            sec.appendChild(el('div', 'cc-section-title', t('phonekit.cc.devices')));
            device.devices.forEach((d) => {
                const row = el('button', 'cc-device' + (d.active ? ' is-active' : ''));
                row.type = 'button';
                row.appendChild(el('span', 'cc-device-label', d.label || ''));
                if (typeof d.battery === 'number') row.appendChild(el('span', 'cc-device-battery', `${d.battery}%`));
                if (d.active) row.appendChild(el('span', 'cc-device-active', t('phonekit.cc.active')));
                row.addEventListener('click', () => {
                    if (!paused && !d.active) postNui('device', { id: d.id });
                });
                sec.appendChild(row);
            });
            body.appendChild(sec);
        }
        renderHistoryList(body);
        ccEl.appendChild(body);
    }

    function openCc() {
        if (ccOpen || coverShown()) return;
        ccOpen = true;
        postNui('screen', { level: 'on' });
        renderCc();
    }

    function closeCc() {
        ccOpen = false;
        renderCc();
    }

    // -------------------------------------------------------------
    // Cover screen (fold closed)
    // -------------------------------------------------------------
    function renderCover() {
        emptyNode(coverEl);
        const shown = coverShown() && !rootEl.classList.contains('hidden');
        coverEl.classList.toggle('hidden', !shown);
        frameEl.classList.toggle('is-covered', shown);
        if (!shown) return;
        coverEl.appendChild(el('div', 'cover-time')).setAttribute('data-clock', '');
        const meta = el('div', 'cover-meta');
        meta.appendChild(el('span', null)).setAttribute('data-date', '');
        meta.appendChild(el('span', null)).setAttribute('data-battery', '');
        coverEl.appendChild(meta);
        const items = waitingItems(3);
        if (items.length > 0) {
            coverEl.appendChild(el('div', 'cover-waiting', `${t('phonekit.cover.waiting')} ${waitingItems(99).length}`));
            items.forEach((item) => {
                const btn = el('button', 'cover-item' + (pendingCoverApp && item.tile === pendingCoverApp ? ' is-picked' : ''), item.label);
                btn.type = 'button';
                btn.addEventListener('click', () => {
                    if (paused || !item.tile) return;
                    pendingCoverApp = item.tile;
                    renderCover();
                });
                coverEl.appendChild(btn);
            });
        }
        if (ring) coverEl.appendChild(ringEl);
        updateClock();
        renderStatus();
    }

    // -------------------------------------------------------------
    // Ring card: on the cover, on the lock screen, or a full card
    // -------------------------------------------------------------
    function renderRing() {
        emptyNode(ringEl);
        if (!ring) {
            ringEl.classList.add('hidden');
            if (ringEl.parentNode !== glassEl) glassEl.appendChild(ringEl);
            return;
        }
        ringEl.classList.remove('hidden');
        ringEl.appendChild(el('div', 'ring-title', ring.title || ''));
        if (ring.body) ringEl.appendChild(el('div', 'ring-body', ring.body));
        const row = el('div', 'ring-actions');
        [[false, 'phonekit.ring.decline', 'uikit-btn-danger'], [true, 'phonekit.ring.answer', 'uikit-btn-primary']].forEach((a) => {
            const btn = el('button', `uikit-btn ${a[2]}`, t(a[1]));
            btn.type = 'button';
            btn.addEventListener('click', () => {
                if (paused || !ring) return;
                postNui('ring', { ringId: ring.ringId, answer: a[0] });
                ring = null;
                renderRing();
            });
            row.appendChild(btn);
        });
        ringEl.appendChild(row);
        if (coverShown()) {
            ringEl.className = 'phone-ring on-cover';
            coverEl.appendChild(ringEl);
        } else if (locked) {
            ringEl.className = 'phone-ring on-lock';
            lockEl.insertBefore(ringEl, lockEl.querySelector('.lock-hint'));
        } else {
            ringEl.className = 'phone-ring';
            glassEl.appendChild(ringEl);
        }
    }

    // -------------------------------------------------------------
    // Keypad keys (keypad, burner) and the qwerty hard keyboard
    // -------------------------------------------------------------
    function buildKeys() {
        emptyNode(keysEl);
        const nav = el('div', 'keys-nav');
        [['ArrowUp', '↑'], ['Enter', 'OK'], ['ArrowDown', '↓'], ['Backspace', t('phonekit.back')]].forEach((k) => {
            const btn = el('button', 'key-btn', k[1]);
            btn.type = 'button';
            btn.addEventListener('click', () => handleKey(k[0], null));
            nav.appendChild(btn);
        });
        keysEl.appendChild(nav);
        const pad = el('div', 'keys-pad');
        ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'].forEach((k) => {
            const btn = el('button', 'key-btn', k);
            btn.type = 'button';
            btn.addEventListener('click', () => handleKey(k, null));
            pad.appendChild(btn);
        });
        keysEl.appendChild(pad);

        emptyNode(hardKbEl);
        ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'].forEach((rowKeys) => {
            const row = el('div', 'hardkb-row');
            rowKeys.split('').forEach((ch) => row.appendChild(el('span', 'hardkb-key', ch)));
            hardKbEl.appendChild(row);
        });
    }

    // -------------------------------------------------------------
    // Exit contract and keyboard
    // -------------------------------------------------------------
    function screenName() {
        if (coverShown()) return 'cover';
        if (ccOpen) return 'cc';
        if (locked) return 'lock';
        return currentView === 'home' ? 'home' : 'app';
    }

    function fieldFocused() {
        const a = document.activeElement;
        if (!a) return false;
        const tag = a.tagName.toLowerCase();
        return tag === 'textarea' || (tag === 'input' && a.type !== 'checkbox' && a.type !== 'range');
    }

    function closeAll() {
        if (currentView === 'note_edit') saveCurrentNote();
        else if (currentView === 'contact_edit') saveCurrentContact();
        postNui('close', {});
    }

    function runExit(result) {
        if (result === 'close') { closeAll(); return true; }
        if (result === 'close_cc') { closeCc(); return true; }
        if (result === 'back') {
            if (screenName() === 'lock' || screenName() === 'cover') return true;
            goBack();
            return true;
        }
        if (result === 'home') { goHome(); return true; }
        return false;
    }

    // Keys a screen uses on its own (keypad list, lock screen OK, calculator digits).
    function screenKey(key) {
        if (locked && isKeypadModel()) {
            if (key === 'Enter') { unlock(); return true; }
            return /^[0-9*#]$/.test(key) || key === 'ArrowUp' || key === 'ArrowDown';
        }
        if (locked || ccOpen || coverShown()) return false;
        if (currentView === 'home' && isKeypadModel() && (key === 'ArrowUp' || key === 'ArrowDown' || key === 'Enter' || /^[0-9]$/.test(key))) {
            keypadHomeKey(key);
            return true;
        }
        if (currentView === 'calculator' && calcKeyHandler && !fieldFocused()) {
            const map = { '+': '+', '-': '-', '*': '×', '/': '÷', '=': '=', Enter: '=', '%': '%', '.': '.', Delete: 'C' };
            if (/^[0-9]$/.test(key)) { calcKeyHandler(key); return true; }
            if (map[key]) { calcKeyHandler(map[key]); return true; }
        }
        return false;
    }

    // `code` = KeyboardEvent.code (exit contract), `key` = KeyboardEvent.key (screens). Returns true when handled.
    function handleKey(key, code) {
        if (paused) return true;
        const keyCode = code || key;
        const used = keyCode !== closeKeyCode || !DL.isFKey(keyCode) ? screenKey(key) : false;
        const state = {
            screen: screenName(),
            isFieldFocused: fieldFocused(),
            model: device.model,
            openKeyCode: closeKeyCode,
            screenUsedKey: used,
        };
        const exitInput = key === 'Escape' || key === 'Backspace' ? key : keyCode;
        const result = DL.decideExit(state, exitInput);
        if (result === 'edit' || result === 'none') return used;
        return runExit(result);
    }

    window.addEventListener('keydown', (e) => {
        if (rootEl.classList.contains('hidden')) return;
        if (handleKey(e.key, e.code)) e.preventDefault();
    });

    // Right mouse button = back (control centre open: close it)
    window.addEventListener('contextmenu', (e) => {
        if (rootEl.classList.contains('hidden')) return;
        e.preventDefault();
        if (paused) return;
        runExit(DL.decideExit({ screen: screenName(), model: device.model }, 'RightMouse'));
    });

    // Home bar: tap = exit contract row; a swipe up that starts on it unlocks the lock screen.
    let homeBarStart = null;
    homeBarEl.addEventListener('pointerdown', (e) => { homeBarStart = e.clientY; });
    homeBarEl.addEventListener('pointerup', (e) => {
        if (paused || homeBarStart === null) return;
        const dy = homeBarStart - e.clientY;
        homeBarStart = null;
        if (locked && dy >= 46) { unlock(); return; }
        if (dy < 10) runExit(DL.decideExit({ screen: screenName(), model: device.model }, 'HomeBar'));
    });
    if (homeBtn) homeBtn.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            if (!paused) runExit(DL.decideExit({ screen: screenName(), model: device.model }, 'HomeBar'));
        }
    });

    // Swipe up >= 46 px on the lock screen unlocks; swipe up on the control centre closes it.
    function swipeUp(target, onSwipe) {
        let startY = null;
        target.addEventListener('pointerdown', (e) => { startY = e.clientY; });
        target.addEventListener('pointerup', (e) => {
            if (startY === null || paused) return;
            const dy = startY - e.clientY;
            startY = null;
            if (dy >= 46) onSwipe();
        });
    }
    swipeUp(lockEl, unlock);
    swipeUp(ccEl, closeCc);

    // Pull-down >= 46 px that starts on the status-bar strip opens the control centre.
    let statusStart = null;
    statusEl.addEventListener('pointerdown', (e) => { statusStart = e.clientY; });
    window.addEventListener('pointerup', (e) => {
        if (statusStart === null) return;
        const dy = e.clientY - statusStart;
        statusStart = null;
        if (!paused && dy >= 46 && !isKeypadModel()) openCc();
    });

    // A focused field that is removed never fires focusout: check every 500 ms so game input comes back.
    window.addEventListener('focusin', () => {
        if (fieldFocused() && !typingReported) {
            typingReported = true;
            postNui('typing', { on: true });
        }
    });
    window.addEventListener('focusout', () => {
        setTimeout(() => {
            if (typingReported && !fieldFocused()) {
                typingReported = false;
                postNui('typing', { on: false });
            }
        }, 0);
    });
    setInterval(() => {
        if (typingReported && !fieldFocused()) {
            typingReported = false;
            postNui('typing', { on: false });
        }
    }, 500);

    // Mouse hover tracking over phone frame
    if (frameEl) {
        frameEl.addEventListener('mouseenter', () => postNui('hover', { hovering: true }));
        frameEl.addEventListener('mouseleave', () => postNui('hover', { hovering: false }));
    }

    window.addEventListener('resize', () => {
        if (!rootEl.classList.contains('hidden')) applyPlacement();
    });

    function shellClose() {
        if (currentView === 'note_edit') saveCurrentNote();
        else if (currentView === 'contact_edit') saveCurrentContact();
        rootEl.classList.add('hidden');
        if (bannerTimeout) {
            clearTimeout(bannerTimeout);
            bannerTimeout = null;
        }
        bannerEl.classList.add('hidden');
        currentView = 'home';
        appStack = [];
        clearContent();
        locked = false;
        ccOpen = false;
        ring = null;
        pendingCoverApp = null;
        paused = false;
        renderLock();
        renderCc();
        renderRing();
        renderCover();
    }

    // Self-test probes from the client script (spec § Self-tests (0.2)): press a key through the real keydown
    // handler or open the control centre, then answer with the shell state on the `selftest` callback.
    function selftestProbe(data) {
        if (data.op === 'key') {
            window.dispatchEvent(new KeyboardEvent('keydown', { key: String(data.key || ''), code: String(data.code || '') }));
        } else if (data.op === 'cc') {
            openCc();
        }
        const top = appStack[appStack.length - 1];
        const rect = frameEl.getBoundingClientRect();
        postNui('selftest', {
            id: data.id,
            screen: screenName(),
            top: currentView === 'custom_app' && top ? top.screenId : null,
            fold: device.fold || null,
            x: rect.left, y: rect.top, w: rect.width, h: rect.height,
            vw: window.innerWidth, vh: window.innerHeight,
        });
    }

    // Window message listener
    window.addEventListener('message', (event) => {
        const data = event.data;
        if (!data || !data.type) return;

        if (data.type === 'aeterna:theme' && data.href) {
            let link = document.querySelector('link[data-aeterna-theme]');
            if (!link) {
                link = document.createElement('link');
                link.rel = 'stylesheet';
                link.setAttribute('data-aeterna-theme', 'true');
                document.head.appendChild(link);
            }
            link.href = data.href;
        } else if (data.type === 'locale' && data.strings) {
            locales = Object.assign(locales, data.strings);
            buildKeys();
        } else if (data.type === 'device') {
            device = {
                model: DL.MODELS[data.model] ? data.model : DL.DEFAULT_MODEL,
                label: data.label || '',
                fold: DL.normalizeFold(data.model, data.fold),
                voice: data.voice !== false,
                color: typeof data.color === 'string' && /^#[0-9A-Fa-f]{6}$/.test(data.color) ? data.color : null,
                devices: Array.isArray(data.devices) ? data.devices : [],
                cover: data.cover !== false,
            };
            if (data.builtins) enabledBuiltins = Object.assign({}, enabledBuiltins, data.builtins);
            applyDevice();
            if (!rootEl.classList.contains('hidden')) {
                if (currentView === 'home') renderHomeScreen();
                else if (currentView === 'custom_app') layoutPanes();
                if (ccOpen) renderCc();
            }
        } else if (data.type === 'fold') {
            applyFold(data.fold);
        } else if (data.type === 'battery') {
            battery = data.none ? { none: true } : { pct: Number(data.pct) || 0, charging: data.charging === true };
            renderStatus();
        } else if (data.type === 'power') {
            if (data.on === false) shellClose();
        } else if (data.type === 'live') {
            liveState = data.text ? { id: data.id, text: data.text } : null;
            renderStatus();
        } else if (data.type === 'ring') {
            ring = { ringId: data.ringId, id: data.id, title: data.title, body: data.body };
            renderRing();
        } else if (data.type === 'ringStop') {
            if (ring && (!data.ringId || ring.ringId === data.ringId)) {
                ring = null;
                renderRing();
            }
        } else if (data.type === 'history') {
            historyEntries = Array.isArray(data.entries) ? data.entries : [];
            historySeenAt = Number(data.seenAt) || 0;
            if (locked) renderLock();
            if (ccOpen) renderCc();
            renderCover();
        } else if (data.type === 'closeKey') {
            closeKeyCode = typeof data.code === 'string' && /^(F[0-9]{1,2}|Key[A-Z]|Digit[0-9])$/.test(data.code) ? data.code : null;
        } else if (data.type === 'paused') {
            paused = data.on === true;
            frameEl.classList.toggle('is-paused', paused);
        } else if (data.type === 'shell:open') {
            const wasHidden = rootEl.classList.contains('hidden');
            rootEl.classList.remove('hidden');
            if (data.settings) {
                currentSettings = Object.assign(currentSettings, data.settings);
            }
            if (data.builtins) {
                enabledBuiltins = Object.assign({}, enabledBuiltins, data.builtins);
            }
            if (data.time) {
                setServerTime(data.time);
            }
            currentApps = data.apps || [];
            currentIntents = data.intents || {};
            lockEnabled = data.lockScreen === true;
            itemMode = data.itemMode === true;
            applyPlacement(data.place, data.position);
            applyDevice();
            applySettings(currentSettings);
            startClock();
            renderStatus();
            if (wasHidden) {
                locked = DL.shouldLock(lockEnabled, badges, historyEntries, historySeenAt);
                renderLock();
                renderHomeScreen();
                postNui('screen', { level: 'on' });
            } else if (currentView === 'home') {
                renderHomeScreen();
            }
            renderRing();
        } else if (data.type === 'shell:close') {
            shellClose();
        } else if (data.type === 'screen:show') {
            showAppScreen(data);
        } else if (data.type === 'screen:update') {
            updateAppScreen(data.screenId, data.patch);
        } else if (data.type === 'badge') {
            badges[data.id] = data.count;
            if (currentView === 'home') renderHomeScreen();
            if (locked) renderLock();
            renderCover();
        } else if (data.type === 'banner') {
            showBanner(data);
        } else if (data.type === 'builtin:data') {
            if (data.notes) notesData = data.notes;
            if (data.contacts) contactsData = data.contacts;
        } else if (data.type === 'layout:apply') {
            applyPlacement(data.place, data.position);
        } else if (data.type === 'selftest') {
            selftestProbe(data);
        }
    });

    buildKeys();
})();
