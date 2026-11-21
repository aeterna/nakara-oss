// aeterna_testkit NUI: the eye-check card. Text is set with textContent only.

const card = document.getElementById('eye');
const header = document.getElementById('eye-header');
const ask = document.getElementById('eye-ask');
const normally = document.getElementById('eye-normally');
const expectText = document.getElementById('eye-expect-text');
const buttons = {
    pass: document.getElementById('eye-pass'),
    mismatch: document.getElementById('eye-mismatch'),
    skip: document.getElementById('eye-skip'),
};

let locale = {
    'testkit.eye.normally': 'Normally you will see:',
    'testkit.eye.pass': 'Pass',
    'testkit.eye.mismatch': "Doesn't match",
    'testkit.eye.skip': 'Skip',
};
const PRESETS = ['asphalt', 'paper', 'night-market'];

function post(name, payload) {
    fetch('https://aeterna_testkit/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {}),
    }).catch(() => {});
}

function applyTheme(msg) {
    const preset = PRESETS.includes(msg.preset) ? msg.preset : 'asphalt';
    document.documentElement.setAttribute('data-preset', preset);
    const existing = document.getElementById('aeterna-theme-override');
    const href = msg.href;
    if (typeof href === 'string' && href.startsWith('nui://') && href.endsWith('.css')) {
        if (existing) {
            existing.setAttribute('href', href);
        } else {
            const link = document.createElement('link');
            link.id = 'aeterna-theme-override';
            link.rel = 'stylesheet';
            link.setAttribute('href', href);
            document.head.appendChild(link);
        }
    } else if (existing) {
        existing.remove();
    }
}

function applyLocale() {
    normally.textContent = locale['testkit.eye.normally'];
    buttons.pass.textContent = locale['testkit.eye.pass'];
    buttons.mismatch.textContent = locale['testkit.eye.mismatch'];
    buttons.skip.textContent = locale['testkit.eye.skip'];
}

function show(msg) {
    header.textContent = typeof msg.header === 'string' ? msg.header : '';
    ask.textContent = typeof msg.ask === 'string' ? msg.ask : '';
    expectText.textContent = typeof msg.expect === 'string' ? msg.expect : '';
    applyLocale();
    card.classList.remove('hidden');
    buttons.pass.focus();
}

function hide() {
    card.classList.add('hidden');
}

Object.keys(buttons).forEach((answer) => {
    buttons[answer].addEventListener('click', () => {
        if (!card.classList.contains('hidden')) {
            post('eyeAnswer', { answer });
        }
    });
});

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !card.classList.contains('hidden')) {
        e.preventDefault();
        post('escape', {});
    }
});

window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== 'object') return;
    if (msg.type === 'aeterna:theme') {
        applyTheme(msg);
    } else if (msg.type === 'locale') {
        if (msg.strings && typeof msg.strings === 'object') {
            Object.keys(locale).forEach((k) => {
                if (typeof msg.strings[k] === 'string') locale[k] = msg.strings[k];
            });
        }
        applyLocale();
    } else if (msg.type === 'eye:show') {
        show(msg);
    } else if (msg.type === 'eye:hide') {
        hide();
    }
});

applyLocale();
