// app.js -- aeterna_phonekit NUI application.
// Text rendered strictly with textContent; SVG nodes constructed through DOM.
// Plain JavaScript without external dependencies.

(function () {
    'use strict';

    const rootEl = document.getElementById('phonekit-root');
    const frameEl = document.getElementById('phone-frame');
    const contentEl = document.getElementById('phone-content');
    const timeEl = document.getElementById('phone-time');
    const bannerEl = document.getElementById('phone-banner');
    const homeBtn = document.getElementById('phone-home-btn');

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

    // Navigation state
    // 'home' | 'calculator' | 'notes' | 'note_edit' | 'contacts' | 'contact_edit' | 'settings' | 'custom_app'
    let currentView = 'home';
    let currentAppId = null;
    let activeCustomSpec = null;
    let activeCustomScreenId = null;
    let activeCustomValues = {};
    let activeEditingNote = null;
    let activeEditingContact = null;

    let bannerTimeout = null;
    let clockInterval = null;

    // Helper: NUI callback POST
    function postNui(event, data) {
        const resource = window.GetParentResourceName ? window.GetParentResourceName() : 'aeterna_phonekit';
        return fetch(`https://${resource}/${event}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    // Helper: Translate locale key
    function t(key) {
        return locales[key] || key;
    }

    // Update Clock in status bar
    function updateClock() {
        if (!timeEl) return;
        const now = new Date();
        let hours = now.getHours();
        const minutes = String(now.getMinutes()).padStart(2, '0');

        if (currentSettings.clock24) {
            timeEl.textContent = `${String(hours).padStart(2, '0')}:${minutes}`;
        } else {
            const ampm = hours >= 12 ? 'PM' : 'AM';
            hours = hours % 12;
            hours = hours ? hours : 12;
            timeEl.textContent = `${hours}:${minutes} ${ampm}`;
        }
    }

    function startClock() {
        updateClock();
        if (clockInterval) clearInterval(clockInterval);
        clockInterval = setInterval(updateClock, 10000);
    }

    // Apply layout coordinates or default classes
    function applyPlacement(place, position) {
        frameEl.classList.remove('pos-bottom-right', 'pos-bottom-left');

        if (place && typeof place === 'object' && place.x !== undefined && place.y !== undefined) {
            const scale = Number(place.scale) || 1.0;
            const w = 320;
            const h = 640;
            const ax = Number(place.ax) || 0;
            const ay = Number(place.ay) || 0;

            frameEl.style.left = `calc(${place.x * 100}vw - ${ax * w * scale}px)`;
            frameEl.style.top = `calc(${place.y * 100}vh - ${ay * h * scale}px)`;
            frameEl.style.right = 'auto';
            frameEl.style.bottom = 'auto';
            frameEl.style.transform = `scale(${scale})`;
            frameEl.style.transformOrigin = 'top left';
        } else {
            frameEl.style.left = '';
            frameEl.style.top = '';
            frameEl.style.right = '';
            frameEl.style.bottom = '';
            frameEl.style.transform = '';
            frameEl.style.transformOrigin = '';

            if (position === 'bottom-left') {
                frameEl.classList.add('pos-bottom-left');
            } else {
                frameEl.classList.add('pos-bottom-right');
            }
        }
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

    // Clear content container
    function clearContent() {
        while (contentEl.firstChild) {
            contentEl.removeChild(contentEl.firstChild);
        }
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

        while (bannerEl.firstChild) {
            bannerEl.removeChild(bannerEl.firstChild);
        }

        const iconBox = document.createElement('div');
        iconBox.className = 'phone-banner-icon';
        const iconSvg = window.PhonekitIcons ? window.PhonekitIcons.create('bell', 16) : null;
        if (iconSvg) iconBox.appendChild(iconSvg);

        const textBox = document.createElement('div');
        textBox.className = 'phone-banner-text';

        const titleEl = document.createElement('div');
        titleEl.className = 'phone-banner-title';
        titleEl.textContent = banner.title || 'Notification';
        textBox.appendChild(titleEl);

        if (banner.body) {
            const bodyEl = document.createElement('div');
            bodyEl.className = 'phone-banner-body';
            bodyEl.textContent = banner.body;
            textBox.appendChild(bodyEl);
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
    // View: Home Screen
    // -------------------------------------------------------------
    function renderHomeScreen() {
        currentView = 'home';
        currentAppId = null;
        activeCustomSpec = null;
        activeCustomScreenId = null;

        clearContent();

        const grid = document.createElement('div');
        grid.className = 'home-screen';

        // Built-in Apps list
        const builtinsList = [
            { id: 'calculator', label: t('phonekit.app.calculator'), icon: 'calculator', order: 10 },
            { id: 'notes', label: t('phonekit.app.notes'), icon: 'file-text', order: 20 },
            { id: 'contacts', label: t('phonekit.app.contacts'), icon: 'users', order: 30 },
            { id: 'settings', label: t('phonekit.app.settings'), icon: 'settings', order: 40 },
        ];

        const allTiles = [];

        for (let i = 0; i < builtinsList.length; i++) {
            const b = builtinsList[i];
            if (enabledBuiltins[b.id] !== false) {
                allTiles.push({
                    isBuiltin: true,
                    id: b.id,
                    label: b.label,
                    icon: b.icon,
                    order: b.order,
                });
            }
        }

        for (let i = 0; i < currentApps.length; i++) {
            const a = currentApps[i];
            allTiles.push({
                isBuiltin: false,
                owner: a.owner,
                id: a.id,
                label: a.label,
                icon: a.icon,
                order: Number(a.order) || 100,
            });
        }

        allTiles.sort((a, b) => {
            if (a.order !== b.order) return a.order - b.order;
            return a.id.localeCompare(b.id);
        });

        for (let i = 0; i < allTiles.length; i++) {
            const tileData = allTiles[i];
            const tileBtn = document.createElement('button');
            tileBtn.type = 'button';
            tileBtn.className = 'app-tile';
            tileBtn.setAttribute('aria-label', tileData.label);

            const iconBox = document.createElement('div');
            iconBox.className = 'app-icon-box';

            const iconSvg = window.PhonekitIcons ? window.PhonekitIcons.create(tileData.icon, 24) : null;
            if (iconSvg) iconBox.appendChild(iconSvg);

            const badgeCount = Number(badges[tileData.id]) || 0;
            if (badgeCount > 0) {
                const badgeEl = document.createElement('div');
                badgeEl.className = 'app-badge';
                badgeEl.textContent = badgeCount > 99 ? '99+' : String(badgeCount);
                iconBox.appendChild(badgeEl);
            }

            const labelEl = document.createElement('div');
            labelEl.className = 'app-label';
            labelEl.textContent = tileData.label;

            tileBtn.appendChild(iconBox);
            tileBtn.appendChild(labelEl);

            tileBtn.addEventListener('click', () => {
                if (tileData.isBuiltin) {
                    if (tileData.id === 'calculator') renderCalculator();
                    else if (tileData.id === 'notes') renderNotesList();
                    else if (tileData.id === 'contacts') renderContactsList();
                    else if (tileData.id === 'settings') renderSettings();
                    postNui('tap', { id: tileData.id, owner: '' });
                } else {
                    postNui('tap', { id: tileData.id, owner: tileData.owner });
                }
            });

            grid.appendChild(tileBtn);
        }

        contentEl.appendChild(grid);
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

        const header = createHeader(t('phonekit.app.calculator'), null, () => renderHomeScreen());
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

        const header = createHeader(t('phonekit.app.notes'), null, () => renderHomeScreen());
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
            saveCurrentNote();
            renderNotesList();
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

        form.appendChild(titleInput);
        form.appendChild(bodyInput);

        function saveCurrentNote() {
            const cleanTitle = titleInput.value.trim().substring(0, 60);
            const cleanBody = bodyInput.value.trim().substring(0, 2000);

            if (!cleanTitle && !cleanBody) {
                if (!isNew) {
                    notesData = notesData.filter((n) => n.id !== note.id);
                    postNui('builtin:save', { app: 'notes', data: notesData });
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
            });
            notesData = updatedList;
        }

        if (!isNew) {
            const deleteBtn = document.createElement('button');
            deleteBtn.type = 'button';
            deleteBtn.className = 'btn-danger-outline';
            deleteBtn.textContent = 'Delete note';
            deleteBtn.addEventListener('click', () => {
                notesData = notesData.filter((n) => n.id !== note.id);
                postNui('builtin:save', { app: 'notes', data: notesData });
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

        const header = createHeader(t('phonekit.app.contacts'), null, () => renderHomeScreen());
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
            saveCurrentContact();
            renderContactsList();
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

        form.appendChild(nameInput);
        form.appendChild(numInput);

        function saveCurrentContact() {
            const cleanName = nameInput.value.trim().substring(0, 40);
            const cleanNum = numInput.value.trim().substring(0, 20);

            if (!cleanName && !cleanNum) {
                if (!isNew) {
                    contactsData = contactsData.filter((c) => c.id !== contact.id);
                    postNui('builtin:save', { app: 'contacts', data: contactsData });
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
            });
            contactsData = updatedList;
        }

        if (!isNew) {
            const deleteBtn = document.createElement('button');
            deleteBtn.type = 'button';
            deleteBtn.className = 'btn-danger-outline';
            deleteBtn.textContent = 'Delete contact';
            deleteBtn.addEventListener('click', () => {
                contactsData = contactsData.filter((c) => c.id !== contact.id);
                postNui('builtin:save', { app: 'contacts', data: contactsData });
                renderContactsList();
            });
            form.appendChild(deleteBtn);
        }

        body.appendChild(form);
        screen.appendChild(body);
        contentEl.appendChild(screen);
    }

    // -------------------------------------------------------------
    // View: Settings App
    // -------------------------------------------------------------
    function renderSettings() {
        currentView = 'settings';
        currentAppId = 'settings';
        clearContent();

        const screen = document.createElement('div');
        screen.className = 'app-screen';

        const header = createHeader(t('phonekit.app.settings'), null, () => renderHomeScreen());
        screen.appendChild(header);

        const body = document.createElement('div');
        body.className = 'app-body';

        // Text Size section
        const textSection = document.createElement('div');
        textSection.className = 'settings-section';

        const textRow = document.createElement('div');
        textRow.className = 'settings-row';

        const textLabel = document.createElement('span');
        textLabel.className = 'settings-label';
        textLabel.textContent = t('phonekit.settings.textSize');

        const textSegment = document.createElement('div');
        textSegment.className = 'segment-control';

        const normBtn = document.createElement('button');
        normBtn.type = 'button';
        normBtn.className = 'segment-btn' + (currentSettings.textSize === 'normal' ? ' active' : '');
        normBtn.textContent = 'Normal';
        normBtn.addEventListener('click', () => {
            currentSettings.textSize = 'normal';
            normBtn.classList.add('active');
            largeBtn.classList.remove('active');
            applySettings(currentSettings);
            postNui('settings', { key: 'textSize', value: 'normal' });
        });

        const largeBtn = document.createElement('button');
        largeBtn.type = 'button';
        largeBtn.className = 'segment-btn' + (currentSettings.textSize === 'large' ? ' active' : '');
        largeBtn.textContent = 'Large';
        largeBtn.addEventListener('click', () => {
            currentSettings.textSize = 'large';
            largeBtn.classList.add('active');
            normBtn.classList.remove('active');
            applySettings(currentSettings);
            postNui('settings', { key: 'textSize', value: 'large' });
        });

        textSegment.appendChild(normBtn);
        textSegment.appendChild(largeBtn);
        textRow.appendChild(textLabel);
        textRow.appendChild(textSegment);
        textSection.appendChild(textRow);
        body.appendChild(textSection);

        // 24-hour clock section
        const clockSection = document.createElement('div');
        clockSection.className = 'settings-section';

        const clockRow = document.createElement('div');
        clockRow.className = 'settings-row';

        const clockLabel = document.createElement('span');
        clockLabel.className = 'settings-label';
        clockLabel.textContent = t('phonekit.settings.clock24');

        const switchLabel = document.createElement('label');
        switchLabel.className = 'toggle-switch';

        const switchInput = document.createElement('input');
        switchInput.type = 'checkbox';
        switchInput.checked = currentSettings.clock24;
        switchInput.addEventListener('change', () => {
            currentSettings.clock24 = switchInput.checked;
            updateClock();
            postNui('settings', { key: 'clock24', value: switchInput.checked });
        });

        const slider = document.createElement('span');
        slider.className = 'toggle-slider';

        switchLabel.appendChild(switchInput);
        switchLabel.appendChild(slider);
        clockRow.appendChild(clockLabel);
        clockRow.appendChild(switchLabel);
        clockSection.appendChild(clockRow);
        body.appendChild(clockSection);

        // Edit layout section (shown only when layout resource is active)
        if (currentSettings.hasLayout) {
            const layoutSection = document.createElement('div');
            layoutSection.className = 'settings-section';

            const layoutBtn = document.createElement('button');
            layoutBtn.type = 'button';
            layoutBtn.className = 'btn-settings-action';
            const sliderIcon = window.PhonekitIcons ? window.PhonekitIcons.create('sliders', 16) : null;
            if (sliderIcon) layoutBtn.appendChild(sliderIcon);

            const btnText = document.createElement('span');
            btnText.textContent = t('phonekit.settings.layout');
            layoutBtn.appendChild(btnText);

            layoutBtn.addEventListener('click', () => {
                postNui('settings', { key: 'layout', value: true });
            });

            layoutSection.appendChild(layoutBtn);
            body.appendChild(layoutSection);
        }

        screen.appendChild(body);
        contentEl.appendChild(screen);
    }

    // -------------------------------------------------------------
    // View: Custom App Spec (from server showApp)
    // -------------------------------------------------------------
    function renderCustomApp(screenId, appId, title, subtitle, blocks) {
        currentView = 'custom_app';
        activeCustomScreenId = screenId;
        currentAppId = appId;
        activeCustomSpec = { title, subtitle, blocks };
        activeCustomValues = {};

        clearContent();

        const screen = document.createElement('div');
        screen.className = 'app-screen';

        const header = createHeader(title, subtitle, () => {
            postNui('back', {});
            renderHomeScreen();
        });
        screen.appendChild(header);

        const body = document.createElement('div');
        body.className = 'app-body';

        for (let i = 0; i < blocks.length; i++) {
            const b = blocks[i];
            const blockEl = createSpecBlock(b);
            if (blockEl) body.appendChild(blockEl);
        }

        screen.appendChild(body);
        contentEl.appendChild(screen);
    }

    function createSpecBlock(b) {
        if (!b) return null;

        if (b.type === 'text') {
            const p = document.createElement('p');
            p.className = 'block-text';
            p.textContent = b.label || '';
            return p;
        }

        if (b.type === 'divider') {
            const hr = document.createElement('div');
            hr.className = 'block-divider';
            return hr;
        }

        if (b.type === 'progress') {
            const box = document.createElement('div');
            box.className = 'block-progress-box';

            const head = document.createElement('div');
            head.className = 'block-progress-head';
            const lbl = document.createElement('span');
            lbl.textContent = b.label || '';
            const pct = document.createElement('span');
            pct.textContent = Math.round((b.value || 0) * 100) + '%';
            head.appendChild(lbl);
            head.appendChild(pct);

            const track = document.createElement('div');
            track.className = 'block-progress-track';
            const fill = document.createElement('div');
            fill.className = 'block-progress-fill';
            fill.style.width = Math.max(0, Math.min(100, (b.value || 0) * 100)) + '%';
            track.appendChild(fill);

            box.appendChild(head);
            box.appendChild(track);
            return box;
        }

        if (b.type === 'field') {
            const box = document.createElement('div');
            box.className = 'block-field';

            const lbl = document.createElement('label');
            lbl.className = 'block-field-label';
            lbl.textContent = b.label || '';
            box.appendChild(lbl);

            const inp = document.createElement('input');
            inp.type = b.input === 'number' ? 'number' : 'text';
            inp.className = 'input-field';
            if (b.placeholder) inp.placeholder = b.placeholder;
            if (b.disabled) inp.disabled = true;
            if (b.value !== undefined && b.value !== null) inp.value = b.value;

            activeCustomValues[b.id] = b.input === 'number' ? Number(inp.value) || 0 : inp.value;

            inp.addEventListener('input', () => {
                activeCustomValues[b.id] = b.input === 'number' ? Number(inp.value) || 0 : inp.value;
            });

            box.appendChild(inp);
            return box;
        }

        if (b.type === 'toggle') {
            const row = document.createElement('div');
            row.className = 'settings-row';

            const lbl = document.createElement('span');
            lbl.className = 'settings-label';
            lbl.textContent = b.label || '';
            row.appendChild(lbl);

            const switchLabel = document.createElement('label');
            switchLabel.className = 'toggle-switch';

            const switchInput = document.createElement('input');
            switchInput.type = 'checkbox';
            switchInput.checked = b.value === true;
            if (b.disabled) switchInput.disabled = true;

            activeCustomValues[b.id] = switchInput.checked;

            switchInput.addEventListener('change', () => {
                activeCustomValues[b.id] = switchInput.checked;
            });

            const slider = document.createElement('span');
            slider.className = 'toggle-slider';

            switchLabel.appendChild(switchInput);
            switchLabel.appendChild(slider);
            row.appendChild(switchLabel);
            return row;
        }

        if (b.type === 'select') {
            const box = document.createElement('div');
            box.className = 'block-field';

            const lbl = document.createElement('label');
            lbl.className = 'block-field-label';
            lbl.textContent = b.label || '';
            box.appendChild(lbl);

            const select = document.createElement('select');
            select.className = 'input-field';
            if (b.disabled) select.disabled = true;

            const opts = b.options || [];
            for (let j = 0; j < opts.length; j++) {
                const optEl = document.createElement('option');
                optEl.value = opts[j].id;
                optEl.textContent = opts[j].label;
                if (opts[j].id === b.value) optEl.selected = true;
                select.appendChild(optEl);
            }

            activeCustomValues[b.id] = select.value;
            select.addEventListener('change', () => {
                activeCustomValues[b.id] = select.value;
            });

            box.appendChild(select);
            return box;
        }

        if (b.type === 'list') {
            const listContainer = document.createElement('div');
            listContainer.className = 'uikit-list-box';

            if (b.label) {
                const listTitle = document.createElement('div');
                listTitle.className = 'block-field-label';
                listTitle.textContent = b.label;
                listContainer.appendChild(listTitle);
            }

            const items = b.items || [];
            for (let j = 0; j < items.length; j++) {
                const item = items[j];
                const itemRow = document.createElement('div');
                itemRow.className = 'uikit-list-item' + (item.disabled ? ' disabled' : '');

                if (item.icon && window.PhonekitIcons) {
                    const iconSvg = window.PhonekitIcons.create(item.icon, 16);
                    if (iconSvg) itemRow.appendChild(iconSvg);
                }

                const itemLbl = document.createElement('span');
                itemLbl.className = 'uikit-list-item-label';
                itemLbl.textContent = item.label || '';
                itemRow.appendChild(itemLbl);

                if (item.meta) {
                    const itemMeta = document.createElement('span');
                    itemMeta.className = 'uikit-list-item-meta';
                    itemMeta.textContent = item.meta;
                    itemRow.appendChild(itemMeta);
                }

                if (!item.disabled) {
                    itemRow.addEventListener('click', () => {
                        postNui('action', {
                            screenId: activeCustomScreenId,
                            action: item.id,
                            values: activeCustomValues,
                        });
                    });
                }

                listContainer.appendChild(itemRow);
            }

            return listContainer;
        }

        if (b.type === 'buttons') {
            const row = document.createElement('div');
            row.className = 'block-buttons-row';

            const items = b.items || [];
            for (let j = 0; j < items.length; j++) {
                const btn = items[j];
                const btnEl = document.createElement('button');
                btnEl.type = 'button';
                btnEl.className = `uikit-btn uikit-btn-${btn.variant || 'secondary'}`;
                if (btn.disabled) btnEl.disabled = true;

                if (btn.icon && window.PhonekitIcons) {
                    const iconSvg = window.PhonekitIcons.create(btn.icon, 14);
                    if (iconSvg) btnEl.appendChild(iconSvg);
                }

                const btnLbl = document.createElement('span');
                btnLbl.textContent = btn.label || '';
                btnEl.appendChild(btnLbl);

                if (!btn.disabled) {
                    btnEl.addEventListener('click', () => {
                        postNui('action', {
                            screenId: activeCustomScreenId,
                            action: btn.id,
                            values: activeCustomValues,
                        });
                    });
                }

                row.appendChild(btnEl);
            }

            return row;
        }

        return null;
    }

    // Helper: Create standard header
    function createHeader(title, subtitle, onBack) {
        const header = document.createElement('div');
        header.className = 'app-header';

        const backBtn = document.createElement('button');
        backBtn.type = 'button';
        backBtn.className = 'app-header-btn';
        backBtn.setAttribute('aria-label', t('phonekit.back'));
        const backIcon = window.PhonekitIcons ? window.PhonekitIcons.create('chevron-left', 18) : null;
        if (backIcon) backBtn.appendChild(backIcon);
        backBtn.addEventListener('click', onBack);

        const titles = document.createElement('div');
        titles.className = 'app-header-titles';

        const titleEl = document.createElement('div');
        titleEl.className = 'app-header-title';
        titleEl.textContent = title || '';
        titles.appendChild(titleEl);

        if (subtitle) {
            const subEl = document.createElement('div');
            subEl.className = 'app-header-sub';
            subEl.textContent = subtitle;
            titles.appendChild(subEl);
        }

        header.appendChild(backBtn);
        header.appendChild(titles);
        return header;
    }

    // Bottom home button action
    if (homeBtn) {
        homeBtn.addEventListener('click', () => {
            if (currentView === 'home') {
                postNui('close', {});
            } else if (currentView === 'custom_app') {
                postNui('back', {});
                renderHomeScreen();
            } else if (currentView === 'note_edit') {
                renderNotesList();
            } else if (currentView === 'contact_edit') {
                renderContactsList();
            } else {
                renderHomeScreen();
            }
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
        } else if (data.type === 'shell:open') {
            rootEl.classList.remove('hidden');
            if (data.settings) {
                currentSettings = Object.assign(currentSettings, data.settings);
            }
            if (data.builtins) {
                enabledBuiltins = Object.assign(enabledBuiltins, data.builtins);
            }
            currentApps = data.apps || [];
            applyPlacement(data.place, data.position);
            applySettings(currentSettings);
            startClock();
            renderHomeScreen();
        } else if (data.type === 'shell:close') {
            rootEl.classList.add('hidden');
            if (bannerTimeout) {
                clearTimeout(bannerTimeout);
                bannerTimeout = null;
            }
            bannerEl.classList.add('hidden');
            currentView = 'home';
        } else if (data.type === 'screen:show') {
            renderCustomApp(data.screenId, data.id, data.title, data.subtitle, data.blocks || []);
        } else if (data.type === 'screen:update') {
            if (activeCustomSpec && activeCustomScreenId === data.screenId && data.patch && data.patch.blocks) {
                for (const blockId in data.patch.blocks) {
                    const partial = data.patch.blocks[blockId];
                    for (let i = 0; i < activeCustomSpec.blocks.length; i++) {
                        if (activeCustomSpec.blocks[i].id === blockId) {
                            Object.assign(activeCustomSpec.blocks[i], partial);
                            break;
                        }
                    }
                }
                renderCustomApp(activeCustomScreenId, currentAppId, activeCustomSpec.title, activeCustomSpec.subtitle, activeCustomSpec.blocks);
            }
        } else if (data.type === 'badge') {
            badges[data.id] = data.count;
            if (currentView === 'home') {
                renderHomeScreen();
            }
        } else if (data.type === 'banner') {
            showBanner(data);
        } else if (data.type === 'builtin:data') {
            if (data.notes) notesData = data.notes;
            if (data.contacts) contactsData = data.contacts;
        } else if (data.type === 'layout:apply') {
            applyPlacement(data.place, data.position);
        }
    });

    // Keyboard and mouse navigation
    window.addEventListener('keydown', (e) => {
        if (rootEl.classList.contains('hidden')) return;

        if (e.key === 'Escape') {
            e.preventDefault();
            postNui('close', {});
        } else if (e.key === 'Backspace') {
            const tag = document.activeElement ? document.activeElement.tagName.toLowerCase() : '';
            if (tag !== 'input' && tag !== 'textarea') {
                e.preventDefault();
                if (currentView === 'home') {
                    postNui('close', {});
                } else if (currentView === 'custom_app') {
                    postNui('back', {});
                    renderHomeScreen();
                } else if (currentView === 'note_edit') {
                    renderNotesList();
                } else if (currentView === 'contact_edit') {
                    renderContactsList();
                } else {
                    renderHomeScreen();
                }
            }
        }
    });

    // Right-click returns to previous screen
    window.addEventListener('contextmenu', (e) => {
        if (rootEl.classList.contains('hidden')) return;
        e.preventDefault();
        if (currentView === 'home') {
            postNui('close', {});
        } else if (currentView === 'custom_app') {
            postNui('back', {});
            renderHomeScreen();
        } else if (currentView === 'note_edit') {
            renderNotesList();
        } else if (currentView === 'contact_edit') {
            renderContactsList();
        } else {
            renderHomeScreen();
        }
    });

    // Mouse hover tracking over phone frame
    if (frameEl) {
        frameEl.addEventListener('mouseenter', () => {
            postNui('hover', { hovering: true });
        });
        frameEl.addEventListener('mouseleave', () => {
            postNui('hover', { hovering: false });
        });
    }
})();
