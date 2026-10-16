// The bot without WhatsApp, Gemini or a database: each is replaced by a fake.
// Run: npm test   (from the supabase folder)
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { handle, type Deps } from './bot.ts';
import { extract, sanitize } from './gemini.ts';
import { RESPONSE_SCHEMA } from './prompt.ts';
import { renderConfirmed, renderPlan } from './render.ts';
import { looseKey, partyRef, resolve } from './resolve.ts';
import type { Confirmed, Context, Draft, Extraction, Plan } from './types.ts';
import { parseWebhook, verifySignature } from './whatsapp.ts';

const ctx = (extra: Partial<Context> = {}): Context => ({
  today: '2026-10-16',
  parties: [
    { id: 'p-rashid', name: 'Rashid', type: 'supplier', balance: 0 },
    { id: 'p-akram', name: 'Akram Traders', type: 'buyer', balance: 15000 },
  ],
  items: [{ id: 'i-cloth', name: 'Used cloth', name_ur: 'پرانا کپڑا' }],
  categories: ['Kiraya'],
  pending: null,
  last_saved: null,
  ...extra,
});

const draft = (d: Partial<Draft>): Draft => ({
  type: 'purchase', date: null, party: null, buyer: null, item: null, weight_kg: null, rate_per_kg: null,
  paid_now: null, method: null, goods_through_me: null, commissions: null, costs: null, direction: null,
  amount: null, category: null, stock_kind: null, cost_per_kg: null, note: null, ...d,
});

const purchase = draft({ party: 'Rasheed', weight_kg: 500, rate_per_kg: 120, paid_now: 20000, method: 'cash' });

describe('reading names', () => {
  test('different spellings of one name find the same party', () => {
    assert.equal(looseKey('Rasheed'), looseKey('Rashid'));
    assert.deepEqual(partyRef('rasheed', ctx().parties, 'supplier'), { id: 'p-rashid', name: 'Rashid' });
    assert.deepEqual(partyRef('AKRAM traders', ctx().parties, 'buyer'), { id: 'p-akram', name: 'Akram Traders' });
  });

  test('an unknown name becomes a new party, and short names never match loosely', () => {
    assert.deepEqual(partyRef('saleem bhai', ctx().parties, 'supplier'), { name: 'Saleem Bhai', party_type: 'supplier' });
    const parties = [{ id: 'p-ali', name: 'Ali', type: 'other' as const, balance: 0 }];
    assert.deepEqual(partyRef('Ola', parties, 'buyer'), { name: 'Ola', party_type: 'buyer' });
  });
});

describe('checking an entry before reading it back', () => {
  test('a purchase gets ids, today and the only cloth type', () => {
    const r = resolve([purchase], ctx());
    assert.ok(r.ok);
    assert.deepEqual(r.entries[0], {
      type: 'deal', kind: 'purchase', date: '2026-10-16', party: { id: 'p-rashid', name: 'Rashid' },
      buyer: null, item: { id: 'i-cloth', name: 'Used cloth' }, weight_kg: 500, rate: 120,
      paid_now: 20000, paid_method: 'cash', goods_through_me: false, notes: null, costs: [], commissions: [],
    });
  });

  test('missing details become questions, nothing is guessed', () => {
    const two = ctx({ items: [...ctx().items, { id: 'i-jeans', name: 'Jeans', name_ur: null }] });
    const r = resolve([draft({ party: 'Rashid', weight_kg: 500 })], two);
    assert.equal(r.ok, false);
    assert.deepEqual(!r.ok && r.problems.map((p) => p.issue), ['item', 'rate']);
  });

  test('commission deal maps who bears costs and who pays commission', () => {
    const r = resolve([draft({
      type: 'commission', party: 'Rashid', buyer: 'Akram Traders', weight_kg: 1000, rate_per_kg: 90,
      commissions: [{ from: 'buyer', mode: 'per_kg', value: 2 }],
      costs: [{ description: 'Kiraya', amount: 3000, borne_by: 'buyer', paid_to: 'Bilal Goods' }],
    })], ctx());
    assert.ok(r.ok);
    const deal = r.entries[0];
    assert.equal(deal.type, 'deal');
    if (deal.type !== 'deal') return;
    assert.deepEqual(deal.commissions, [{ from: 'buyer', mode: 'per_kg', value: 2 }]);
    assert.deepEqual(deal.costs, [{
      description: 'Kiraya', amount: 3000, charged_to: 'buyer', paid_to: { name: 'Bilal Goods', party_type: 'transporter' },
    }]);
  });

  test('commission deal problems: same party, money on the spot, no commission', () => {
    const r = resolve([draft({ type: 'commission', party: 'Rashid', buyer: 'rasheed', paid_now: 500 })], ctx());
    assert.deepEqual(!r.ok && r.problems.map((p) => p.issue), ['same_party', 'commission', 'paid_on_commission']);
  });

  test('payment, expense and stock', () => {
    const r = resolve([
      draft({ type: 'payment', party: 'akram traders', direction: 'in', amount: 15000, method: 'bank' }),
      draft({ type: 'expense', category: 'kiraya', amount: 15000, date: '2026-10-15' }),
      draft({ type: 'stock', stock_kind: 'wastage', weight_kg: 20, note: 'geela' }),
    ], ctx());
    assert.ok(r.ok);
    assert.deepEqual(r.entries.map((e) => e.type), ['payment', 'expense', 'stock']);
    assert.equal(r.entries[1].type === 'expense' && r.entries[1].category, 'Kiraya');
    assert.equal(r.entries[2].type === 'stock' && r.entries[2].cost_per_kg, null);
  });

  test('stock coming in needs its value; dates in the future are refused', () => {
    const r = resolve([
      draft({ type: 'stock', stock_kind: 'opening', weight_kg: 100 }),
      draft({ type: 'payment', party: 'Rashid', direction: 'out', amount: 5, date: '2026-10-20' }),
    ], ctx());
    assert.deepEqual(!r.ok && r.problems, [{ entry: 0, issue: 'cost_per_kg' }, { entry: 1, issue: 'future_date' }]);
  });
});

describe('what the user sees', () => {
  test('a purchase is read back with the total and what is left on credit', () => {
    const r = resolve([purchase], ctx());
    assert.ok(r.ok);
    const plan: Plan = { action: 'save', lang: 'ur', entries: r.entries, drafts: [purchase] };
    assert.equal(renderPlan(plan, '2026-10-16'), [
      '🛒 *Khareed* · Rashid se',
      'Used cloth · 500 kg × 120 = Rs 60,000',
      'Abhi diye: Rs 20,000 · Cash',
      'Udhaar: Rs 40,000',
      '',
      'Sahi hai to *Haan* karein. Kuch ghalat ho to bata dein.',
    ].join('\n'));
  });

  test('new parties, other dates and English are shown', () => {
    const r = resolve([draft({ type: 'payment', party: 'Saleem', direction: 'out', amount: 2500.5, date: '2026-10-15' })], ctx());
    assert.ok(r.ok);
    const text = renderPlan({ action: 'save', lang: 'en', entries: r.entries, drafts: [] }, '2026-10-16');
    assert.match(text, /💸 \*Paid\* to Saleem \(new party\)\nRs 2,500\.5 · cash\nDate: 15 Oct/);
  });

  test('after saving: balances in the trader\'s words', () => {
    const done: Confirmed = {
      action: 'save', saved: [],
      balances: [{ name: 'Rashid', balance: -40000 }, { name: 'Akram', balance: 5000 }, { name: 'Bilal', balance: 0 }],
    };
    assert.equal(renderConfirmed(done, 'ur'),
      '✅ Save ho gaya.\n\nRashid: Rs 40,000 dena hai\nAkram: Rs 5,000 lena hai\nBilal: hisaab barabar\n\nGhalti ho to *undo* likhein.');
  });
});

describe('the model\'s answer is never trusted as is', () => {
  test('wrong types and unknown values are dropped or nulled', () => {
    const e = sanitize({
      language: 'klingon', intent: 'record',
      entries: [
        { type: 'sale', party: ' Akram ', weight_kg: '1,200', rate_per_kg: 'abc', method: 'gold', date: 'kal',
          commissions: [{ from: 'x', mode: 'per_kg', value: 2 }, { mode: 'bad', value: 1 }] },
        { type: 'loan', amount: 5 },
        'nonsense',
      ],
    });
    assert.equal(e.language, 'roman_urdu');
    assert.equal(e.entries.length, 1);
    const d = e.entries[0];
    assert.equal(d.party, 'Akram');
    assert.equal(d.weight_kg, 1200);
    assert.equal(d.rate_per_kg, null);
    assert.equal(d.method, null);
    assert.equal(d.date, null);
    assert.deepEqual(d.commissions, [{ from: 'buyer', mode: 'per_kg', value: 2 }]);
  });

  test('every field of an entry is required in the schema, so the model always fills it or says null', () => {
    const draftSchema = RESPONSE_SCHEMA.properties.entries.items;
    assert.deepEqual([...draftSchema.required].sort(), Object.keys(draftSchema.properties).sort());
  });
});

describe('when Gemini is busy', () => {
  const answer = { candidates: [{ content: { parts: [{ text: JSON.stringify({ language: 'english', intent: 'reply', entries: [], reply: 'hi' }) }] } }] };
  const fakeGemini = (statuses: Record<string, number[]>) => {
    const calls: string[] = [];
    const fetchFn = (async (url: string) => {
      const model = /models\/([^:]+):/.exec(url)![1];
      calls.push(model);
      const status = statuses[model]?.shift() ?? 200;
      return new Response(status === 200 ? JSON.stringify(answer) : '{"error":{}}', { status });
    }) as unknown as typeof fetch;
    return { calls, fetchFn };
  };
  const cfg = { apiKey: 'k', models: ['main', 'backup'] };
  const noWait = async () => {};

  test('it waits and tries again', async () => {
    const g = fakeGemini({ main: [503] });
    const e = await extract('hi', ctx(), cfg, g.fetchFn, noWait);
    assert.equal(e.reply, 'hi');
    assert.deepEqual(g.calls, ['main', 'main']);
  });

  test('it moves to the backup model when the main one stays busy or is missing', async () => {
    const busy = fakeGemini({ main: [503, 429, 503] });
    await extract('hi', ctx(), cfg, busy.fetchFn, noWait);
    assert.deepEqual(busy.calls, ['main', 'main', 'main', 'backup']);

    const missing = fakeGemini({ main: [404] });
    await extract('hi', ctx(), cfg, missing.fetchFn, noWait);
    assert.deepEqual(missing.calls, ['main', 'backup']);
  });

  test('a bad request is not retried', async () => {
    const g = fakeGemini({ main: [400] });
    await assert.rejects(extract('hi', ctx(), cfg, g.fetchFn, noWait), /Gemini main 400/);
    assert.deepEqual(g.calls, ['main']);
  });

  test('when every model is busy it gives up with the last error', async () => {
    const g = fakeGemini({ main: [503, 503, 503], backup: [503, 503, 503] });
    await assert.rejects(extract('hi', ctx(), cfg, g.fetchFn, noWait), /Gemini backup 503/);
    assert.equal(g.calls.length, 6);
  });
});

describe('webhook', () => {
  const secret = 'app-secret';
  const sign = (body: string) => 'sha256=' + createHmac('sha256', secret).update(body).digest('hex');

  test('only bodies signed with the app secret are accepted', async () => {
    const body = '{"entry":[]}';
    assert.equal(await verifySignature(body, sign(body), secret), true);
    assert.equal(await verifySignature(body + ' ', sign(body), secret), false);
    assert.equal(await verifySignature(body, null, secret), false);
    assert.equal(await verifySignature(body, sign(body), ''), false);
  });

  test('text, button taps and other messages are read; receipts are ignored', () => {
    const msgs = parseWebhook({ entry: [{ changes: [{ value: {
      statuses: [{ id: 'x', status: 'read' }],
      messages: [
        { id: 'm1', from: '923001234567', type: 'text', text: { body: 'Akram se 5000 mile' } },
        { id: 'm2', from: '923001234567', type: 'interactive', interactive: { type: 'button_reply', button_reply: { id: 'yes', title: 'Haan' } } },
        { id: 'm3', from: '923001234567', type: 'audio', audio: { id: 'a' } },
      ],
    } }] }] });
    assert.deepEqual(msgs.map((m) => [m.id, m.kind, m.text]), [
      ['m1', 'text', 'Akram se 5000 mile'], ['m2', 'button', 'yes'], ['m3', 'other', ''],
    ]);
  });
});

// ==================== THE CONVERSATION ====================

function fakes(context: Context | null, reading?: Extraction | Error) {
  const sent: string[] = [];
  const calls: string[] = [];
  let pending: Plan | null = context?.pending ?? null;
  const seen = new Set<string>();
  const deps: Deps = {
    db: {
      claimMessage: async (id) => (seen.has(id) ? false : (seen.add(id), true)),
      context: async () => (context ? { ...context, pending } : null),
      setPending: async (_, plan) => { pending = plan; calls.push(plan ? `pending:${plan.action}` : 'pending:cleared'); },
      confirm: async () => {
        if (!pending) throw new Error('nothing to confirm');
        calls.push(`confirm:${pending.action}`);
        pending = null;
        return { action: 'save', saved: [], balances: [{ name: 'Rashid', balance: -40000 }] };
      },
    },
    read: async () => {
      calls.push('read');
      if (reading instanceof Error) throw reading;
      return reading ?? { language: 'roman_urdu', intent: 'reply', entries: [], reply: null };
    },
    wa: {
      sendText: async (_, text) => { sent.push(text); },
      sendButtons: async (_, text, buttons) => { sent.push(`${text}\n[${buttons.map((b) => b.title).join('] [')}]`); },
      markRead: async () => {},
    },
  };
  return { deps, sent, calls, pending: () => pending };
}

const text = (body: string, id = `m-${Math.random()}`) => ({ id, from: '923001234567', kind: 'text' as const, text: body });
const reading = (entries: Draft[], extra: Partial<Extraction> = {}): Extraction =>
  ({ language: 'roman_urdu', intent: 'record', entries, reply: null, ...extra });

describe('conversation', () => {
  test('entry -> read back with buttons -> "haan" saves it and shows the balance', async () => {
    const f = fakes(ctx(), reading([purchase]));
    await handle(text('Rasheed se 500 kg 120 pe liya 20 hazar diye'), f.deps);
    assert.match(f.sent[0], /\*Khareed\* · Rashid se[\s\S]*\[✅ Haan, save karo\] \[❌ Nahi\]$/);
    assert.equal(f.pending()?.action, 'save');

    await handle(text('Haan!'), f.deps);
    assert.deepEqual(f.calls, ['read', 'pending:save', 'confirm:save']);
    assert.match(f.sent[1], /Save ho gaya[\s\S]*Rashid: Rs 40,000 dena hai/);
  });

  test('"nahi" discards the waiting entry without saving', async () => {
    const f = fakes(ctx(), reading([purchase]));
    await handle(text('Rashid se 500 kg 120 pe liya'), f.deps);
    await handle({ id: 'b1', from: '923001234567', kind: 'button', text: 'no' }, f.deps);
    assert.deepEqual(f.calls, ['read', 'pending:save', 'pending:cleared']);
    assert.equal(f.sent[1], 'Theek hai, kuch save nahi hua.');
  });

  test('a correction while an entry waits replaces it', async () => {
    const f = fakes(ctx(), reading([{ ...purchase, rate_per_kg: 125 }]));
    await handle(text('Rashid se 500 kg 120 pe liya'), f.deps);
    await handle(text('nahi rate 125 tha'), f.deps);
    assert.match(f.sent[1], /500 kg × 125 = Rs 62,500/);
    assert.deepEqual(f.calls, ['read', 'pending:save', 'read', 'pending:save']);
  });

  test('a greeting or "madad" gets examples of what to send, without asking the model', async () => {
    const f = fakes(ctx());
    await handle(text('Assalam o Alaikum!'), f.deps);
    assert.match(f.sent[0], /^Assalam o alaikum! Apna hisaab aise likh kar bhejein:\n• Rashid se 500 kg/);
    assert.deepEqual(f.calls, []);
  });

  test('yes with nothing waiting saves nothing', async () => {
    const f = fakes(ctx());
    await handle(text('ok'), f.deps);
    assert.deepEqual(f.calls, []);
    assert.equal(f.sent[0], 'Koi entry intezar mein nahi. Nayi entry bhejein.');
  });

  test('missing details are asked, nothing waits for a yes', async () => {
    const f = fakes(ctx(), reading([draft({ type: 'payment', party: 'Rashid', amount: 5000 })]));
    await handle(text('Rashid 5000'), f.deps);
    assert.equal(f.sent[0], 'Thori si baat reh gayi:\n• Paise mile ya diye?');
    assert.equal(f.pending(), null);
  });

  test('undo reads back the last saved entry and cancels it on yes', async () => {
    const saved = resolve([purchase], ctx());
    assert.ok(saved.ok);
    const last = { id: 'log-1', at: '', plan: { action: 'save', lang: 'ur', entries: saved.entries, drafts: [] } as Plan };
    const f = fakes(ctx({ last_saved: last }));
    await handle(text('Undo'), f.deps);
    assert.match(f.sent[0], /^↩️ Yeh pichli entry cancel karni hai\?\n\n🛒 \*Khareed\* · Rashid se/);
    assert.deepEqual(f.pending(), { action: 'undo', lang: 'ur', log_id: 'log-1', entries: saved.entries });
    assert.deepEqual(f.calls, ['pending:undo']);
  });

  test('unknown numbers and redelivered messages get no reply', async () => {
    const stranger = fakes(null, reading([purchase]));
    await handle(text('hello'), stranger.deps);
    assert.deepEqual([stranger.sent, stranger.calls], [[], []]);

    const f = fakes(ctx(), reading([purchase]));
    await handle(text('Rashid se liya', 'same'), f.deps);
    await handle(text('Rashid se liya', 'same'), f.deps);
    assert.equal(f.sent.length, 1);
  });

  test('voice notes get a polite "text only for now"; a model outage gets an apology', async () => {
    const f = fakes(ctx(), new Error('Gemini 503'));
    await handle({ id: 'v', from: '923001234567', kind: 'other', text: '' }, f.deps);
    await handle(text('Rashid se liya'), f.deps);
    assert.deepEqual(f.sent, [
      'Abhi main sirf likha hua message samajhta hoon. Voice note aur tasveer jald.',
      'Abhi message parhne mein masla hai. Thori der baad dobara bhejein.',
    ]);
  });

  test('English messages get English replies', async () => {
    const f = fakes(ctx(), reading([draft({ type: 'payment', party: 'Akram Traders', direction: 'in', amount: 15000 })], { language: 'english' }));
    await handle(text('received 15000 from akram traders'), f.deps);
    assert.match(f.sent[0], /💰 \*Received\* from Akram Traders\nRs 15,000 · cash[\s\S]*\[✅ Yes, save\] \[❌ No\]/);
  });
});
