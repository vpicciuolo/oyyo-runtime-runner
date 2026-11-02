# OYYO Runtime Runner — Windows demo

Install a single-user OYYO local workspace through Codex. A valid tester demo key is required to decrypt the release before installation.

## Install with Codex

Paste this into Codex:

> Install OYYO from https://github.com/vpicciuolo/oyyo-runtime-runner. Open the OYYO key pop-up and handle installation automatically.

Codex downloads the installer to a temporary working directory and opens a small **local Windows pop-up**. Enter your tester key into the masked field, approve the OYYO-only shortcut exception, and click **Install OYYO**. No folder selection, manual file copying, or terminal key entry is needed. The key is not posted into your Codex chat.

The installer shows download progress, checks SHA-256, authenticates/decrypts the release with AES-256-GCM, installs under `%LOCALAPPDATA%\OYYO\runtime`, registers the Codex plugin, adds your branded Desktop and Start menu shortcuts, and opens OYYO. Invalid keys stop installation before extraction. If Codex requests plugin enablement, follow its prompt.

If Windows blocks the installer itself, Codex must obtain your permission for an exception limited to this installer process. The system-wide execution policy and Codex approval settings must not be changed.

Open **OYYO** from either shortcut afterwards. It starts Codex desktop if necessary, activates or reuses the plugin, waits for the local service, then opens your default browser. Startup uses no GPT/model request. Models download separately and must pass local checks before use.

## Requirements and current scope

- Windows x64, Codex installed and signed in, Node.js 22+ (the existing Codex runtime can be used).
- At least 8 GB RAM for the smallest listed candidates; 16 GB or more recommended. Actual compatibility and quality are checked locally. No promise that every model works on every PC.
- Python plus pypdf, python-docx, python-pptx and reportlab for document import/export. The pilot reports missing dependencies.
- Internet for installation and model downloads. Local text inference runs on this computer; Codex requests use the user's existing Codex account and permissions.
- Includes chat, model catalog, local qualification, agent workflows, memory, document export and a Codex session bridge. Speech requires its separate local speech pack. Local image/video generation is not included; media tools depend on the selected Codex session.
- **Windows only.** macOS is not supported by this release.

## Demo key and encryption

The demo key is 64 hexadecimal ASCII characters encoding 32 random bytes (256 bits). It is not stored in this repository. It is entered in the masked local pop-up, briefly passed to the local decryptor through the child-process environment, and not sent to GitHub or an activation server. Avoid sharing it in chats, screenshots, logs or command-line arguments.

Encryption protects the downloadable package from people without the key. **A valid key holder can inspect the decrypted installed code.** This is not DRM, tamper-proof licensing, or source protection against a licensed tester. This offline shared demo key has no expiry, per-user tracking or server-side revocation. Rotating the key protects future releases; it cannot revoke a previously downloaded package/key pair.

This is an owner-authorized demo, not a fully validated enterprise release. Third-party components retain their own licenses and notices. Proprietary OYYO materials remain copyrighted; demo access does not transfer their ownership.

## Updates in the installed app

Starting with v0.1.3, OYYO checks this repository's `release.json` on launch and every six hours. Settings also has **Check for updates**. A newer version shows **Update available** in the web interface. The user reviews and approves installation; no silent replacement occurs. Repository commits without a new release version do not trigger an update.

The update installer requests the demo key again, verifies and decrypts the package, installs application files alongside the previous version, preserves the existing data directory and hardware preferences, and switches the shortcuts/plugin registration. Active work blocks switching versions. Existing models, chats, memory and notes remain in their data directory. Restart Codex if its loaded plugin is still the old version. Keep the previous application folder until the update has been checked.

Publisher workflow: upload a new encrypted versioned release first, then update `release.json` with its version, exact download URL, byte count, SHA-256 and optional `notes`. Only advance the version after the release is available. Key rotation requires giving testers the new key; existing keys are never uploaded to GitHub.
