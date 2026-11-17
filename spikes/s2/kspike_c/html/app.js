(function() {
    'use strict';

    function getResourceName() {
        if (typeof GetParentResourceName === 'function') {
            return GetParentResourceName();
        }
        return 'kspike_c';
    }

    function postResult(testName, data) {
        var payload = Object.assign({ test: testName }, data, { origin: location.origin });

        // Show results in status line using textContent (never innerHTML)
        var statusEl = document.getElementById('status');
        if (statusEl) {
            statusEl.textContent = 'Test ' + testName + ':\n' + JSON.stringify(payload, null, 2);
        }

        if (typeof GetParentResourceName === 'function') {
            fetch('https://' + getResourceName() + '/result', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            }).catch(function() {});
        } else {
            console.log('[kspike_c] Result (' + testName + '):', payload);
        }
    }

    async function runChecks(testName, linkEl, sheetHref) {
        var result = {
            href: sheetHref,
            linkLoaded: false,
            sheetNotNull: false,
            cssRulesReadable: 'unknown',
            accentApplied: false,
            varApplied: false,
            fontLoaded: false,
            fontCheck: false,
            fontFaces: [],
            origin: location.origin
        };

        if (!linkEl) {
            postResult(testName, result);
            return;
        }

        // Wait for link load or check sheet
        await new Promise(function(resolve) {
            if (linkEl.sheet) {
                result.linkLoaded = true;
                result.sheetNotNull = true;
                resolve();
            } else {
                linkEl.addEventListener('load', function() {
                    result.linkLoaded = true;
                    result.sheetNotNull = (linkEl.sheet !== null);
                    resolve();
                }, { once: true });
                linkEl.addEventListener('error', function() {
                    result.linkLoaded = false;
                    resolve();
                }, { once: true });
                setTimeout(function() {
                    result.linkLoaded = linkEl.sheet !== null;
                    result.sheetNotNull = (linkEl.sheet !== null);
                    resolve();
                }, 1500);
            }
        });

        // Test cssRulesReadable
        try {
            var sheets = document.styleSheets;
            var foundSheet = null;
            for (var i = 0; i < sheets.length; i++) {
                if (sheets[i].href && sheets[i].href.includes(sheetHref)) {
                    foundSheet = sheets[i];
                    break;
                }
            }
            if (foundSheet) {
                var rules = foundSheet.cssRules;
                result.cssRulesReadable = 'ok';
            } else {
                result.cssRulesReadable = 'sheet-not-found';
            }
        } catch (err) {
            result.cssRulesReadable = err.name || String(err);
        }

        // Test accentApplied on line1
        var line1 = document.getElementById('line1');
        if (line1) {
            var computedColor = window.getComputedStyle(line1).color;
            result.accentApplied = (computedColor === 'rgb(232, 116, 42)');
            result.computedColor = computedColor;
        }

        // Test varApplied (--accent on documentElement)
        try {
            var accentVar = window.getComputedStyle(document.documentElement).getPropertyValue('--accent').trim();
            result.varApplied = (accentVar === '#e8742a');
            result.accentVar = accentVar;
        } catch (err) {
            result.varApplied = false;
        }

        // Test fontLoaded using document.fonts
        try {
            await document.fonts.load('16px KspikeFont');
            result.fontLoaded = true;
        } catch (err) {
            result.fontLoaded = false;
            result.fontLoadError = err.name || String(err);
        }

        try {
            result.fontCheck = document.fonts.check('16px KspikeFont');
        } catch (err) {
            result.fontCheck = false;
        }

        // List FontFaces in document.fonts
        var faces = [];
        if (document.fonts && typeof document.fonts.forEach === 'function') {
            document.fonts.forEach(function(fontFace) {
                faces.push({
                    family: fontFace.family,
                    status: fontFace.status,
                    weight: fontFace.weight
                });
            });
        }
        result.fontFaces = faces;

        postResult(testName, result);
    }

    // On load, notify ready and schedule Test A
    window.addEventListener('DOMContentLoaded', function() {
        if (typeof GetParentResourceName === 'function') {
            fetch('https://' + getResourceName() + '/ready', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            }).catch(function() {});
        }

        var staticLink = document.getElementById('static-link');

        // Run checks 3s after link loads, and again at 10s
        setTimeout(function() {
            runChecks('A', staticLink, 'kspike_theme/theme.css');
        }, 3000);

        setTimeout(function() {
            runChecks('A-10s', staticLink, 'kspike_theme/theme.css');
        }, 10000);
    });

    // Listen for Test B (dynamic link message from Lua)
    window.addEventListener('message', function(event) {
        var data = event.data;
        if (data && data.type === 'theme' && data.href) {
            var dynLink = document.createElement('link');
            dynLink.rel = 'stylesheet';
            dynLink.id = 'dyn';
            dynLink.href = data.href;
            document.head.appendChild(dynLink);

            setTimeout(function() {
                runChecks('B', dynLink, data.href);
            }, 3000);

            setTimeout(function() {
                runChecks('B-10s', dynLink, data.href);
            }, 10000);
        }
    });
})();
