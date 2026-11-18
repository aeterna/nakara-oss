// html/app.js -- NUI application logic for aeterna_hudkit.
// Strict rule: text updates through textContent only (no dynamic innerHTML).

(function () {
    const RESOURCE_NAME = 'aeterna_hudkit';

    let currentSettings = {
        numbers: false,
        speedUnit: 'kmh',
        minimapMode: 'always',
    };
    let localeStrings = {};
    let lowThreshold = 20;

    // DOM Elements
    const statusContainer = document.getElementById('status-bars');
    const partStatus = document.getElementById('part-status');
    const partVehicle = document.getElementById('part-vehicle');
    const partStreet = document.getElementById('part-street');
    const settingsCard = document.getElementById('settings-card');

    const speedValueEl = document.getElementById('speed-value');
    const speedUnitEl = document.getElementById('speed-unit');
    const gearIndicatorEl = document.getElementById('gear-indicator');
    const fuelClusterEl = document.querySelector('.fuel-cluster');
    const fuelBarFillEl = document.getElementById('fuel-bar-fill');
    const compassBadgeEl = document.getElementById('compass-badge');
    const streetNameEl = document.getElementById('street-name');
    const zoneNameEl = document.getElementById('zone-name');

    // Settings Controls
    const optNumbers = document.getElementById('opt-numbers');
    const unitKmhBtn = document.getElementById('unit-kmh');
    const unitMphBtn = document.getElementById('unit-mph');
    const modeAlwaysBtn = document.getElementById('mode-always');
    const modeVehicleBtn = document.getElementById('mode-vehicle');
    const modeNeverBtn = document.getElementById('mode-never');
    const btnEditLayout = document.getElementById('btn-edit-layout');
    const btnSettingsClose = document.getElementById('btn-settings-close');

    // Bar state registry
    const builtInBars = ['health', 'armour', 'hunger', 'thirst', 'stress'];
    const barElements = {}; // barId -> { row, fill, value, icon }
    let extraBarsList = [];
    let vehicleVisible = false;
    let vehiclePlacedHidden = false;
    let lastReportedSizes = null;

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

    function createBarRow(id, iconName) {
        const row = document.createElement('div');
        row.className = 'bar-row';
        row.dataset.bar = id;

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

        const val = document.createElement('span');
        val.className = 'bar-value';
        if (!currentSettings.numbers) {
            val.classList.add('hidden-numbers');
        }
        val.textContent = '100';

        row.appendChild(iconWrap);
        row.appendChild(track);
        row.appendChild(val);

        return { row, fill, value: val, iconWrap };
    }

    function reorderBars() {
        const builtInOrder = ['health', 'armour', 'hunger', 'thirst', 'stress'];
        for (let i = 0; i < builtInOrder.length; i++) {
            const id = builtInOrder[i];
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
        const sizes = {
            status: measurePart(partStatus),
            vehicle: measurePart(partVehicle),
            street: measurePart(partStreet),
        };

        if (
            !lastReportedSizes ||
            lastReportedSizes.status.w !== sizes.status.w ||
            lastReportedSizes.status.h !== sizes.status.h ||
            lastReportedSizes.vehicle.w !== sizes.vehicle.w ||
            lastReportedSizes.vehicle.h !== sizes.vehicle.h ||
            lastReportedSizes.street.w !== sizes.street.w ||
            lastReportedSizes.street.h !== sizes.street.h
        ) {
            lastReportedSizes = sizes;
            post('ready', { sizes });
        }
    }

    function updateAllLowStatus() {
        for (const id in barElements) {
            if (id !== 'health') {
                const bar = barElements[id];
                const currentVal = parseFloat(bar.value.textContent);
                if (!isNaN(currentVal)) {
                    if (currentVal <= lowThreshold) {
                        bar.row.classList.add('is-low');
                    } else {
                        bar.row.classList.remove('is-low');
                    }
                }
            }
        }
        const currentFuel = parseFloat(fuelBarFillEl.style.width) || 0;
        if (currentFuel <= lowThreshold) {
            fuelClusterEl.classList.add('is-low');
        } else {
            fuelClusterEl.classList.remove('is-low');
        }
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

    function updateBarValue(id, val, iconName) {
        if (val === null || val === undefined) {
            if (barElements[id]) {
                if (barElements[id].row.parentNode) {
                    barElements[id].row.parentNode.removeChild(barElements[id].row);
                }
                delete barElements[id];
                reorderBars();
                reportSizes();
            }
            return;
        }
        const bar = ensureBar(id, iconName);
        bar.row.classList.remove('hud-hidden');

        const clamped = Math.max(0, Math.min(100, Math.round(val)));
        bar.fill.style.width = clamped + '%';
        bar.value.textContent = String(clamped);

        if (id !== 'health') {
            if (clamped <= lowThreshold) {
                bar.row.classList.add('is-low');
            } else {
                bar.row.classList.remove('is-low');
            }
        }
        reorderBars();
    }

    function renderExtraBars() {
        // Remove old extra bars not in list
        const activeIds = new Set(extraBarsList.map(b => b.id));
        let changed = false;
        for (const id in barElements) {
            if (!builtInBars.includes(id) && !activeIds.has(id)) {
                if (barElements[id].row.parentNode) {
                    barElements[id].row.parentNode.removeChild(barElements[id].row);
                }
                delete barElements[id];
                changed = true;
            }
        }

        for (let i = 0; i < extraBarsList.length; i++) {
            const def = extraBarsList[i];
            if (def.value === null || def.value === undefined) {
                if (barElements[def.id]) {
                    if (barElements[def.id].row.parentNode) {
                        barElements[def.id].row.parentNode.removeChild(barElements[def.id].row);
                    }
                    delete barElements[def.id];
                    changed = true;
                }
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

    function applyPlace(id, place) {
        let el = null;
        if (id === 'status') el = partStatus;
        else if (id === 'vehicle') el = partVehicle;
        else if (id === 'street') el = partStreet;

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

        if (id === 'vehicle') {
            vehiclePlacedHidden = !!place.hidden;
            if (vehiclePlacedHidden || !vehicleVisible) {
                el.classList.add('hud-hidden');
            } else {
                el.classList.remove('hud-hidden');
            }
        } else {
            if (place.hidden) {
                el.classList.add('hud-hidden');
            } else {
                el.classList.remove('hud-hidden');
            }
        }
    }

    function setSettingsState(s) {
        if (!s) return;
        currentSettings = Object.assign({}, currentSettings, s);

        // Update numbers display
        optNumbers.checked = !!currentSettings.numbers;
        for (const id in barElements) {
            if (currentSettings.numbers) {
                barElements[id].value.classList.remove('hidden-numbers');
            } else {
                barElements[id].value.classList.add('hidden-numbers');
            }
        }

        // Update speed unit buttons
        if (currentSettings.speedUnit === 'mph') {
            unitMphBtn.classList.add('active');
            unitKmhBtn.classList.remove('active');
            speedUnitEl.textContent = 'mph';
        } else {
            unitKmhBtn.classList.add('active');
            unitMphBtn.classList.remove('active');
            speedUnitEl.textContent = 'km/h';
        }

        // Update minimap mode buttons
        modeAlwaysBtn.classList.toggle('active', currentSettings.minimapMode === 'always');
        modeVehicleBtn.classList.toggle('active', currentSettings.minimapMode === 'vehicle');
        modeNeverBtn.classList.toggle('active', currentSettings.minimapMode === 'never');
    }

    function updateLocaleTexts() {
        document.getElementById('txt-settings-title').textContent = translate('hudkit.settings.title', 'HUD settings');
        document.getElementById('lbl-numbers').textContent = translate('hudkit.settings.numbers', 'Show numbers on bars');
        document.getElementById('lbl-speed-unit').textContent = translate('hudkit.settings.speedUnit', 'Speed unit');
        document.getElementById('lbl-minimap-mode').textContent = translate('hudkit.settings.minimap', 'Minimap');
        document.getElementById('txt-edit-layout').textContent = translate('hudkit.settings.layout', 'Edit layout');

        unitKmhBtn.textContent = translate('hudkit.unit.kmh', 'km/h');
        unitMphBtn.textContent = translate('hudkit.unit.mph', 'mph');
        modeAlwaysBtn.textContent = translate('hudkit.settings.minimap.always', 'Always');
        modeVehicleBtn.textContent = translate('hudkit.settings.minimap.vehicle', 'In vehicle');
        modeNeverBtn.textContent = translate('hudkit.settings.minimap.never', 'Never');
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
                if (typeof item.vehicle.fuel === 'number') {
                    const fuelClamped = Math.max(0, Math.min(100, Math.round(item.vehicle.fuel)));
                    fuelBarFillEl.style.width = fuelClamped + '%';
                    if (fuelClamped <= lowThreshold) {
                        fuelClusterEl.classList.add('is-low');
                    } else {
                        fuelClusterEl.classList.remove('is-low');
                    }
                }
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
                if (vehicleVisible && !vehiclePlacedHidden) {
                    partVehicle.classList.remove('hud-hidden');
                } else {
                    partVehicle.classList.add('hud-hidden');
                }
            }
        } else if (item.type === 'settings:apply') {
            if (typeof item.low === 'number') {
                lowThreshold = item.low;
            }
            setSettingsState(item.settings);
            updateAllLowStatus();
        } else if (item.type === 'settings:open') {
            if (typeof item.low === 'number') {
                lowThreshold = item.low;
            }
            setSettingsState(item.settings);
            updateAllLowStatus();
            settingsCard.classList.remove('hud-hidden');
        } else if (item.type === 'settings:close') {
            settingsCard.classList.add('hud-hidden');
        }
    });

    // Setup initial built-in bars
    ensureBar('health', 'heart');
    ensureBar('armour', 'shield');

    // Attach static icons
    const fuelIconContainer = document.getElementById('fuel-icon');
    if (fuelIconContainer) fuelIconContainer.appendChild(window.HudIcons.create('fuel', 12));

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
