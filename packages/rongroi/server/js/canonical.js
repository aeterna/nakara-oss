'use strict';

// RFC 8785 (JCS) canonical JSON for the policy digest. Node built-ins only.
//
// Numbers are integers only (a policy is configuration, not a measurement), object keys sort by UTF-16
// code units, and strings use the JCS escape set: `"`, `\` and the control characters, nothing else.

function quote(value) {
    let out = '"';
    for (let i = 0; i < value.length; i++) {
        const code = value.charCodeAt(i);
        if (code === 0x22) out += '\\"';
        else if (code === 0x5c) out += '\\\\';
        else if (code === 0x08) out += '\\b';
        else if (code === 0x09) out += '\\t';
        else if (code === 0x0a) out += '\\n';
        else if (code === 0x0c) out += '\\f';
        else if (code === 0x0d) out += '\\r';
        else if (code < 0x20) out += '\\u' + code.toString(16).padStart(4, '0');
        else if (code >= 0xd800 && code <= 0xdbff) {
            const next = value.charCodeAt(i + 1);
            if (!(next >= 0xdc00 && next <= 0xdfff)) throw new TypeError('canonical JSON needs valid Unicode');
            out += value[i] + value[i + 1];
            i++;
        } else if (code >= 0xdc00 && code <= 0xdfff) {
            throw new TypeError('canonical JSON needs valid Unicode');
        } else out += value[i];
    }
    return out + '"';
}

function encode(value) {
    if (value === null) return 'null';
    const type = typeof value;
    if (type === 'boolean') return value ? 'true' : 'false';
    if (type === 'number') {
        if (!Number.isSafeInteger(value)) throw new TypeError('canonical JSON holds integers only');
        return String(value);
    }
    if (type === 'string') return quote(value);
    if (type !== 'object') throw new TypeError(`canonical JSON cannot encode ${type}`);
    if (Array.isArray(value)) return '[' + Array.from(value, encode).join(',') + ']';
    const keys = Object.keys(value).sort();
    return '{' + keys.map((key) => quote(key) + ':' + encode(value[key])).join(',') + '}';
}

function canonicalize(value) {
    return encode(value);
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { canonicalize };
}
