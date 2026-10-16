// The conversation: read a message, read the entry back, save on yes.
//
//   message ──> model reads it ──> resolve.ts checks it ──> "Sahi hai?" [Haan] [Nahi]
//                                                                 │
//   "haan" / button ─────────────────────────────> bot_confirm() saves it ──> new balances
//
// Everything outside (database, model, WhatsApp) is passed in, so this file
// is tested without any of them.

import { renderConfirmed, renderError, renderPlan, renderProblems, say } from './render.ts';
import { resolve } from './resolve.ts';
import type { Confirmed, Context, Extraction, Lang, Plan } from './types.ts';
import type { Incoming } from './whatsapp.ts';

export interface Deps {
  db: {
    claimMessage(waId: string): Promise<boolean>;
    context(whatsapp: string): Promise<Context | null>;
    setPending(whatsapp: string, plan: Plan | null): Promise<void>;
    confirm(whatsapp: string, waId: string): Promise<Confirmed>;
  };
  read(text: string, ctx: Context): Promise<Extraction>;
  wa: {
    sendText(to: string, text: string): Promise<void>;
    sendButtons(to: string, text: string, buttons: { id: string; title: string }[], shortText: string): Promise<void>;
    markRead(messageId: string): Promise<void>;
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

  let reading: Extraction;
  try {
    reading = await deps.read(msg.text, ctx);
  } catch (e) {
    deps.log?.('reading the message failed', e);
    return wa.sendText(to, say.aiDown(lang));
  }
  const replyLang = langOf(reading);

  if (reading.intent === 'undo_last') return askUndo(ctx, to, replyLang, deps);
  if (reading.intent === 'reply' || !reading.entries.length) {
    return wa.sendText(to, reading.reply ?? say.notUnderstood(replyLang));
  }

  const resolved = resolve(reading.entries, ctx);
  if (!resolved.ok) {
    if (!resolved.problems.length) return wa.sendText(to, say.notUnderstood(replyLang));
    return wa.sendText(to, renderProblems(resolved.problems, reading.entries.length, replyLang, ctx.items.map((i) => i.name)));
  }
  const plan: Plan = { action: 'save', lang: replyLang, entries: resolved.entries, drafts: reading.entries };
  await db.setPending(to, plan);
  return confirmButtons(to, renderPlan(plan, ctx.today), replyLang, deps);
}

async function askUndo(ctx: Context, to: string, lang: Lang, deps: Deps) {
  const last = ctx.last_saved;
  if (!last) return deps.wa.sendText(to, say.nothingToUndo(lang));
  const plan: Plan = { action: 'undo', lang, log_id: last.id, entries: last.plan.entries };
  await deps.db.setPending(to, plan);
  return confirmButtons(to, renderPlan(plan, ctx.today), lang, deps);
}

function confirmButtons(to: string, text: string, lang: Lang, deps: Deps) {
  return deps.wa.sendButtons(to, text, [
    { id: 'yes', title: say.yes(lang) },
    { id: 'no', title: say.no(lang) },
  ], say.confirmShort(lang));
}
