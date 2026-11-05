'use strict';

// File backend for report storage (ADR 0001, section 4). This file holds the Kit's only SaveResourceFile
// call. A name is checked before any path is built. Case and index files alternate between two slots, so a
// torn write leaves the older parsed value readable.

const NAME_RE = /^(case|index|report)-[0-9a-f]{1,64}$/;
const FOLDER = 'cache/rongroi-reports';

function checkName(name) {
    if (typeof name !== 'string' || !NAME_RE.test(name)) {
        throw new TypeError('name must be case-, index- or report- followed by 1 to 64 lowercase hex characters');
    }
}

function slotPath(name, slot) {
    return `${FOLDER}/${name}.${slot}.json`;
}

function oncePath(name) {
    return `${FOLDER}/${name}.json`;
}

function loadText(path) {
    const text = LoadResourceFile(GetCurrentResourceName(), path);
    return typeof text === 'string' && text.length > 0 ? text : null;
}

function parse(text) {
    if (text === null) return undefined;
    try {
        return JSON.parse(text);
    } catch {
        return undefined;
    }
}

function saveText(path, text) {
    if (SaveResourceFile(GetCurrentResourceName(), path, text, -1) === false) {
        throw new Error('rongroi storage: write failed');
    }
}

function readSlot(path) {
    const value = parse(loadText(path));
    if (value === null || typeof value !== 'object' || typeof value.seq !== 'number'
        || !Number.isFinite(value.seq) || !('data' in value)) {
        return null;
    }
    return value;
}

function readOnce(path) {
    const value = parse(loadText(path));
    return value !== null && typeof value === 'object' ? value : null;
}

function createFileBackend() {
    function read(name) {
        checkName(name);
        const once = readOnce(oncePath(name));
        if (once !== null) return once;
        const a = readSlot(slotPath(name, 'a'));
        const b = readSlot(slotPath(name, 'b'));
        if (a === null) return b === null ? null : b.data;
        if (b === null) return a.data;
        return (a.seq >= b.seq ? a : b).data;
    }

    function write(name, obj) {
        checkName(name);
        const a = readSlot(slotPath(name, 'a'));
        const b = readSlot(slotPath(name, 'b'));
        const pick = a === null
            ? ['a', b === null ? 0 : b.seq]
            : b === null ? ['b', a.seq]
                : a.seq >= b.seq ? ['b', a.seq] : ['a', b.seq];
        saveText(slotPath(name, pick[0]), JSON.stringify({ seq: pick[1] + 1, data: obj }));
    }

    function writeOnce(name, obj) {
        checkName(name);
        saveText(oncePath(name), JSON.stringify(obj));
    }

    function remove(name) {
        checkName(name);
        for (const path of [slotPath(name, 'a'), slotPath(name, 'b'), oncePath(name)]) {
            if (loadText(path) !== null) saveText(path, '');
        }
    }

    return { read, write, writeOnce, remove };
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { createFileBackend };
}
