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
