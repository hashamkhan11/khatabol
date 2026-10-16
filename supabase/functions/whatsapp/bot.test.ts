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
import type { Confirmed, Context, Draft, Extraction, Plan, Usage } from './types.ts';
import { MediaTooBig, parseWebhook, verifySignature, WhatsApp } from './whatsapp.ts';

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
    const r = await extract({ text: 'hi' }, ctx(), cfg, g.fetchFn, noWait);
    assert.equal(r.extraction.reply, 'hi');
    assert.deepEqual(g.calls, ['main', 'main']);
  });

  test('it moves to the backup model when the main one stays busy or is missing', async () => {
    const busy = fakeGemini({ main: [503, 429, 503] });
    await extract({ text: 'hi' }, ctx(), cfg, busy.fetchFn, noWait);
    assert.deepEqual(busy.calls, ['main', 'main', 'main', 'backup']);

    const missing = fakeGemini({ main: [404] });
    await extract({ text: 'hi' }, ctx(), cfg, missing.fetchFn, noWait);
    assert.deepEqual(missing.calls, ['main', 'backup']);
  });

  test('a bad request is not retried', async () => {
    const g = fakeGemini({ main: [400] });
    await assert.rejects(extract({ text: 'hi' }, ctx(), cfg, g.fetchFn, noWait), /Gemini main 400/);
    assert.deepEqual(g.calls, ['main']);
  });

  test('when every model is busy it gives up with the last error', async () => {
    const g = fakeGemini({ main: [503, 503, 503], backup: [503, 503, 503] });
    await assert.rejects(extract({ text: 'hi' }, ctx(), cfg, g.fetchFn, noWait), /Gemini backup 503/);
    assert.equal(g.calls.length, 6);
  });
});

describe('voice notes and photos go to Gemini, with the token count back', () => {
  test('the media is sent inline next to the caption, and the usage is read from the answer', async () => {
    let sent: any;
    const fetchFn = (async (_url: string, init: RequestInit) => {
      sent = JSON.parse(String(init.body));
      return new Response(JSON.stringify({
        candidates: [{ content: { parts: [
          { text: 'thinking...', thought: true },
          { text: JSON.stringify({ language: 'roman_urdu', intent: 'reply', entries: [], reply: 'ok', heard: ' Rashid se 500 kilo liya ' }) },
        ] } }],
        usageMetadata: {
          promptTokenCount: 5200, candidatesTokenCount: 310, thoughtsTokenCount: 640,
          promptTokensDetails: [{ modality: 'TEXT', tokenCount: 4240 }, { modality: 'AUDIO', tokenCount: 960 }],
        },
      }));
    }) as unknown as typeof fetch;

    const r = await extract(
      { text: 'Rashid wala', media: { kind: 'audio', mime: 'audio/ogg', data: new Uint8Array([104, 105]) } },
      ctx(), { apiKey: 'k', models: ['main'] }, fetchFn,
    );
    const parts = sent.contents[0].parts;
    assert.deepEqual(parts[0], { inlineData: { mimeType: 'audio/ogg', data: 'aGk=' } });
    assert.match(parts[1].text, /Message: Voice note \(attached\)\.\nCaption: Rashid wala$/);
    assert.equal(r.extraction.heard, 'Rashid se 500 kilo liya');
    assert.deepEqual(r.usage, { model: 'main', input_tokens: 5200, output_tokens: 310, thinking_tokens: 640, media_tokens: 960 });
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
        { id: 'm3', from: '923001234567', type: 'audio', audio: { id: 'a1', mime_type: 'audio/ogg; codecs=opus', voice: true } },
        { id: 'm4', from: '923001234567', type: 'image', image: { id: 'i1', caption: 'Akram ki payment' } },
        { id: 'm5', from: '923001234567', type: 'video', video: { id: 'v1' } },
      ],
    } }] }] });
    assert.deepEqual(msgs.map((m) => [m.id, m.kind, m.text, m.mediaId]), [
      ['m1', 'text', 'Akram se 5000 mile', undefined], ['m2', 'button', 'yes', undefined],
      ['m3', 'audio', '', 'a1'], ['m4', 'image', 'Akram ki payment', 'i1'], ['m5', 'other', '', undefined],
    ]);
  });

  test('media is downloaded through its short-lived link, and refused when too big', async () => {
    const urls: string[] = [];
    const fetchFn = (async (url: string, init: RequestInit) => {
      urls.push(`${url} ${(init.headers as Record<string, string>).authorization}`);
      if (url.endsWith('/a1')) return Response.json({ url: 'https://lookaside.example/file?id=a1', mime_type: 'audio/ogg; codecs=opus', file_size: 3 });
      if (url.endsWith('/big')) return Response.json({ url: 'https://lookaside.example/big', mime_type: 'image/jpeg', file_size: 50_000_000 });
      return new Response(new Uint8Array([1, 2, 3]));
    }) as unknown as typeof fetch;
    const wa = new WhatsApp({ token: 'tok', phoneNumberId: '1', apiVersion: 'v25.0' }, fetchFn);

    const media = await wa.downloadMedia('a1', 100);
    assert.deepEqual(media, { mime: 'audio/ogg', data: new Uint8Array([1, 2, 3]) });
    assert.deepEqual(urls, ['https://graph.facebook.com/v25.0/a1 Bearer tok', 'https://lookaside.example/file?id=a1 Bearer tok']);
    await assert.rejects(wa.downloadMedia('big', 100), MediaTooBig);
  });
});

// ==================== THE CONVERSATION ====================

const usage: Usage = { model: 'gemini-test', input_tokens: 4000, output_tokens: 300, thinking_tokens: 0, media_tokens: 0 };

function fakes(context: Context | null, reading?: Extraction | Error) {
  const sent: string[] = [];
  const calls: string[] = [];
  const read: { text: string; media?: string }[] = [];
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
      logUsage: async (_, waId, kind) => { calls.push(`usage:${kind}`); },
    },
    read: async (m) => {
      calls.push('read');
      read.push({ text: m.text, ...(m.media ? { media: `${m.media.kind} ${m.media.mime} ${m.media.data.length}` } : {}) });
      if (reading instanceof Error) throw reading;
      return { extraction: reading ?? { language: 'roman_urdu', intent: 'reply', entries: [], reply: null, heard: null }, usage };
    },
    wa: {
      sendText: async (_, text) => { sent.push(text); },
      sendButtons: async (_, text, buttons) => { sent.push(`${text}\n[${buttons.map((b) => b.title).join('] [')}]`); },
      markRead: async () => {},
      downloadMedia: async (id, maxBytes) => {
        if (id === 'huge') throw new MediaTooBig('huge');
        if (id === 'gone') throw new Error('WhatsApp media 404');
        calls.push(`download:${maxBytes}`);
        return { mime: id.startsWith('img') ? 'image/jpeg' : 'audio/ogg', data: new Uint8Array(10) };
      },
    },
  };
  return { deps, sent, calls, read, pending: () => pending };
}

const text = (body: string, id = `m-${Math.random()}`) => ({ id, from: '923001234567', kind: 'text' as const, text: body });
const reading = (entries: Draft[], extra: Partial<Extraction> = {}): Extraction =>
  ({ language: 'roman_urdu', intent: 'record', entries, reply: null, heard: null, ...extra });
const voice = (mediaId = 'aud1') => ({ id: `v-${Math.random()}`, from: '923001234567', kind: 'audio' as const, text: '', mediaId });
const photo = (caption = '', mediaId = 'img1') =>
  ({ id: `p-${Math.random()}`, from: '923001234567', kind: 'image' as const, text: caption, mediaId });

describe('conversation', () => {
  test('entry -> read back with buttons -> "haan" saves it and shows the balance', async () => {
    const f = fakes(ctx(), reading([purchase]));
    await handle(text('Rasheed se 500 kg 120 pe liya 20 hazar diye'), f.deps);
    assert.match(f.sent[0], /\*Khareed\* · Rashid se[\s\S]*\[✅ Haan, save karo\] \[❌ Nahi\]$/);
    assert.equal(f.pending()?.action, 'save');

    await handle(text('Haan!'), f.deps);
    assert.deepEqual(f.calls, ['read', 'usage:text', 'pending:save', 'confirm:save']);
    assert.match(f.sent[1], /Save ho gaya[\s\S]*Rashid: Rs 40,000 dena hai/);
  });

  test('"nahi" discards the waiting entry without saving', async () => {
    const f = fakes(ctx(), reading([purchase]));
    await handle(text('Rashid se 500 kg 120 pe liya'), f.deps);
    await handle({ id: 'b1', from: '923001234567', kind: 'button', text: 'no' }, f.deps);
    assert.deepEqual(f.calls, ['read', 'usage:text', 'pending:save', 'pending:cleared']);
    assert.equal(f.sent[1], 'Theek hai, kuch save nahi hua.');
  });

  test('a correction while an entry waits replaces it', async () => {
    const f = fakes(ctx(), reading([{ ...purchase, rate_per_kg: 125 }]));
    await handle(text('Rashid se 500 kg 120 pe liya'), f.deps);
    await handle(text('nahi rate 125 tha'), f.deps);
    assert.match(f.sent[1], /500 kg × 125 = Rs 62,500/);
    assert.deepEqual(f.calls, ['read', 'usage:text', 'pending:save', 'read', 'usage:text', 'pending:save']);
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

  test('videos and documents get a polite "not yet"; a model outage gets an apology', async () => {
    const f = fakes(ctx(), new Error('Gemini 503'));
    await handle({ id: 'v', from: '923001234567', kind: 'other', text: '' }, f.deps);
    await handle(text('Rashid se liya'), f.deps);
    assert.deepEqual(f.sent, [
      'Main likha hua message, voice note aur tasveer samajhta hoon. Video aur document abhi nahi.',
      'Abhi message parhne mein masla hai. Thori der baad dobara bhejein.',
    ]);
  });

  test('a voice note is read back with what was heard on top, then "haan" saves it', async () => {
    const f = fakes(ctx(), reading([purchase], { heard: 'Rasheed se 500 kilo liya 120 rate 20 hazar cash diye' }));
    await handle(voice(), f.deps);
    assert.deepEqual(f.read, [{ text: '', media: 'audio audio/ogg 10' }]);
    assert.match(f.sent[0], /^🎤 Maine suna: "Rasheed se 500 kilo liya 120 rate 20 hazar cash diye"\n\n🛒 \*Khareed\* · Rashid se/);
    assert.match(f.sent[0], /\[✅ Haan, save karo\] \[❌ Nahi\]$/);
    await handle(text('haan'), f.deps);
    assert.deepEqual(f.calls, ['download:5000000', 'read', 'usage:audio', 'pending:save', 'confirm:save']);
  });

  test('a voice note with something missing still shows what was heard', async () => {
    const f = fakes(ctx(), reading([draft({ type: 'payment', party: 'Rashid', amount: null })], { heard: 'Rashid ko diye' }));
    await handle(voice(), f.deps);
    assert.match(f.sent[0], /^🎤 Maine suna: "Rashid ko diye"\n\nThori si baat reh gayi:/);
    assert.equal(f.pending(), null);
  });

  test('a photo goes to the model with its caption, and nothing "heard" is shown', async () => {
    const f = fakes(ctx(), reading([draft({ type: 'payment', party: 'Akram Traders', direction: 'in', amount: 15000, method: 'bank' })],
      { heard: 'should not show' }));
    await handle(photo('Akram ki payment'), f.deps);
    assert.deepEqual(f.read, [{ text: 'Akram ki payment', media: 'image image/jpeg 10' }]);
    assert.doesNotMatch(f.sent[0], /Maine suna/);
    assert.deepEqual(f.calls, ['download:10000000', 'read', 'usage:image', 'pending:save']);
  });

  test('media too big or that cannot be downloaded gets a clear reply, without asking the model', async () => {
    const f = fakes(ctx(), reading([purchase]));
    await handle(voice('huge'), f.deps);
    await handle(photo('', 'gone'), f.deps);
    assert.deepEqual(f.sent, [
      'Yeh bohat lamba/bara hai. Voice note 2-3 minute tak ka bhejein, ya tasveer chhoti kar ke.',
      'Yeh file khul nahi saki. Dobara bhejein, ya likh kar bhej dein.',
    ]);
    assert.deepEqual(f.calls, []);
  });

  test('typed messages log their tokens too, and a failing log does not stop the reply', async () => {
    const f = fakes(ctx(), reading([purchase]));
    f.deps.db.logUsage = async () => { throw new Error('db down'); };
    await handle(text('Rasheed se 500 kg 120 pe liya 20 hazar diye'), f.deps);
    assert.match(f.sent[0], /\*Khareed\*/);
  });

  test('English messages get English replies', async () => {
    const f = fakes(ctx(), reading([draft({ type: 'payment', party: 'Akram Traders', direction: 'in', amount: 15000 })], { language: 'english' }));
    await handle(text('received 15000 from akram traders'), f.deps);
    assert.match(f.sent[0], /💰 \*Received\* from Akram Traders\nRs 15,000 · cash[\s\S]*\[✅ Yes, save\] \[❌ No\]/);
  });
});
