// Inline Lucide icons for aeterna_camera (ISC License, see NOTICE). Built with SVG DOM nodes only, never innerHTML.
'use strict';

const SVG_NS = 'http://www.w3.org/2000/svg';

const ICON_SHAPES = {
    'x': [
        ['path', { d: 'M18 6 6 18' }],
        ['path', { d: 'm6 6 12 12' }],
    ],
    'trash': [
        ['path', { d: 'M3 6h18' }],
        ['path', { d: 'M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6' }],
        ['path', { d: 'M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2' }],
    ],
    'chevron-left': [
        ['path', { d: 'm15 18-6-6 6-6' }],
    ],
    'image': [
        ['rect', { width: '18', height: '18', x: '3', y: '3', rx: '2', ry: '2' }],
        ['circle', { cx: '9', cy: '9', r: '2' }],
        ['path', { d: 'm21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21' }],
    ],
};

function createIcon(name, size) {
    const shapes = Object.hasOwn(ICON_SHAPES, name) ? ICON_SHAPES[name] : null;
    if (!shapes) return null;
    const px = String(size || 18);
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
        for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
        svg.appendChild(node);
    }
    return svg;
}

window.AeternaCameraIcons = { create: createIcon };
