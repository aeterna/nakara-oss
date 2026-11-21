Locales = Locales or {}
Locales.en = Locales.en or {}

Locales.en['notify.motd.dismiss'] = 'Don\'t show again'
Locales.en['notify.motd.continue'] = 'Continue'
Locales.en['notify.announce.title'] = 'Announcement'
Locales.en['notify.announce.by'] = 'By {name}'
Locales.en['notify.announce.console'] = 'Console'
Locales.en['notify.announce.usage'] = 'Usage: aeterna_announce <text>'
Locales.en['notify.announce.denied'] = 'You do not have permission to send announcements'
Locales.en['notify.action.unbound'] = 'Unbound'
Locales.en['notify.sound.on'] = 'Notification sounds on'
Locales.en['notify.sound.off'] = 'Notification sounds off'
Locales.en['notify.sound.disabled'] = 'This server has turned notification sounds off'
Locales.en['notify.countdown.title'] = 'Countdown'
Locales.en['notify.countdown.usage'] = 'Usage: aeterna_announce_countdown <minutes 1-60> <text>'
Locales.en['notify.countdown.busy'] = 'A countdown is already running'
Locales.en['notify.key.action1'] = 'Notification: first action'
Locales.en['notify.key.action2'] = 'Notification: second action'

-- 0.2 self-tests (expect texts and test toast strings)
Locales.en['notify.selftest.toast_types'] = 'Four toasts, one per type, in the configured corner, each with a lifetime bar that empties in time'
Locales.en['notify.selftest.stack_merge'] = 'Six identical toasts show as one toast reading ×6, which does not jump'
Locales.en['notify.selftest.action_press'] = 'A toast with two buttons; pressing the key bound to action 1 closes it and the test receives the first action\'s id'
Locales.en['notify.selftest.sound_plays'] = 'Each toast type plays its sound once; with the player\'s setting off, none plays'
Locales.en['notify.selftest.countdown_banner'] = 'A 30-second countdown banner counts down in mm:ss and disappears at zero'
Locales.en['notify.selftest.motion_reduced'] = 'With reduced motion on, toasts appear and disappear with no slide and no lifetime bar'
Locales.en['notify.selftest.toast'] = 'Self-test: {type} toast'
Locales.en['notify.selftest.merge'] = 'Self-test: the same toast six times'
Locales.en['notify.selftest.action'] = 'Self-test: a toast with two buttons'
Locales.en['notify.selftest.action1'] = 'First'
Locales.en['notify.selftest.action2'] = 'Second'
Locales.en['notify.selftest.sound_on'] = 'Sound on: {type}'
Locales.en['notify.selftest.sound_off'] = 'Your sound setting off: {type}'
Locales.en['notify.selftest.countdown'] = 'Self-test countdown'
Locales.en['notify.selftest.motion'] = 'Self-test: this toast comes and goes'

return Locales.en
