# Gaming Café Management System

A lightweight, web-based system to run a 10-PC gaming café — replacing PanCafe, with the specific goal of **deterring staff from pocketing unrecorded revenue**, while installing **nothing** on the gaming machines.

---

## Background & why this exists

The café ran from 2017–2022. A handwritten ledger failed because staff could simply not record a session and pocket the cash. PanCafe helped — but it required a dedicated server PC plus a heavy client installed on every gaming machine, which was costly and slowed the PCs down.

This system keeps PanCafe's useful part (knowing what happened on each PC) while removing its weaknesses: no dedicated server, and **zero software on the ten gaming PCs**.

---

## Core principles (locked)

1. **Deterrence-first, not enforcement.** v1 does not try to technically *catch* every theft. It makes stealing harder and riskier through record completeness, owner visibility, and immutable logs. (A network-watcher device to *detect* unlogged PC use is a possible v1.5 upgrade, not now.)
2. **Zero install on the ten gaming PCs.** Hard constraint. Staff and owner use a web app in a browser. The gaming machines are never touched.
3. **No dedicated on-site server.** Everything runs in the cloud (Supabase free tier) and is reached by a web link.
4. **Cost = ₹0 for v1.** Free tiers only.
5. **Cashier controls the session clock.** With nothing on the PCs, the cashier starts/stops sessions. The design accounts for this trust gap rather than pretending it away.
6. **Records are append-only.** Nothing is ever deleted. Corrections happen through approved, logged adjustments.

---

## What's IN v1 vs later

**In v1:** session tracking (start/stop, per-PC), switching a customer between PCs within one visit, "PC busy" validation, walk-in cash/UPI billing, cashier shift cash count, owner remote view, immutable log.

**Later phases:** member prepaid wallets (advance / outstanding balances), petty cash & remittance approvals, richer reports, optional member self-view, optional network-watcher.

**Deliberately dropped:** POS / food-and-drink sales (service-only business). Full double-entry accounting (a simpler cash ledger is enough for now; double-entry can layer on later if ever needed).

---

## Members vs walk-ins (important design rule)

Time and money are tracked **separately**.

- **Every session** records usage: who, which PC(s), how long. This powers the floor view, PC switching, and the busy/free validation.
- **Only walk-in sessions** carry an amount and a payment. Walk-ins pay per visit.
- **Members do not have per-session revenue.** They may be in advance or carry an outstanding balance, so per-session billing makes no sense for them. Their money lives in their account balance, handled in a later phase.

So: members = usage record only. Walk-ins = usage record + payment.

---

## PC switching within a session

A session represents a customer's **visit**, not a single PC. Within a visit, time is logged in **segments** — each segment is a stretch on one PC. Moving from PC-01 to PC-02 closes the PC-01 segment and opens a PC-02 segment, in the same session. Total time = sum of segments.

**Busy/free is computed, never stored.** A PC is "busy" whenever it has an open segment (one with no end time). This is the single source of truth.

**Validation:** you cannot start a session on, or switch onto, a PC that currently has an open segment. This guarantees one live session per machine.

---

## Payments & anti-theft model (honest version)

- **UPI (~80% of payments):** customer pays directly to the **owner's UPI ID** (a fixed QR shown at each PC). This money never touches the cashier, so it is inherently safe from cashier theft. The customer declares the payment in the system (no login needed — it's just a claim); the **owner approves** it against what actually landed in his account. This also catches the "cashier gives customer his own UPI ID" scam, because a payment that isn't in the owner's account can't be approved.
- **Cash (~20%, members or one-time customers):** the theft-vulnerable channel. Governed by the **cashier shift count**: opening float → expected cash (from recorded cash sales) → counted cash → variance. A shortage surfaces at shift close.
- **Honest limits:** deterrence has a ceiling. A fully anonymous cash walk-in who refuses a receipt and is never entered into the system can still be missed. Closing that last gap requires the network-watcher device (later), not software on the PCs.

**No OTP / SMS in v1.** Not needed: the owner's approval is the security gate, not customer login. (WhatsApp OTP at ~₹0.13/msg is a cheap future option if proper member self-service accounts are ever wanted.)

---

## Architecture

```
Gaming PCs (10)        →  nothing installed; untouched
Cashier (counter PC)   →  web app in a browser
Owner (phone)          →  same web app, remote, anytime
        │
        ▼
   Web app (HTML/JavaScript, hosted free on a static host)
        │
        ▼
   Supabase (free tier): PostgreSQL database + Auth + auto APIs
```

- **Database / backend / login:** Supabase free tier (standard Postgres, **not** OrioleDB).
- **Security:** Row Level Security (RLS) is **ON** for every table. The public API key ships in the browser by design, so RLS — not the interface — is what actually protects the data. Money-touching actions live in server-side logic, never trusted to the browser.
- **Front end:** plain HTML/JavaScript, hosted free (e.g. Cloudflare Pages / Netlify / Vercel).

---

## Data model (v1)

- **pcs** — the ten machines (roster only; busy/free is computed).
- **sessions** — one row per visit (member or walk-in; start/end).
- **session_segments** — each stretch of time on one PC within a visit; switching adds a segment.
- *(later)* customers, wallet/ledger, payments, shifts, cash movements, audit log.

---

## Build order

1. **Session tracker** — pcs, sessions, segments; start/stop; switching; busy/free validation; floor view. ← current phase
2. **Cash & payments** — walk-in billing, UPI declaration + owner approval, shift cash count.
3. **Members & wallet** — accounts, advance/outstanding balances.
4. **Petty cash, remittance, reports, polish** — approvals, owner reports, staff PIN.

---

## Open items to decide

- Owner UPI ID to design the payment/QR flow around.
- Which free static host for the front end.
- Member wallet mechanics (how advance/outstanding is recorded and shown).
- A free daily database export for backup (the Supabase free tier keeps **no** backups).

---

## Security notes (read before committing anything)

- **Never commit secrets to this repo:** not the database password, not the `service_role` key, not any connection string. Keep this repo **private** regardless.
- The Supabase **anon/public** key is designed to be public and is safe in front-end code, but keeping the repo private is still the right default for a business project.
- Every table gets RLS enabled plus explicit access policies. A brand-new table returning "no rows" usually means its policy hasn't been added yet — that's the lock working, not a bug.
