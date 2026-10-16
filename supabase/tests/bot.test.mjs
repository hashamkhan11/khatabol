// The WhatsApp bot's database side: linked numbers, confirm before save, undo.
// Run: npm test   (from the supabase folder)
import { afterEach, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb } from './helpers.mjs';

const NUMBER = '923001234567';
let L, me, rashid, cloth;

beforeEach(async () => {
  L = await freshDb();
  me = await L.createUser();
  await L.signIn(me);
  rashid = await L.one('create_party', { p_name: 'Rashid', p_type: 'supplier' });
  cloth = await L.one('create_item', { p_name_en: 'Used cloth' });
  await L.query('reset role');
  await L.query('insert into bot_senders (whatsapp, owner_id) values ($1, $2)', [NUMBER, me]);
  await asBot();
});

afterEach(() => L.close());

// The Edge Function calls with the service key: no signed-in user.
async function asBot() {
  await L.db.exec('reset role');
  await L.db.query("select set_config('request.jwt.claim.sub', '', false)");
  await L.db.exec('set role service_role');
}

const plan = (...entries) => ({ action: 'save', entries });
const pend = (p, number = NUMBER) => L.rpc('bot_set_pending', { p_whatsapp: number, p_plan: p });
const confirm = (waId = 'wamid.1') => L.one('bot_confirm', { p_whatsapp: NUMBER, p_wa_id: waId });
const context = (number = NUMBER) => L.one('bot_context', { p_whatsapp: number });

async function asAdmin(fn) {
  await L.db.exec('reset role');
  try {
    return await fn();
  } finally {
    await asBot();
  }
}
const balance = (id) => asAdmin(() => L.balance(id));

const purchase = (extra = {}) => ({
  type: 'deal', kind: 'purchase', date: '2026-10-16',
  party: { id: rashid }, item: { id: cloth }, weight_kg: 500, rate: 120, paid_now: 20000, ...extra,
});

describe('who may use the bot', () => {
  test('an unknown number gets nothing and can save nothing', async () => {
    assert.equal(await context('923009999999'), null);
    await assert.rejects(pend(plan(purchase()), '923009999999'), /number not linked/);
    await assert.rejects(L.one('bot_confirm', { p_whatsapp: '923009999999' }), /number not linked/);
  });

  test('the app and anonymous users cannot call the bot functions or read its tables', async () => {
    await L.signIn(me);
    await assert.rejects(context(), /permission denied/);
    await assert.rejects(L.query('select * from bot_senders'), /permission denied/);
    await L.signIn(null);
    await L.db.exec('reset role; set role anon');
    await assert.rejects(confirm(), /permission denied/);
  });

  test('context lists parties with balances, cloth types and recent expense categories', async () => {
    await pend(plan(purchase()));
    await confirm();
    await pend(plan({ type: 'expense', category: 'Chai pani', amount: 300 }));
    await confirm('wamid.2');
    const c = await context();
    assert.match(c.today, /^\d{4}-\d{2}-\d{2}$/);
    assert.deepEqual(c.parties.map((p) => [p.name, p.balance]), [['Rashid', -40000]]);
    assert.deepEqual(c.items.map((i) => i.name), ['Used cloth']);
    assert.deepEqual(c.categories, ['Chai pani']);
    assert.equal(c.pending, null);
    assert.equal(c.last_saved.plan.entries[0].category, 'Chai pani');
  });
});

describe('confirm, then save', () => {
  test('a confirmed purchase is saved from WhatsApp and the new balance comes back', async () => {
    await pend(plan(purchase()));
    assert.equal((await context()).pending.entries[0].rate, 120);
    const r = await confirm('wamid.abc');
    assert.deepEqual(r.balances, [{ name: 'Rashid', balance: -40000 }]);
    assert.equal(await balance(rashid), -40000);
    const [d] = await asAdmin(() => L.query('select source, source_ref from deals'));
    assert.deepEqual(d, { source: 'whatsapp', source_ref: 'wamid.abc' });
    assert.equal((await context()).pending, null);
  });

  test('nothing is saved without a plan waiting, and a plan is saved only once', async () => {
    await assert.rejects(confirm(), /nothing to confirm/);
    await pend(plan(purchase()));
    await confirm();
    await assert.rejects(confirm(), /nothing to confirm/);
    assert.equal(await balance(rashid), -40000);
  });

  test('a new plan replaces the one waiting', async () => {
    await pend(plan(purchase()));
    await pend(plan(purchase({ rate: 125 })));
    await confirm();
    assert.equal(await balance(rashid), -42500);
  });

  test('if one entry fails nothing is saved and the plan keeps waiting', async () => {
    await pend(plan(purchase(), { type: 'payment', party: { id: rashid }, direction: 'out', amount: 0 }));
    await assert.rejects(confirm(), /payment amount must be positive/);
    assert.equal(await balance(rashid), 0);
    assert.notEqual((await context()).pending, null);
  });

  test('new parties and cloth types are created once and reused by name', async () => {
    await pend(plan(
      purchase({ party: { name: 'Saleem', party_type: 'supplier' }, item: { name: 'Jeans' }, paid_now: 0 }),
      { type: 'payment', party: { name: 'saleem ' }, direction: 'out', amount: 10000 },
      purchase({ party: { name: 'rashid' }, item: { name: 'used CLOTH' }, paid_now: 0, weight_kg: 1 }),
    ));
    const r = await confirm();
    assert.deepEqual(r.balances, [{ name: 'Rashid', balance: -120 }, { name: 'Saleem', balance: -50000 }]);
    const parties = await asAdmin(() => L.query('select name, type from parties order by name'));
    assert.deepEqual(parties, [{ name: 'Rashid', type: 'supplier' }, { name: 'Saleem', type: 'supplier' }]);
    const items = await asAdmin(() => L.query('select name_en from items order by name_en'));
    assert.deepEqual(items.map((i) => i.name_en), ['Jeans', 'Used cloth']);
  });

  test('commission deal: roles map to the seller and the buyer', async () => {
    await pend(plan({
      type: 'deal', kind: 'commission', party: { id: rashid }, buyer: { name: 'Akram', party_type: 'buyer' },
      weight_kg: 1000, rate: 100, goods_through_me: false,
      commissions: [{ from: 'buyer', mode: 'per_kg', value: 2 }],
      costs: [{ description: 'Kiraya', amount: 3000, charged_to: 'buyer', paid_to: { name: 'Bilal Goods', party_type: 'transporter' } }],
    }));
    const r = await confirm();
    assert.deepEqual(r.balances, [
      { name: 'Akram', balance: 5000 },
      { name: 'Bilal Goods', balance: -3000 },
      { name: 'Rashid', balance: 0 },
    ]);
  });

  test('payment, expense on credit and stock out', async () => {
    await pend(plan(
      { type: 'payment', party: { id: rashid }, direction: 'in', amount: 5000, method: 'bank', note: 'Meezan' },
      { type: 'expense', category: 'Kiraya', amount: 15000, paid_to: { id: rashid } },
      { type: 'stock', item: { id: cloth }, kind: 'opening', weight_kg: 100, cost_per_kg: 90 },
      { type: 'stock', item: { id: cloth }, kind: 'wastage', weight_kg: 10, reason: 'geela' },
    ));
    const r = await confirm();
    assert.deepEqual(r.saved.map((s) => s.type), ['payment', 'expense', 'stock', 'stock']);
    assert.equal(await balance(rashid), -20000);
    const [s] = await asAdmin(async () => { await L.signIn(me); return L.rpc('stock_summary'); });
    assert.equal(Number(s.weight_kg), 90);
  });

  test('a waiting plan expires after a day', async () => {
    await pend(plan(purchase()));
    await asAdmin(() => L.query("update bot_pending set created_at = now() - interval '25 hours'"));
    assert.equal((await context()).pending, null);
    await assert.rejects(confirm(), /nothing to confirm/);
  });
});

describe('undo and redelivery', () => {
  test('undo cancels everything the last confirmed plan saved, once', async () => {
    await pend(plan(purchase(), { type: 'expense', category: 'Chai', amount: 200 },
                    { type: 'stock', item: { id: cloth }, kind: 'sample', weight_kg: 5 }));
    await confirm();
    const last = (await context()).last_saved;
    await pend({ action: 'undo', log_id: last.id });
    const r = await confirm('wamid.undo');
    assert.equal(r.action, 'undo');
    assert.deepEqual(r.balances, [{ name: 'Rashid', balance: 0 }]);
    const open = await asAdmin(() => L.query(`
      select (select count(*) from deals where cancelled_at is null) deals,
             (select count(*) from expenses where cancelled_at is null) expenses,
             (select count(*) from stock_adjustments where cancelled_at is null) stock`));
    assert.deepEqual(open[0], { deals: 0, expenses: 0, stock: 0 });
    assert.equal((await context()).last_saved, null);

    await pend({ action: 'undo', log_id: last.id });
    await assert.rejects(confirm(), /already undone/);
  });

  test('a redelivered WhatsApp message is claimed only once', async () => {
    assert.equal(await L.one('bot_claim_message', { p_wa_id: 'wamid.x' }), true);
    assert.equal(await L.one('bot_claim_message', { p_wa_id: 'wamid.x' }), false);
  });
});

describe('token log', () => {
  const logUsage = (extra = {}) => L.rpc('bot_log_usage', {
    p_whatsapp: NUMBER, p_wa_id: 'wamid.1', p_kind: 'text', p_model: 'gemini-3.8-flash',
    p_input: 4000, p_output: 300, p_thinking: 700, p_media: 0, ...extra,
  });

  test('each message the model read is logged and summed per day with the paid-plan estimate', async () => {
    await logUsage();
    await logUsage({ p_wa_id: 'wamid.2', p_kind: 'audio', p_input: 5000, p_media: 960 });
    const [day] = await asAdmin(() => L.query('select * from bot_usage_daily'));
    assert.equal(Number(day.messages), 2);
    assert.equal(Number(day.voice_notes), 1);
    assert.equal(Number(day.input_tokens), 9000);
    assert.equal(Number(day.output_tokens), 2000);
    // 9000 × 0.75 + 2000 × 3.75 = 14250 per million
    assert.equal(Number(day.est_usd), 0.0143);
  });

  test('only the bot can write it, and only for a linked number', async () => {
    await assert.rejects(logUsage({ p_whatsapp: '923009999999' }), /foreign key/);
    await assert.rejects(logUsage({ p_kind: 'video' }), /bot_usage_kind/);
    await L.signIn(me);
    await assert.rejects(logUsage(), /permission denied/);
    await assert.rejects(L.query('select * from bot_usage_daily'), /permission denied/);
  });
});
