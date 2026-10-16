// Calls the bot_* database functions through the Supabase REST API with the
// service key. The bot never touches tables directly.

import type { Confirmed, Context, Plan } from './types.ts';

export class DbError extends Error {}

export class Db {
  url: string;
  key: string;
  fetchFn: typeof fetch;

  constructor(url: string, key: string, fetchFn: typeof fetch = fetch) {
    this.url = url.replace(/\/$/, '');
    this.key = key;
    this.fetchFn = fetchFn;
  }

  claimMessage(waId: string): Promise<boolean> {
    return this.rpc('bot_claim_message', { p_wa_id: waId });
  }

  context(whatsapp: string): Promise<Context | null> {
    return this.rpc('bot_context', { p_whatsapp: whatsapp });
  }

  setPending(whatsapp: string, plan: Plan | null): Promise<void> {
    return this.rpc('bot_set_pending', { p_whatsapp: whatsapp, p_plan: plan });
  }

  confirm(whatsapp: string, waId: string): Promise<Confirmed> {
    return this.rpc('bot_confirm', { p_whatsapp: whatsapp, p_wa_id: waId });
  }

  private async rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
    const headers: Record<string, string> = { 'content-type': 'application/json', apikey: this.key };
    // Legacy service_role keys are JWTs and also go in Authorization;
    // the newer sb_secret_ keys go in apikey only.
    if (this.key.startsWith('eyJ')) headers.authorization = `Bearer ${this.key}`;
    const res = await this.fetchFn(`${this.url}/rest/v1/rpc/${fn}`, {
      method: 'POST', headers, body: JSON.stringify(args),
    });
    const text = await res.text();
    if (!res.ok) {
      let message = text;
      try {
        message = JSON.parse(text).message ?? text;
      } catch { /* not JSON */ }
      throw new DbError(message);
    }
    return (text ? JSON.parse(text) : null) as T;
  }
}
