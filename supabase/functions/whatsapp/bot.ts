// The conversation: read a message, read the entry back, save on yes.
//
//   message ──> model reads it ──> resolve.ts checks it ──> "Sahi hai?" [Haan] [Nahi]
//                                                                 │
//   "haan" / button ─────────────────────────────> bot_confirm() saves it ──> new balances
//
// Everything outside (database, model, WhatsApp) is passed in, so this file
// is tested without any of them.

import type { Message, Reading } from './gemini.ts';
import { heardLine, renderConfirmed, renderError, renderPlan, renderProblems, say } from './render.ts';
import { resolve } from './resolve.ts';
import type { Confirmed, Context, Extraction, Lang, Media, Plan, Usage } from './types.ts';
import { type Incoming, MediaTooBig } from './whatsapp.ts';

// Voice notes are small (about 1 MB for 5 minutes); photos from a phone are
// a few MB at most. Bigger files are refused before they reach the model.
export const MAX_BYTES = { audio: 5_000_000, image: 10_000_000 };

export interface Deps {
  db: {
    claimMessage(waId: string): Promise<boolean>;
    context(whatsapp: string): Promise<Context | null>;
    setPending(whatsapp: string, plan: Plan | null): Promise<void>;
    confirm(whatsapp: string, waId: string): Promise<Confirmed>;
    logUsage(whatsapp: string, waId: string, kind: 'text' | 'audio' | 'image', usage: Usage): Promise<void>;
  };
  read(msg: Message, ctx: Context): Promise<Reading>;
  wa: {
    sendText(to: string, text: string): Promise<void>;
    sendButtons(to: string, text: string, buttons: { id: string; title: string }[], shortText: string): Promise<void>;
    markRead(messageId: string): Promise<void>;
    downloadMedia(mediaId: string, maxBytes: number): Promise<Media>;
  };
  log?(message: string, error?: unknown): void;
}

const YES = new Set(['yes', 'haan', 'han', 'ha', 'haa', 'haanji', 'han ji', 'haan ji', 'ji', 'jee', 'ji haan',
  'g', 'y', 'ok', 'okay', 'oky', 'theek', 'theek hai', 'thik', 'thik hai', 'thek hai', 'sahi', 'sahi hai',
  'bilkul', 'done', 'save', 'save karo', 'kar do', 'karo', '👍', '✅', 'ہاں', 'جی', 'جی ہاں', 'ٹھیک ہے']);
const NO = new Set(['no', 'nahi', 'nahin', 'nai', 'nhi', 'na', 'n', 'mat', 'mat karo', 'rehne do', 'rehnay do',
  'cancel', 'chhoro', 'chodo', '❌', '👎', 'نہیں', 'نہ']);
const HELP = new Set(['help', 'madad', 'menu', 'hi', 'hello', 'salam', 'salaam', 'aoa', 'assalam o alaikum',
  'assalamualaikum', 'asalam o alaikum', 'السلام علیکم']);
const UNDO = new Set(['undo', 'wapas', 'wapis', 'wapas lo', 'pichli cancel', 'last cancel', 'cancel last']);

export function normalise(text: string): string {
  return text.toLowerCase().replace(/[.!,?؟۔]+/g, ' ').replace(/\s+/g, ' ').trim();
}

const langOf = (e: Extraction): Lang => (e.language === 'english' ? 'en' : 'ur');

export async function handle(msg: Incoming, deps: Deps): Promise<void> {
  const { db, wa } = deps;
  if (!(await db.claimMessage(msg.id))) return; // a redelivery
  const ctx = await db.context(msg.from);
  if (!ctx) return; // not a linked number: stay silent

  await wa.markRead(msg.id);
  const to = msg.from;
  const pending = ctx.pending;
  const lang: Lang = pending?.lang ?? 'ur';
  const answer = msg.kind === 'button' ? msg.text : normalise(msg.text);

  if (msg.kind === 'other') return wa.sendText(to, say.notText(lang));
  if (msg.kind === 'audio' || msg.kind === 'image') return readMessage(msg, ctx, lang, deps);

  // Yes / no to the entry waiting, without asking the model.
  if (YES.has(answer)) {
    if (!pending) return wa.sendText(to, say.nothingPending(lang));
    try {
      const done = await db.confirm(to, msg.id);
      return wa.sendText(to, renderConfirmed(done, pending.lang));
    } catch (e) {
      deps.log?.('confirm failed', e);
      return wa.sendText(to, renderError(e instanceof Error ? e.message : String(e), pending.lang));
    }
  }
  if (NO.has(answer)) {
    if (!pending) return wa.sendText(to, say.nothingPending(lang));
    await db.setPending(to, null);
    return wa.sendText(to, say.discarded(pending.lang));
  }
  if (UNDO.has(answer)) return askUndo(ctx, to, lang, deps);
  if (HELP.has(answer)) return wa.sendText(to, say.help(lang));
  if (msg.kind === 'button' || !answer) return;
  return readMessage(msg, ctx, lang, deps);
}

/** A typed message, voice note or photo the model has to read. */
async function readMessage(msg: Incoming, ctx: Context, lang: Lang, deps: Deps) {
  const { db, wa } = deps;
  const to = msg.from;
  const kind = msg.kind === 'audio' || msg.kind === 'image' ? msg.kind : 'text';

  const message: Message = { text: msg.text };
  if (kind !== 'text') {
    try {
      message.media = { kind, ...(await wa.downloadMedia(msg.mediaId ?? '', MAX_BYTES[kind])) };
    } catch (e) {
      if (e instanceof MediaTooBig) return wa.sendText(to, say.mediaTooBig(lang));
      deps.log?.('downloading the media failed', e);
      return wa.sendText(to, say.mediaFailed(lang));
    }
  }

  let reading: Extraction;
  try {
    const result = await deps.read(message, ctx);
    reading = result.extraction;
    try {
      await db.logUsage(to, msg.id, kind, result.usage);
    } catch (e) {
      deps.log?.('logging token usage failed', e); // never worth losing the reply over
    }
  } catch (e) {
    deps.log?.('reading the message failed', e);
    return wa.sendText(to, say.aiDown(lang));
  }
  const replyLang = langOf(reading);
  const heard = kind === 'audio' && reading.heard ? heardLine(reading.heard, replyLang) : '';

  if (reading.intent === 'undo_last') return askUndo(ctx, to, replyLang, deps, heard);
  if (reading.intent === 'reply' || !reading.entries.length) {
    return wa.sendText(to, heard + (reading.reply ?? say.notUnderstood(replyLang)));
  }

  const resolved = resolve(reading.entries, ctx);
  if (!resolved.ok) {
    if (!resolved.problems.length) return wa.sendText(to, heard + say.notUnderstood(replyLang));
    return wa.sendText(to, heard +
      renderProblems(resolved.problems, reading.entries.length, replyLang, ctx.items.map((i) => i.name)));
  }
  const plan: Plan = { action: 'save', lang: replyLang, entries: resolved.entries, drafts: reading.entries };
  await db.setPending(to, plan);
  return confirmButtons(to, heard + renderPlan(plan, ctx.today), replyLang, deps);
}

async function askUndo(ctx: Context, to: string, lang: Lang, deps: Deps, heard = '') {
  const last = ctx.last_saved;
  if (!last) return deps.wa.sendText(to, heard + say.nothingToUndo(lang));
  const plan: Plan = { action: 'undo', lang, log_id: last.id, entries: last.plan.entries };
  await deps.db.setPending(to, plan);
  return confirmButtons(to, heard + renderPlan(plan, ctx.today), lang, deps);
}

function confirmButtons(to: string, text: string, lang: Lang, deps: Deps) {
  return deps.wa.sendButtons(to, text, [
    { id: 'yes', title: say.yes(lang) },
    { id: 'no', title: say.no(lang) },
  ], say.confirmShort(lang));
}
