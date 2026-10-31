# Security policy

Report suspected vulnerabilities privately to **developer@lunixi.com**. Include affected version, reproducible synthetic inputs, expected/actual behavior and impact. Do not send private keys, access/checkout tokens, PAN/CVV or customer information. Do not post exploitable details publicly before coordination.

Security fixes target the latest released version. Review CHANGELOG.md and dependency advisories before deployment. Version 0.1.0 is the initial source release; it is not a claim of certification or a live merchant acceptance test.

## Integration guarantees and responsibilities

- OpenSSL provides Ed25519, HMAC-SHA256, TLS verification and constant-time comparison. No custom curve implementation exists.
- SDK HTTP redirects are rejected; the gateway origin must use HTTPS. Ambient proxy configuration is not inherited. Use an injected transport for a reviewed enterprise proxy, retaining TLS/hostname verification and redirect restrictions.
- Persist one idempotency key per financial operation before the first request; reuse it after uncertain outcomes. SDK retries never create a replacement key.
- Webhooks must be verified over raw bytes. Commit event receipts and payment changes together, and roll back both on failure. Retain receipts according to the gateway's redelivery/reconciliation policy; never blindly prune them at the timestamp-tolerance boundary.
- Reconcile order/intent identity, amount, currency and final status. Browser returns, pending/unknown split states, or successful token creation are insufficient for fulfillment.
- Never log credentials, raw request/response/webhook bodies, card data or customer PII. SDK errors omit payloads. Application logging must preserve this boundary.
- The Rails example disables request info logging because Rails includes redirect destinations in those logs. Checkout tokens are encrypted at rest. Demo HTTP Basic authentication is not a customer authorization system; integrate your own session/tenant/order authorization before deployment.
- The fixed-origin hosted redirect produces one weak Brakeman warning. Its precise fingerprint, rationale and injection tests are recorded in samples/rails/config/brakeman.ignore. No security category is globally disabled.

## Required checks

Run `bundle exec rake test`, `bundle exec rake rails:test`, `bundle exec rubocop`, `bundle exec bundle-audit check --update`, and `bundle exec brakeman --force --rails8 --path samples/rails --no-pager`. CI runs all checks with synthetic credentials. Live TEST-merchant acceptance and credentials provisioning are separate operational checks; automated tests move no money.
