// WhatsApp Cloud API: checking that a webhook really came from Meta, reading
// the messages in it, and sending replies.

export interface WhatsAppConfig {
  token: string;
  phoneNumberId: string;
  apiVersion: string;
}

/** One message from the user, reduced to what the bot needs. */
export interface Incoming {
  id: string;
  from: string;
  /** text: typed message. button: a tap on one of our reply buttons. other: voice, image... */
  kind: 'text' | 'button' | 'other';
  text: string;
}

/**
 * Meta signs every webhook with the app secret (X-Hub-Signature-256).
 * Anything without a valid signature is rejected.
 */
export async function verifySignature(rawBody: string, header: string | null, appSecret: string): Promise<boolean> {
  if (!header?.startsWith('sha256=') || !appSecret) return false;
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(appSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody)));
  const expected = Array.from(mac, (b) => b.toString(16).padStart(2, '0')).join('');
  const given = header.slice('sha256='.length).toLowerCase();
  if (given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}

/** Messages in a webhook body. Delivery and read receipts are ignored. */
export function parseWebhook(body: unknown): Incoming[] {
  const out: Incoming[] = [];
  // deno-lint-ignore no-explicit-any
  const b = body as any;
  for (const entry of b?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      for (const m of change?.value?.messages ?? []) {
        if (typeof m?.id !== 'string' || typeof m?.from !== 'string') continue;
        if (m.type === 'text') {
          out.push({ id: m.id, from: m.from, kind: 'text', text: String(m.text?.body ?? '') });
        } else if (m.type === 'interactive' && m.interactive?.type === 'button_reply') {
          out.push({ id: m.id, from: m.from, kind: 'button', text: String(m.interactive.button_reply?.id ?? '') });
        } else if (m.type === 'button') {
          out.push({ id: m.id, from: m.from, kind: 'button', text: String(m.button?.payload ?? m.button?.text ?? '') });
        } else {
          out.push({ id: m.id, from: m.from, kind: 'other', text: '' });
        }
      }
    }
  }
  return out;
}

export class WhatsApp {
  cfg: WhatsAppConfig;
  fetchFn: typeof fetch;

  constructor(cfg: WhatsAppConfig, fetchFn: typeof fetch = fetch) {
    this.cfg = cfg;
    this.fetchFn = fetchFn;
  }

  sendText(to: string, text: string) {
    return this.post({ recipient_type: 'individual', to, type: 'text', text: { body: text.slice(0, 4096), preview_url: false } });
  }

  /** A message with up to three reply buttons. Their ids come back as a button message. */
  async sendButtons(to: string, text: string, buttons: { id: string; title: string }[], shortText: string) {
    // The text above buttons can be at most 1024 characters.
    if (text.length > 1024) {
      await this.sendText(to, text);
      text = shortText;
    }
    return this.post({
      recipient_type: 'individual',
      to,
      type: 'interactive',
      interactive: {
        type: 'button',
        body: { text },
        action: { buttons: buttons.slice(0, 3).map((b) => ({ type: 'reply', reply: { id: b.id, title: b.title.slice(0, 20) } })) },
      },
    });
  }

  /** Blue ticks and "typing..." while the bot reads the message. Best effort. */
  async markRead(messageId: string) {
    try {
      await this.post({ status: 'read', message_id: messageId, typing_indicator: { type: 'text' } });
    } catch {
      // not worth failing a reply over
    }
  }

  async post(payload: Record<string, unknown>) {
    const url = `https://graph.facebook.com/${this.cfg.apiVersion}/${this.cfg.phoneNumberId}/messages`;
    const res = await this.fetchFn(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${this.cfg.token}` },
      body: JSON.stringify({ messaging_product: 'whatsapp', ...payload }),
    });
    if (!res.ok) throw new Error(`WhatsApp ${res.status}: ${(await res.text()).slice(0, 300)}`);
  }
}
