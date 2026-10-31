# Changelog

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
