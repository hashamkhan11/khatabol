// WhatsApp webhook (Supabase Edge Function).
//   GET  — Meta checks the webhook URL once, with the verify token.
//   POST — incoming messages. Answered with 200 at once; the reply is sent in
//          the background so Meta does not time out and resend.
// Setup and secrets: see README.md in this folder.

import { handle } from './bot.ts';
import { Db } from './db.ts';
import { extract } from './gemini.ts';
import { parseWebhook, verifySignature, WhatsApp } from './whatsapp.ts';

const env = (name: string, fallback?: string) => {
  const v = Deno.env.get(name) ?? fallback;
  if (v === undefined) throw new Error(`Missing secret ${name}`);
  return v;
};

const wa = new WhatsApp({
  token: env('WHATSAPP_TOKEN'),
  phoneNumberId: env('WHATSAPP_PHONE_NUMBER_ID'),
  apiVersion: env('WHATSAPP_API_VERSION', 'v25.0'),
});
const db = new Db(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'));
const gemini = {
  apiKey: env('GEMINI_API_KEY'),
  models: [env('GEMINI_MODEL', 'gemini-3.8-flash'),
    ...env('GEMINI_FALLBACK_MODELS', 'gemini-3.6-flash,gemini-3.5-flash-lite').split(',').map((m) => m.trim()).filter(Boolean)],
};
const appSecret = env('WHATSAPP_APP_SECRET');
const verifyToken = env('WHATSAPP_VERIFY_TOKEN');

const log = (message: string, error?: unknown) => console.error(message, error instanceof Error ? error.message : error ?? '');

Deno.serve(async (req) => {
  const url = new URL(req.url);

  if (req.method === 'GET') {
    const ok = url.searchParams.get('hub.mode') === 'subscribe' &&
      url.searchParams.get('hub.verify_token') === verifyToken;
    return ok ? new Response(url.searchParams.get('hub.challenge') ?? '') : new Response('Forbidden', { status: 403 });
  }
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const raw = await req.text();
  if (!(await verifySignature(raw, req.headers.get('x-hub-signature-256'), appSecret))) {
    return new Response('Bad signature', { status: 401 });
  }

  let messages;
  try {
    messages = parseWebhook(JSON.parse(raw));
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const work = (async () => {
    for (const msg of messages) {
      try {
        await handle(msg, { db, wa, read: (text, ctx) => extract(text, ctx, gemini), log });
      } catch (e) {
        log(`message ${msg.id} failed`, e);
      }
    }
  })();
  // Keep the function alive after the response until the replies are sent.
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) runtime.waitUntil(work);
  else await work;
  return new Response('ok');
});
