// spikes/s1/kspike_a/html/app.js
// NUI logic for element owner A.

const box = document.getElementById('box');
box.textContent = 'A';

const DEFAULT_X = 0.05;
const DEFAULT_Y = 0.30;

let currentX = DEFAULT_X;
let currentY = DEFAULT_Y;

function postNui(endpoint, data) {
    const resource = window.GetParentResourceName ? window.GetParentResourceName() : 'kspike_a';
    return fetch(`https://${resource}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {})
    }).catch(() => {});
}

function updateBoxPosition(x, y) {
    currentX = x;
    currentY = y;
    box.style.left = (x * window.innerWidth) + 'px';
    box.style.top = (y * window.innerHeight) + 'px';
}

// Initial positioning at default location
updateBoxPosition(currentX, currentY);

// Measure initial dimensions and notify Lua
const rect = box.getBoundingClientRect();
postNui('ready', {
    w: rect.width,
    h: rect.height
});

// Listen for position updates from Lua
window.addEventListener('message', (event) => {
    const item = event.data;
    if (item && item.type === 'pos') {
        const x = Number(item.x) || 0;
        const y = Number(item.y) || 0;
        updateBoxPosition(x, y);

        const updatedRect = box.getBoundingClientRect();
        postNui('applied', {
            x: x,
            y: y,
            left: updatedRect.left,
            top: updatedRect.top
        });
    }
});

// Maintain relative coordinates on screen resize
window.addEventListener('resize', () => {
    updateBoxPosition(currentX, currentY);
});
