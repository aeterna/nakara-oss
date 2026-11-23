// aeterna_uikit slider grid math. Pure, so spec/slider_math.test.js can run it under node --test
// (it sets window.AeternaUikitSlider in the page and globalThis.AeternaUikitSlider under node).
// The page snaps every value to the grid min + n * step (0 <= n <= floor((max - min) / step)) before
// sending it, so it always passes the server re-check (shared/logic/uikit.lua L.isSliderValue).

(function (root) {
    'use strict';

    // Decimal places of a number, including exponent notation (1e-7 -> 7, 1.5e-7 -> 8).
    function decimalsOf(x) {
        const text = String(Number(x)).toLowerCase();
        const parts = text.split('e');
        const dot = parts[0].indexOf('.');
        const mantissa = dot < 0 ? 0 : parts[0].length - dot - 1;
        const exponent = parts.length > 1 ? Number(parts[1]) : 0;
        return Math.max(0, mantissa - exponent);
    }

    // The same tolerance as the server: 1e-6 of a step.
    function lastIndex(min, max, step) {
        return Math.max(0, Math.floor((max - min) / step + 1e-6));
    }

    function snap(v, min, max, step) {
        const num = Number(v);
        const raw = Number.isFinite(num) ? (num - min) / step : 0;
        const n = Math.min(lastIndex(min, max, step), Math.max(0, Math.round(raw)));
        const decimals = Math.min(20, Math.max(decimalsOf(step), decimalsOf(min)));
        return Number((min + n * step).toFixed(decimals));
    }

    root.AeternaUikitSlider = { decimalsOf, snap };
})(typeof window !== 'undefined' ? window : globalThis);
