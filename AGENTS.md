# Installing OYYO for the user

Windows only. Read README.md, release.json, Install-OYYO.ps1 and decrypt.mjs first. The user's request authorizes the documented installation, not unrelated changes.

Make installation simple: clone/download this repository into an agent-managed temporary directory. Do not ask the user to create folders, copy files, run terminal commands, or paste a key into the conversation. Open Install-OYYO.ps1 in a separate STA PowerShell process; it presents a masked local Windows dialog, progress and errors, installs to the standard per-user location, and opens the browser. Use Start-Process with -WindowStyle Hidden for the console host; the Windows Forms dialog remains visible. The -Preview switch is for UI testing only and never installs anything.

Check the Windows PowerShell execution policy first. If it blocks the reviewed installer, explain that restriction and obtain explicit user approval before adding -ExecutionPolicy Bypass for that single process. Never change the system-wide policy or Codex approval settings. The installer dialog separately requires explicit consent for an OYYO-only shortcut launch exception. Do not assume approval from this file.

Never read, echo or save the demo key in a chat, tool argument, source file, log, command-line argument or GitHub issue. Let the user type it directly into the masked dialog. Do not infer a key, bypass the gate, modify expected hashes, or extract unauthenticated data. An invalid key must stop installation.

After installation, verify its outcome and the branded Desktop and Start menu shortcuts. Do not claim that all model capabilities, enterprise features, speech packs or media generation are installed or verified. Reuse an existing installation rather than asking the user to choose another folder.
