#!/usr/bin/env node
//-
// SPDX-License-Identifier: BSD-2-Clause
//
// Drive docs/index.html in a real browser, with GitHub's API replaced by a mock.
//
// The page stopped being a form when it learned to dispatch a workflow: it now holds a token,
// talks to api.github.com, turns four status codes into four different sentences, polls for a run
// it has to recognise as its own, and hands over an artifact link. None of that is visible in a
// diff, and all of it is the kind of thing that is wrong in a way nobody notices until a reader
// pastes a token and gets "it failed".
//
// So the API is mocked rather than called: every status code can be produced on demand, a build
// can be made to finish in two polls, and no token and no Actions minutes are spent. What this
// cannot check is GitHub's real behaviour - the CORS preflight on a POST, the exact shape of a
// runs listing, whether the artifact link resolves. Those need one real build, and one real build
// is the thing to do before trusting any of this.
//
//     node tools/test-build-page.mjs          (needs playwright and a chromium)
//
// Exits 0 when every case passes, 1 otherwise.

import { chromium } from 'playwright';
import { createServer } from 'http';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const HERE = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(HERE, '..', 'docs', 'index.html'), 'utf8');
const srv = createServer((q, r) => { r.writeHead(200, {'content-type':'text/html; charset=utf-8'}); r.end(html); });
await new Promise(r => srv.listen(8111, r));
// The page reads the repository out of its own hostname, so the test has to be served from one
// that looks like a Pages site. Chromium is told to resolve it to loopback rather than the test
// requiring a line in /etc/hosts.
const b = await chromium.launch({
  executablePath: process.env.CHROMIUM || undefined,
  args: ['--host-resolver-rules=MAP someone.github.io 127.0.0.1']
});
const URL = 'http://someone.github.io:8111/my-fork/';
const fails = [];
const check = (name, cond, got) => { console.log((cond ? 'ok   ' : 'FAIL ') + name + (cond ? '' : '  -> ' + got)); if (!cond) fails.push(name); };

async function page(mock) {
  const c = await b.newContext({ viewport: { width: 1280, height: 1100 } });
  await c.route('https://github.com/**', r => r.fulfill({ status: 200,
    contentType: 'text/html', body: '<title>new issue</title>' }));
  const p = await c.newPage();
  p.on('pageerror', e => { console.log('PAGEERROR: ' + e.message); fails.push('pageerror'); });
  const seen = [];
  await c.route('https://api.github.com/**', async route => {
    const req = route.request();
    seen.push({ method: req.method(), url: req.url(), auth: req.headers()['authorization'],
                body: req.postData() });
    const res = mock(req, seen);
    await route.fulfill({ status: res.status, contentType: 'application/json',
                          body: res.body === undefined ? '{}' : JSON.stringify(res.body) });
  });
  await p.goto(URL, { waitUntil: 'load' });
  return { p, c, seen };
}
/* The token lives behind a disclosure now - the open route is the one offered first - so every
   token case has to open it the way a reader would. */
const openToken = async p => { await p.click('#token_block > summary'); };

const live = p => p.evaluate(() => ({
  state: document.getElementById('live').getAttribute('data-state'),
  head: document.getElementById('live_state').textContent,
  detail: document.getElementById('live_detail').textContent,
  err: document.getElementById('live_err').textContent,
  clock: document.getElementById('live_clock').textContent,
  dl: document.getElementById('live_dl').className.includes('hidden') ? null : document.getElementById('live_dl').href,
  log: document.getElementById('live_log').className.includes('hidden') ? null : document.getElementById('live_log').href,
  cardShown: !document.getElementById('live_card').className.includes('hidden'),
  actionsShown: !document.getElementById('actions').className.includes('hidden'),
}));

// ---------------------------------------------------------------- 1. happy path
{
  let runCalls = 0;
  const { p, c, seen } = await page((req) => {
    const u = req.url();
    if (req.method() === 'POST' && u.includes('/dispatches')) return { status: 204 };
    if (u.includes('/actions/runs?')) return { status: 200, body: { workflow_runs: [
      { id: 7, name: '26.7 serial at 115200 ' + globalThis.BID, display_title: '26.7 serial at 115200 ' + globalThis.BID }] } };
    if (/\/actions\/runs\/7$/.test(u)) { runCalls++;
      return { status: 200, body: runCalls < 2 ? { status: 'in_progress' } : { status: 'completed', conclusion: 'success' } }; }
    if (u.includes('/artifacts')) return { status: 200, body: { artifacts: [
      { id: 99, name: 'xgs-opnsense-26.7-serial-115200', size_in_bytes: 512 * 1024 * 1024 }] } };
    return { status: 404, body: { message: 'unexpected ' + u } };
  });
  // the page generates its own id; capture it from the dispatch body
  await openToken(p);
  await p.fill('#token', 'github_pat_test');
  check('the token button is never dead', !(await p.isDisabled('#build')), 'disabled');
  await p.click('#build');
  await p.waitForTimeout(900);
  const disp = seen.find(s => s.method === 'POST');
  check('dispatch is a POST to the workflow', !!disp && disp.url.includes('/actions/workflows/build.yml/dispatches'), disp && disp.url);
  check('dispatch carries a bearer token', disp && disp.auth === 'Bearer github_pat_test', disp && disp.auth);
  check('token is never in a URL', !seen.some(s => s.url.includes('github_pat_test')), 'leaked');
  const sent = JSON.parse(disp.body);
  globalThis.BID = sent.inputs.build_id;
  check('dispatch ref is main', sent.ref === 'main', sent.ref);
  check('dispatch carries all six inputs', Object.keys(sent.inputs).sort().join(',') ===
    'build_id,console_speed,image_type,opnsense_version,project_ref,serial_console', Object.keys(sent.inputs).join(','));
  check('build_id looks like a nonce', /^web-[a-z0-9]+-[a-z0-9]{6}$/.test(sent.inputs.build_id), sent.inputs.build_id);
  await p.waitForFunction(() => document.getElementById('live').getAttribute('data-state') === 'done', null, { timeout: 60000 });
  const v = await live(p);
  check('finishes in the done state', v.state === 'done' && v.head === 'Ready', JSON.stringify(v));
  check('reports the artifact name and size', v.detail.includes('xgs-opnsense-26.7-serial-115200') && v.detail.includes('512 MB'), v.detail);
  check('says it was not booted', v.detail.includes('not been booted'), v.detail);
  check('offers the download link GitHub serves', v.dl === 'https://github.com/someone/my-fork/actions/runs/7/artifacts/99', v.dl);
  check('offers the run link', v.log === 'https://github.com/someone/my-fork/actions/runs/7', v.log);
  check('the choose-options buttons are out of the way while it runs', v.actionsShown === false, 'still shown');
  await p.click('#live_clear');
  const after = await live(p);
  check('"Start another" puts the buttons back', after.actionsShown && !after.cardShown, JSON.stringify(after));
  await c.close();
}

// --------------------------------------------- 1b. the token button with no token in the field
{
  const { p, c, seen } = await page(() => ({ status: 200, body: {} }));
  await p.click('#build');
  await p.waitForTimeout(250);
  check('pressing it with no token opens the field',
        await p.evaluate(() => document.getElementById('token_block').open), 'stayed shut');
  check('and focuses it',
        await p.evaluate(() => document.activeElement.id) === 'token', await p.evaluate(() => document.activeElement.id));
  check('and dispatches nothing', seen.length === 0, seen.length + ' calls');
  await c.close();
}

// ---------------------------------------------------------------- 2. failure paths
for (const [name, status, body, wantIn] of [
  ['401 says the token was rejected', 401, { message: 'Bad credentials' }, 'rejected the token'],
  ['403 names the permission needed', 403, { message: 'Resource not accessible' }, 'Actions: Read and write'],
  ['403 rate limit is told apart', 403, { message: 'API rate limit exceeded' }, 'rate-limiting'],
  ['404 says the token cannot see the repo', 404, { message: 'Not Found' }, 'cannot see someone/my-fork'],
  ['422 mentions the default branch', 422, { message: 'Workflow does not have workflow_dispatch trigger' }, 'default branch'],
  ['500 is reported with its code', 500, { message: 'oops' }, 'answered 500'],
]) {
  const { p, c } = await page(() => ({ status, body }));
  await openToken(p);
  await p.fill('#token', 'tok');
  await p.click('#build');
  await p.waitForTimeout(500);
  const v = await live(p);
  check(name, v.state === 'failed' && v.err.includes(wantIn), JSON.stringify(v));
  await c.close();
}

// ---------------------------------------------------------------- 3. the build fails
{
  const { p, c } = await page((req) => {
    const u = req.url();
    if (req.method() === 'POST') return { status: 204 };
    if (u.includes('/actions/runs?')) return { status: 200, body: { workflow_runs: [{ id: 5, name: 'x', display_title: 'x' }] } };
    return { status: 200, body: { status: 'completed', conclusion: 'failure' } };
  });
  await openToken(p);
  await p.fill('#token', 'tok');
  await p.click('#build');
  await p.waitForTimeout(1500);
  const v = await live(p);
  // the run carries no build id, so this exercises "never appeared" OR the failure - check we are not stuck silent
  check('a run that is not ours does not get claimed', v.state === 'working' && v.head === 'Queued', JSON.stringify(v));
  await c.close();
}

// ---------------------------------------------------------------- 3b. the open route
{
  let appeared = false, finished = false, bid = null;
  const { p, c, seen } = await page((req) => {
    const u = req.url();
    if (u.includes('/actions/runs?')) return { status: 200, body: { workflow_runs:
      appeared ? [{ id: 11, name: 'x ' + bid, display_title: 'x ' + bid }] : [] } };
    if (/\/actions\/runs\/11$/.test(u)) return { status: 200,
      body: finished ? { status: 'completed', conclusion: 'success' } : { status: 'in_progress' } };
    if (u.includes('/artifacts')) return { status: 200, body: { artifacts: [
      { id: 42, name: 'xgs-opnsense-26.7-serial-115200', size_in_bytes: 400 * 1024 * 1024 }] } };
    return { status: 404, body: { message: 'unexpected ' + u } };
  });
  const [popup] = await Promise.all([ c.waitForEvent('page'), p.click('#go') ]);
  await popup.waitForLoadState('domcontentloaded').catch(() => {});
  const opened = decodeURIComponent(popup.url());
  check('the open route really opens a tab', !!popup, 'no tab');
  check('the tab is the new-issue form', opened.includes('/issues/new?labels=build'), opened);
  bid = (opened.match(/"build_id": "([^"]+)"/) || [])[1];
  check('the issue body carries a build_id', /^web-[a-z0-9]+-[a-z0-9]{6}$/.test(bid || ''), bid);
  await p.waitForTimeout(300);
  let v = await live(p);
  check('it waits for the human press', v.state === 'working' && v.head === 'Waiting for you', JSON.stringify(v));
  check('it names the button to press', v.detail.includes('Submit new issue'), v.detail);
  check('a counter is running', /^\d+seconds$|^\d+:\d\delapsed$/.test(v.clock), v.clock);
  await p.waitForTimeout(2200);
  const later = (await live(p)).clock;
  check('the counter ticks between polls', later !== v.clock, v.clock + ' -> ' + later);
  check('the polls carry no Authorization', !seen.some(s => s.auth), 'a token was sent');
  appeared = true;
  await p.waitForFunction(() => document.getElementById('live_state').textContent === 'Building', null, { timeout: 60000 });
  finished = true;
  await p.waitForFunction(() => document.getElementById('live').dataset.state === 'done', null, { timeout: 90000 });
  v = await live(p);
  check('the counter stops when it is done', v.clock === '', JSON.stringify(v.clock));
  check('the open route ends with the download', v.state === 'done' && v.dl ===
    'https://github.com/someone/my-fork/actions/runs/11/artifacts/42', JSON.stringify(v));
  await c.close();
}

// ---------------------------------------------------------------- 3c. the anonymous allowance
{
  const { p, c } = await page(() => ({ status: 403, body: { message: 'API rate limit exceeded' } }));
  await Promise.all([ c.waitForEvent('page'), p.click('#go') ]);
  await p.waitForTimeout(600);
  const v = await live(p);
  check('a spent anonymous allowance is not called a failure', v.state === 'working', JSON.stringify(v));
  check('it says the build is unaffected', v.detail.includes('build is unaffected'), v.detail);
  check('it offers the run on GitHub', !!v.log, 'no link');
  await c.close();
}

// ---------------------------------------------------------------- 4. the token route still works
{
  const { p, c } = await page(() => ({ status: 200, body: {} }));
  await p.click('#copy');
  await p.waitForTimeout(300);
  const said = await p.textContent('#copied');
  check('the copy button still reports', said.includes('Copied') || said.includes('Could not copy'), said);
  const shown = await p.textContent('#json');
  check('the copied request carries no build_id', !shown.includes('build_id'), shown);
  await c.close();
}

// ---------------------------------------------------------------- 5. token memory
{
  const c = await b.newContext({ viewport: { width: 1280, height: 1000 } });
  const p = await c.newPage();
  await p.goto(URL, { waitUntil: 'load' });
  await openToken(p);
  await p.fill('#token', 'secret-one');
  check('a token is not stored unless asked', await p.evaluate(() => localStorage.getItem('xgs.token')) === null, 'stored anyway');
  await p.check('#keep');
  check('ticking the box stores it', await p.evaluate(() => localStorage.getItem('xgs.token')) === 'secret-one', 'not stored');
  await p.reload({ waitUntil: 'load' });
  await openToken(p);
  check('it comes back on reload', await p.inputValue('#token') === 'secret-one', await p.inputValue('#token'));
  await p.uncheck('#keep');
  check('unticking forgets it', await p.evaluate(() => localStorage.getItem('xgs.token')) === null, 'still stored');
  await c.close();
}

await b.close(); srv.close();
console.log('\n' + (fails.length ? fails.length + ' FAILED: ' + fails.join(', ') : 'all passed'));
process.exit(fails.length ? 1 : 0);
