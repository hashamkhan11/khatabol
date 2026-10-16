// Turns the model's reading of a message (names, maybe gaps) into entries
// ready to save (ids, all required fields), or says what is missing.
// The database checks everything again when saving; this step exists so the
// bot can ask a clear question instead of failing after the user says yes.

import type {
  Context, DealEntry, Draft, Entry, ItemInfo, ItemRef, PartyInfo, PartyRef, PartyType,
} from './types.ts';
import { STOCK_IN } from './types.ts';

/** Something the bot has to ask before it can read the entry back. */
export type Issue =
  | 'party' | 'buyer' | 'item' | 'weight' | 'rate' | 'amount' | 'direction'
  | 'category' | 'stock_kind' | 'cost_per_kg' | 'commission' | 'same_party'
  | 'paid_on_commission' | 'future_date';

export interface Problem {
  entry: number;
  issue: Issue;
}

export type Resolved = { ok: true; entries: Entry[] } | { ok: false; problems: Problem[] };

export function resolve(drafts: Draft[], ctx: Context): Resolved {
  const entries: Entry[] = [];
  const problems: Problem[] = [];
  drafts.forEach((d, i) => {
    const issues: Issue[] = [];
    const entry = resolveOne(d, ctx, issues);
    if (issues.length) problems.push(...issues.map((issue) => ({ entry: i, issue })));
    else if (entry) entries.push(entry);
  });
  return problems.length || !entries.length ? { ok: false, problems } : { ok: true, entries };
}

function resolveOne(d: Draft, ctx: Context, issues: Issue[]): Entry | null {
  const date = d.date && /^\d{4}-\d{2}-\d{2}$/.test(d.date) ? d.date : ctx.today;
  if (date > ctx.today) issues.push('future_date');
  const positive = (n: number | null): n is number => typeof n === 'number' && Number.isFinite(n) && n > 0;
  const party = (name: string | null, type: PartyType, issue: Issue): PartyRef | null => {
    const ref = name?.trim() ? partyRef(name, ctx.parties, type) : null;
    if (!ref) issues.push(issue);
    return ref;
  };

  switch (d.type) {
    case 'purchase':
    case 'sale':
    case 'commission': {
      const isCommission = d.type === 'commission';
      const seller = party(d.party, d.type === 'sale' ? 'buyer' : 'supplier', 'party');
      const buyer = isCommission ? party(d.buyer, 'buyer', 'buyer') : null;
      if (seller && buyer && sameParty(seller, buyer)) issues.push('same_party');

      const item = d.item?.trim() ? itemRef(d.item, ctx.items)
        : ctx.items.length === 1 ? { id: ctx.items[0].id, name: ctx.items[0].name } : null;
      if (!isCommission && !item) issues.push('item');

      const weight = positive(d.weight_kg) ? d.weight_kg : null;
      const rate = typeof d.rate_per_kg === 'number' && d.rate_per_kg >= 0 ? d.rate_per_kg : null;
      if (!isCommission && weight === null) issues.push('weight');
      if (!isCommission && rate === null) issues.push('rate');

      const goodsThroughMe = isCommission && d.goods_through_me === true;
      const commissions = (d.commissions ?? []).filter((c) => positive(c.value));
      if (isCommission) {
        if (!commissions.length && !goodsThroughMe) issues.push('commission');
        const needsWeight = goodsThroughMe || commissions.some((c) => c.mode !== 'fixed');
        const needsRate = goodsThroughMe || commissions.some((c) => c.mode === 'percent');
        if (needsWeight && weight === null) issues.push('weight');
        if (needsRate && rate === null) issues.push('rate');
        if (positive(d.paid_now)) issues.push('paid_on_commission');
      }

      const costs = (d.costs ?? []).filter((c) => positive(c.amount)).map((c) => ({
        description: c.description?.trim() || 'Kharcha',
        amount: c.amount,
        charged_to: chargedTo(d.type as DealEntry['kind'], c.borne_by),
        paid_to: c.paid_to?.trim() ? partyRef(c.paid_to, ctx.parties, 'transporter') : null,
      }));

      if (!seller) return null;
      return {
        type: 'deal',
        kind: d.type,
        date,
        party: seller,
        buyer,
        item,
        weight_kg: weight,
        rate,
        paid_now: !isCommission && positive(d.paid_now) ? d.paid_now : null,
        paid_method: !isCommission && positive(d.paid_now) ? d.method ?? 'cash' : null,
        goods_through_me: goodsThroughMe,
        notes: d.note?.trim() || null,
        costs,
        commissions: commissions.map((c) => ({ from: c.from === 'buyer' ? 'buyer' : 'party', mode: c.mode, value: c.value })),
      };
    }

    case 'payment': {
      const p = party(d.party, 'other', 'party');
      if (d.direction !== 'in' && d.direction !== 'out') issues.push('direction');
      if (!positive(d.amount)) issues.push('amount');
      if (!p || issues.length) return null;
      return {
        type: 'payment', date, party: p, direction: d.direction!, amount: d.amount!,
        method: d.method ?? 'cash', note: d.note?.trim() || null,
      };
    }

    case 'expense': {
      const category = d.category?.trim() ? matchCategory(d.category, ctx.categories) : null;
      if (!category) issues.push('category');
      if (!positive(d.amount)) issues.push('amount');
      const paidTo = d.party?.trim() ? partyRef(d.party, ctx.parties, 'other') : null;
      if (issues.length) return null;
      return { type: 'expense', date, category: category!, amount: d.amount!, paid_to: paidTo, notes: d.note?.trim() || null };
    }

    case 'stock': {
      const item = d.item?.trim() ? itemRef(d.item, ctx.items)
        : ctx.items.length === 1 ? { id: ctx.items[0].id, name: ctx.items[0].name } : null;
      if (!item) issues.push('item');
      if (!d.stock_kind) issues.push('stock_kind');
      if (!positive(d.weight_kg)) issues.push('weight');
      const incoming = d.stock_kind !== null && STOCK_IN.includes(d.stock_kind);
      const cost = typeof d.cost_per_kg === 'number' && d.cost_per_kg >= 0 ? d.cost_per_kg : null;
      if (incoming && cost === null) issues.push('cost_per_kg');
      if (issues.length) return null;
      return {
        type: 'stock', date, item: item!, kind: d.stock_kind!, weight_kg: d.weight_kg!,
        cost_per_kg: incoming ? cost : null, reason: d.note?.trim() || null,
      };
    }
  }
  return null;
}

// purchase: the seller is the party; sale: the buyer is the party.
function chargedTo(kind: DealEntry['kind'], borneBy: 'me' | 'seller' | 'buyer'): 'party' | 'buyer' | null {
  if (borneBy === 'me') return null;
  if (kind === 'purchase') return borneBy === 'seller' ? 'party' : null;
  if (kind === 'sale') return borneBy === 'buyer' ? 'party' : null;
  return borneBy === 'seller' ? 'party' : 'buyer';
}

function sameParty(a: PartyRef, b: PartyRef): boolean {
  if ('id' in a && 'id' in b) return a.id === b.id;
  return key(a.name) === key(b.name);
}

// ==================== MATCHING NAMES ====================

/** "Rashid Bhai!" -> "rashidbhai". Keeps Urdu letters. */
export function key(name: string): string {
  return name.toLowerCase().normalize('NFC').replace(/[^\p{L}\p{N}]/gu, '');
}

/**
 * The way people spell the same Roman Urdu name differently: Rasheed,
 * Rashid, Rashed. Drops vowels and doubled letters: all become "rshd".
 */
export function looseKey(name: string): string {
  const k = key(name).replace(/[aeiouy]/g, '').replace(/(.)\1+/g, '$1');
  // Too short to tell names apart: "Ali" and "Ola" would both be "l".
  return k.length >= 3 ? k : '';
}

/**
 * The party a name refers to. An exact match (ignoring case and spaces) wins.
 * Otherwise a single party whose name sounds the same is used. Otherwise the
 * name is a new party, which the bot reads back as new before saving.
 */
export function partyRef(name: string, parties: PartyInfo[], newType: PartyType): PartyRef {
  const exact = parties.filter((p) => key(p.name) === key(name));
  if (exact.length >= 1) return { id: exact[0].id, name: exact[0].name };
  const loose = looseKey(name);
  const similar = loose ? parties.filter((p) => looseKey(p.name) === loose) : [];
  if (similar.length === 1) return { id: similar[0].id, name: similar[0].name };
  return { name: titleCase(name.trim()), party_type: newType };
}

export function itemRef(name: string, items: ItemInfo[]): ItemRef {
  const names = (i: ItemInfo) => [i.name, i.name_ur ?? ''].filter(Boolean);
  const exact = items.find((i) => names(i).some((n) => key(n) === key(name)));
  if (exact) return { id: exact.id, name: exact.name };
  const loose = looseKey(name);
  const similar = loose ? items.filter((i) => names(i).some((n) => looseKey(n) === loose)) : [];
  if (similar.length === 1) return { id: similar[0].id, name: similar[0].name };
  return { name: titleCase(name.trim()) };
}

/** Uses an existing category's spelling when the user means the same one. */
function matchCategory(category: string, categories: string[]): string {
  return categories.find((c) => key(c) === key(category)) ?? category.trim();
}

function titleCase(s: string): string {
  return s.replace(/(^|\s)(\p{Ll})/gu, (_, sp, ch) => sp + ch.toUpperCase());
}
