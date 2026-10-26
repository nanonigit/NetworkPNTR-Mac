"""Execute only the inspected checksum-pinned browser findings filter function."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

BASELINE = 'e75ae371ad777ffd1eecdd28d2781a6519b05591'
API_SHA256 = '18b4529a99b508964348bf83b7777597ca3cb80a64565380e1b1320005700fe1'
SIGNATURE = 'function findingFilterParams(q: Omit<FindingQuery, "page" | "pageSize">): URLSearchParams {'
# Filled from the inspected immutable function, not supplied by a fixture or command argument.
FUNCTION_SHA256 = '6a98d554bf6172094f793f7a89339372a94e25d7ae75b66738c1b8d0c695dcce'
DRIVER = """const fs=require('node:fs');const input=JSON.parse(fs.readFileSync(0,'utf8'));
const filter=new Function(input.source+';return findingFilterParams;')();
const result=input.cases.map(item=>{
 const q={...item.query};if(item.operation==='tree')delete q.assetScope;
 const params=filter(q);
 if(item.operation!=='tree'){params.set('page',String(q.page));params.set('limit',String(q.pageSize));}
 return {...item,expected:Object.fromEntries(params)};
});process.stdout.write(JSON.stringify(result));"""


def execute_function(function, cases):
    if hashlib.sha256(function.encode()).hexdigest() != FUNCTION_SHA256:
        raise RuntimeError('Pinned findings function mismatch')
    executable = function.replace(SIGNATURE, 'function findingFilterParams(q) {', 1)
    if executable == function:
        raise RuntimeError('Pinned findings signature missing')
    if len(cases) > 32 or any(item.get('operation') not in ('flat', 'group', 'tree') for item in cases):
        raise RuntimeError('Finite findings oracle cases required')
    result = subprocess.run(['node', '-e', DRIVER], input=json.dumps({'source': executable, 'cases': cases}).encode(),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=True)
    if len(result.stdout) > 128 * 1024:
        raise RuntimeError('Finite findings oracle output exceeded')
    return json.loads(result.stdout)


def source_function(source):
    raw = Path(source).read_bytes()
    if hashlib.sha256(raw).hexdigest() != API_SHA256:
        raise RuntimeError('Pinned findings source mismatch')
    text = raw.decode()
    start = text.index(SIGNATURE); end = text.index('\n}\n', start) + 2
    return text[start:end]


def execute(source, cases):
    return execute_function(source_function(source), cases)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: findings_filter_oracle.py PINNED_API_TS CASE_FIXTURE_JSON')
    fixture = json.loads(Path(sys.argv[2]).read_text())
    function = source_function(sys.argv[1])
    print(json.dumps({'baseline': BASELINE, 'source_file': 'web/src/lib/api.ts', 'source_sha256': API_SHA256,
                      'function_sha256': FUNCTION_SHA256, 'source_function': function,
                      'scope': 'Executed source filter query projection only; no rendered UI/API/runtime acceptance',
                      'cases': execute_function(function, fixture['cases'])}, ensure_ascii=False, indent=2))
