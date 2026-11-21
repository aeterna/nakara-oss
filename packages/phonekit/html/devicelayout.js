// devicelayout.js -- Pure layout math and device definitions for aeterna_phonekit 0.2.
// Chrome 103 compatible, zero DOM access, self-contained for browser and Node.

(function (global) {
    'use strict';

    const DEFAULT_MODEL = 'slab';

    // Eight models defined in spec § Models and frames, § Model names
    const MODELS = {
        keypad: {
            id: 'keypad',
            neutralName: 'Keypad',
            universeName: 'Whiz Keypad',
            width: 300,
            height: 660,
            canFold: false,
            defaultFold: null,
            homeStyle: 'list',
            tilesPerPage: null,
            calls: true,
            batteryMult: 4,
            rank: 1,
            colors: ['#33363B', '#3A5F8F', '#D9762B'],
        },
        burner: {
            id: 'burner',
            neutralName: 'Burner',
            universeName: 'Badger Burner',
            width: 300,
            height: 660,
            canFold: false,
            defaultFold: null,
            homeStyle: 'list',
            tilesPerPage: null,
            calls: true,
            batteryMult: 3,
            rank: 0,
            colors: ['#18191B', '#4B5240'],
        },
        qwerty: {
            id: 'qwerty',
            neutralName: 'Qwerty',
            universeName: 'Badger Qwerty',
            width: 392,
            height: 760,
            canFold: false,
            defaultFold: null,
            homeStyle: 'grid',
            tilesPerPage: 8,
            calls: true,
            batteryMult: 2,
            rank: 2,
            colors: ['#2B2D30', '#B8BCC2'],
        },
        slab: {
            id: 'slab',
            neutralName: 'Slab',
            universeName: 'Facade Slab',
            width: 392,
            height: 812,
            canFold: false,
            defaultFold: null,
            homeStyle: 'grid',
            tilesPerPage: 12,
            calls: true,
            batteryMult: 1,
            rank: 4,
            colors: ['#3D4046', '#C9CCD1', '#CDBB9A', '#5C7FA8'],
        },
        fold: {
            id: 'fold',
            neutralName: 'Fold',
            universeName: 'Facade Fold',
            openWidth: 380,
            openHeight: 842,
            closedWidth: 380,
            closedHeight: 430,
            canFold: true,
            defaultFold: 'open',
            homeStyle: 'grid',
            tilesPerPage: 12,
            calls: true,
            batteryMult: 1,
            rank: 5,
            colors: ['#36383D', '#D4C3A3', '#6F8F7A'],
        },
        pro: {
            id: 'pro',
            neutralName: 'Pro',
            universeName: 'iFruit Pro',
            width: 392,
            height: 812,
            canFold: false,
            defaultFold: null,
            homeStyle: 'grid',
            tilesPerPage: 12,
            calls: true,
            batteryMult: 1.2,
            rank: 6,
            colors: ['#45474B', '#BDBFC2', '#3F536E', '#B9A584'],
        },
        book: {
            id: 'book',
            neutralName: 'Book',
            universeName: 'iFruit Book',
            openWidth: 780,
            openHeight: 700,
            closedWidth: 380,
            closedHeight: 812,
            canFold: true,
            defaultFold: 'closed',
            homeStyle: 'grid',
            tilesClosed: 12,
            tilesOpen: 24,
            panesClosed: 1,
            panesOpen: 2,
            calls: true,
            batteryMult: 1,
            rank: 7,
            colors: ['#404247', '#CED0D3'],
        },
        pad: {
            id: 'pad',
            neutralName: 'Pad',
            universeName: 'iFruit Pad',
            width: 600,
            height: 812,
            canFold: false,
            defaultFold: null,
            homeStyle: 'grid',
            tilesPerPage: 20,
            calls: false,
            batteryMult: 1.5,
            rank: 3,
            colors: ['#C4C7CB', '#4E5056', '#6C8DB3'],
        },
    };

    function getModel(modelId) {
        if (modelId && Object.prototype.hasOwnProperty.call(MODELS, modelId)) {
            return MODELS[modelId];
        }
        return MODELS[DEFAULT_MODEL];
    }

    function canFold(modelId) {
        return !!getModel(modelId).canFold;
    }

    function getDefaultFold(modelId) {
        return getModel(modelId).defaultFold;
    }

    function normalizeFold(modelId, foldState) {
        const m = getModel(modelId);
        if (!m.canFold) return null;
        if (foldState === 'open' || foldState === 'closed') {
            return foldState;
        }
        return m.defaultFold;
    }

    function getDimensions(modelId, foldState) {
        const m = getModel(modelId);
        if (!m.canFold) {
            return { width: m.width, height: m.height };
        }
        const state = normalizeFold(modelId, foldState);
        if (state === 'closed') {
            return { width: m.closedWidth, height: m.closedHeight };
        }
        return { width: m.openWidth, height: m.openHeight };
    }

    // fit = min(1, (vh − 0.048 × vh) / h, (vw − 0.048 × vh) / w)
    function calculateFit(width, height, vw, vh) {
        const w = Number(width) || 0;
        const h = Number(height) || 0;
        const viewW = Number(vw) || 0;
        const viewH = Number(vh) || 0;
        if (w <= 0 || h <= 0 || viewW <= 0 || viewH <= 0) {
            return 1;
        }
        const marginH = 0.048 * viewH;
        const fitH = (viewH - marginH) / h;
        const fitW = (viewW - marginH) / w;
        const fit = Math.min(1, fitH, fitW);
        return fit > 0 && isFinite(fit) ? fit : 1;
    }

    function calculateDrawnScale(placeScale, fit) {
        const scale = Number(placeScale) || 1.0;
        const fitVal = Number(fit) || 1.0;
        return Math.min(scale, fitVal);
    }

    function getPanesPerPage(modelId, foldState) {
        const m = getModel(modelId);
        if (m.id === 'book') {
            return normalizeFold(modelId, foldState) === 'open' ? m.panesOpen : m.panesClosed;
        }
        return 1;
    }

    function getTilesPerPage(modelId, foldState) {
        const m = getModel(modelId);
        if (m.id === 'book') {
            return normalizeFold(modelId, foldState) === 'open' ? m.tilesOpen : m.tilesClosed;
        }
        return m.tilesPerPage;
    }

    function isTwoPane(modelId, foldState) {
        return modelId === 'book' && normalizeFold(modelId, foldState) === 'open';
    }

    function isCoverScreen(modelId, foldState) {
        return modelId === 'fold' && normalizeFold(modelId, foldState) === 'closed';
    }

    function isKeypad(modelId) {
        return getModel(modelId).homeStyle === 'list';
    }

    function canMakeCalls(modelId) {
        return !!getModel(modelId).calls;
    }

    function getBatteryMultiplier(modelId) {
        return getModel(modelId).batteryMult;
    }

    function getRank(modelId) {
        return getModel(modelId).rank;
    }

    function getColors(modelId) {
        return getModel(modelId).colors.slice();
    }

    function getDefaultColor(modelId) {
        return getModel(modelId).colors[0];
    }

    function getDisplayName(modelId, preset) {
        const m = getModel(modelId);
        return preset === 'universe' ? m.universeName : m.neutralName;
    }

    // Active device comparator: highest rank, tie-breaker smallest id
    function compareDevices(a, b) {
        const rankA = getRank(a && a.model);
        const rankB = getRank(b && b.model);
        if (rankB !== rankA) {
            return rankB - rankA;
        }
        const idA = String((a && a.id) || '');
        const idB = String((b && b.id) || '');
        return idA.localeCompare(idB);
    }

    // Clamp coordinates within viewport with inset
    function clampPosition(x, y, width, height, scale, vw, vh, inset) {
        const ins = inset !== undefined ? inset : 24;
        const sc = scale || 1;
        const totalW = width * sc;
        const totalH = height * sc;
        const minX = ins;
        const minY = ins;
        const maxX = Math.max(minX, vw - totalW - ins);
        const maxY = Math.max(minY, vh - totalH - ins);
        return {
            x: Math.max(minX, Math.min(x, maxX)),
            y: Math.max(minY, Math.min(y, maxY)),
        };
    }

    const DeviceLayout = {
        DEFAULT_MODEL,
        MODELS,
        getModel,
        canFold,
        getDefaultFold,
        normalizeFold,
        getDimensions,
        calculateFit,
        calculateDrawnScale,
        getPanesPerPage,
        getTilesPerPage,
        isTwoPane,
        isCoverScreen,
        isKeypad,
        canMakeCalls,
        getBatteryMultiplier,
        getRank,
        getColors,
        getDefaultColor,
        getDisplayName,
        compareDevices,
        clampPosition,
    };

    if (typeof module !== 'undefined' && module.exports) {
        module.exports = DeviceLayout;
    }
    if (typeof global !== 'undefined') {
        global.DeviceLayout = DeviceLayout;
    }
})(typeof window !== 'undefined' ? window : this);
