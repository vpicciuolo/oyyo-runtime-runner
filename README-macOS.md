# OYYO Runtime Runner for macOS

The macOS runner is additive. The existing Windows `release.json`, PowerShell
installer, decryptor and assets remain unchanged.

## Release state

`release-macos-arm64.json` and `release-macos-x64.json` intentionally have the
status `awaiting-production-encryption`. The installer refuses a manifest in
that state. The release owner must review the plaintext artifact in the private
repository, encrypt it outside this public repository with the existing OYYO
demo key, upload only the encrypted `.oyyo` asset, then replace the manifest's
status, SHA-256 and byte count with the exact published values.

Never commit a plaintext package, demo key, Keychain export, signing key or
test credential to this repository.

## User installation

1. Install and sign in to the Codex desktop app.
2. Download or clone this repository after the matching macOS manifest is
   marked `ready`.
3. Open `Install-OYYO.command`.
4. On the first install only, enter the existing 64-character OYYO demo key in
   the masked macOS dialog. Do not paste the key into Codex or a terminal.

The runner authenticates the encrypted package before extraction, stores the
activation in the user's login Keychain, installs versioned files under
`~/Library/Application Support/OYYO/versions`, preserves shared data under
`~/Library/Application Support/OYYO/data`, and creates the stable
`~/Applications/OYYO.app` link. Updates retrieve the activation from Keychain
without displaying the key dialog and retain older version directories for
safe rollback and running-process retirement.

The package is authenticated with the legacy cross-platform envelope contract:

- magic: `OYYOPKG1` (8 bytes)
- nonce: 12 bytes
- GCM authentication tag: 16 bytes
- ciphertext: remaining bytes
- cipher: AES-256-GCM
- AAD: `OYYO Windows demo package v1` (exact bytes; retained for compatibility)

## Maintainer verification

Run:

```sh
node --test tests/decrypt-macos.test.mjs
OYYO_TEST_USE_EPHEMERAL_KEYCHAIN=1 zsh tests/install-macos.test.zsh
```

To include the complete native package in the same first-install and keyless
update acceptance flow, provide its archive explicitly:

```sh
OYYO_TEST_USE_EPHEMERAL_KEYCHAIN=1 \
OYYO_FULL_MACOS_ARCHIVE=/absolute/path/to/oyyo-macos-arm64-0.1.10.tar.gz \
zsh tests/install-macos.test.zsh
```

The integration test creates an ephemeral encrypted fixture and an isolated,
temporary Keychain containing only a random disposable activation. It uses
temporary install/application/Desktop roots, verifies first install, keyless
update, data preservation and rollback, and deletes the test Keychain on exit.
Without the explicit ephemeral-Keychain flag, a locked login Keychain causes
the real Keychain round-trip to be reported as skipped while the guarded test
adapter exercises the remaining flow. The production path cannot select that
adapter and always uses `/usr/bin/security` and the login Keychain.
