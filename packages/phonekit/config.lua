Config = {}

-- Default screen placement ('bottom-right' or 'bottom-left', 24 px inset)
Config.position = 'bottom-right'

-- When true, server asks other resources before the phone opens
Config.ask = false

-- Hold a phone prop and play the base-game phone animation while open
Config.animation = true

-- Built-in apps to show on the home screen
Config.apps = {
    calculator = true,
    notes = true,
    contacts = true,
    settings = true,
}

-- Maximum apps allowed from other resources; extra apps are refused with a warn
Config.maxApps = 24

-- 0.2 ------------------------------------------------------------------------

-- 'single': every player holds one phone of Config.singleModel.
-- 'items': the phone is an inventory item; a resource that owns the items answers the open gate.
Config.devices = 'single'

-- One of: keypad, burner, qwerty, slab, fold, pro, book, pad
Config.singleModel = 'slab'

-- Display names: 'neutral' (Keypad, Slab, ...) or 'universe' (names from the game's own universe)
Config.names = 'neutral'

-- Per model: label (plain text, 24 characters at most), apps (app spec), colors (hex list, first = default),
-- prop. Missing keys take the shipped default. App spec: comma-separated tokens, '*' = every app, '-x' removes x,
-- anything else adds it; built-in ids or '<owner>:<id>'. 'settings' is always kept.
Config.models = {
    burner = { apps = '*,-contacts' },
}

-- The held prop. Config.models[m].prop overrides it per model.
Config.prop = 'prop_npc_phone_02'

-- false turns the battery off: no drain, no battery in the status bar, battery exports return nil.
Config.battery = {
    tickSec = 10,          -- server tick, 5-60
    standby = 0.25,        -- %/min while carried and switched on
    screen = 1.0,          -- %/min extra while any phone screen is on
    call = 1.5,            -- %/min extra while a call is connected (set by an add-on)
    media = 2.5,           -- %/min extra while a camera viewfinder is up (set by an add-on)
    vehicleSec = 300,      -- seconds from 0 to 100 % in a vehicle; 0 = vehicles do not charge
    warnAt = { 20, 10, 5 },
    saveStep = 5,
    pulseTtlSec = 45,
    startPct = 100,        -- battery of a phone the server has never seen
}

-- true turns on the lock screen (shown on open when something is waiting)
Config.lockScreen = false

-- false: a fold never closes (it stays open and the fold key does nothing)
Config.cover = true
