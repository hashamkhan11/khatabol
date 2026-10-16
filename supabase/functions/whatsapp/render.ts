// Everything the bot says, in Roman Urdu or English.
// Entries are read back from the resolved plan, never from model-written
// text, so what the user confirms is exactly what gets saved.

import type { Problem } from './resolve.ts';
import type { Confirmed, DealEntry, Entry, Lang, PartyRef, Plan, StockKind } from './types.ts';

const t = (lang: Lang, ur: string, en: string) => (lang === 'en' ? en : ur);

// ==================== NUMBERS AND DATES ====================

const moneyFmt = new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 });
const kgFmt = new Intl.NumberFormat('en-US', { maximumFractionDigits: 3 });
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** 60000 -> "Rs 60,000" */
export const money = (n: number) => `Rs ${moneyFmt.format(Math.abs(n))}`;
export const kg = (n: number) => `${kgFmt.format(n)} kg`;
const round2 = (n: number) => Math.round(n * 100) / 100;

/** "2026-10-14" -> "14 Oct", with the year when it is not this year. */
export function shortDate(iso: string, today: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return `${d} ${MONTHS[m - 1]}${iso.slice(0, 4) === today.slice(0, 4) ? '' : ` ${y}`}`;
}

// ==================== READING BACK A PLAN ====================

const METHOD: Record<string, [string, string]> = {
  cash: ['Cash', 'cash'], bank: ['Bank', 'bank'], other: ['Deegar', 'other'],
};

const STOCK_KIND: Record<StockKind, [string, string]> = {
  opening: ['Shuru ka stock', 'Opening stock'],
  found: ['Ginti mein zyada nikla', 'Found in count'],
  other_in: ['Deegar (aamad)', 'Other (in)'],
  wastage: ['Kharab / zaya', 'Damaged / wasted'],
  shortage: ['Ginti mein kam nikla', 'Short in count'],
  own_use: ['Apna istemal', 'Own use'],
  sample: ['Namoona', 'Sample'],
  other_out: ['Deegar (nikasi)', 'Other (out)'],
};

const method = (m: string | null, lang: Lang) => (lang === 'en' ? METHOD[m ?? 'cash'][1] : METHOD[m ?? 'cash'][0]);

function partyName(p: PartyRef, lang: Lang): string {
  return 'id' in p ? p.name : `${p.name} ${t(lang, '(nayi party)', '(new party)')}`;
}

function itemName(i: { name: string; id?: string } | null, lang: Lang): string | null {
  if (!i) return null;
  return 'id' in i ? i.name : `${i.name} ${t(lang, '(nayi qisam)', '(new cloth type)')}`;
}

/** The message asking the user to confirm a plan. */
export function renderPlan(plan: Plan, today: string): string {
  const lang = plan.lang;
  const blocks = plan.entries.map((e) => renderEntry(e, lang, today));
  if (plan.action === 'undo') {
    return [t(lang, '↩️ Yeh pichli entry cancel karni hai?', '↩️ Cancel this last entry?'), ...blocks].join('\n\n');
  }
  return [...blocks, t(lang, 'Sahi hai to *Haan* karein. Kuch ghalat ho to bata dein.',
    'Tap *Yes* to save. If something is wrong, just tell me.')].join('\n\n');
}

export function renderEntry(e: Entry, lang: Lang, today: string): string {
  const lines: string[] = [];
  switch (e.type) {
    case 'deal':
      lines.push(...renderDeal(e, lang));
      break;
    case 'payment': {
      const p = partyName(e.party, lang);
      lines.push(e.direction === 'in'
        ? t(lang, `💰 *Paise mile* · ${p} se`, `💰 *Received* from ${p}`)
        : t(lang, `💸 *Paise diye* · ${p} ko`, `💸 *Paid* to ${p}`));
      lines.push(`${money(e.amount)} · ${method(e.method, lang)}`);
      break;
    }
    case 'expense':
      lines.push(t(lang, `🧾 *Kharcha* · ${e.category}`, `🧾 *Expense* · ${e.category}`));
      lines.push(money(e.amount) + (e.paid_to
        ? t(lang, ` · ${partyName(e.paid_to, lang)} ka udhaar`, ` · on credit from ${partyName(e.paid_to, lang)}`)
        : ''));
      break;
    case 'stock': {
      const incoming = e.cost_per_kg !== null;
      const label = STOCK_KIND[e.kind][lang === 'en' ? 1 : 0];
      lines.push(incoming
        ? t(lang, `⬆️ *Stock aaya* · ${label}`, `⬆️ *Stock in* · ${label}`)
        : t(lang, `⬇️ *Stock gaya* · ${label}`, `⬇️ *Stock out* · ${label}`));
      lines.push(`${itemName(e.item, lang)} · ${kg(e.weight_kg)}` +
        (incoming ? ` · ${money(e.cost_per_kg!)}/kg = ${money(round2(e.weight_kg * e.cost_per_kg!))}` : ''));
      break;
    }
  }
  const note = e.type === 'payment' ? e.note : e.type === 'stock' ? e.reason : e.notes;
  if (note) lines.push(`Note: ${note}`);
  if (e.date !== today) lines.push(t(lang, `Tareekh: ${shortDate(e.date, today)}`, `Date: ${shortDate(e.date, today)}`));
  return lines.join('\n');
}

function renderDeal(e: DealEntry, lang: Lang): string[] {
  const party = partyName(e.party, lang);
  const total = e.weight_kg !== null && e.rate !== null ? round2(e.weight_kg * e.rate) : null;
  const item = itemName(e.item, lang);
  const goods = e.weight_kg === null ? item
    : [item, `${kg(e.weight_kg)}${e.rate !== null ? ` × ${moneyFmt.format(e.rate)} = ${money(total!)}` : ''}`]
        .filter(Boolean).join(' · ');
  const lines: string[] = [];

  if (e.kind === 'commission') {
    const buyer = partyName(e.buyer!, lang);
    lines.push(t(lang, `🤝 *Commission sauda* · ${party} se ${buyer} ko`, `🤝 *Commission deal* · ${party} to ${buyer}`));
    if (goods) lines.push(goods);
    if (total !== null) {
      lines.push(e.goods_through_me
        ? t(lang, 'Maal ki raqam mere khate se', 'Goods money passes through my khata')
        : t(lang, 'Maal ki raqam seedhi buyer se seller ko', 'Goods money goes straight from buyer to seller'));
    }
    for (const c of e.commissions) {
      const from = c.from === 'buyer' ? buyer : party;
      const amount = round2(c.mode === 'fixed' ? c.value
        : c.mode === 'per_kg' ? c.value * (e.weight_kg ?? 0) : c.value * (total ?? 0) / 100);
      const how = c.mode === 'per_kg' ? ` (${money(c.value)}/kg)` : c.mode === 'percent' ? ` (${c.value}%)` : '';
      lines.push(t(lang, `Commission: ${from} se ${money(amount)}${how}`, `Commission: ${money(amount)}${how} from ${from}`));
    }
  } else {
    const buying = e.kind === 'purchase';
    lines.push(buying
      ? t(lang, `🛒 *Khareed* · ${party} se`, `🛒 *Purchase* from ${party}`)
      : t(lang, `📦 *Farokht* · ${party} ko`, `📦 *Sale* to ${party}`));
    if (goods) lines.push(goods);
    if (e.paid_now) {
      lines.push(buying
        ? t(lang, `Abhi diye: ${money(e.paid_now)} · ${method(e.paid_method, lang)}`, `Paid now: ${money(e.paid_now)} · ${method(e.paid_method, lang)}`)
        : t(lang, `Abhi mile: ${money(e.paid_now)} · ${method(e.paid_method, lang)}`, `Received now: ${money(e.paid_now)} · ${method(e.paid_method, lang)}`));
    }
    const credit = total !== null ? round2(total - (e.paid_now ?? 0)) : 0;
    if (credit > 0) lines.push(t(lang, `Udhaar: ${money(credit)}`, `On credit: ${money(credit)}`));
  }

  for (const c of e.costs) {
    const who = c.charged_to === null ? t(lang, 'mere zimme', 'borne by me')
      : t(lang, `${partyName(c.charged_to === 'buyer' ? e.buyer! : e.party, lang)} ke zimme`,
          `charged to ${partyName(c.charged_to === 'buyer' ? e.buyer! : e.party, lang)}`);
    const owed = c.paid_to ? t(lang, ` · ${partyName(c.paid_to, lang)} ko dena hai`, ` · owed to ${partyName(c.paid_to, lang)}`) : '';
    lines.push(t(lang, `Kharcha: ${c.description} ${money(c.amount)} · ${who}${owed}`,
      `Cost: ${c.description} ${money(c.amount)} · ${who}${owed}`));
  }
  return lines;
}

// ==================== AFTER SAVING ====================

export function balanceLine(name: string, balance: number, lang: Lang): string {
  if (balance > 0) return t(lang, `${name}: ${money(balance)} lena hai`, `${name} owes you ${money(balance)}`);
  if (balance < 0) return t(lang, `${name}: ${money(balance)} dena hai`, `You owe ${name} ${money(balance)}`);
  return t(lang, `${name}: hisaab barabar`, `${name}: settled`);
}

export function renderConfirmed(r: Confirmed, lang: Lang): string {
  const head = r.action === 'undo'
    ? t(lang, '↩️ Cancel ho gaya.', '↩️ Cancelled.')
    : t(lang, '✅ Save ho gaya.', '✅ Saved.');
  const balances = r.balances.map((b) => balanceLine(b.name, Number(b.balance), lang));
  const tail = r.action === 'save' ? [t(lang, 'Ghalti ho to *undo* likhein.', 'Made a mistake? Send *undo*.')] : [];
  return [head, balances.join('\n'), ...tail].filter(Boolean).join('\n\n');
}

// ==================== QUESTIONS AND SHORT REPLIES ====================

export function renderProblems(problems: Problem[], entryCount: number, lang: Lang, itemNames: string[]): string {
  const items = itemNames.length ? ` (${itemNames.slice(0, 6).join(', ')})` : '';
  const ask: Record<Problem['issue'], [string, string]> = {
    party: ['Kis party ka hai?', 'Which party is it?'],
    buyer: ['Khareedne wala kaun hai?', 'Who is the buyer?'],
    item: [`Kaun sa kapra?${items}`, `Which cloth type?${items}`],
    weight: ['Kitne kg?', 'How many kg?'],
    rate: ['Rate kya tha (fi kg)?', 'What was the rate per kg?'],
    amount: ['Raqam kitni thi?', 'How much was it?'],
    direction: ['Paise mile ya diye?', 'Did you receive the money or pay it?'],
    category: ['Kharcha kis cheez ka tha?', 'What was the expense for?'],
    stock_kind: ['Stock kyun aaya ya gaya? (kharab, namoona, apna istemal, shuru ka stock...)',
      'Why did the stock change? (damaged, sample, own use, opening stock...)'],
    cost_per_kg: ['Is stock ki qeemat fi kg kya hai?', 'What is this stock worth per kg?'],
    commission: ['Commission kitna hai, aur kis se?', 'How much commission, and from whom?'],
    same_party: ['Bechne wala aur khareedne wala alag hon.', 'The seller and the buyer must be different.'],
    paid_on_commission: ['Commission sauday ki payment alag message mein bhejein.',
      'Send payments for a commission deal as a separate message.'],
    future_date: ['Tareekh aage ki hai. Sahi tareekh kya hai?', 'That date is in the future. Which date was it?'],
  };
  const seen = new Set<string>();
  const lines: string[] = [];
  for (const p of problems) {
    const text = (entryCount > 1 ? `${p.entry + 1}. ` : '') + ask[p.issue][lang === 'en' ? 1 : 0];
    if (!seen.has(text)) lines.push(`• ${text}`);
    seen.add(text);
  }
  return [t(lang, 'Thori si baat reh gayi:', 'I need a little more:'), ...lines].join('\n');
}

export const say = {
  help: (lang: Lang) => t(lang,
    'Assalam o alaikum! Apna hisaab aise likh kar bhejein:\n' +
      '• Rashid se 500 kg kapra 120 rate pe liya, 20 hazar cash diye\n' +
      '• Akram ko 200 kg 150 pe becha\n' +
      '• Akram se 10 hazar mile\n' +
      '• Dukaan ka kiraya 15000\n' +
      '• 20 kg maal kharab ho gaya\n\n' +
      'Main parh kar wapas bataunga. Aap *Haan* karein to save hoga. Ghalti ho to *undo* likhein.',
    'Hello! Send your entries like this:\n' +
      '• Bought 500 kg cloth from Rashid at 120, paid 20,000 cash\n' +
      '• Sold 200 kg to Akram at 150\n' +
      '• Received 10,000 from Akram\n' +
      '• Shop rent 15000\n' +
      '• 20 kg of stock got damaged\n\n' +
      "I'll read it back. Tap *Yes* and it is saved. Made a mistake? Send *undo*."),
  notText: (lang: Lang) => t(lang,
    'Abhi main sirf likha hua message samajhta hoon. Voice note aur tasveer jald.',
    'For now I can only read text messages. Voice notes and pictures are coming soon.'),
  nothingPending: (lang: Lang) => t(lang, 'Koi entry intezar mein nahi. Nayi entry bhejein.', 'Nothing is waiting. Send a new entry.'),
  discarded: (lang: Lang) => t(lang, 'Theek hai, kuch save nahi hua.', 'OK, nothing was saved.'),
  nothingToUndo: (lang: Lang) => t(lang, 'Undo karne ke liye koi entry nahi.', 'There is nothing to undo.'),
  notUnderstood: (lang: Lang) => t(lang, 'Maaf kijiye, samajh nahi aaya. Thora aur tafseel se likh dein?',
    "Sorry, I didn't get that. Could you write it with a little more detail?"),
  aiDown: (lang: Lang) => t(lang, 'Abhi message parhne mein masla hai. Thori der baad dobara bhejein.',
    'I cannot read messages right now. Please try again in a little while.'),
  yes: (lang: Lang) => t(lang, '✅ Haan, save karo', '✅ Yes, save'),
  no: (lang: Lang) => t(lang, '❌ Nahi', '❌ No'),
  confirmShort: (lang: Lang) => t(lang, 'Sahi hai?', 'Is this right?'),
};

// Database functions raise plain-English messages; the common ones in Roman Urdu.
const DB_MESSAGES: Record<string, string> = {
  'party not found': 'Party nahi mili',
  'cloth type not found': 'Kapre ki qisam nahi mili',
  'deal not found': 'Sauda nahi mila',
  'seller and buyer must be different parties': 'Bechne wala aur khareedne wala alag hon',
  'record payments for commission deals separately': 'Commission sauday ki payment alag se bhejein',
  'payment amount must be positive': 'Raqam zero se zyada honi chahiye',
  'weight must be positive': 'Wazan zero se zyada hona chahiye',
  'stock coming in needs a cost per kg': 'Aane wale stock ki qeemat fi kg likhein',
  'deal is already cancelled': 'Yeh sauda pehle hi cancel ho chuka hai (shayad app se)',
  'entry is already cancelled': 'Yeh line pehle hi cancel ho chuki hai (shayad app se)',
  'expense not found or already cancelled': 'Kharcha pehle hi cancel hai (shayad app se)',
  'stock adjustment not found or already cancelled': 'Stock ki line pehle hi cancel hai (shayad app se)',
  'nothing to confirm': 'Koi entry intezar mein nahi. Nayi entry bhejein.',
  'already undone': 'Yeh entry pehle hi cancel ho chuki hai',
};

export function renderError(message: string, lang: Lang): string {
  if (message === 'nothing to confirm') return say.nothingPending(lang);
  const known = DB_MESSAGES[message];
  if (lang === 'en') return `Not saved: ${message}`;
  return `Save nahi hua: ${known ?? message}`;
}
