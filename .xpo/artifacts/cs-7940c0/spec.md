# Stable local signing with a self-signed code-signing certificate

## What
Sign local builds with a self-signed certificate ("Colorsip Local Signing") in the developer's login keychain instead of ad hoc, so the app's designated requirement becomes `identifier "com.nicolas-bettenburg.colorsip" and certificate leaf = H"…"` instead of a cdhash. TCC grants then survive rebuilds and apply to builds from any worktree.

## Why
Ad-hoc signing makes the designated requirement a cdhash, which changes on every build. TCC stops honoring the Screen Recording / Accessibility grant, and the onboarding guide reappears on every launch.

## How
1. **`scripts/create-signing-cert.sh`** (run via `make signing-cert`):
   - Exits early if a valid `Colorsip Local Signing` identity already exists (`security find-identity -v -p codesigning`).
   - Generates a key + self-signed cert with `/usr/bin/openssl` (LibreSSL, so the PKCS#12 is importable by `security`): 10-year validity, `basicConstraints=critical,CA:false`, `keyUsage=critical,digitalSignature`, `extendedKeyUsage=critical,codeSigning`.
   - Imports the PKCS#12 into the login keychain with `-T /usr/bin/codesign`, using a random throwaway password; temp files live in a `mktemp -d` dir removed on exit.
   - Trusts the cert for code signing only (`security add-trusted-cert -r trustRoot -p codeSign`), which shows a macOS password prompt.
   - Writes `Config/Signing.local.xcconfig` (untracked) with `COLORSIP_SIGNING_IDENTITY = Colorsip Local Signing`.
2. **Xcode config**: new tracked `Config/Signing.xcconfig`: `COLORSIP_SIGNING_IDENTITY = -`, then `#include? "Signing.local.xcconfig"`, then `CODE_SIGN_IDENTITY = $(COLORSIP_SIGNING_IDENTITY)`. Set it as the Colorsip target's base configuration (Debug + Release) and remove the target-level `CODE_SIGN_IDENTITY = "-"` so the xcconfig wins. Xcode ⌘R then uses the cert when present, ad hoc otherwise. `.gitignore` ignores `Config/Signing.local.xcconfig`.
3. **Makefile**:
   - `build` passes `COLORSIP_SIGNING_IDENTITY="Colorsip Local Signing"` when that identity is in the keychain (so it works in fresh worktrees that lack the untracked xcconfig), else prints a one-line hint about `make signing-cert` and builds ad hoc.
   - It must not pass `CODE_SIGN_IDENTITY` directly: command-line settings apply to every target, and the ColorsipCore SPM resource bundle target then fails with "requires a development team". The custom setting is only read by the app target's xcconfig.
   - New `signing-cert` target; `help` lists it.
4. **README**: replace the "signed locally" paragraph with a "Keep permissions across rebuilds" section: run `make signing-cert` once, what it does, the one-time "codesign wants to access key → Always Allow" prompt, then `make reset-permissions` and grant once more. Keep the reset instructions for ad-hoc builds. CI is unaffected (no cert → ad hoc).

## Acceptance criteria
- `make signing-cert` creates and trusts the identity; rerunning it is a no-op (apart from rewriting the local xcconfig).
- With the cert, `make build` succeeds and `codesign -d -r- Builds/Colorsip.app` shows an `identifier … and certificate leaf = H"…"` requirement, identical across two rebuilds.
- Without the cert, `make build` and Xcode still build (ad hoc), as in CI.
- A Screen Recording grant made for one build still applies after a rebuild.
- README documents setup and the reset.

## Testing
Not unit-testable (keychain, codesign, TCC). Verified by hand: run the script, build twice, compare designated requirements, grant Screen Recording, rebuild, confirm the guide doesn't reappear.
