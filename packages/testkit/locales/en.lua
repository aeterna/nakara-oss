Locales = Locales or {}
Locales.en = Locales.en or {}

Locales.en['testkit.key.menu'] = 'Starter Kit test menu'
Locales.en['testkit.key.leave'] = 'Leave the player B test role'
Locales.en['testkit.menu.title'] = 'Starter Kit tests'
Locales.en['testkit.menu.run'] = 'Run all'
Locales.en['testkit.menu.invite'] = 'Invite player B'
Locales.en['testkit.menu.cancel'] = 'Cancel run'
Locales.en['testkit.menu.report'] = 'Show report'
Locales.en['testkit.idle'] = 'No run going'
Locales.en['testkit.busy'] = 'Another test run is going: {phase}, {since} s'
Locales.en['testkit.denied'] = 'You do not have permission to run the Starter Kit tests.'
Locales.en['testkit.gate.on'] = 'Destructive tests on'
Locales.en['testkit.gate.off'] = 'Destructive tests off'
Locales.en['testkit.b.none'] = 'Player B: none'
Locales.en['testkit.b.ready'] = 'Player B (id {id}): ready'
Locales.en['testkit.invite.prompt'] = 'Server id of player B'
Locales.en['testkit.invite.body'] = 'Player A asks you to help test the server as player B. You will see a few checks and answer them.'
Locales.en['testkit.invite.invalid'] = 'That player cannot be invited now.'
Locales.en['testkit.invite.declined'] = 'Player B declined or did not answer.'
Locales.en['testkit.eye.header'] = 'Look {index} · {suite}'
Locales.en['testkit.eye.role_b'] = 'Look {index} · {suite} · as player B'
Locales.en['testkit.eye.normally'] = 'Normally you will see:'
Locales.en['testkit.eye.pass'] = 'Pass'
Locales.en['testkit.eye.mismatch'] = "Doesn't match"
Locales.en['testkit.eye.skip'] = 'Skip'
Locales.en['testkit.report.saved'] = 'Report saved to reports/latest.md and reports/latest.json. Attach it as {file}.'
Locales.en['testkit.report.footer'] = 'No player names, identifiers, IPs, convar values or paths.'
Locales.en['testkit.selftest.expect.card'] = "A card in the lower left corner with a question and three buttons: Pass, Doesn't match, Skip. A uikit panel opened behind it stays open"
Locales.en['testkit.selftest.expect.card_b'] = 'Player B sees the same card, headed "as player B"'

return Locales.en
