Config = {
    snap = 8,
    -- Snap steps offered in the editor (0.2). `snap` stays the default for players who have not picked.
    snapSteps = { 8, 16, 32 },
    scale = {
        min = 0.5,
        max = 2.0,
        step = 0.05,
    },
    maxElements = 64,
    menu = true,
    -- true: the menu entry opens a panel with Edit, Reset all and Export / import (0.2). false: it opens the editor.
    menuPanel = true,
    -- Preset layouts (up to 8): name (≤ 24, ^[%w_%-]+$) → { ["<owner>/<id>"] = { x, y, ax, ay, scale } }.
    -- Elements a preset does not name go to their owner's default. A preset never sets `hidden`.
    -- Label: locale key layout.preset.<name>, or the name itself.
    presets = {
        default = {},
        compact = {
            ['aeterna_hudkit/status'] = { x = 0.17, y = 0.97, ax = 0, ay = 1, scale = 0.85 },
            ['aeterna_hudkit/vehicle'] = { x = 0.17, y = 0.89, ax = 0, ay = 1, scale = 0.85 },
            ['aeterna_hudkit/street'] = { x = 0.17, y = 0.83, ax = 0, ay = 1, scale = 0.85 },
            ['aeterna_hudkit/voice'] = { x = 0.17, y = 0.78, ax = 0, ay = 1, scale = 0.85 },
            ['aeterna_hudkit/compass'] = { x = 0.015, y = 0.76, ax = 0, ay = 1, scale = 0.85 },
            ['aeterna_notify/toasts'] = { x = 0.015, y = 0.03, ax = 0, ay = 0, scale = 0.85 },
        },
        centered = {
            ['aeterna_hudkit/status'] = { x = 0.49, y = 0.97, ax = 1, ay = 1, scale = 1 },
            ['aeterna_hudkit/vehicle'] = { x = 0.51, y = 0.97, ax = 0, ay = 1, scale = 1 },
            ['aeterna_hudkit/street'] = { x = 0.5, y = 0.89, ax = 0.5, ay = 1, scale = 1 },
            ['aeterna_hudkit/voice'] = { x = 0.5, y = 0.84, ax = 0.5, ay = 1, scale = 1 },
            ['aeterna_hudkit/compass'] = { x = 0.5, y = 0.02, ax = 0.5, ay = 0, scale = 1 },
            ['aeterna_notify/announce'] = { x = 0.5, y = 0.08, ax = 0.5, ay = 0, scale = 1 },
            ['aeterna_notify/toasts'] = { x = 0.985, y = 0.03, ax = 1, ay = 0, scale = 1 },
        },
    },
}
