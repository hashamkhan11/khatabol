// Reads a message with Google Gemini. Swapping the model provider means
// replacing this file: the rest of the bot only sees an Extraction.

import { contextPrompt, RESPONSE_SCHEMA, SYSTEM_PROMPT } from './prompt.ts';
import type { Context, Draft, Extraction, Media, Usage } from './types.ts';

export interface GeminiConfig {
  apiKey: string;
  /** Tried in order: the next one is used when one is busy or unavailable. */
  models: string[];
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** What the user sent: typed text, or a voice note or photo with its caption. */
export interface Message {
  text: string;
  media?: Media & { kind: 'audio' | 'image' };
}

export interface Reading {
  extraction: Extraction;
  usage: Usage;
}

function base64(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

function userParts(msg: Message, ctx: Context) {
  const context = contextPrompt(ctx);
  if (!msg.media) return [{ text: `${context}\n\nMessage:\n${msg.text}` }];
  const what = msg.media.kind === 'audio' ? 'Voice note (attached).' : 'Photo (attached).';
  const caption = msg.text.trim() ? `\nCaption: ${msg.text}` : '';
  return [
    { inlineData: { mimeType: msg.media.mime, data: base64(msg.media.data) } },
    { text: `${context}\n\nMessage: ${what}${caption}` },
  ];
}

export async function extract(
  msg: Message, ctx: Context, cfg: GeminiConfig, fetchFn = fetch, wait = sleep,
): Promise<Reading> {
  const body = {
    systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents: [{ role: 'user', parts: userParts(msg, ctx) }],
    generationConfig: {
      temperature: 0,
      responseMimeType: 'application/json',
      responseJsonSchema: RESPONSE_SCHEMA,
    },
  };

  // Busy (503, 429, other 5xx): wait and try again, then move to the next
  // model. Not found (404): next model. Anything else is a real error.
  let res: Response | undefined;
  let used = '';
  let failure = '';
  models: for (const model of cfg.models) {
    used = model;
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
    for (const delay of [0, 2000, 5000]) {
      if (delay) await wait(delay);
      res = await fetchFn(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-goog-api-key': cfg.apiKey },
        body: JSON.stringify(body),
      });
      if (res.ok) break models;
      failure = `Gemini ${model} ${res.status}: ${(await res.text()).slice(0, 300)}`;
      if (res.status === 404) continue models;
      if (res.status < 500 && res.status !== 429) throw new Error(failure);
    }
  }
  if (!res?.ok) throw new Error(failure);

  const json = await res.json();
  const parts: { text?: string; thought?: boolean }[] = json?.candidates?.[0]?.content?.parts ?? [];
  const answer = parts.filter((p) => !p.thought && p.text).map((p) => p.text).join('');
  if (!answer) throw new Error(`Gemini returned no text: ${JSON.stringify(json).slice(0, 300)}`);
  return { extraction: sanitize(JSON.parse(answer)), usage: usageOf(json, used) };
}

/** Token counts as Gemini reports them. */
function usageOf(json: Record<string, unknown>, model: string): Usage {
  // deno-lint-ignore no-explicit-any
  const u = (json.usageMetadata ?? {}) as any;
  const count = (v: unknown) => (typeof v === 'number' && v > 0 ? Math.round(v) : 0);
  const details: { modality?: string; tokenCount?: number }[] =
    Array.isArray(u.promptTokensDetails) ? u.promptTokensDetails : [];
  return {
    model,
    input_tokens: count(u.promptTokenCount),
    output_tokens: count(u.candidatesTokenCount),
    thinking_tokens: count(u.thoughtsTokenCount),
    media_tokens: details.filter((d) => d.modality !== 'TEXT').reduce((sum, d) => sum + count(d.tokenCount), 0),
  };
}

// ==================== NEVER TRUST THE MODEL'S JSON ====================

const oneOf = <T extends string>(v: unknown, allowed: readonly T[]): T | null =>
  typeof v === 'string' && (allowed as readonly string[]).includes(v) ? (v as T) : null;
const num = (v: unknown): number | null => {
  const n = typeof v === 'string' ? Number(v.replace(/,/g, '')) : v;
  return typeof n === 'number' && Number.isFinite(n) ? n : null;
};
const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v.trim().slice(0, 200) : null);
const arr = (v: unknown): Record<string, unknown>[] =>
  Array.isArray(v) ? v.filter((x) => x && typeof x === 'object') : [];

/** Coerces the model's answer into an Extraction, dropping anything malformed. */
export function sanitize(raw: unknown): Extraction {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const entries: Draft[] = arr(r.entries).flatMap((e) => {
    const type = oneOf(e.type, ['purchase', 'sale', 'commission', 'payment', 'expense', 'stock'] as const);
    if (!type) return [];
    const date = str(e.date);
    return [{
      type,
      date: date && /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : null,
      party: str(e.party),
      buyer: str(e.buyer),
      item: str(e.item),
      weight_kg: num(e.weight_kg),
      rate_per_kg: num(e.rate_per_kg),
      paid_now: num(e.paid_now),
      method: oneOf(e.method, ['cash', 'bank', 'other'] as const),
      goods_through_me: typeof e.goods_through_me === 'boolean' ? e.goods_through_me : null,
      commissions: arr(e.commissions).flatMap((c) => {
        const mode = oneOf(c.mode, ['per_kg', 'percent', 'fixed'] as const);
        const value = num(c.value);
        return mode && value !== null ? [{ from: c.from === 'seller' ? 'seller' : 'buyer', mode, value }] : [];
      }) as Draft['commissions'],
      costs: arr(e.costs).flatMap((c) => {
        const amount = num(c.amount);
        return amount !== null ? [{
          description: str(c.description) ?? 'Kharcha',
          amount,
          borne_by: oneOf(c.borne_by, ['me', 'seller', 'buyer'] as const) ?? 'me',
          paid_to: str(c.paid_to),
        }] : [];
      }),
      direction: oneOf(e.direction, ['in', 'out'] as const),
      amount: num(e.amount),
      category: str(e.category),
      stock_kind: oneOf(e.stock_kind,
        ['opening', 'found', 'other_in', 'wastage', 'shortage', 'own_use', 'sample', 'other_out'] as const),
      cost_per_kg: num(e.cost_per_kg),
      note: str(e.note),
    }];
  });
  return {
    language: oneOf(r.language, ['roman_urdu', 'urdu', 'english'] as const) ?? 'roman_urdu',
    intent: oneOf(r.intent, ['record', 'undo_last', 'reply'] as const) ?? (entries.length ? 'record' : 'reply'),
    entries: entries.slice(0, 10),
    reply: typeof r.reply === 'string' && r.reply.trim() ? r.reply.trim().slice(0, 1000) : null,
    heard: typeof r.heard === 'string' && r.heard.trim() ? r.heard.trim().slice(0, 600) : null,
  };
}
