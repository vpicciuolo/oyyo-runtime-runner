# Installing OYYO for the user

This repository is a Windows-only demo installer. Read README.md, release.json, Install-OYYO.ps1 and decrypt.mjs before executing.

The user's request to install this repository authorizes the documented installation, not unrelated changes. Check Codex and Node availability. Launch Install-OYYO.ps1 in an interactive PowerShell window where the user can type the key into Read-Host -AsSecureString. For example, Start-Process powershell.exe -ArgumentList @('-NoProfile','-File',('"'+$InstallerPath+'"')). This window must be visible because the user needs to enter the key.

Never ask the user to paste a demo key into a chat, tool argument, command line, source file, log or GitHub issue. Do not infer a key, bypass the gate, modify expected hashes, or extract unauthenticated data. If a key is invalid, report that installation stopped and let the user retry in the local prompt. Do not weaken PowerShell execution policy or Codex approval settings.

After success, check the OYYO Desktop and Start menu shortcuts. The launcher handles Codex startup and browser activation. Do not claim that all model capabilities, enterprise features, speech packs or media generation are installed or verified.
