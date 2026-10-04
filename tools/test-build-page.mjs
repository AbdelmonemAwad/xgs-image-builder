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

// ------------------------------- 1. the token route, when the token's owner owns the repository
{
  let runCalls = 0, bid = null;
  const { p, c, seen } = await page((req) => {
    const u = req.url();
    if (u.endsWith('/user')) return { status: 200, body: { login: 'someone' } };
    if (req.method() === 'POST' && u.includes('/dispatches')) return { status: 204 };
    if (u.endsWith('/repos/someone/my-fork')) return { status: 200, body: { default_branch: 'trunk' } };
    if (u.includes('/actions/runs?')) return { status: 200, body: { workflow_runs: [
      { id: 7, name: '26.7 serial ' + bid, display_title: '26.7 serial ' + bid }] } };
    if (/\/actions\/runs\/7$/.test(u)) { runCalls++;
      return { status: 200, body: runCalls < 2 ? { status: 'in_progress' } : { status: 'completed', conclusion: 'success' } }; }
    if (u.includes('/artifacts')) return { status: 200, body: { artifacts: [
      { id: 99, name: 'xgs-opnsense-26.7-serial-115200', size_in_bytes: 512 * 1024 * 1024 }] } };
    return { status: 404, body: { message: 'unexpected ' + u } };
  });
  await openToken(p);
  await p.fill('#token', 'github_pat_test');
  check('the token button is never dead', !(await p.isDisabled('#build')), 'disabled');
  const [req] = await Promise.all([ p.waitForRequest(r => r.method() === 'POST'), p.click('#build') ]);
  const disp = { url: req.url(), auth: req.headers()['authorization'], body: req.postData() };
  check('dispatch is a POST to the workflow', disp.url.includes('/actions/workflows/build.yml/dispatches'), disp.url);
  check('dispatch carries a bearer token', disp.auth === 'Bearer github_pat_test', disp.auth);
  check('token is never in a URL', !seen.some(x => x.url.includes('github_pat_test')), 'leaked');
  check('it did not fork what is already yours', !seen.some(x => x.url.endsWith('/forks')), 'forked anyway');
  const sent = JSON.parse(disp.body);
  bid = sent.inputs.build_id;
  check('dispatch uses the default branch it was told', sent.ref === 'trunk', sent.ref);
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

// -------------------------- 1a. the token route when it is somebody else's repository: it forks
{
  let bid = null, forkExists = false, forkPosts = 0, enabled = false;
  const { p, c, seen } = await page((req) => {
    const u = req.url(), m = req.method();
    if (u.endsWith('/user')) return { status: 200, body: { login: 'visitor' } };
    if (u.endsWith('/repos/visitor/my-fork')) return forkExists
      ? { status: 200, body: { default_branch: 'main', fork: true } }
      : { status: 404, body: { message: 'Not Found' } };
    if (m === 'POST' && u.endsWith('/repos/someone/my-fork/forks')) {
      forkPosts++; forkExists = true; return { status: 202, body: {} };
    }
    if (m === 'PUT' && u.includes('/actions/permissions')) { enabled = true; return { status: 204 }; }
    if (m === 'POST' && u.includes('/dispatches')) return { status: 204 };
    if (u.includes('/actions/runs?')) return { status: 200, body: { workflow_runs: [
      { id: 3, name: bid, display_title: bid }] } };
    if (/\/actions\/runs\/3$/.test(u)) return { status: 200, body: { status: 'completed', conclusion: 'success' } };
    if (u.includes('/artifacts')) return { status: 200, body: { artifacts: [
      { id: 8, name: 'xgs-opnsense-26.7-serial-115200', size_in_bytes: 390 * 1024 * 1024 }] } };
    return { status: 404, body: { message: 'unexpected ' + m + ' ' + u } };
  });
  await openToken(p);
  await p.fill('#token', 'tok');
  const [disp] = await Promise.all([
    p.waitForRequest(r => r.method() === 'POST' && r.url().includes('/dispatches')),
    p.click('#build')
  ]);
  bid = JSON.parse(disp.postData()).inputs.build_id;
  check('it forks the repository it is not yours', forkPosts === 1, forkPosts + ' fork calls');
  check('it turns workflows on for the fork', enabled, 'never enabled');
  check('it dispatches into the fork, not the original',
        disp.url().includes('/repos/visitor/my-fork/'), disp.url());
  await p.waitForFunction(() => document.getElementById('live').dataset.state === 'done', null, { timeout: 60000 });
  const v = await live(p);
  check('and the download comes from the fork',
        v.dl === 'https://github.com/visitor/my-fork/actions/runs/3/artifacts/8', v.dl);
  await c.close();
}

// ------------------------------------------- 1a2. a fork that already exists is not forked again
{
  let forkPosts = 0;
  const { p, c } = await page((req) => {
    const u = req.url(), m = req.method();
    if (u.endsWith('/user')) return { status: 200, body: { login: 'visitor' } };
    if (u.endsWith('/repos/visitor/my-fork')) return { status: 200, body: { default_branch: 'main' } };
    if (m === 'POST' && u.endsWith('/forks')) { forkPosts++; return { status: 202, body: {} }; }
    if (m === 'PUT' && u.includes('/actions/permissions')) return { status: 204 };
    if (m === 'POST' && u.includes('/dispatches')) return { status: 204 };
    return { status: 200, body: { workflow_runs: [] } };
  });
  await openToken(p);
  await p.fill('#token', 'tok');
  await Promise.all([ p.waitForRequest(r => r.url().includes('/dispatches')), p.click('#build') ]);
  check('an existing fork is reused, not forked again', forkPosts === 0, forkPosts + ' fork calls');
  await c.close();
}

// ------------------------------------------------- 1a3. a token that may not create a repository
{
  const { p, c } = await page((req) => {
    const u = req.url(), m = req.method();
    if (u.endsWith('/user')) return { status: 200, body: { login: 'visitor' } };
    if (u.endsWith('/repos/visitor/my-fork')) return { status: 404, body: { message: 'Not Found' } };
    if (m === 'POST' && u.endsWith('/forks')) return { status: 403, body: { message: 'Resource not accessible by personal access token' } };
    return { status: 404, body: {} };
  });
  await openToken(p);
  await p.fill('#token', 'tok');
  await p.click('#build');
  await p.waitForFunction(() => document.getElementById('live').dataset.state === 'failed', null, { timeout: 20000 });
  const v = await live(p);
  check('a token that cannot fork says exactly that', v.err.includes('Forking makes a new repository'), v.err);
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
    if (u.endsWith('/user')) return { status: 200, body: { login: 'someone' } };
    if (u.endsWith('/repos/someone/my-fork')) return { status: 200, body: { default_branch: 'main' } };
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

// ------------------------------------------------- 3b. the open route follows its own issue
/* Classified by the marker the workflow writes, not by the prose - so a reworded comment cannot
   stop the page understanding its own reply. Both are exercised: the marker, and the fallback for
   a comment written before markers existed. */
const DECLINE = 'Nothing was built. That is this repository refusing, not a fault.\n\nTwo ways to '
  + 'get your own.\n\n<!-- xgs-result: declined -->';
const DECLINE_OLD = 'Nothing was built, and the page you filed this from will time out waiting.';
const STARTED = 'Build started: OPNsense `26.7` `serial` at `115200` baud.\n\n<!-- xgs-result: started -->';
const MALFORMED = 'This request was not started.\n\n```\nimage_type=\'dvd\' is not one of\n```\n\n<!-- xgs-result: malformed -->';

async function openRoute(mock) {
  const { p, c, seen } = await page(mock);
  const [popup] = await Promise.all([ c.waitForEvent('page'), p.click('#go') ]);
  await popup.waitForLoadState('domcontentloaded').catch(() => {});
  const bid = (decodeURIComponent(popup.url()).match(/"build_id": "([^"]+)"/) || [])[1];
  return { p, c, seen, bid };
}

// the refusal, which is the case that used to be fifteen minutes of silence
{
  let filed = false, answered = false, bid = null;
  const ctx = await openRoute((req) => {
    const u = req.url();
    if (u.includes('/issues?')) return { status: 200, body: filed
      ? [{ number: 9, body: 'x ' + bid + ' x', html_url: 'https://github.com/someone/my-fork/issues/9' }] : [] };
    if (u.includes('/issues/9/comments')) return { status: 200, body: answered ? [{ body: DECLINE }] : [] };
    return { status: 200, body: { workflow_runs: [] } };
  });
  bid = ctx.bid;
  await ctx.p.waitForTimeout(300);
  let v = await live(ctx.p);
  check('before Submit it waits for the human', v.head === 'Waiting for you', JSON.stringify(v));
  filed = true;
  await ctx.p.waitForFunction(() => document.getElementById('live_state').textContent === 'Filed', null, { timeout: 30000 });
  v = await live(ctx.p);
  check('once filed it says so', v.head === 'Filed', JSON.stringify(v));
  check('and links the issue', v.log === 'https://github.com/someone/my-fork/issues/9', v.log);
  answered = true;
  await ctx.p.waitForFunction(() => document.getElementById('live').dataset.state === 'failed', null, { timeout: 30000 });
  v = await live(ctx.p);
  check('a refusal is shown, not waited out', v.head === 'This repository refused it', JSON.stringify(v));
  check('and the repository own words are on the page', v.err.includes('refusing, not a fault'), v.err);
  check('the marker itself is not shown to the reader', !v.err.includes('xgs-result'), v.err);
  check('the counter stops on a refusal', v.clock === '', v.clock);
  await ctx.c.close();
}

// the same, classified by prose because the comment predates the marker
{
  let bid = null;
  const ctx = await openRoute((req) => {
    const u = req.url();
    if (u.includes('/issues?')) return { status: 200, body: [{ number: 9, body: 'x ' + bid, html_url: 'u' }] };
    if (u.includes('/issues/9/comments')) return { status: 200, body: [{ body: DECLINE_OLD }] };
    return { status: 200, body: { workflow_runs: [] } };
  });
  bid = ctx.bid;
  await ctx.p.waitForFunction(() => document.getElementById('live').dataset.state === 'failed', null, { timeout: 30000 });
  check('a comment with no marker is still understood',
        (await live(ctx.p)).head === 'This repository refused it', JSON.stringify(await live(ctx.p)));
  await ctx.c.close();
}

// a malformed request is told apart from a refusal
{
  let bid = null;
  const ctx = await openRoute((req) => {
    const u = req.url();
    if (u.includes('/issues?')) return { status: 200, body: [{ number: 9, body: 'x ' + bid, html_url: 'u' }] };
    if (u.includes('/issues/9/comments')) return { status: 200, body: [{ body: MALFORMED }] };
    return { status: 200, body: { workflow_runs: [] } };
  });
  bid = ctx.bid;
  await ctx.p.waitForFunction(() => document.getElementById('live').dataset.state === 'failed', null, { timeout: 30000 });
  const v = await live(ctx.p);
  check('a malformed request is not called a refusal', v.head === 'The request was not started', v.head);
  check('and the reason is carried over', v.err.includes('is not one of'), v.err);
  await ctx.c.close();
}

// the acceptance: the comment hands over to the run watcher
{
  let bid = null, finished = false;
  const ctx = await openRoute((req) => {
    const u = req.url();
    if (u.includes('/issues?')) return { status: 200, body: [{ number: 9, body: bid, html_url: 'u' }] };
    if (u.includes('/issues/9/comments')) return { status: 200, body: [{ body: STARTED }] };
    if (u.includes('/actions/runs?')) return { status: 200, body: { workflow_runs: [{ id: 5, name: bid, display_title: bid }] } };
    if (/\/actions\/runs\/5$/.test(u)) return { status: 200, body: finished
      ? { status: 'completed', conclusion: 'success' } : { status: 'in_progress' } };
    if (u.includes('/artifacts')) return { status: 200, body: { artifacts: [
      { id: 42, name: 'xgs-opnsense-26.7-serial-115200', size_in_bytes: 400 * 1024 * 1024 }] } };
    return { status: 404, body: { message: 'unexpected ' + u } };
  });
  bid = ctx.bid;
  await ctx.p.waitForFunction(() => document.getElementById('live_state').textContent === 'Building', null, { timeout: 40000 });
  check('an accepted request hands over to the run', true, '');
  check('the open route never sends a token', !ctx.seen.some(x => x.auth), 'a token was sent');
  finished = true;
  await ctx.p.waitForFunction(() => document.getElementById('live').dataset.state === 'done', null, { timeout: 60000 });
  const v = await live(ctx.p);
  check('and ends with the download', v.dl === 'https://github.com/someone/my-fork/actions/runs/5/artifacts/42', v.dl);
  await ctx.c.close();
}

// ---------------------------------------------------------------- 3c. the anonymous allowance
{
  const ctx = await openRoute(() => ({ status: 403, body: { message: 'API rate limit exceeded' } }));
  await ctx.p.waitForTimeout(600);
  const v = await live(ctx.p);
  check('a spent anonymous allowance is not called a failure', v.state === 'working', JSON.stringify(v));
  check('and says nothing here is broken', v.detail.includes('Nothing here is broken'), v.detail);
  await ctx.c.close();
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
