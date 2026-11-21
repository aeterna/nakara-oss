-- aeterna_invkit configuration.

Config = Config or {}

Config.stash = {
    scope = 'character',
    slots = 40,
    maxWeight = 100000,
    label = 'invkit.stash.label',
    points = {},
    command = false,
    anywhere = false,
}

-- Phone item mode (0.2): answer aeterna_phonekit's open gate from phone items in ox_inventory.
-- Turn it on together with aeterna_phonekit's Config.devices = 'items'.
-- items: ox item name -> phonekit model id (keypad, burner, qwerty, slab, fold, pro, book, pad); at most 32.
Config.phone = {
    enabled = false,
    items = {
        phone = 'slab', -- the common generic phone item name
        phone_keypad = 'keypad', phone_burner = 'burner', phone_qwerty = 'qwerty', phone_slab = 'slab',
        phone_fold = 'fold', phone_pro = 'pro', phone_book = 'book', phone_pad = 'pad',
    },
}
