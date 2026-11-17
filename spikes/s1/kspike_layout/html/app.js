// spikes/s1/kspike_layout/html/app.js
// Test menu and overlay editor for HUD elements.

const menuContainer = document.getElementById('menu-container');
const editorContainer = document.getElementById('editor-container');
const menuStatus = document.getElementById('menu-status');
const boxesContainer = document.getElementById('boxes-layer');
const doneBtn = document.getElementById('btn-done');

const btnLayout = document.getElementById('btn-menu-layout');
const btnReset = document.getElementById('btn-menu-reset');
const btnRerun = document.getElementById('btn-menu-rerun');
const btnClose = document.getElementById('btn-menu-close');

let activeDrag = null;
let lastMovePostTime = 0;
let registeredElements = [];
let currentView = 'none';

function postNui(endpoint, data) {
    const resource = window.GetParentResourceName ? window.GetParentResourceName() : 'kspike_layout';
    return fetch(`https://${resource}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {})
    }).catch(() => {});
}

function clamp(val, min, max) {
    return Math.max(min, Math.min(max, val));
}

function showMenu(count) {
    currentView = 'menu';
    document.body.className = 'active menu-mode';
    editorContainer.classList.add('hidden');
    menuContainer.classList.remove('hidden');
    menuStatus.textContent = 'กล่องที่ลงทะเบียน: ' + (count !== undefined ? count : 0);
}

function showEditor(elements) {
    currentView = 'editor';
    document.body.className = 'active editor-mode';
    menuContainer.classList.add('hidden');
    editorContainer.classList.remove('hidden');
    renderElements(elements || []);
}

function hideAll() {
    currentView = 'none';
    document.body.className = 'hidden';
    menuContainer.classList.add('hidden');
    editorContainer.classList.add('hidden');
}

function closeUI() {
    hideAll();
    postNui('close', {});
}

// Menu button click listeners
btnLayout.addEventListener('click', () => {
    postNui('menu_edit', {});
});

btnReset.addEventListener('click', () => {
    postNui('menu_reset', {});
    menuStatus.textContent = 'รีเซ็ตแล้ว';
});

btnRerun.addEventListener('click', () => {
    hideAll();
    postNui('menu_rerun_s2', {});
});

btnClose.addEventListener('click', () => {
    closeUI();
});

doneBtn.addEventListener('click', () => {
    closeUI();
});

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || e.key === 'Esc') {
        closeUI();
    }
});

function renderElements(elements) {
    registeredElements = elements || [];
    while (boxesContainer.firstChild) {
        boxesContainer.removeChild(boxesContainer.firstChild);
    }

    registeredElements.forEach((elem) => {
        const box = document.createElement('div');
        box.className = 'outline-box';
        box.dataset.owner = elem.owner;
        box.dataset.id = elem.id;

        const leftPx = elem.x * window.innerWidth;
        const topPx = elem.y * window.innerHeight;

        box.style.width = elem.w + 'px';
        box.style.height = elem.h + 'px';
        box.style.left = leftPx + 'px';
        box.style.top = topPx + 'px';

        const label = document.createElement('span');
        label.className = 'box-label';
        label.textContent = elem.owner + '/' + elem.id;
        box.appendChild(label);

        box.addEventListener('pointerdown', (e) => {
            e.preventDefault();
            box.setPointerCapture(e.pointerId);
            box.classList.add('dragging');

            const currentLeft = parseFloat(box.style.left) || 0;
            const currentTop = parseFloat(box.style.top) || 0;

            activeDrag = {
                pointerId: e.pointerId,
                elem: box,
                owner: elem.owner,
                id: elem.id,
                startX: e.clientX,
                startY: e.clientY,
                initialLeft: currentLeft,
                initialTop: currentTop,
                lastXFraction: elem.x,
                lastYFraction: elem.y
            };
            lastMovePostTime = Date.now();
        });

        boxesContainer.appendChild(box);
    });
}

window.addEventListener('pointermove', (e) => {
    if (!activeDrag || activeDrag.pointerId !== e.pointerId) {
        return;
    }

    const deltaX = e.clientX - activeDrag.startX;
    const deltaY = e.clientY - activeDrag.startY;

    const newLeftPx = activeDrag.initialLeft + deltaX;
    const newTopPx = activeDrag.initialTop + deltaY;

    const fractionX = clamp(newLeftPx / window.innerWidth, 0, 1);
    const fractionY = clamp(newTopPx / window.innerHeight, 0, 1);

    activeDrag.elem.style.left = (fractionX * window.innerWidth) + 'px';
    activeDrag.elem.style.top = (fractionY * window.innerHeight) + 'px';

    activeDrag.lastXFraction = fractionX;
    activeDrag.lastYFraction = fractionY;

    const found = registeredElements.find(
        (el) => el.owner === activeDrag.owner && el.id === activeDrag.id
    );
    if (found) {
        found.x = fractionX;
        found.y = fractionY;
    }

    const now = Date.now();
    if (now - lastMovePostTime >= 100) {
        lastMovePostTime = now;
        postNui('moved', {
            owner: activeDrag.owner,
            id: activeDrag.id,
            x: fractionX,
            y: fractionY
        });
    }
});

function finishDrag(e) {
    if (!activeDrag || activeDrag.pointerId !== e.pointerId) {
        return;
    }

    const drag = activeDrag;
    activeDrag = null;

    drag.elem.classList.remove('dragging');
    try {
        drag.elem.releasePointerCapture(e.pointerId);
    } catch (_) {}

    postNui('moved', {
        owner: drag.owner,
        id: drag.id,
        x: drag.lastXFraction,
        y: drag.lastYFraction
    });
}

window.addEventListener('pointerup', finishDrag);
window.addEventListener('pointercancel', finishDrag);

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data) return;

    if (data.action === 'menu') {
        showMenu(data.count);
    } else if (data.action === 'open') {
        showEditor(data.elements || []);
    } else if (data.action === 'close') {
        hideAll();
    }
});

window.addEventListener('resize', () => {
    if (currentView === 'editor' && registeredElements.length > 0) {
        renderElements(registeredElements);
    }
});
