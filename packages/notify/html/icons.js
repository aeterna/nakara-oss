// Inline Lucide icon map for aeterna_notify (ISC License, see NOTICE).
// Constructed via SVG DOM nodes only (never innerHTML).

const SVG_NS = 'http://www.w3.org/2000/svg';

const ICON_SHAPES = {
    'home': [
        ['path', { d: 'M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8' }],
        ['path', { d: 'M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z' }],
    ],
    'bell': [
        ['path', { d: 'M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9' }],
        ['path', { d: 'M10.3 21a1.94 1.94 0 0 0 3.4 0' }],
    ],
    'box': [
        ['path', { d: 'M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z' }],
        ['path', { d: 'm3.3 7 8.7 5 8.7-5' }],
        ['path', { d: 'M12 22V12' }],
    ],
    'user': [
        ['path', { d: 'M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2' }],
        ['circle', { cx: '12', cy: '7', r: '4' }],
    ],
    'users': [
        ['path', { d: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2' }],
        ['circle', { cx: '9', cy: '7', r: '4' }],
        ['path', { d: 'M22 21v-2a4 4 0 0 0-3-3.87' }],
        ['path', { d: 'M16 3.13a4 4 0 0 1 0 7.75' }],
    ],
    'phone': [
        ['path', { d: 'M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92z' }],
    ],
    'message-circle': [
        ['path', { d: 'M7.9 20A9 9 0 1 0 4 16.1L2 22Z' }],
    ],
    'calculator': [
        ['rect', { width: '16', height: '20', x: '4', y: '2', rx: '2' }],
        ['line', { x1: '8', x2: '16', y1: '6', y2: '6' }],
        ['line', { x1: '16', x2: '16', y1: '14', y2: '18' }],
        ['path', { d: 'M16 10h.01' }],
        ['path', { d: 'M12 10h.01' }],
        ['path', { d: 'M8 10h.01' }],
        ['path', { d: 'M12 14h.01' }],
        ['path', { d: 'M8 14h.01' }],
        ['path', { d: 'M12 18h.01' }],
        ['path', { d: 'M8 18h.01' }],
    ],
    'file-text': [
        ['path', { d: 'M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z' }],
        ['path', { d: 'M14 2v4a2 2 0 0 0 2 2h4' }],
        ['path', { d: 'M10 9H8' }],
        ['path', { d: 'M16 13H8' }],
        ['path', { d: 'M16 17H8' }],
    ],
    'settings': [
        ['path', { d: 'M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z' }],
        ['circle', { cx: '12', cy: '12', r: '3' }],
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
    'map': [
        ['path', { d: 'M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z' }],
        ['path', { d: 'M15 5.764v15' }],
        ['path', { d: 'M9 3.236v15' }],
    ],
    'map-pin': [
        ['path', { d: 'M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0' }],
        ['circle', { cx: '12', cy: '10', r: '3' }],
    ],
    'car': [
        ['path', { d: 'M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2' }],
        ['circle', { cx: '7', cy: '17', r: '2' }],
        ['path', { d: 'M9 17h6' }],
        ['circle', { cx: '17', cy: '17', r: '2' }],
    ],
    'wrench': [
        ['path', { d: 'M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z' }],
    ],
    'shield': [
        ['path', { d: 'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z' }],
    ],
    'heart': [
        ['path', { d: 'M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z' }],
    ],
    'droplet': [
        ['path', { d: 'M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z' }],
    ],
    'utensils': [
        ['path', { d: 'M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2' }],
        ['path', { d: 'M7 2v20' }],
        ['path', { d: 'M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7' }],
    ],
    'clock': [
        ['circle', { cx: '12', cy: '12', r: '10' }],
        ['polyline', { points: '12 6 12 12 16 14' }],
    ],
    'calendar': [
        ['path', { d: 'M8 2v4' }],
        ['path', { d: 'M16 2v4' }],
        ['rect', { width: '18', height: '18', x: '3', y: '4', rx: '2' }],
        ['path', { d: 'M3 10h18' }],
    ],
    'info': [
        ['circle', { cx: '12', cy: '12', r: '10' }],
        ['path', { d: 'M12 16v-4' }],
        ['path', { d: 'M12 8h.01' }],
    ],
    'alert-triangle': [
        ['path', { d: 'm21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3' }],
        ['path', { d: 'M12 9v4' }],
        ['path', { d: 'M12 17h.01' }],
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
    'search': [
        ['circle', { cx: '11', cy: '11', r: '8' }],
        ['path', { d: 'm21 21-4.3-4.3' }],
    ],
    'lock': [
        ['rect', { width: '18', height: '11', x: '3', y: '11', rx: '2', ry: '2' }],
        ['path', { d: 'M7 11V7a5 5 0 0 1 10 0v4' }],
    ],
    'unlock': [
        ['rect', { width: '18', height: '11', x: '3', y: '11', rx: '2', ry: '2' }],
        ['path', { d: 'M7 11V7a5 5 0 0 1 9.9-1' }],
    ],
    'key': [
        ['path', { d: 'm15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l2.1-2.1a1 1 0 0 0 0-1.4L19 4' }],
        ['path', { d: 'm21 2-9.6 9.6' }],
        ['circle', { cx: '7.5', cy: '15.5', r: '5.5' }],
    ],
    'star': [
        ['polygon', { points: '12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2' }],
    ],
    'flag': [
        ['path', { d: 'M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z' }],
        ['line', { x1: '4', x2: '4', y1: '22', y2: '15' }],
    ],
    'trash': [
        ['path', { d: 'M3 6h18' }],
        ['path', { d: 'M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6' }],
        ['path', { d: 'M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2' }],
    ],
    'log-out': [
        ['path', { d: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4' }],
        ['polyline', { points: '16 17 21 12 16 7' }],
        ['line', { x1: '21', x2: '9', y1: '12', y2: '12' }],
    ],
    'log-in': [
        ['path', { d: 'M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4' }],
        ['polyline', { points: '10 17 15 12 10 7' }],
        ['line', { x1: '15', x2: '3', y1: '12', y2: '12' }],
    ],
    'chevron-right': [
        ['path', { d: 'm9 18 6-6-6-6' }],
    ],
    'chevron-left': [
        ['path', { d: 'm15 18-6-6 6-6' }],
    ],
    'arrow-up': [
        ['path', { d: 'm5 12 7-7 7 7' }],
        ['path', { d: 'M12 19V5' }],
    ],
    'arrow-down': [
        ['path', { d: 'M12 5v14' }],
        ['path', { d: 'm19 12-7 7-7-7' }],
    ],
};

function createLucideIcon(name, size) {
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
        for (const [k, v] of Object.entries(attrs)) {
            node.setAttribute(k, v);
        }
        svg.appendChild(node);
    }
    return svg;
}

window.AeternaNotifyIcons = {
    create: createLucideIcon,
    has: (name) => Object.hasOwn(ICON_SHAPES, name),
};
