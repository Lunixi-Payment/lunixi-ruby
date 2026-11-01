# Contributing

Use Ruby 3.3+ and Bundler. Run `bundle install`, then the validation commands in README.md. Node.js is needed for independent JSON.stringify compatibility tests. Use only synthetic credentials and local TLS fixtures in automated tests.

Keep the SDK framework independent and the Rails layer thin. Preserve canonical minor-unit strings, exact canonical bytes, persistent idempotency keys, raw-body webhook authentication, transactional deduplication and fail-closed reconciliation. Add a regression test for changed financial or security behavior. Do not add undocumented gateway endpoints or pretend an unimplemented service has typed coverage.

All buyer-facing sample strings belong in English and Turkish locale files. Keep README.md, README.tr.md, docs guides and the changelog consistent. Use the supplied Lunixi logo; the MIT code license does not grant separate trademark rights.

Before opening a pull request, run tests, RuboCop, bundler-audit, Brakeman and `gem build lunixi-sdk.gemspec`. Never commit `.env`, private key files, local databases, vendor bundles or audit output containing application data. Report vulnerabilities privately as described in SECURITY.md.
