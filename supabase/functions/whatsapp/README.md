# WhatsApp bot

A Supabase Edge Function that turns WhatsApp messages into khata entries.

```
"Rashid se 500 kg 120 pe liya, 20 hazar cash diye"
        │
        ▼
🛒 *Khareed* · Rashid se
Used cloth · 500 kg × 120 = Rs 60,000
Abhi diye: Rs 20,000 · Cash
Udhaar: Rs 40,000
                     [✅ Haan, save karo] [❌ Nahi]
        │  Haan
        ▼
✅ Save ho gaya.
Rashid: Rs 40,000 dena hai
```

## How it works

| Step | File | |
|---|---|---|
| Receive | `index.ts`, `whatsapp.ts` | Checks Meta's signature, answers 200 at once, replies in the background. Downloads a voice note or photo from WhatsApp when there is one. |
| Read | `gemini.ts`, `prompt.ts` | Gemini turns the message, voice note or photo into entries with names, as JSON in a fixed schema. Its answer is never trusted as is: every field is checked and coerced. |
| Check | `resolve.ts` | Matches names to existing parties and cloth types ("Rasheed" = "Rashid"), fills today's date, and asks for anything missing instead of guessing. |
| Read back | `render.ts` | Words the entry in Roman Urdu or English from the checked data, not from model text, so what he confirms is exactly what gets saved. |
| Save | `bot_confirm()` in the database | Saves only after "haan" or the button, in one transaction, through the same functions the app uses. |

Also:

- A correction while an entry waits ("nahi, rate 125 tha") replaces it.
- **undo** reads back the last saved entry and cancels it after a yes.
- Numbers that are not linked get no reply. A message WhatsApp delivers twice is handled once.
- **Voice notes** (Urdu, Punjabi or English) are read like a typed message. The
  read-back starts with what the bot heard (`🎤 Maine suna: "..."`), so a
  mishearing is easy to spot before saying yes.
- **Photos** of a parchi, bill, register page or a bank / JazzCash / Easypaisa
  screenshot become entries, one per line. A caption adds to the photo
  ("Rashid ko bheje"). Numbers that are not written on it are never worked out.
- Voice notes and photos are passed to Gemini and not stored anywhere. Up to
  5 MB for a voice note and 10 MB for a photo; videos and documents get a
  polite "not yet".
- **Token log:** every message the model reads is logged in `bot_usage` (model,
  input, output and thinking tokens, and how many were the voice note or photo).
  See [Cost](#cost).

To use a different AI provider, replace `gemini.ts`; nothing else depends on it.

## Setup

You need a Meta developer account and a Gemini API key. Secrets go into
Supabase, never into this repository.

1. **Gemini:** create an API key at <https://aistudio.google.com/apikey>.
2. **Meta app:** at <https://developers.facebook.com/apps> create an app of type
   *Business* and add the **WhatsApp** product. Under *WhatsApp → API Setup*:
   - note the **Phone number ID** of the test number;
   - add the trader's number under *To* as an allowed recipient (the test number
     can only message up to 5 verified numbers);
   - the temporary access token expires in 24 hours. For a lasting one, create a
     *System user* in Business Settings, give it the app with
     `whatsapp_business_messaging`, and generate a token.
   - The **App secret** is under *App settings → Basic*.
3. **Secrets** (from the `supabase` folder; pick any random text for the verify token):

   ```
   npx supabase@2.120.0 secrets set WHATSAPP_TOKEN=... WHATSAPP_PHONE_NUMBER_ID=... WHATSAPP_APP_SECRET=... WHATSAPP_VERIFY_TOKEN=... GEMINI_API_KEY=...
   ```

   Optional: `GEMINI_MODEL` (default `gemini-3.8-flash`),
   `GEMINI_FALLBACK_MODELS` (used in turn when it is busy; default
   `gemini-3.6-flash,gemini-3.5-flash-lite`) and
   `WHATSAPP_API_VERSION` (default `v25.0`).
4. **Deploy:**

   ```
   npx supabase@2.120.0 db push
   npx supabase@2.120.0 functions deploy whatsapp --no-verify-jwt --use-api
   ```

5. **Webhook:** in the Meta app under *WhatsApp → Configuration*, set
   - Callback URL: `https://<project-ref>.supabase.co/functions/v1/whatsapp`
   - Verify token: the same text as `WHATSAPP_VERIFY_TOKEN`

   Then subscribe to the **messages** field.
6. **Link the trader's number** to his app login, once, in the Supabase SQL editor.
   Use the number as WhatsApp writes it: country code, no `+`, no spaces.

   ```sql
   insert into bot_senders (whatsapp, owner_id)
   select '923001234567', id from auth.users where email = 'his-login@example.com';
   ```

Logs: Supabase dashboard → *Edge Functions → whatsapp → Logs*.

## Cost

Each message is logged with its token counts. To see them per day (Pakistan
time), in the Supabase SQL editor:

```sql
select * from bot_usage_daily;
```

`est_usd` is what the day would cost on the paid Gemini plan at
`gemini-3.8-flash` prices; on the free plan it costs nothing. A voice note
uses about 32 tokens per second of audio, a photo about 258 per 768 × 768 tile.

Note: on Gemini's free plan Google may use the messages to improve its models.
Switch the API key's project to a paid plan before real business data matters.

## Tests

```
cd supabase
npm test
```

`bot.test.ts` runs the conversation with fake WhatsApp, Gemini and database.
`tests/bot.test.mjs` tests the database side on PGlite.
