# Changelog

## 1.2.0 — 2026-11-12

- Document the optional `basketItems[].productCategory` field of the `create_intent` body: the Lunixi product category code, used by payment methods with legal installment limits (e.g. shopping loan) and other platform features. The body is sent unchanged; leaving it out keeps today's behaviour, and the gateway answers an unknown code with 400.
- `Lunixi::ProductCategory`: the 40 product category codes as frozen string constants (e.g. `Lunixi::ProductCategory::MOBILE_PHONE`) and the frozen `Lunixi::ProductCategory::ALL` in dictionary order. The list only grows by appending; values are not checked against it before sending.

## 1.1.0 — 2026-11-04

- Document the optional `enabledInstallments` field of the `create_intent` body: the installment counts the hosted form may offer for one payment (`[1]` = single payment only). It only narrows the panel settings, the card and the platform maximum; leaving it out means no restriction. The body is sent unchanged; send distinct integers 1–36 that include 1, in ascending order (the gateway answers any other list with 400).

## 1.0.1 — 2026-11-01

- Align Rails sample API mocks and expectations with canonical minor-unit strings while preserving numeric-input rejection tests; runtime admission is unchanged.
- Preserve response parsing limits and error handling in a private helper; close RuboCop findings without suppressions.
- Update 1.0.1 installation and exact-tag publishing guidance.

## 1.0.0 — 2026-11-01

- Reject explicit null capture/refund amounts; full remaining operations use omission or the dedicated API described in MIGRATION-1.0.md.

- Breaking: public money request/response fields require canonical minor-unit strings; JSON numbers are rejected.
- Exact signed 64-bit fiat arithmetic and currency-aware decimal text conversion preserve values above JavaScript’s safe-integer limit.
- See [MIGRATION-1.0.md](MIGRATION-1.0.md) before upgrading.


## 0.1.2 — 2026-10-31

- Add strict backend payment-page URL and official embedded-form configuration helpers, without rebuilding hosted URLs from tokens.
- Default the Rails example to an on-site CDN-mounted form with escaped JSON, nonce CSP and optional explicit hosted mode.
- Freeze and encrypt request/mode before network dispatch, cache encrypted backend URLs, retain original uncertain keys/bodies and fence replay at 23 hours.
- Add an explicit migration preserving pre-existing orders as legacy hosted attempts; unknown legacy requests or missing URLs require reconciliation rather than a new charge.
- Preserve nonce CSP while allowing exact operator-approved HTTPS form-action origins for provider/legacy POSTs; reject unsafe origin configuration before use.


## 0.1.1 — 2026-10-31

- Add a bounded stateless Rails POST return adapter before parameter/session processing. It ignores gateway browser fields and redirects to the existing authenticated GET; checkout CSRF remains required.
- Add cross-site, empty-body, oversize and session-resume integration regressions. Browser returns never mark an order paid.

## 0.1.0 — 2026-10-31

- Initial server-side Ruby SDK: OpenSSL Ed25519 signing, JavaScript-compatible compact JSON, concurrent token cache and bounded HTTPS transport.
- Payment intent/status/list/methods/capture/refund/void/split helpers and fraud decision/event helpers.
- Caller-owned persistent idempotency keys, safe same-key retries, safe typed errors and redirect/path injection protection.
- Raw-body v2 webhooks with timestamp validation, rotation, constant-time comparison and a transactional replay-store contract.
- Executable Rails 8.1 reference integration with encrypted checkout tokens, CSRF, EN/TR UI and atomic database webhook handling.
- Offline cryptographic, transport/TLS and Rails integration tests; lint, dependency audit, Rails security scanning and CI.
- English and Turkish SDK/Rails guides. Source distribution; RubyGems publication is a separate release step.
