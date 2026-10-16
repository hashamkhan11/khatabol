// Shapes shared by the bot's modules.

export type Lang = 'ur' | 'en';

export type PartyType = 'supplier' | 'factory' | 'buyer' | 'transporter' | 'other';
export type PaymentMethod = 'cash' | 'bank' | 'other';
export type CommissionMode = 'per_kg' | 'percent' | 'fixed';
export type StockKind =
  | 'opening' | 'found' | 'other_in'
  | 'wastage' | 'shortage' | 'own_use' | 'sample' | 'other_out';

export const STOCK_IN: readonly StockKind[] = ['opening', 'found', 'other_in'];

// ==================== WHAT THE DATABASE TELLS THE BOT ====================

export interface PartyInfo {
  id: string;
  name: string;
  type: PartyType;
  balance: number;
}

export interface ItemInfo {
  id: string;
  name: string;
  name_ur: string | null;
}

/** bot_context(): everything needed to read one message. */
export interface Context {
  today: string;
  parties: PartyInfo[];
  items: ItemInfo[];
  categories: string[];
  pending: Plan | null;
  last_saved: { id: string; plan: Plan; at: string } | null;
}

// ==================== WHAT THE MODEL RETURNS ====================

/**
 * One entry as the model read it from the message: names, not ids, and
 * nothing checked yet. Fields that do not apply to the type are null.
 */
export interface Draft {
  type: 'purchase' | 'sale' | 'commission' | 'payment' | 'expense' | 'stock';
  date: string | null;
  party: string | null;
  buyer: string | null;
  item: string | null;
  weight_kg: number | null;
  rate_per_kg: number | null;
  paid_now: number | null;
  method: PaymentMethod | null;
  goods_through_me: boolean | null;
  commissions: { from: 'seller' | 'buyer'; mode: CommissionMode; value: number }[] | null;
  costs: { description: string; amount: number; borne_by: 'me' | 'seller' | 'buyer'; paid_to: string | null }[] | null;
  direction: 'in' | 'out' | null;
  amount: number | null;
  category: string | null;
  stock_kind: StockKind | null;
  cost_per_kg: number | null;
  note: string | null;
}

export interface Extraction {
  language: 'roman_urdu' | 'urdu' | 'english';
  intent: 'record' | 'undo_last' | 'reply';
  entries: Draft[];
  /** For intent "reply": a question about missing details, or a short answer. */
  reply: string | null;
  /** Voice notes: what he said, written out, so he can check it was heard right. */
  heard: string | null;
}

/** A voice note or photo, downloaded from WhatsApp. */
export interface Media {
  mime: string;
  data: Uint8Array;
}

/** What one reading cost, from the model's own count. */
export interface Usage {
  model: string;
  input_tokens: number;
  output_tokens: number;
  thinking_tokens: number;
  /** The part of input_tokens that was the voice note or photo. */
  media_tokens: number;
}

// ==================== WHAT GETS SAVED ====================

/** An existing party ({id}) or a new one (no id). */
export type PartyRef = { id: string; name: string } | { name: string; party_type: PartyType };
export type ItemRef = { id: string; name: string } | { name: string };

export interface DealEntry {
  type: 'deal';
  kind: 'purchase' | 'sale' | 'commission';
  date: string;
  party: PartyRef;
  buyer: PartyRef | null;
  item: ItemRef | null;
  weight_kg: number | null;
  rate: number | null;
  paid_now: number | null;
  paid_method: PaymentMethod | null;
  goods_through_me: boolean;
  notes: string | null;
  costs: { description: string; amount: number; charged_to: 'party' | 'buyer' | null; paid_to: PartyRef | null }[];
  commissions: { from: 'party' | 'buyer'; mode: CommissionMode; value: number }[];
}

export interface PaymentEntry {
  type: 'payment';
  date: string;
  party: PartyRef;
  direction: 'in' | 'out';
  amount: number;
  method: PaymentMethod;
  note: string | null;
}

export interface ExpenseEntry {
  type: 'expense';
  date: string;
  category: string;
  amount: number;
  paid_to: PartyRef | null;
  notes: string | null;
}

export interface StockEntry {
  type: 'stock';
  date: string;
  item: ItemRef;
  kind: StockKind;
  weight_kg: number;
  cost_per_kg: number | null;
  reason: string | null;
}

export type Entry = DealEntry | PaymentEntry | ExpenseEntry | StockEntry;

/**
 * What the bot read back and waits for a yes on. bot_confirm() saves it.
 * drafts keeps the model's reading so a follow-up message can correct it.
 */
export type Plan =
  | { action: 'save'; lang: Lang; entries: Entry[]; drafts: Draft[] }
  | { action: 'undo'; lang: Lang; log_id: string; entries: Entry[] };

/** bot_confirm() result. */
export interface Confirmed {
  action: 'save' | 'undo';
  saved: { type: Entry['type']; id: string }[];
  balances: { name: string; balance: number }[];
}
