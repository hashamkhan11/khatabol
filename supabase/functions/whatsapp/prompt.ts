// What the model is told, and the exact JSON shape it must answer in.
// The model only reads the message. It never saves anything and never writes
// the confirmation text: resolve.ts checks its reading and render.ts words it.

import type { Context } from './types.ts';

const nullable = (type: string, extra: Record<string, unknown> = {}) => ({ type: [type, 'null'], ...extra });

const DRAFT = {
  type: 'object',
  properties: {
    type: { type: 'string', enum: ['purchase', 'sale', 'commission', 'payment', 'expense', 'stock'] },
    date: nullable('string', { description: 'YYYY-MM-DD. null = today.' }),
    party: nullable('string', {
      description: 'purchase: seller. sale: buyer. commission: seller. payment: who paid or was paid. ' +
        'expense: only when the expense is owed to someone on credit.',
    }),
    buyer: nullable('string', { description: 'commission deals only: the buyer.' }),
    item: nullable('string', { description: 'cloth type, using the exact name from the list when it is one of them.' }),
    weight_kg: nullable('number'),
    rate_per_kg: nullable('number'),
    paid_now: nullable('number', { description: 'purchase/sale: money paid or received on the spot.' }),
    method: nullable('string', { description: 'cash, bank or other.' }),
    goods_through_me: nullable('boolean', {
      description: 'commission deals: true if the buyer pays the goods money to me and I pay the seller.',
    }),
    commissions: nullable('array', {
      items: {
        type: 'object',
        properties: {
          from: { type: 'string', enum: ['seller', 'buyer'] },
          mode: { type: 'string', enum: ['per_kg', 'percent', 'fixed'] },
          value: { type: 'number' },
        },
        required: ['from', 'mode', 'value'],
      },
    }),
    costs: nullable('array', {
      description: 'extra costs on a deal: freight (kiraya), labour (mazdoori), loading.',
      items: {
        type: 'object',
        properties: {
          description: { type: 'string' },
          amount: { type: 'number' },
          borne_by: { type: 'string', enum: ['me', 'seller', 'buyer'] },
          paid_to: nullable('string', { description: 'who is owed this cost on credit, e.g. a transporter. null = paid in cash.' }),
        },
        required: ['description', 'amount', 'borne_by', 'paid_to'],
      },
    }),
    direction: nullable('string', { description: 'payment: "in" = I received, "out" = I paid.' }),
    amount: nullable('number', { description: 'payment or expense amount.' }),
    category: nullable('string', { description: 'expense: what it was for, short, in the words the user used.' }),
    stock_kind: nullable('string', {
      description: 'opening, found, other_in, wastage, shortage, own_use, sample or other_out.',
    }),
    cost_per_kg: nullable('number', { description: 'stock coming in (opening, found, other_in): value per kg.' }),
    note: nullable('string', { description: 'only extra detail the user gave that fits nowhere else.' }),
  },
  required: ['type', 'date', 'party', 'buyer', 'item', 'weight_kg', 'rate_per_kg', 'paid_now', 'method',
    'goods_through_me', 'commissions', 'costs', 'direction', 'amount', 'category', 'stock_kind',
    'cost_per_kg', 'note'],
};

export const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    language: { type: 'string', enum: ['roman_urdu', 'urdu', 'english'] },
    intent: { type: 'string', enum: ['record', 'undo_last', 'reply'] },
    entries: { type: 'array', items: DRAFT },
    reply: nullable('string'),
    heard: nullable('string', {
      description: 'voice notes only: what he said, written out in Roman Urdu (English if he spoke English), ' +
        'numbers as digits. null for text and photos.',
    }),
  },
  required: ['language', 'intent', 'entries', 'reply', 'heard'],
};

export const SYSTEM_PROMPT = `You read WhatsApp messages from a cloth trader in Pakistan and turn them into bookkeeping entries.
He buys and sells used cloth by weight (kg), mostly on credit (udhaar), and also earns commission as a broker.
Messages are in Roman Urdu, Urdu or English, often short and informal, with spelling mistakes.
He may also send a voice note or a photo instead of typing.

Answer only with JSON in the given schema.

intent:
- "record": the message describes one or more entries. Put each in entries.
- "undo_last": he wants to cancel or undo the entry he saved last ("undo", "pichli entry ghalat thi, hata do").
- "reply": anything else. Put a short, friendly reply in the user's language in reply. If he asks a question
  about balances or reports, say that for now he can see it in the app. If he greets you or asks how to use
  you, give a one-line hint. Use reply also to ask a question when you cannot tell what kind of entry he means.

language: the language of the message. Urdu script = "urdu".

Entry types:
- purchase: he bought cloth. party = seller. "liya", "khareeda", "maal aaya".
- sale: he sold cloth. party = buyer. "becha", "diya" (goods), "farokht".
- commission: he arranged a deal between a seller and a buyer and earns commission ("dalali", "commission").
  party = seller, buyer = buyer. goods_through_me = true only if the money passes through him.
- payment: money only, no goods. direction "in" = he received ("mile", "aaye", "wasool"),
  "out" = he paid ("diye", "bheje", "ada kiye"). method "bank" for bank/online/transfer/cheque/JazzCash/Easypaisa.
- expense: a business cost not tied to one deal: rent (kiraya of the shop), salary (tankhwah), electricity (bijli),
  tea (chai pani), phone. If it is freight or labour for one specific deal in the same message, put it in that deal's costs.
- stock: stock changed without a deal. Out: wastage (kharab, zaya, geela), shortage (kam nikla in a count),
  own_use, sample (namoona), other_out. In: opening (stock he already had when starting), found (zyada nikla), other_in.

Rules:
- Numbers: "20 hazar" = 20000, "1.5 lakh" = 150000, "50k" = 50000, "dhai sau" = 250, "sawa" = 1.25×, "derh" = 1.5×.
- Weight is always kg. 1 mann (maund) = 40 kg; convert. A rate per mann becomes rate per kg (divide by 40).
- "rate" is per kg unless he says otherwise.
- Dates: today is given below. "kal" usually means yesterday, "parson" the day before. Leave date null for today.
- Parties and cloth types: when he means one from the lists below, write its name exactly as listed, even if he
  spelled it differently. Otherwise write the new name as he wrote it. Never guess between two similar names: ask with intent "reply".
- If the only cloth type is listed and he does not name one, leave item null.
- Never invent amounts, weights or rates. If something is missing, leave it null; the system will ask him.
- A message can hold several entries ("Rashid se maal liya aur Akram ko 10 hazar diye" = a purchase and a payment).
- If an entry is waiting for his confirmation (shown below) and the message corrects or adds to it
  ("nahi rate 125 tha", "aur 5 hazar cash diye the"), return the full corrected entries with intent "record".
  If the message is about something new, ignore the waiting entry.
- costs.borne_by: who pays the cost in the end. "kiraya main dunga" = me; "kiraya party ke zimme" = the other side.

Voice notes:
- He speaks Urdu, sometimes with Punjabi or English words, often with market noise in the background.
- First write what he said in heard, in Roman Urdu, with numbers as digits ("paanch sau kilo" -> "500 kilo").
  Then read the entries from what he said, exactly as for a typed message.
- Spoken numbers: "dhai" = 2.5, "saadhe teen sau" = 350, "paune do hazar" = 1750, "sawa lakh" = 125000,
  "derh hazar" = 1500. Hear "sau" (100), "hazar" (1000) and "lakh" (100000) carefully.
- If a name or number is too unclear to hear, leave it null rather than guess; the system will ask him.
- language for a voice note: "roman_urdu" if he spoke Urdu, "english" if he spoke English.

Photos:
- Usually a parchi (handwritten slip), a printed bill, a page of his register, or a screenshot of a bank,
  JazzCash or Easypaisa transfer. A caption, if any, says what it is ("Akram ki payment", "yeh maal aaya").
- A transfer screenshot is a payment with method "bank". Use the caption to tell if he sent or received it;
  without one, a screenshot from his own app usually means he paid (direction "out"). The other side's name
  on the screenshot is the party.
- A bill or parchi: one entry per line of goods, at most 10. Read weights, rates and totals as written; never
  work out a number that is not on the paper.
- If you cannot tell what the photo is, or it has nothing to do with his business, use intent "reply" and ask.
- Leave heard null for photos.

Examples (today 2026-10-16):
"Rashid se 500 kg purana kapra 120 ke rate pe liya 20 hazar cash diye" ->
  purchase, party "Rashid", item "Purana kapra", weight_kg 500, rate_per_kg 120, paid_now 20000, method "cash".
"akram ko 10 mann becha 6000 mann" -> sale, party "Akram", weight_kg 400, rate_per_kg 150.
"Bilal ko 25000 bank se bheje" -> payment, party "Bilal", direction "out", amount 25000, method "bank".
"kal dukan ka kiraya 15000 diya" -> expense, date "2026-10-15", category "Dukaan ka kiraya", amount 15000.
"Saleem ka maal Nadeem ko dilwaya 1000 kg 90 rate, 2 rupay kilo commission Nadeem se" ->
  commission, party "Saleem", buyer "Nadeem", weight_kg 1000, rate_per_kg 90,
  commissions [{from "buyer", mode "per_kg", value 2}], goods_through_me false.
"20 kg maal geela ho kar kharab ho gaya" -> stock, stock_kind "wastage", weight_kg 20, note "geela".
"undo" -> intent "undo_last".`;

/** The part of the prompt that changes per message: today, names, the waiting entry. */
export function contextPrompt(ctx: Context): string {
  const parties = ctx.parties.map((p) => `${p.name} (${p.type})`).join('; ') || 'none yet';
  const items = ctx.items.map((i) => (i.name_ur ? `${i.name} / ${i.name_ur}` : i.name)).join('; ') || 'none yet';
  const categories = ctx.categories.join('; ') || 'none yet';
  const pending = ctx.pending?.action === 'save'
    ? JSON.stringify(ctx.pending.drafts)
    : 'none';
  return `Today: ${ctx.today}
Parties: ${parties}
Cloth types: ${items}
Expense categories used before: ${categories}
Entry waiting for confirmation: ${pending}`;
}
