// Exercise the LuCI view's lifecycle and RPC behavior without a router.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function harness() {
  const nodes = {}, listeners = {}, calls = [], polls = new Set();
  let clock = 1790000000000, response;
  function E(tag, attrs, children) {
    const node = { tag, attrs: attrs || {}, children, isConnected: true };
    if (node.attrs.id) nodes[node.attrs.id] = node;
    return node;
  }
  const ctx = vm.createContext({
    E, _: s => s, Date: { now: () => clock },
    document: { getElementById: id => nodes[id] },
    window: {
      addEventListener: (name, fn) => { listeners[name] = fn; },
      removeEventListener: name => { delete listeners[name]; }
    },
    view: { extend: o => o },
    rpc: { declare: spec => () => { calls.push(spec.method); return Promise.resolve(response); } },
    ui: { createHandlerFn: (self, fn) => fn.bind(self), addNotification: () => {} },
    poll: { add: fn => polls.add(fn), remove: fn => polls.delete(fn) },
    dom: { content: (node, children) => { node.children = children; } },
    qrcode: { svg: url => E('svg', { url }) },
    L: { bind: (fn, self) => fn.bind(self), hasViewPermission: () => true }
  });
  vm.runInContext("String.prototype.format = function(...args) { let i=0; return this.replace(/%[sd]/g, () => args[i++]); };", ctx);
  const source = fs.readFileSync('packages/luci-app-letkite/htdocs/luci-static/resources/view/letkite/overview.js', 'utf8');
  const app = vm.runInContext('(function(){' + source + '\n})()', ctx);
  const status = en => ({ installed: true, cli: true, agent: { enrolled: false, enrollment: en } });
  const code = { state: 'waiting', user_code: 'BDFK-QRTW', verification_uri: 'https://id.letkite.dev/device', verification_uri_complete: 'https://id.letkite.dev/device?code=BDFK-QRTW', expires_at: clock / 1000 + 600 };
  const root = app.render(status({ state: 'unclaimed' }));
  return {
    app, nodes, calls, polls, root, code, status, listeners,
    set: value => { response = value; },
    advance: seconds => { clock += seconds * 1000; },
    tick: async () => { for (const fn of [...polls]) await fn(); }
  };
}
function text(node) {
  if (Array.isArray(node)) return node.map(text).join(' ');
  if (node && typeof node === 'object') return text(node.children);
  return node == null ? '' : String(node);
}
function find(node, tag) {
  if (Array.isArray(node)) return node.flatMap(n => find(n, tag));
  if (!node || typeof node !== 'object') return [];
  return [...(node.tag === tag ? [node] : []), ...find(node.children, tag)];
}

test('opening asks automatically, countdown expires and refreshes, then success names the node', async () => {
  const h = harness();
  h.set(h.status(h.code));
  await h.tick();
  assert.deepEqual(h.calls, ['claim_status']);
  assert.match(text(h.nodes['letkite-pair']), /BDFK-QRTW/);
  assert.match(text(h.nodes['letkite-pair']), /https:\/\/dashboard.letkite.dev → Add device → Enter the code/);
  assert.equal(find(h.nodes['letkite-pair'], 'svg')[0].attrs.url, h.code.verification_uri_complete);
  assert.match(text(h.nodes['letkite-pair']), /600 seconds/);
  assert.equal(find(h.nodes['letkite-pair'], 'button').length, 0);
  h.advance(1);
  await h.tick();
  assert.match(text(h.nodes['letkite-pair']), /599 seconds/);
  assert.equal(h.calls.length, 1);
  h.advance(600);
  h.set(h.status({ ...h.code, user_code: 'NEWC-ODEX', expires_at: h.code.expires_at + 601 }));
  await h.tick();
  assert.deepEqual(h.calls, ['claim_status', 'claim_status']);
  assert.match(text(h.nodes['letkite-pair']), /NEWC-ODEX/);
  h.advance(11);
  h.set({ installed: true, agent: { enrolled: true, name: 'owrt-arm', enrollment: { state: 'enrolled' } } });
  await h.tick();
  assert.equal(h.calls.at(-1), 'status');
  assert.match(text(h.nodes['letkite-pair']), /Paired as owrt-arm/);
  h.advance(20);
  await h.tick();
  assert.equal(h.calls.at(-1), 'status');
});

test('denied claims require retry; ordinary status does not restart the claim', async () => {
  const h = harness();
  const denied = h.status({ state: 'unclaimed', error: 'denied', problem: 'declined' });
  h.set(denied);
  await h.tick();
  assert.match(text(h.nodes['letkite-pair']), /declined/);
  h.advance(11);
  await h.tick();
  assert.deepEqual(h.calls, ['claim_status', 'status']);
  find(h.nodes['letkite-pair'], 'button')[0].attrs.click();
  h.set(h.status(h.code));
  await h.tick();
  assert.equal(h.calls.at(-1), 'claim_status');
});

test('unsupported agent error remains visible and does not loop', async () => {
  const h = harness();
  h.set({ ok: false, error: 'update the agent' });
  await h.tick();
  assert.match(text(h.nodes['letkite-pair']), /update the agent/);
  assert.equal(h.app.claimStopped, true);
});

test('pagehide and LuCI navigation each remove polling and never request another code', async () => {
  for (const close of [h => h.listeners.pagehide(), h => { h.root.isConnected = false; }]) {
    const h = harness();
    h.set(h.status(h.code));
    await h.tick();
    close(h);
    h.advance(601);
    await h.tick();
    await h.tick();
    assert.equal(h.calls.length, 1);
    assert.equal(h.polls.size, 0);
  }
});

test('a response arriving after closing the page cannot restart polling', async () => {
  const h = harness();
  let resolve;
  h.set(new Promise(r => { resolve = r; }));
  const tick = h.tick();
  h.listeners.pagehide();
  resolve(h.status(h.code));
  await tick;
  h.advance(601);
  await h.tick();
  assert.equal(h.calls.length, 1);
  assert.equal(h.polls.size, 0);
});
