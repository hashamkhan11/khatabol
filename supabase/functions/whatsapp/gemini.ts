// Reads a message with Google Gemini. Swapping the model provider means
// replacing this file: the rest of the bot only sees an Extraction.

import { contextPrompt, RESPONSE_SCHEMA, SYSTEM_PROMPT } from './prompt.ts';
import type { Context, Draft, Extraction } from './types.ts';

export interface GeminiConfig {
  apiKey: string;
  model: string;
}

export async function extract(text: string, ctx: Context, cfg: GeminiConfig, fetchFn = fetch): Promise<Extraction> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${cfg.model}:generateContent`;
  const body = {
    systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents: [{ role: 'user', parts: [{ text: `${contextPrompt(ctx)}\n\nMessage:\n${text}` }] }],
    generationConfig: {
      temperature: 0,
      responseMimeType: 'application/json',
      responseJsonSchema: RESPONSE_SCHEMA,
    },
  };

  let res: Response | undefined;
  for (let attempt = 0; attempt < 2; attempt++) {
    res = await fetchFn(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': cfg.apiKey },
      body: JSON.stringify(body),
    });
    if (res.status < 500 && res.status !== 429) break;
    await new Promise((r) => setTimeout(r, 1500));
  }
  if (!res!.ok) throw new Error(`Gemini ${res!.status}: ${(await res!.text()).slice(0, 300)}`);

  const json = await res!.json();
  const parts: { text?: string; thought?: boolean }[] = json?.candidates?.[0]?.content?.parts ?? [];
  const answer = parts.filter((p) => !p.thought && p.text).map((p) => p.text).join('');
  if (!answer) throw new Error(`Gemini returned no text: ${JSON.stringify(json).slice(0, 300)}`);
  return sanitize(JSON.parse(answer));
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
  };
}
