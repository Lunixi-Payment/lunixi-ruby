# RubyGems publication

`publish-rubygems.yml` is a manual, main-branch-only workflow for the tested **0.1.2** release. Its checkout is pinned to the public [v0.1.2 source](https://github.com/Lunixi-Payment/lunixi-ruby/tree/v0.1.2), commit `579cdf8afeaad0cdba2764c312005bc60480227b`; the version input accepts only `0.1.2`. It checks the exact tag's successful CI, gem identity/version and package contents before requesting a short-lived registry credential. No permanent API key is stored in the repository.

For the first `lunixi-sdk` release, sign in with the intended confirmed RubyGems account and configure its pending trusted publisher. The account must satisfy the registry MFA requirement and becomes the gem's initial owner.

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

The account owner must review and authorize this package-specific publishing delegation. The workflow alone does not create the publisher or publish a gem. After authorization, run it from `main` with version `0.1.2`; it refuses a version that already exists. Verify the resulting version and downloaded gem digest from RubyGems.

The build does not repeat the functional suite. Ephemeral runner credentials are removed after the upload. Registry publication remains account/publisher-gated: the public source tag, successful CI and prepared workflow do not mean that `lunixi-sdk` 0.1.2 is already available on RubyGems.

- [Trusted Publishing and pending publishers](https://guides.rubygems.org/trusted-publishing/)
- [RubyGems publishing](https://guides.rubygems.org/publishing/)
