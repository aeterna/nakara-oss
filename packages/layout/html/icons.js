// Inline Lucide icon map for aeterna_layout (ISC License, see NOTICE).
// Constructed via SVG DOM nodes only (never innerHTML).

const SVG_NS = 'http://www.w3.org/2000/svg';

const ICON_SHAPES = {
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
    'check': [
        ['path', { d: 'M20 6 9 17l-5-5' }],
    ],
    'x': [
        ['path', { d: 'M18 6 6 18' }],
        ['path', { d: 'm6 6 12 12' }],
    ],
    'plus': [
        ['path', { d: 'M5 12h14' }],
        ['path', { d: 'M12 5v14' }],
    ],
    'minus': [
        ['path', { d: 'M5 12h14' }],
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

window.AeternaLayoutIcons = {
    create: createLucideIcon,
    has: (name) => Object.hasOwn(ICON_SHAPES, name),
};
