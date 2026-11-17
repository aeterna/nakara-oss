(function() {
    'use strict';

    var runCounter = 1;

    function getResourceName() {
        if (typeof GetParentResourceName === 'function') {
            return GetParentResourceName();
        }
        return 'kspike_c';
    }

    function updateStatusPanel(testName, payload) {
        var runEl = document.getElementById('run-counter');
        if (runEl) {
            runEl.textContent = 'Run: ' + runCounter;
        }

        var statusEl = document.getElementById('status');
        if (statusEl) {
            if (testName && payload) {
                statusEl.textContent = 'Run ' + runCounter + ' - Test ' + testName + ':\n' + JSON.stringify(payload, null, 2);
            } else {
                statusEl.textContent = 'Run ' + runCounter + ': running checks...';
            }
        }
    }

    function postResult(testName, data, runNum) {
        var currentRun = runNum || runCounter;
        var payload = Object.assign({ test: testName, run: currentRun }, data, { origin: location.origin });

        // Show results in status line using textContent (never innerHTML)
        updateStatusPanel(testName, payload);

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

    async function runChecks(testName, linkEl, sheetHref, runNum) {
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
            postResult(testName, result, runNum);
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

        postResult(testName, result, runNum);
    }

    function scheduleTestA(targetRun) {
        var staticLink = document.getElementById('static-link');
        setTimeout(function() {
            runChecks('A', staticLink, 'kspike_theme/theme.css', targetRun);
        }, 3000);

        setTimeout(function() {
            runChecks('A-10s', staticLink, 'kspike_theme/theme.css', targetRun);
        }, 10000);
    }

    function scheduleTestB(href, targetRun) {
        var dynLink = document.createElement('link');
        dynLink.rel = 'stylesheet';
        dynLink.id = 'dyn';
        dynLink.href = href;
        document.head.appendChild(dynLink);

        setTimeout(function() {
            runChecks('B', dynLink, href, targetRun);
        }, 3000);

        setTimeout(function() {
            runChecks('B-10s', dynLink, href, targetRun);
        }, 10000);
    }

    // On load, notify ready and schedule initial Test A
    window.addEventListener('DOMContentLoaded', function() {
        updateStatusPanel();

        if (typeof GetParentResourceName === 'function') {
            fetch('https://' + getResourceName() + '/ready', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            }).catch(function() {});
        }

        scheduleTestA(runCounter);
    });

    // Listen for messages from Lua
    window.addEventListener('message', function(event) {
        var data = event.data;
        if (!data) return;

        if (data.type === 'theme' && data.href) {
            // Initial dynamic theme link
            scheduleTestB(data.href, runCounter);
        } else if (data.type === 'rerun') {
            runCounter++;
            updateStatusPanel();

            // Remove existing link with id 'dyn' if any
            var existingDyn = document.getElementById('dyn');
            if (existingDyn && existingDyn.parentNode) {
                existingDyn.parentNode.removeChild(existingDyn);
            }

            // Run Test A checks again on static link
            scheduleTestA(runCounter);

            // Run Test B again with a fresh dyn link
            var href = data.href || 'nui://kspike_theme/theme.css';
            scheduleTestB(href, runCounter);
        }
    });
})();
