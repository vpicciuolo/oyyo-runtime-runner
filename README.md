# OYYO Runtime Runner — Windows demo

Install a single-user OYYO local workspace through Codex. A valid tester demo key is required to decrypt the release before installation.

## Install with Codex

Paste this into Codex:

> Install OYYO from https://github.com/vpicciuolo/oyyo-runtime-runner. Follow its Windows installation instructions and open the local secure key prompt so I can enter my tester demo key. Do not ask me to paste the key into chat or save it in a file.

Codex should clone this repository, inspect `Install-OYYO.ps1` and `decrypt.mjs`, and launch the installer in an interactive PowerShell window:

```powershell
git clone https://github.com/vpicciuolo/oyyo-runtime-runner.git
powershell.exe -NoProfile -File .\oyyo-runtime-runner\Install-OYYO.ps1
```

Enter the key at the masked local prompt. The installer downloads the encrypted release, checks its SHA-256, authenticates and decrypts it with AES-256-GCM, extracts it under `%LOCALAPPDATA%\OYYO\runtime`, registers the OYYO Codex plugin, and creates **Desktop and Start menu shortcuts**. No valid key means no package extraction or installation. Sign in to Codex and enable OYYO if Codex requests it.

Open **OYYO** from either shortcut. It starts Codex desktop if necessary, reuses or activates the plugin through Codex, waits for the local service, then opens your default browser. Activation uses no GPT/model request. Models download separately and must pass local checks before automatic use. Keep the installation folder in place.

## Requirements and current scope

- Windows x64, Codex installed and signed in, Node.js 22+ (the existing Codex runtime can be used).
- At least 8 GB RAM for the smallest listed candidates; 16 GB or more recommended. Actual compatibility and quality are checked locally. No promise that every model works on every PC.
- Python plus pypdf, python-docx, python-pptx and reportlab for document import/export. The pilot reports missing dependencies.
- Internet for installation and model downloads. Local text inference runs on this computer; Codex requests use the user's existing Codex account and permissions.
- Includes chat, model catalog, local qualification, agent workflows, memory, document export and a Codex session bridge. Speech requires its separate local speech pack. Local image/video generation is not included; media tools depend on the selected Codex session.
- **Windows only.** macOS is not supported by this release.

## Demo key and encryption

The demo key is 64 hexadecimal ASCII characters encoding 32 random bytes (256 bits). It is not stored in this repository. It is entered locally, briefly passed to the local decryptor through the child-process environment, and not sent to GitHub or an activation server. Avoid sharing it in chats, screenshots, logs or command-line arguments.

Encryption protects the downloadable package from people without the key. **A valid key holder can inspect the decrypted installed code.** This is not DRM, tamper-proof licensing, or source protection against a licensed tester. This offline shared demo key has no expiry, per-user tracking or server-side revocation. Rotating the key protects future releases; it cannot revoke a previously downloaded package/key pair.

This is an owner-authorized demo, not a fully validated enterprise release. Third-party components retain their own licenses and notices. Proprietary OYYO materials remain copyrighted; demo access does not transfer their ownership.
