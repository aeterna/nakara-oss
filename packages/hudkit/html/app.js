// html/app.js -- NUI application logic for aeterna_hudkit.
// Strict rule: text updates through textContent only (no dynamic innerHTML).

(function () {
    const RESOURCE_NAME = 'aeterna_hudkit';

    let currentSettings = {
        numbers: false,
        speedUnit: 'kmh',
        minimapMode: 'always',
        barStyle: 'bar',
    };
    let localeStrings = {};
    let lowThreshold = 20;

    // DOM Elements
    const statusContainer = document.getElementById('status-bars');
    const partStatus = document.getElementById('part-status');
    const partVehicle = document.getElementById('part-vehicle');
    const partStreet = document.getElementById('part-street');
    const partCompass = document.getElementById('part-compass');
    const partVoice = document.getElementById('part-voice');
    const settingsCard = document.getElementById('settings-card');

    const PARTS = {
        status: partStatus,
        vehicle: partVehicle,
        street: partStreet,
        compass: partCompass,
        voice: partVoice,
    };

    const speedValueEl = document.getElementById('speed-value');
    const speedUnitEl = document.getElementById('speed-unit');
    const gearIndicatorEl = document.getElementById('gear-indicator');
    const fuelClusterEl = document.querySelector('.fuel-cluster');
    const fuelBarFillEl = document.getElementById('fuel-bar-fill');
    const fuelRingEl = document.getElementById('fuel-ring');
    const fuelValueEl = document.getElementById('fuel-value');
    const seatbeltEl = document.getElementById('seatbelt-icon');
    const compassBadgeEl = document.getElementById('compass-badge');
    const streetNameEl = document.getElementById('street-name');
    const zoneNameEl = document.getElementById('zone-name');
    const compassTicksEl = document.getElementById('compass-ticks');
    const compassDegEl = document.getElementById('compass-deg');
    const voiceMicEl = document.getElementById('voice-mic');
    const voiceModeEl = document.getElementById('voice-mode');
    const voiceRadioEl = document.getElementById('voice-radio');

    // Settings Controls
    const optNumbers = document.getElementById('opt-numbers');
    const unitKmhBtn = document.getElementById('unit-kmh');
    const unitMphBtn = document.getElementById('unit-mph');
    const modeAlwaysBtn = document.getElementById('mode-always');
    const modeVehicleBtn = document.getElementById('mode-vehicle');
    const modeNeverBtn = document.getElementById('mode-never');
    const styleBarBtn = document.getElementById('style-bar');
    const styleRingBtn = document.getElementById('style-ring');
    const btnEditLayout = document.getElementById('btn-edit-layout');
    const btnSettingsClose = document.getElementById('btn-settings-close');

    // Bar state: barState keeps the last value of every shown bar so a style switch can rebuild them.
    const builtInBars = ['health', 'armour', 'hunger', 'thirst', 'stress'];
    const barState = {}; // barId -> { value, icon }
    const barElements = {}; // barId -> { row, value, setValue }
    let extraBarsList = [];
    let lastFuel = 100;
    let fuelRing = null;
    let lastReportedSizes = null;

    // Runtime visibility of parts that are not always on screen; layout's `hidden` is kept apart.
    let vehicleVisible = false;
    let compassReceived = false;
    let voiceAvailable = false;
    const placedHidden = {};

    // Compass tape
    const DIR_KEYS = {
        0: 'hudkit.dir.n', 45: 'hudkit.dir.ne', 90: 'hudkit.dir.e', 135: 'hudkit.dir.se',
        180: 'hudkit.dir.s', 225: 'hudkit.dir.sw', 270: 'hudkit.dir.w', 315: 'hudkit.dir.nw',
    };
    const DIR_FALLBACK = { 0: 'N', 45: 'NE', 90: 'E', 135: 'SE', 180: 'S', 225: 'SW', 270: 'W', 315: 'NW' };
    const TICK_STEP = 15;
    let compassSpan = 120;
    let compassDeg = null;
    const tickPool = [];

    function post(endpoint, data) {
        return fetch(`https://${RESOURCE_NAME}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    function translate(key, fallback) {
        if (Object.hasOwn(localeStrings, key)) {
            return localeStrings[key];
        }
        return fallback || key;
    }

    function clampPct(v) {
        return Math.max(0, Math.min(100, Math.round(v)));
    }

    // Ring gauge. r = 15.9155 makes the circumference 100, so the dash equals the percentage
    // (same as HudLogic.ringDash(value, 100) in shared/logic/hud.lua).
    const SVG_NS = 'http://www.w3.org/2000/svg';
    const RING_R = '15.9155';

    function ringDashOffset(pct) {
        const f = Math.max(0, Math.min(100, pct)) / 100;
        return 100 * (1 - f);
    }

    function createRing(iconName, iconSize) {
        const root = document.createElement('div');
        root.className = 'ring';

        const svg = document.createElementNS(SVG_NS, 'svg');
        svg.setAttribute('viewBox', '0 0 36 36');
        svg.setAttribute('class', 'ring-svg');
        svg.setAttribute('aria-hidden', 'true');

        const track = document.createElementNS(SVG_NS, 'circle');
        track.setAttribute('class', 'ring-track');
        track.setAttribute('cx', '18');
        track.setAttribute('cy', '18');
        track.setAttribute('r', RING_R);

        const fill = document.createElementNS(SVG_NS, 'circle');
        fill.setAttribute('class', 'ring-fill');
        fill.setAttribute('cx', '18');
        fill.setAttribute('cy', '18');
        fill.setAttribute('r', RING_R);
        fill.setAttribute('stroke-dasharray', '100 100');
        fill.setAttribute('stroke-dashoffset', '0');

        svg.appendChild(track);
        svg.appendChild(fill);
        root.appendChild(svg);

        const iconWrap = document.createElement('span');
        iconWrap.className = 'ring-icon';
        const iconNode = window.HudIcons.create(iconName || 'activity', iconSize || 14);
        if (iconNode) iconWrap.appendChild(iconNode);
        root.appendChild(iconWrap);

        return {
            root,
            setValue: (pct) => fill.setAttribute('stroke-dashoffset', String(ringDashOffset(pct))),
        };
    }

    function createValueLabel() {
        const val = document.createElement('span');
        val.className = 'bar-value';
        if (!currentSettings.numbers) {
            val.classList.add('hidden-numbers');
        }
        val.textContent = '100';
        return val;
    }

    function createBarRow(id, iconName) {
        const row = document.createElement('div');
        row.className = 'bar-row';
        row.dataset.bar = id;

        if (currentSettings.barStyle === 'ring') {
            row.classList.add('is-ring');
            const ring = createRing(iconName, 14);
            const val = createValueLabel();
            row.appendChild(ring.root);
            row.appendChild(val);
            return { row, value: val, setValue: ring.setValue };
        }

        const iconWrap = document.createElement('span');
        iconWrap.className = 'bar-icon';
        const iconNode = window.HudIcons.create(iconName || 'activity', 14);
        if (iconNode) {
            iconWrap.appendChild(iconNode);
        }

        const track = document.createElement('div');
        track.className = 'bar-track';

        const fill = document.createElement('div');
        fill.className = 'bar-fill';
        fill.style.width = '100%';
        track.appendChild(fill);

        const val = createValueLabel();

        row.appendChild(iconWrap);
        row.appendChild(track);
        row.appendChild(val);

        return { row, value: val, setValue: (pct) => { fill.style.width = pct + '%'; } };
    }

    function reorderBars() {
        for (let i = 0; i < builtInBars.length; i++) {
            const id = builtInBars[i];
            if (barElements[id] && barElements[id].row.parentNode === statusContainer) {
                statusContainer.appendChild(barElements[id].row);
            }
        }
        const sortedExtras = extraBarsList.slice().sort((a, b) => {
            const orderA = typeof a.order === 'number' ? a.order : 100;
            const orderB = typeof b.order === 'number' ? b.order : 100;
            if (orderA !== orderB) return orderA - orderB;
            return (a.id || '').localeCompare(b.id || '');
        });
        for (let i = 0; i < sortedExtras.length; i++) {
            const id = sortedExtras[i].id;
            if (barElements[id] && barElements[id].row.parentNode === statusContainer) {
                statusContainer.appendChild(barElements[id].row);
            }
        }
    }

    function measurePart(el) {
        if (!el) return { w: 0, h: 0 };
        const wasHidden = el.classList.contains('hud-hidden');
        const prevVisibility = el.style.visibility;
        if (wasHidden) {
            el.style.visibility = 'hidden';
            el.classList.remove('hud-hidden');
        }
        const rect = el.getBoundingClientRect();
        if (wasHidden) {
            el.classList.add('hud-hidden');
            el.style.visibility = prevVisibility;
        }
        return {
            w: Math.max(8, Math.round(rect.width)),
            h: Math.max(8, Math.round(rect.height)),
        };
    }

    function reportSizes() {
        const sizes = {};
        let changed = !lastReportedSizes;
        for (const id of Object.keys(PARTS)) {
            sizes[id] = measurePart(PARTS[id]);
            if (lastReportedSizes && (lastReportedSizes[id].w !== sizes[id].w || lastReportedSizes[id].h !== sizes[id].h)) {
                changed = true;
            }
        }
        if (changed) {
            lastReportedSizes = sizes;
            post('ready', { sizes });
        }
    }

    function applyTone(id, row, value) {
        if (id === 'health') return;
        row.classList.toggle('is-low', value <= lowThreshold);
    }

    function setFuel(value) {
        lastFuel = clampPct(value);
        fuelBarFillEl.style.width = lastFuel + '%';
        if (fuelRing) fuelRing.setValue(lastFuel);
        fuelValueEl.textContent = String(lastFuel);
        fuelClusterEl.classList.toggle('is-low', lastFuel <= lowThreshold);
    }

    function updateAllLowStatus() {
        for (const id in barElements) {
            if (barState[id]) applyTone(id, barElements[id].row, clampPct(barState[id].value));
        }
        setFuel(lastFuel);
    }

    function ensureBar(id, iconName) {
        if (barElements[id]) return barElements[id];
        const barObj = createBarRow(id, iconName);
        barElements[id] = barObj;
        statusContainer.appendChild(barObj.row);
        reorderBars();
        reportSizes();
        return barObj;
    }

    function removeBar(id) {
        delete barState[id];
        if (!barElements[id]) return false;
        if (barElements[id].row.parentNode) {
            barElements[id].row.parentNode.removeChild(barElements[id].row);
        }
        delete barElements[id];
        return true;
    }

    function updateBarValue(id, val, iconName) {
        if (val === null || val === undefined) {
            if (removeBar(id)) {
                reorderBars();
                reportSizes();
            }
            return;
        }
        const clamped = clampPct(val);
        barState[id] = { value: clamped, icon: iconName };
        const bar = ensureBar(id, iconName);
        bar.row.classList.remove('hud-hidden');
        bar.setValue(clamped);
        bar.value.textContent = String(clamped);
        applyTone(id, bar.row, clamped);
        reorderBars();
    }

    // Style switch: rebuild every shown bar in the new style from its last value.
    function rebuildBars() {
        const saved = Object.assign({}, barState);
        for (const id of Object.keys(barElements)) {
            if (barElements[id].row.parentNode) {
                barElements[id].row.parentNode.removeChild(barElements[id].row);
            }
            delete barElements[id];
        }
        for (const id of Object.keys(saved)) {
            updateBarValue(id, saved[id].value, saved[id].icon);
        }
        const ring = currentSettings.barStyle === 'ring';
        partStatus.classList.toggle('style-ring', ring);
        partVehicle.classList.toggle('style-ring', ring);
        reportSizes();
    }

    function renderExtraBars() {
        const activeIds = new Set(extraBarsList.map(b => b.id));
        let changed = false;
        for (const id in barElements) {
            if (!builtInBars.includes(id) && !activeIds.has(id)) {
                removeBar(id);
                changed = true;
            }
        }

        for (let i = 0; i < extraBarsList.length; i++) {
            const def = extraBarsList[i];
            if (def.value === null || def.value === undefined) {
                if (removeBar(def.id)) changed = true;
            } else {
                updateBarValue(def.id, def.value, def.icon);
                changed = true;
            }
        }
        reorderBars();
        if (changed) {
            reportSizes();
        }
    }

    function runtimeVisible(id) {
        if (id === 'vehicle') return vehicleVisible;
        if (id === 'compass') return compassReceived;
        if (id === 'voice') return voiceAvailable;
        return true;
    }

    function refreshPart(id) {
        const el = PARTS[id];
        if (!el) return;
        el.classList.toggle('hud-hidden', !!placedHidden[id] || !runtimeVisible(id));
    }

    function applyPlace(id, place) {
        const el = PARTS[id];
        if (!el || !place) return;

        const scale = typeof place.scale === 'number' ? place.scale : 1.0;
        const width = el.offsetWidth || 180;
        const height = el.offsetHeight || 60;

        const left = Math.round(place.x * window.innerWidth - place.ax * width * scale);
        const top = Math.round(place.y * window.innerHeight - place.ay * height * scale);

        el.style.left = left + 'px';
        el.style.top = top + 'px';
        el.style.transform = `scale(${scale})`;
        el.style.transformOrigin = '0 0';

        placedHidden[id] = !!place.hidden;
        refreshPart(id);
    }

    // Mirror of CompassLogic.visibleTicks (shared/logic/compass.lua).
    function compassTicks(heading, span) {
        const list = [];
        const first = Math.ceil((heading - span / 2) / TICK_STEP) * TICK_STEP;
        for (let t = first; t <= heading + span / 2; t += TICK_STEP) {
            const deg = ((t % 360) + 360) % 360;
            list.push({ deg, offset: (t - heading) / span, label: Object.hasOwn(DIR_KEYS, deg) });
        }
        return list;
    }

    function renderCompass() {
        if (compassDeg === null) return;
        const ticks = compassTicks(compassDeg, compassSpan);
        while (tickPool.length < ticks.length) {
            const root = document.createElement('div');
            root.className = 'compass-tick';
            const label = document.createElement('span');
            label.className = 'compass-tick-label';
            root.appendChild(label);
            compassTicksEl.appendChild(root);
            tickPool.push({ root, label });
        }
        for (let i = 0; i < tickPool.length; i++) {
            const el = tickPool[i];
            const t = ticks[i];
            if (!t) {
                el.root.style.display = 'none';
                continue;
            }
            el.root.style.display = '';
            el.root.style.left = (50 + t.offset * 100) + '%';
            el.root.classList.toggle('is-major', t.label);
            el.label.textContent = t.label ? translate(DIR_KEYS[t.deg], DIR_FALLBACK[t.deg]) : '';
        }
        compassDegEl.textContent = String(compassDeg) + '°';
    }

    function setVoice(item) {
        voiceAvailable = item.available === true;
        voiceMicEl.classList.toggle('is-talking', voiceAvailable && item.talking === true);
        const hasMode = typeof item.mode === 'string' && item.mode !== '';
        voiceModeEl.textContent = hasMode ? item.mode : '';
        voiceModeEl.classList.toggle('hud-hidden', !hasMode);
        voiceRadioEl.classList.toggle('hud-hidden', item.radio !== true);
        voiceRadioEl.classList.toggle('is-active', item.radio === true && item.radioActive === true);
        refreshPart('voice');
    }

    function setSeatbelt(state) {
        if (state === true || state === false) {
            seatbeltEl.classList.remove('hud-hidden');
            seatbeltEl.classList.toggle('is-off', state === false);
            const label = state
                ? translate('hudkit.vehicle.seatbelt.on', 'Seatbelt on')
                : translate('hudkit.vehicle.seatbelt.off', 'Seatbelt off');
            seatbeltEl.setAttribute('aria-label', label);
            seatbeltEl.setAttribute('title', label);
        } else {
            seatbeltEl.classList.add('hud-hidden');
        }
    }

    function setSettingsState(s) {
        if (!s) return;
        const prevStyle = currentSettings.barStyle;
        currentSettings = Object.assign({}, currentSettings, s);
        if (currentSettings.barStyle !== 'ring') currentSettings.barStyle = 'bar';

        // Update numbers display
        optNumbers.checked = !!currentSettings.numbers;
        for (const id in barElements) {
            barElements[id].value.classList.toggle('hidden-numbers', !currentSettings.numbers);
        }
        fuelValueEl.classList.toggle('hidden-numbers', !currentSettings.numbers);

        // Update speed unit buttons
        if (currentSettings.speedUnit === 'mph') {
            unitMphBtn.classList.add('active');
            unitKmhBtn.classList.remove('active');
            speedUnitEl.textContent = translate('hudkit.unit.mph', 'mph');
        } else {
            unitKmhBtn.classList.add('active');
            unitMphBtn.classList.remove('active');
            speedUnitEl.textContent = translate('hudkit.unit.kmh', 'km/h');
        }

        // Update minimap mode buttons
        modeAlwaysBtn.classList.toggle('active', currentSettings.minimapMode === 'always');
        modeVehicleBtn.classList.toggle('active', currentSettings.minimapMode === 'vehicle');
        modeNeverBtn.classList.toggle('active', currentSettings.minimapMode === 'never');

        // Update bar style buttons; a change redraws the bars and reports the new sizes to layout
        styleBarBtn.classList.toggle('active', currentSettings.barStyle === 'bar');
        styleRingBtn.classList.toggle('active', currentSettings.barStyle === 'ring');
        if (currentSettings.barStyle !== prevStyle) {
            rebuildBars();
        }
    }

    function applyConfig(item) {
        if (typeof item.low === 'number') {
            lowThreshold = item.low;
        }
        if (typeof item.span === 'number') {
            compassSpan = item.span;
            renderCompass();
        }
    }

    function updateLocaleTexts() {
        document.getElementById('txt-settings-title').textContent = translate('hudkit.settings.title', 'HUD settings');
        document.getElementById('lbl-numbers').textContent = translate('hudkit.settings.numbers', 'Show numbers on bars');
        document.getElementById('lbl-speed-unit').textContent = translate('hudkit.settings.speedUnit', 'Speed unit');
        document.getElementById('lbl-minimap-mode').textContent = translate('hudkit.settings.minimap', 'Minimap');
        document.getElementById('lbl-bar-style').textContent = translate('hudkit.settings.barStyle', 'Bar style');
        document.getElementById('txt-edit-layout').textContent = translate('hudkit.settings.layout', 'Edit layout');
        btnSettingsClose.setAttribute('aria-label', translate('hudkit.settings.close', 'Close'));

        unitKmhBtn.textContent = translate('hudkit.unit.kmh', 'km/h');
        unitMphBtn.textContent = translate('hudkit.unit.mph', 'mph');
        modeAlwaysBtn.textContent = translate('hudkit.settings.minimap.always', 'Always');
        modeVehicleBtn.textContent = translate('hudkit.settings.minimap.vehicle', 'In vehicle');
        modeNeverBtn.textContent = translate('hudkit.settings.minimap.never', 'Never');
        styleBarBtn.textContent = translate('hudkit.settings.barStyle.bar', 'Bar');
        styleRingBtn.textContent = translate('hudkit.settings.barStyle.ring', 'Ring');
        voiceRadioEl.setAttribute('aria-label', translate('hudkit.voice.radio', 'Radio'));
        voiceRadioEl.setAttribute('title', translate('hudkit.voice.radio', 'Radio'));
        renderCompass();
    }

    // Message handler from Lua
    window.addEventListener('message', (event) => {
        const item = event.data;
        if (!item || typeof item !== 'object') return;

        if (item.type === 'aeterna:theme') {
            let link = document.getElementById('theme-override');
            if (item.href) {
                if (!link) {
                    link = document.createElement('link');
                    link.id = 'theme-override';
                    link.rel = 'stylesheet';
                    document.head.appendChild(link);
                }
                link.href = item.href;
            } else if (link) {
                link.parentNode.removeChild(link);
            }
        } else if (item.type === 'locale') {
            if (item.strings && typeof item.strings === 'object') {
                localeStrings = item.strings;
                updateLocaleTexts();
            }
        } else if (item.type === 'hud:values') {
            if (item.status) {
                if (typeof item.status.health === 'number') updateBarValue('health', item.status.health, 'heart');
                if (typeof item.status.armour === 'number') updateBarValue('armour', item.status.armour, 'shield');
                if (item.status.hunger !== undefined) updateBarValue('hunger', item.status.hunger, 'utensils');
                if (item.status.thirst !== undefined) updateBarValue('thirst', item.status.thirst, 'droplet');
                if (item.status.stress !== undefined) updateBarValue('stress', item.status.stress, 'alert-triangle');
            }
            if (item.vehicle) {
                if (item.vehicle.speed !== undefined) speedValueEl.textContent = String(Math.round(item.vehicle.speed));
                if (item.vehicle.unit !== undefined) speedUnitEl.textContent = item.vehicle.unit;
                if (item.vehicle.gear !== undefined) gearIndicatorEl.textContent = item.vehicle.gear;
                if (typeof item.vehicle.fuel === 'number') setFuel(item.vehicle.fuel);
            }
            if (item.street) {
                if (item.street.heading !== undefined) compassBadgeEl.textContent = translate(item.street.heading, item.street.heading);
                if (item.street.street !== undefined) streetNameEl.textContent = item.street.street;
                if (item.street.zone !== undefined) zoneNameEl.textContent = item.street.zone;
            }
        } else if (item.type === 'hud:bars') {
            if (Array.isArray(item.bars)) {
                extraBarsList = item.bars;
                renderExtraBars();
            }
        } else if (item.type === 'hud:place') {
            applyPlace(item.id, item);
        } else if (item.type === 'hud:visible') {
            if (item.id === 'vehicle') {
                vehicleVisible = !!item.visible;
                refreshPart('vehicle');
            }
        } else if (item.type === 'hud:compass') {
            if (typeof item.deg === 'number') {
                compassDeg = ((Math.round(item.deg) % 360) + 360) % 360;
                compassReceived = true;
                renderCompass();
                refreshPart('compass');
            }
        } else if (item.type === 'hud:voice') {
            setVoice(item);
        } else if (item.type === 'hud:seatbelt') {
            setSeatbelt(item.state);
        } else if (item.type === 'settings:apply') {
            applyConfig(item);
            setSettingsState(item.settings);
            updateAllLowStatus();
        } else if (item.type === 'settings:open') {
            applyConfig(item);
            setSettingsState(item.settings);
            updateAllLowStatus();
            settingsCard.classList.remove('hud-hidden');
        } else if (item.type === 'settings:close') {
            settingsCard.classList.add('hud-hidden');
        }
    });

    // Setup initial built-in bars
    updateBarValue('health', 100, 'heart');
    updateBarValue('armour', 100, 'shield');

    // Attach static icons
    const fuelIconContainer = document.getElementById('fuel-icon');
    if (fuelIconContainer) fuelIconContainer.appendChild(window.HudIcons.create('fuel', 12));

    fuelRing = createRing('fuel', 12);
    fuelRingEl.appendChild(fuelRing.root);

    seatbeltEl.appendChild(window.HudIcons.create('link', 14));
    voiceMicEl.appendChild(window.HudIcons.create('mic', 16));
    voiceRadioEl.appendChild(window.HudIcons.create('radio', 16));

    const settingsHeaderIcon = document.getElementById('settings-icon');
    if (settingsHeaderIcon) settingsHeaderIcon.appendChild(window.HudIcons.create('settings', 18));

    const closeIcon = document.getElementById('close-icon');
    if (closeIcon) closeIcon.appendChild(window.HudIcons.create('x', 16));

    const layoutIcon = document.getElementById('layout-icon');
    if (layoutIcon) layoutIcon.appendChild(window.HudIcons.create('sliders', 16));

    // Settings user interactions
    optNumbers.addEventListener('change', () => {
        const val = optNumbers.checked;
        setSettingsState({ numbers: val });
        post('settings', { key: 'numbers', value: val });
    });

    unitKmhBtn.addEventListener('click', () => {
        setSettingsState({ speedUnit: 'kmh' });
        post('settings', { key: 'speedUnit', value: 'kmh' });
    });

    unitMphBtn.addEventListener('click', () => {
        setSettingsState({ speedUnit: 'mph' });
        post('settings', { key: 'speedUnit', value: 'mph' });
    });

    modeAlwaysBtn.addEventListener('click', () => {
        setSettingsState({ minimapMode: 'always' });
        post('settings', { key: 'minimapMode', value: 'always' });
    });

    modeVehicleBtn.addEventListener('click', () => {
        setSettingsState({ minimapMode: 'vehicle' });
        post('settings', { key: 'minimapMode', value: 'vehicle' });
    });

    modeNeverBtn.addEventListener('click', () => {
        setSettingsState({ minimapMode: 'never' });
        post('settings', { key: 'minimapMode', value: 'never' });
    });

    styleBarBtn.addEventListener('click', () => {
        setSettingsState({ barStyle: 'bar' });
        post('settings', { key: 'barStyle', value: 'bar' });
    });

    styleRingBtn.addEventListener('click', () => {
        setSettingsState({ barStyle: 'ring' });
        post('settings', { key: 'barStyle', value: 'ring' });
    });

    btnEditLayout.addEventListener('click', () => {
        settingsCard.classList.add('hud-hidden');
        post('layoutEditor', {});
    });

    btnSettingsClose.addEventListener('click', () => {
        settingsCard.classList.add('hud-hidden');
        post('close', {});
    });

    window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (!settingsCard.classList.contains('hud-hidden')) {
                settingsCard.classList.add('hud-hidden');
                post('close', {});
            }
        }
    });

    // Measure parts and report ready to client Lua
    window.addEventListener('DOMContentLoaded', () => {
        reportSizes();
    });
})();
