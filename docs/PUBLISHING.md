# RubyGems publication

`publish-rubygems.yml` is a manual, main-branch-only workflow for a tested version tag. It checks the exact tag's successful CI, gem identity/version and package contents before requesting a short-lived registry credential. No permanent API key is stored in the repository.

For the first `lunixi-sdk` release, sign in with the intended confirmed RubyGems account and configure its pending trusted publisher. The account must satisfy the registry MFA requirement and becomes the gem's initial owner.

| Setting | Value |
| --- | --- |
| Gem | `lunixi-sdk` |
| Repository owner / repository | `Lunixi-Payment` / `lunixi-ruby` |
| Workflow filename | `publish-rubygems.yml` |
| Environment | `release` |
| Reusable workflow fields | Blank |

The account owner must review and authorize this package-specific publishing delegation. The workflow alone does not create the publisher or publish a gem. After authorization, run it from `main` with version `0.1.1`; it refuses a version that already exists. Verify the resulting version and downloaded gem digest from RubyGems.

The build does not repeat the functional suite. Ephemeral runner credentials are removed after the upload.

- [Trusted Publishing and pending publishers](https://guides.rubygems.org/trusted-publishing/)
- [RubyGems publishing](https://guides.rubygems.org/publishing/)
