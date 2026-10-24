// Execute only the inspected parser from the checksum-pinned browser source.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const source = readFileSync(process.argv[2]);
const expected = 'c735ebddab7f790f967a42e54fc993b9dd817a44eea5532bb461fb52dfe17952';
if (createHash('sha256').update(source).digest('hex') !== expected) throw new Error('Pinned transcript source mismatch');
const text = source.toString('utf8');
const start = text.indexOf('function parseUserBody(body: string)');
const end = text.indexOf('\nfunction UserRow(', start);
if (start < 0 || end < 0) throw new Error('Pinned parser boundary missing');
const handler = text.slice(start, end).trim();
const signature = 'function parseUserBody(body: string): { text: string; attachments: MsgAttachment[] }';
if (handler.split(signature).length !== 2) throw new Error('Expected exact TypeScript parser signature');
const executable = handler.replace(signature, 'function parseUserBody(body)');
const parse = new Function(executable + '\nreturn parseUserBody;')();
const file = name => ({name,path:'uploads/' + name,size:1});
const cases = [
    ['plain', 'literal **text**\nnext line'],
    ['malformed', '{ literal not JSON'],
    ['structured', JSON.stringify({text:'hello\nworld',attachments:[file('\u00e9.txt'),file('e\u0301.txt')]})],
    ['empty_list', JSON.stringify({text:'plain',attachments:[]})],
    ['number_text', JSON.stringify({text:42,attachments:[file('a')]})],
    ['missing_text', JSON.stringify({attachments:[file('a')]})],
    ['leading_space', ' ' + JSON.stringify({text:'not parsed',attachments:[file('a')]})],
    ['bom_prefix', '\uFEFF' + JSON.stringify({text:'not parsed',attachments:[file('a')]})],
    ['array_root', JSON.stringify([{attachments:[file('a')]}])],
    ['no_attachments', JSON.stringify({text:'not parsed'})],
    ['duplicate_paths', JSON.stringify({text:'two references',attachments:[file('a'),file('a')]})],
    ['ignore_guest_abs', JSON.stringify({text:'',attachments:[{...file('a'),abs:'/guest/fixture/a'}]})],
];
console.log(JSON.stringify({baseline:'e75ae371ad777ffd1eecdd28d2781a6519b05591',source_file:'web/src/components/transcript.tsx',source_sha256:expected,
    parser_sha256:createHash('sha256').update(handler).digest('hex'),transform:'Erase exactly one inspected TypeScript signature; execute parser with inert string fixtures',
    scope:'Source parser execution with validated metadata projection, not rendered UI or malformed metadata parity',
    cases:cases.map(([name,body])=>{const result=parse(body);return {name,body,expected:{text:result.text,attachments:result.attachments.map(({name,path,size})=>({name,path,size}))}}})}, null, 2));
