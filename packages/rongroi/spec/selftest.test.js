'use strict';

// Startup self-test: one line, no key material, named failing step.
const test = require('node:test');
const assert = require('node:assert/strict');
const selftestPath = require.resolve('../server/js/selftest.js');
const selftest = require('../server/js/selftest.js');
const vectors = require('../test-vectors/envelope-v1.json');

const OK = 'nakara_rongroi selftest: ok x25519 hkdf aes-gcm';

function cloneVectors() {
    return JSON.parse(JSON.stringify(vectors));
}

test('the shipped vector file passes the self-test', () => {
    assert.equal(selftest.runSelfTest(vectors), OK);
});

test('a changed ciphertext byte fails at the aes-gcm step', () => {
    const v = cloneVectors();
    const ct = Buffer.from(v.envelope.ct, 'base64url');
    ct[0] ^= 0x01;
    v.envelope.ct = ct.toString('base64url');
    assert.match(selftest.runSelfTest(v), /^nakara_rongroi selftest: fail aes-gcm /);
});

test('a wrong derived key fails at the hkdf step', () => {
    const v = cloneVectors();
    v.derivedKey = Buffer.alloc(32, 7).toString('base64url');
    assert.match(selftest.runSelfTest(v), /^nakara_rongroi selftest: fail hkdf /);
});

test('a wrong shared secret fails at the x25519 step', () => {
    const v = cloneVectors();
    v.sharedSecret = Buffer.alloc(32, 9).toString('base64url');
    assert.match(selftest.runSelfTest(v), /^nakara_rongroi selftest: fail x25519 /);
});

test('the result is one line and contains no private key material', () => {
    const v = cloneVectors();
    v.envelope.ct = 'AAAA';
    const line = selftest.runSelfTest(v);
    assert.equal(line.includes('\n'), false);
    for (const secret of [vectors.kit.privateKey, vectors.ephemeral.privateKey, vectors.derivedKey]) {
        assert.equal(line.includes(secret), false);
    }
});

// FXServer resolves './envelope.js' against the resource root, where it does not exist. Simulate that by
// making the sibling require fail and checking that selftest asks for the resource-root path instead.
test('it loads envelope.js through the resource-root fallback when the sibling file is missing', () => {
    const Module = module.constructor;
    const originalLoad = Module._load;
    const requests = [];
    Module._load = function (request, parent, isMain) {
        if (parent && parent.filename === selftestPath) {
            requests.push(request);
            if (request === './envelope.js') {
                const err = new Error("Cannot find module './envelope.js'");
                err.code = 'MODULE_NOT_FOUND';
                throw err;
            }
            if (request === './server/js/envelope.js') {
                return originalLoad.call(this, require.resolve('../server/js/envelope.js'), parent, isMain);
            }
        }
        return originalLoad.call(this, request, parent, isMain);
    };
    delete require.cache[selftestPath];
    let loaded;
    try {
        loaded = require(selftestPath);
    } finally {
        Module._load = originalLoad;
        delete require.cache[selftestPath];
    }
    assert.deepEqual(requests, ['./envelope.js', './server/js/envelope.js']);
    assert.equal(loaded.runSelfTest(vectors), OK);
});

test('started as a resource it prints exactly the one self-test line', () => {
    const lines = [];
    const originalLog = console.log;
    globalThis.GetCurrentResourceName = () => 'nakara_rongroi';
    globalThis.LoadResourceFile = (resource, file) => {
        assert.equal(resource, 'nakara_rongroi');
        assert.equal(file, 'test-vectors/envelope-v1.json');
        return JSON.stringify(vectors);
    };
    console.log = (...args) => lines.push(args.join(' '));
    try {
        delete require.cache[selftestPath];
        require('../server/js/selftest.js');
    } finally {
        console.log = originalLog;
        delete globalThis.GetCurrentResourceName;
        delete globalThis.LoadResourceFile;
        delete require.cache[selftestPath];
    }
    assert.deepEqual(lines, [OK]);
});
