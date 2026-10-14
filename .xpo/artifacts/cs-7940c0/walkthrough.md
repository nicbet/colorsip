# Walkthrough: stable local signing

## The problem
macOS privacy grants (TCC: Screen Recording, Accessibility) are stored against the app's *designated requirement* (DR). An ad-hoc signed app (`CODE_SIGN_IDENTITY = -`) has a DR of `cdhash H"…"`, which is a hash of the binary, so every rebuild (and every worktree's build) is a "different app" to TCC. System Settings still shows Colorsip as enabled because that list is keyed by bundle ID, which is why the bug was confusing.

Signing with a real certificate changes the DR to `identifier "com.nicolas-bettenburg.colorsip" and certificate leaf = H"…"`. That depends only on the bundle ID and the certificate, so it stays the same across rebuilds and worktrees.

## Pieces
- **`scripts/create-signing-cert.sh`** (`make signing-cert`): creates a self-signed "Colorsip Local Signing" certificate. Key details:
  - Uses `/usr/bin/openssl` (LibreSSL) on purpose. A Homebrew OpenSSL 3 produces PKCS#12 files with AES encryption that `security import` can't read.
  - Imports into the login keychain with `-T /usr/bin/codesign` so codesign may use the key. macOS may still ask once ("Always Allow").
  - `security add-trusted-cert -p codeSign` trusts it **for code signing only**. Without trust, `find-identity -v` reports `CSSMERR_TP_NOT_TRUSTED` and Xcode won't use it. This step asks for the user's password.
  - Idempotent: if the identity exists it only rewrites `Config/Signing.local.xcconfig`.
- **`Config/Signing.xcconfig`** (tracked, base config of the app target): defaults `COLORSIP_SIGNING_IDENTITY = -`, optionally includes the untracked `Signing.local.xcconfig`, then sets `CODE_SIGN_IDENTITY = $(COLORSIP_SIGNING_IDENTITY)`. The target-level `CODE_SIGN_IDENTITY` was removed from the pbxproj, because target settings override the base xcconfig. This is what makes Xcode ⌘R use the certificate.
- **`Makefile`**: at parse time checks the keychain for the identity. If it's there, `build` passes `COLORSIP_SIGNING_IDENTITY=…`. This matters for xpo worktrees, which never contain the untracked local xcconfig. If not, it prints a hint and builds ad hoc, so CI and fresh clones still work.
- **README**: "Keep permissions across rebuilds" section with the one-time setup and reset.

## Decision that came out of review
The first version passed `CODE_SIGN_IDENTITY` on the xcodebuild command line. Command-line build settings apply to **every** target, including the SPM-generated `ColorsipCore_ColorsipCore` resource bundle, which then failed with "requires a development team". The fix is the indirection through the custom `COLORSIP_SIGNING_IDENTITY` setting: it is global, but only the app target's xcconfig reads it. Don't "simplify" this back to `CODE_SIGN_IDENTITY`.

## Verification
Not unit-testable. Verified by hand: ad-hoc fallback builds (cdhash DR), two signed rebuilds produced the same certificate-leaf DR, and the user confirmed grants survive repeated builds after one `make reset-permissions`.
