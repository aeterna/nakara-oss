// html/icons.js -- Inline Lucide icon map for aeterna_hudkit (ISC License, see NOTICE).
// Constructed via SVG DOM nodes only (never innerHTML).

const SVG_NS = 'http://www.w3.org/2000/svg';

const ICON_SHAPES = {
    'heart': [
        ['path', { d: 'M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z' }],
    ],
    'shield': [
        ['path', { d: 'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z' }],
    ],
    'utensils': [
        ['path', { d: 'M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2' }],
        ['path', { d: 'M7 2v20' }],
        ['path', { d: 'M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7' }],
    ],
    'droplet': [
        ['path', { d: 'M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z' }],
    ],
    'alert-triangle': [
        ['path', { d: 'm21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3' }],
        ['path', { d: 'M12 9v4' }],
        ['path', { d: 'M12 17h.01' }],
    ],
    'car': [
        ['path', { d: 'M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2' }],
        ['circle', { cx: '7', cy: '17', r: '2' }],
        ['path', { d: 'M9 17h6' }],
        ['circle', { cx: '17', cy: '17', r: '2' }],
    ],
    'compass': [
        ['circle', { cx: '12', cy: '12', r: '10' }],
        ['polygon', { points: '16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76' }],
    ],
    'gauge': [
        ['path', { d: 'm12 14 4-4' }],
        ['path', { d: 'M3.34 19a10 10 0 1 1 17.32 0' }],
    ],
    'fuel': [
        ['line', { x1: '3', x2: '15', y1: '22', y2: '22' }],
        ['line', { x1: '4', x2: '14', y1: '9', y2: '9' }],
        ['path', { d: 'M14 22V4a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v18' }],
        ['path', { d: 'M14 13h2a2 2 0 0 1 2 2v2a2 2 0 0 0 2 2h0a2 2 0 0 0 2-2V9.83a2 2 0 0 0-.59-1.42L18 5' }],
    ],
    'sliders': [
        ['line', { x1: '4', x2: '4', y1: '21', y2: '14' }],
        ['line', { x1: '4', x2: '4', y1: '10', y2: '3' }],
        ['line', { x1: '12', x2: '12', y1: '21', y2: '12' }],
        ['line', { x1: '12', x2: '12', y1: '8', y2: '3' }],
        ['line', { x1: '20', x2: '20', y1: '21', y2: '16' }],
        ['line', { x1: '20', x2: '20', y1: '12', y2: '3' }],
        ['line', { x1: '2', x2: '6', y1: '14', y2: '14' }],
        ['line', { x1: '10', x2: '14', y1: '8', y2: '8' }],
        ['line', { x1: '18', x2: '22', y1: '16', y2: '16' }],
    ],
    'settings': [
        ['path', { d: 'M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z' }],
        ['circle', { cx: '12', cy: '12', r: '3' }],
    ],
    'check': [
        ['path', { d: 'M20 6 9 17l-5-5' }],
    ],
    'x': [
        ['path', { d: 'M18 6 6 18' }],
        ['path', { d: 'm6 6 12 12' }],
    ],
    'activity': [
        ['path', { d: 'M22 12h-4l-3 9L9 3l-3 9H2' }],
    ],
    'zap': [
        ['polygon', { points: '13 2 3 14 12 14 11 22 21 10 12 10 13 2' }],
    ],
};

function createLucideIcon(name, size) {
    const shapes = Object.hasOwn(ICON_SHAPES, name) ? ICON_SHAPES[name] : null;
    if (!shapes) return null;
    const px = String(size || 16);
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('width', px);
    svg.setAttribute('height', px);
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    svg.setAttribute('aria-hidden', 'true');

    for (let i = 0; i < shapes.length; i++) {
        const [tag, attrs] = shapes[i];
        const node = document.createElementNS(SVG_NS, tag);
        for (const [k, v] of Object.entries(attrs)) {
            node.setAttribute(k, v);
        }
        svg.appendChild(node);
    }
    return svg;
}

window.HudIcons = {
    create: createLucideIcon,
    has: (name) => Object.hasOwn(ICON_SHAPES, name),
};
