Locales = Locales or {}
Locales.en = Locales.en or {}

-- Server side only (console lines and the self-test expect line). The page's own strings are in html/locale.json.
Locales.en['loading.config.bad'] = 'html/config.json: {field} is not valid; using the default'

-- Self-test expect line (shown on the testkit eye card).
Locales.en['loading.selftest.expect.page'] = 'When you joined, the loading screen showed the server name, then Map, Scripts with a percentage, then Character, and closed by itself'

return Locales.en
