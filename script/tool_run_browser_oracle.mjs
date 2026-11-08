import { readFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import assert from 'node:assert/strict';

const token = readFileSync(0, 'utf8').trim();
const origin = 'http://127.0.0.1:8787';
let stage = 'debugger';
async function waitFor(test) {
  for (let attempt = 0; attempt < 120; attempt++) {
    const value = await test();
    if (value) return value;
    await sleep(100);
  }
  throw new Error(stage);
}

let socket;
try {
  if (!/^[A-Za-z0-9_.-]{30,4096}$/.test(token)) throw new Error('invalid fixture session');
  const page = await waitFor(async () => {
    const response = await fetch('http://127.0.0.1:9222/json/list', { signal: AbortSignal.timeout(1000) }).catch(() => null);
    return response?.ok && (await response.json()).find(entry => entry.type === 'page');
  });
  assert.match(page.webSocketDebuggerUrl, /^ws:\/\/127\.0\.0\.1:9222\/devtools\/page\/[A-F0-9]+$/);
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await waitFor(() => socket.readyState === WebSocket.OPEN);
  const pending = new Map();
  let next = 0;
  let onPaused;
  let onLoadingFinished;
  socket.addEventListener('message', event => {
    const reply = JSON.parse(event.data);
    pending.get(reply.id)?.(reply);
    if (reply.method === 'Fetch.requestPaused') onPaused?.(reply.params);
    if (reply.method === 'Network.loadingFinished') onLoadingFinished?.(reply.params);
  });
  async function send(method, params = {}) {
    const id = ++next;
    const reply = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => { pending.delete(id); reject(new Error(stage)); }, 5000);
      pending.set(id, value => { clearTimeout(timeout); pending.delete(id); resolve(value); });
      socket.send(JSON.stringify({ id, method, params }));
    });
    assert.ok(!reply.error);
    return reply.result;
  }
  async function js(expression) {
    const result = await send('Runtime.evaluate', { expression, returnByValue: true });
    assert.ok(!result.exceptionDetails);
    return result.result.value;
  }
  function wait(expression) { return waitFor(() => js(expression)); }
  async function key(key, code = key, virtual = 0) {
    for (const type of ['keyDown', 'keyUp']) {
      await send('Input.dispatchKeyEvent', { type, key, code, windowsVirtualKeyCode: virtual });
    }
  }
  async function click(expression) {
    const rect = await js(`(() => { const e = ${expression}; e.scrollIntoView({block:'center'}); const r=e.getBoundingClientRect(); return { x:r.x+r.width/2, y:r.y+r.height/2 }; })()`);
    for (const type of ['mousePressed', 'mouseReleased']) {
      await send('Input.dispatchMouseEvent', { type, ...rect, button: 'left', clickCount: 1 });
    }
  }
  await send('Page.enable');
  await send('Page.addScriptToEvaluateOnNewDocument', {
    source: `if(location.origin===${JSON.stringify(origin)}) { localStorage.setItem('artex_token',${JSON.stringify(token)}); localStorage.setItem('artex_locale','en'); }`
  });
  stage = 'initial table';
  await send('Page.navigate', { url: origin + '/function/commands/' });
  await wait("document.querySelectorAll('tbody tr').length===50");
  const columns = await js("[...document.querySelectorAll('thead th')].map(e=>e.innerText)");
  assert.deepEqual(columns, ["Time", "Task", "Worker", "Tool", "Input", "Status"]);
  stage = 'detail';
  await click("document.querySelector('tbody tr')");
  await wait("document.querySelectorAll('[role=dialog] pre').length===2");
  const details = await js("[...document.querySelectorAll('[role=dialog] pre')].map(e=>e.innerText)");
  assert.deepEqual(details, ['{\n  "fixture_input": "plain 53"\n}', '<literal> result 53\n結果']);
  await key('Escape', 'Escape', 27);
  await wait("!document.querySelector('[role=dialog]')");
  stage = 'pagination';
  const range = "[...document.querySelectorAll('span')].find(e=>/^\\d+–\\d+ \\/ 54$/.test(e.textContent))";
  await click(`${range}.parentElement.querySelectorAll('button')[1]`);
  await wait("document.querySelectorAll('tbody tr').length===4");
  stage = 'summary';
  await click("[...document.querySelectorAll('button')].find(e=>e.innerText.trim()==='Statistics')");
  stage = 'summary rendering';
  await wait("document.querySelector('[role=dialog]')?.innerText.includes('WebFetch')");
  const summary = await js(`Object.fromEntries(['Bash','Read','WebFetch'].map(tool => {
    const row = [...document.querySelectorAll('[role=dialog] div.grid')].find(el=>el.querySelector('span')?.innerText===tool);
    return [tool, Number(row?.querySelector('.text-right')?.firstElementChild?.innerText)];
  }))`);
  assert.deepEqual(summary, { Bash: 18, Read: 18, WebFetch: 18 });
  assert.match(await js("document.querySelector('[role=dialog]').innerText"), /54\s*calls/);
  await key('Escape', 'Escape', 27);
  await wait("!document.querySelector('[role=dialog]')");
  stage = 'combined filter';
  await js("document.querySelectorAll('input[placeholder]')[0].focus()");
  await send('Input.insertText', { text: "日本語+ O'Neil" });
  await key('Tab', 'Tab', 9);
  assert.ok(await js("document.activeElement === document.querySelectorAll('input[placeholder]')[1]"));
  await send('Input.insertText', { text: '8802' });
  await wait("document.querySelectorAll('tbody tr').length===5 && [...document.querySelectorAll('tbody tr')].every(e=>e.innerText.includes('#8802'))");
  stage = 'empty filter';
  await js("document.querySelectorAll('input[placeholder]')[1].select()");
  await send('Input.insertText', { text: '9999' });
  await wait("document.querySelector('tbody')?.innerText.includes('No tool execution records')");
  stage = 'server error setup';
  let fulfillment;
  let interceptionError = false;
  onPaused = ({ requestId, request }) => {
    const url = new URL(request.url);
    const matches = request.method === 'GET' && url.origin === origin && url.pathname === '/api/commands'
      && url.searchParams.get('task') === '8801' && url.searchParams.get('q') === "日本語+ O'Neil"
      && url.searchParams.get('page') === '0' && url.searchParams.get('size') === '50';
    if (matches && !fulfillment) {
      fulfillment = send('Fetch.fulfillRequest', {
          requestId, responseCode: 500,
          responseHeaders: [{ name: 'Content-Type', value: 'application/json' }],
          body: Buffer.from('{"error":"Synthetic list failure"}').toString('base64'),
        }).then(() => true, () => false);
    } else {
      send('Fetch.continueRequest', { requestId }).catch(() => { interceptionError = true; });
    }
  };
  await send('Fetch.enable', { patterns: [{ urlPattern: origin + '/api/commands?*', requestStage: 'Request' }] });

  async function replaceExploration(value) {
    await js("document.querySelectorAll('input[placeholder]')[1].select()");
    await send('Input.insertText', { text: value });
  }

  await replaceExploration('8802');
  await wait("document.querySelectorAll('tbody tr').length===5");
  stage = 'server error rendering';
  await replaceExploration('8801');
  assert.equal(await waitFor(() => fulfillment && { promise: fulfillment }).then(result => result.promise), true);
  await wait("document.querySelector('tbody')?.innerText.includes('No tool execution records')");
  assert.equal(interceptionError, false);
  assert.equal(await js("document.body.innerText.includes('Synthetic list failure')"), false);
  await send('Fetch.disable');
  onPaused = undefined;

  stage = 'server error recovery';
  await replaceExploration('8802');
  await wait("document.querySelectorAll('tbody tr').length===5");
  await replaceExploration('8801');
  await wait("document.querySelectorAll('tbody tr').length===6 && [...document.querySelectorAll('tbody tr')].every(e=>e.innerText.includes('#8801'))");
  stage = 'invalid exploration input';
  await js("document.querySelectorAll('input[placeholder]')[0].select()");
  await key('Backspace', 'Backspace', 8);
  await wait("document.querySelectorAll('tbody tr').length===28");
  await replaceExploration('8802x');
  await wait("document.querySelectorAll('input[placeholder]')[1].value==='8802' && document.querySelectorAll('tbody tr').length===26 && [...document.querySelectorAll('tbody tr')].every(e=>e.innerText.includes('#8802'))");

  stage = 'late list response';
  await js("document.querySelectorAll('input[placeholder]')[0].focus()");
  await send('Input.insertText', { text: "日本語+ O'Neil" });
  await wait("document.querySelectorAll('tbody tr').length===5");
  let held;
  let oldResponseFinished = false;
  onLoadingFinished = ({ requestId }) => {
    if (held?.networkId === requestId) oldResponseFinished = true;
  };
  onPaused = event => {
    const url = new URL(event.request.url);
    if (!held && event.request.method === 'GET' && url.origin === origin && url.pathname === '/api/commands'
        && url.searchParams.get('task') === '8801' && url.searchParams.get('q') === "日本語+ O'Neil"
        && url.searchParams.get('page') === '0' && url.searchParams.get('size') === '50') {
      held = event;
    } else {
      send('Fetch.continueRequest', { requestId: event.requestId }).catch(() => { interceptionError = true; });
    }
  };
  await send('Network.enable');
  await send('Fetch.enable', { patterns: [{ urlPattern: origin + '/api/commands?*', requestStage: 'Request' }] });
  await replaceExploration('8801');
  const oldRequest = await waitFor(() => held);
  assert.ok(oldRequest.networkId);
  await replaceExploration('9999');
  await wait("document.querySelector('tbody')?.innerText.includes('No tool execution records')");
  await send('Fetch.continueRequest', { requestId: oldRequest.requestId });
  await waitFor(() => oldResponseFinished);
  const oldBody = await send('Network.getResponseBody', { requestId: oldRequest.networkId });
  const oldPage = JSON.parse(oldBody.base64Encoded ? Buffer.from(oldBody.body, 'base64').toString('utf8') : oldBody.body);
  assert.equal(oldPage.total, 6);
  assert.equal(oldPage.commands.length, 6);
  assert.ok(oldPage.commands.every(row => row.exploration_id === 8801));
  const frame = await send('Runtime.evaluate', {
    expression: "new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))",
    awaitPromise: true,
  });
  assert.ok(!frame.exceptionDetails);
  assert.ok(await js("document.querySelector('tbody')?.innerText.includes('No tool execution records')"));
  assert.equal(interceptionError, false);
  await send('Fetch.disable');
  await send('Network.disable');
  onPaused = undefined;
  onLoadingFinished = undefined;
  console.log(JSON.stringify({
    columns, detail: details, pageRows: [50, 4], summary, combinedRows: 5,
    emptyFilterVisible: true, escapeClosesDialogs: true, tabMovesBetweenFilters: true,
    lateListResponse: { oldRequestFinished: true, oldResponseRows: 6, newerEmptyStateRetained: true },
    invalidExploration: { typed: '8802x', effectiveValue: '8802', matchedRows: 26 },
    listFailure: { injectedStatus: 500, emptyStateDisplayed: true, recoveredRows: 6 },
  }));
} catch {
  console.error('Tool run browser failed at ' + stage);
  process.exitCode = 1;
} finally {
  socket?.close();
}
