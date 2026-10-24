// Execute only the inspected send handler from the checksum-pinned browser file.
// No browser, provider, filesystem mutation or network access occurs in the handler.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const source = readFileSync(process.argv[2]);
const expected = '5f53e5667d1ff131585be7bc0ca1f3641cae49d9a98c68fb0375590788abed22';
if (createHash('sha256').update(source).digest('hex') !== expected) throw new Error('Pinned browser source mismatch');
const text = source.toString('utf8');
const anchor = text.indexOf('// pickFiles uploads into this conversation');
const start = text.indexOf('  async function send() {', anchor);
const end = text.indexOf('  // stop aborts the in-flight run', start);
if (anchor < 0 || start < 0 || end < 0) throw new Error('Pinned send-handler boundary missing');
const handler = text.slice(start, end).trim();
if (handler.split('(e as Error)').length !== 2) throw new Error('Expected one TypeScript cast');
const executable = handler.replace('(e as Error)', '(e)');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const execute = new AsyncFunction('api', 'input', 'attachments', 'side', 'sending', 'running', 'conv',
    'setSending', 'setInput', 'setAttachments', 'setRunning', 'toast', 't', executable + '\nreturn send();');
const file = name => ({ name, path: 'uploads/' + name, size: 1 });
const scenarios = [
    { name: 'text_and_attachment_error', input: 'retry text', attachments: [file('file.txt')], outcome: 'error' },
    { name: 'attachment_only_error_distinct_unicode', input: '', attachments: [file('\u00e9.txt'), file('e\u0301.txt')], outcome: 'error' },
    { name: 'text_and_attachment_accepted', input: 'send text', attachments: [file('file.txt')], outcome: 'accepted' },
    { name: 'empty_guard', input: '', attachments: [], outcome: 'none' },
    { name: 'bom_guard', input: '\uFEFF', attachments: [], outcome: 'none' },
    { name: 'nel_is_content', input: '\u0085', attachments: [], outcome: 'error' },
    { name: 'zero_width_is_content', input: '\u200B', attachments: [], outcome: 'error' },
    { name: 'padded_text_error', input: '\uFEFF \t retry text \r\n', attachments: [file('a')], outcome: 'error' },
    { name: 'bom_attachment_only_error', input: '\uFEFF', attachments: [file('a')], outcome: 'error' },
];
const cases = [];
for (const fixture of scenarios) {
    const state = { draft: fixture.input, attachments: fixture.attachments, sending: false, running: false };
    let request = null, resolve, reject;
    const snapshot = () => structuredClone(state);
    const api = { sendConversationMessage(id, message, attachments) {
        request = structuredClone({ id, message, ...(attachments ? { attachments } : {}) });
        return new Promise((yes, no) => { resolve = yes; reject = no; });
    } };
    const pending = execute(api, fixture.input, fixture.attachments, { handleCommand: () => false }, false, false, { id: 7 },
        value => { state.sending = value; }, value => { state.draft = value; }, value => { state.attachments = value; },
        value => { state.running = value; }, { error: () => {} }, value => value);
    const during = snapshot();
    if (request) {
        if (fixture.outcome === 'accepted') resolve({ status: 'accepted' });
        else reject(new Error('synthetic unavailable provider'));
    }
    await pending;
    cases.push({ ...fixture, request, pending: during, final: snapshot() });
}
console.log(JSON.stringify({ baseline: 'e75ae371ad777ffd1eecdd28d2781a6519b05591',
    source_file: 'web/src/app/(main)/chat/page.tsx', source_sha256: expected,
    handler_sha256: createHash('sha256').update(handler).digest('hex'),
    source_handler: handler, transform: 'Erase exactly one TypeScript error cast; inject bounded state/API stubs',
    scope: 'Executed source-derived send state/wire, not rendered browser/native UI or cloud acceptance', cases }, null, 2));
