Config = Config or {}

Config.toast = {
    position = 'top-left',
    max = 4,
    defaultDuration = 4000,
    -- 0.2
    lifetimeBar = true, -- draw the lifetime bar on timed toasts
    merge = true, -- merge identical toasts into one with a count (false = the 0.1 stack of copies)
    actionDuration = 8000, -- default duration of a toast with actions, ms (1000-15000)
}

Config.announce = {
    queue = 5,
}

Config.motd = {
    enabled = true,
}

-- 0.2: sounds. Nobody hears anything unless the server owner turns them on here.
Config.sound = {
    enabled = false,
    playerDefault = false, -- for a player who has not run aeterna_notify_sound yet
    -- Base-game frontend sounds, played with PlaySoundFrontend(-1, name, set, true).
    -- Not verified on FXServer Enhanced yet; the sound_plays self-test checks them before release.
    byType = {
        info = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        success = { name = 'SELECT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        warning = { name = 'CHECKPOINT_MISSED', set = 'HUD_MINI_GAME_SOUNDSET' },
        error = { name = 'ERROR', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    },
}

-- 0.2: seconds left at which a countdown shows its banner again.
Config.countdown = {
    marks = { 600, 300, 60, 30, 10 },
}

-- 0.2: entries kept for the client `history` export, 0-50; 0 turns history off.
Config.history = {
    max = 50,
}

return Config
