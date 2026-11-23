// Slider grid math the page uses before it sends a value (html/slider-math.js).
// Run: node --test packages/uikit/spec/
import test from 'node:test';
import assert from 'node:assert/strict';
import '../html/slider-math.js';

const { snap, decimalsOf } = globalThis.AeternaUikitSlider;

// The server's check (shared/logic/uikit.lua L.isSliderValue): in range, grid index within 1e-6.
function onServerGrid(v, min, max, step) {
    if (v < min || v > max) return false;
    const steps = (v - min) / step;
    return Math.abs(steps - Math.round(steps)) <= 1e-6;
}

test('decimalsOf counts plain and exponent notation', () => {
    assert.equal(decimalsOf(5), 0);
    assert.equal(decimalsOf(0.1), 1);
    assert.equal(decimalsOf(0.05), 2);
    assert.equal(decimalsOf(1e-7), 7);
    assert.equal(decimalsOf(1.5e-7), 8);
    assert.equal(decimalsOf(1e21), 0);
});

test('an offset min keeps its own decimals (min 0.05, step 0.1)', () => {
    assert.equal(snap(0.05, 0.05, 1.05, 0.1), 0.05);
    assert.equal(snap(0.16, 0.05, 1.05, 0.1), 0.15);
    assert.ok(onServerGrid(snap(0.16, 0.05, 1.05, 0.1), 0.05, 1.05, 0.1));
});

test('a tiny step is not rounded to zero decimals', () => {
    const v = snap(3e-7, 0, 1e-5, 1e-7);
    assert.equal(v, 3e-7);
    assert.ok(onServerGrid(v, 0, 1e-5, 1e-7));
});

test('max off the grid clamps to the last grid point (min 0, max 11, step 3)', () => {
    assert.equal(snap(11, 0, 11, 3), 9);
    assert.equal(snap(100, 0, 11, 3), 9);
    assert.equal(snap(-4, 0, 11, 3), 0);
});

test('float steps land on the grid and inside the range', () => {
    assert.equal(snap(0.3, 0, 0.3, 0.1), 0.3);
    assert.equal(snap(0.7, 0, 1, 0.1), 0.7);
    for (let i = 0; i <= 40; i++) {
        const v = snap(i * 0.037, 0.05, 1.05, 0.1);
        assert.ok(onServerGrid(v, 0.05, 1.05, 0.1), String(v));
    }
});

test('a non-number falls back to min', () => {
    assert.equal(snap(undefined, 10, 20, 1), 10);
    assert.equal(snap('x', 10, 20, 1), 10);
});
