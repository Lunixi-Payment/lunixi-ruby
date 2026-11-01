# RubyGems publication

`publish-rubygems.yml` is a manual workflow dispatched from the exact release tag. For 1.0.1, select `v1.0.1` and enter `1.0.1`. It resolves the tag to the invocation SHA, requires successful public push CI for that same commit, then checks out the immutable source. Gem identity/version and SHA-256 are verified before publishing. No permanent API key is stored in the repository.

Use the existing account-owned trusted publisher for `lunixi-sdk`. Its authorized scope is listed below; registry publication does not require creating a second publisher.

| Setting | Value |
| --- | --- |
| Gem | `lunixi-sdk` |
| Repository owner / repository | `Lunixi-Payment` / `lunixi-ruby` |
| Workflow filename | `publish-rubygems.yml` |
| Environment | `release` |
| Reusable workflow fields | Blank |

The approved initial account is asserted by immutable RubyGems **owner ID `255358`**. The exchange sends `owner` as the JSON string `"255358"`; RubyGems rejects a JSON number and resolves all-digit strings by immutable ID rather than by a reusable handle.

The released `configure-rubygems-credentials` **v2.1.0** does not expose an owner input: its [pinned action definition](https://github.com/rubygems/configure-rubygems-credentials/blob/dc5a8d8553e6ee01fc26761a49e99e733d17954a/action.yml) and [exchange implementation](https://github.com/rubygems/configure-rubygems-credentials/blob/dc5a8d8553e6ee01fc26761a49e99e733d17954a/src/oidc/trustedPublisher.ts) send only the JWT. Until an owner-capable release is reviewed, the workflow embeds a Python-standard-library exchange before its push step. It requests a GitHub ID token for audience `rubygems.org`, then POSTs only `{jwt, owner}` to the fixed HTTPS endpoint `https://rubygems.org/api/v1/oidc/trusted_publisher/exchange_token`.

The contract was checked against the [RubyGems controller at commit `5a641a1e1ac8bd37ba0b11d56b5d7ee379107f85`](https://github.com/rubygems/rubygems.org/blob/5a641a1e1ac8bd37ba0b11d56b5d7ee379107f85/app/controllers/api/v1/oidc/trusted_publisher_controller.rb) and its [owner-binding regression tests](https://github.com/rubygems/rubygems.org/blob/5a641a1e1ac8bd37ba0b11d56b5d7ee379107f85/test/integration/api/v1/oidc/trusted_publisher_controller_test.rb). The server verifies the signed OIDC claims, atomically binds the asserted owner, rejects replay of the same token, and issues a **push-only, 15-minute** credential with HTTP **201**. The workflow rejects redirects, other HTTP statuses, malformed/oversized responses, additional scopes and expiry beyond 16 minutes. It masks request/JWT/API credentials before use, exports only `GEM_HOST_API_KEY` through a mode-600 runner environment file, and never logs HTTP bodies or underlying exception details. It creates no permanent API key and does not alter the publisher's permissions.

The account owner must review and authorize this package-specific publishing delegation. The workflow alone does not create the publisher or publish a gem. For an authorized release, run it from the matching `v1.0.1` tag with version `1.0.1`; it refuses a version that already exists. Verify the resulting version and downloaded gem digest from RubyGems.

The build does not repeat the functional suite. Ephemeral runner credentials are removed after the upload.

## Verified 0.1.2 publication

The account owner authorized the exact publisher above. [Publish run 41249047391](https://github.com/Lunixi-Payment/lunixi-ruby/actions/runs/41249047391) completed successfully from workflow commit `7a4a0e7b6f647490f7f09b650847c38f0b7d3b19`, while the package checkout remained pinned to `579cdf8afeaad0cdba2764c312005bc60480227b`. The original `v0.1.2` tag is unchanged.

[RubyGems 0.1.2](https://rubygems.org/gems/lunixi-sdk/versions/0.1.2) is available with SHA-256 `c9c6386c03a3b853d56335c2f21e91f18d3450a83906d5ad15d9fc07ac1ce16f`. That historical release remains immutable. The current workflow also refuses an already published version.

The downloaded 39,424-byte archive matches the registry checksum. All 23 packaged files match both the prepared gem and the immutable release source; build metadata can differ between independently built archives.

- [Trusted Publishing and pending publishers](https://guides.rubygems.org/trusted-publishing/)
- [RubyGems publishing](https://guides.rubygems.org/publishing/)
