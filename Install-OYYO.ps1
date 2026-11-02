param([string]$InstallDir=(Join-Path $env:LOCALAPPDATA 'OYYO\runtime'))
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if(-not [Environment]::Is64BitOperatingSystem){throw 'OYYO requires Windows x64.'}
$Manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
$NodeCommand=Get-Command node -ErrorAction SilentlyContinue
$NodeBin=if($NodeCommand){$NodeCommand.Source}else{Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'}
if(-not(Test-Path -LiteralPath $NodeBin)){throw 'Install and open Codex first. OYYO needs its local Node runtime or Node.js 22 or later.'}
$NodeMajor=[int]((& $NodeBin --version).TrimStart('v').Split('.')[0]);if($NodeMajor -lt 22){throw 'Node.js 22 or later is required.'}
$Existing=Join-Path $InstallDir 'Install-OYYO.ps1'
if(Test-Path -LiteralPath $Existing){throw 'OYYO is already installed here. Use the OYYO shortcut. Choose a different InstallDir for a separate installation.'}
$Url=[uri]$Manifest.url
if($Url.Scheme -ne 'https' -or $Url.Host -ne 'github.com' -or -not $Url.AbsolutePath.StartsWith('/vpicciuolo/oyyo-runtime-runner/releases/download/')){throw 'Unexpected package source.'}
Write-Host 'OYYO Windows demo installer'
Write-Host 'Your key is requested locally and is not uploaded to GitHub.'
$DemoKey=Read-Host 'Enter your 64-character OYYO demo key' -AsSecureString
$TempRoot=Join-Path ([IO.Path]::GetTempPath()) ('oyyo-install-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempRoot | Out-Null
try {
 $Encrypted=Join-Path $TempRoot 'package.oyyo'
 $Archive=Join-Path $TempRoot 'package.zip'
 Write-Host 'Downloading the encrypted OYYO package...'
 Invoke-WebRequest -Uri $Manifest.url -OutFile $Encrypted -UseBasicParsing
 if((Get-FileHash -LiteralPath $Encrypted -Algorithm SHA256).Hash.ToLower() -ne $Manifest.sha256){throw 'Package checksum mismatch. Installation stopped.'}
 $Pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($DemoKey)
 try{$env:OYYO_DEMO_KEY=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer);& $NodeBin (Join-Path $PSScriptRoot 'decrypt.mjs') $Encrypted $Archive $Manifest.sha256;$DecryptExit=$LASTEXITCODE}
 finally{Remove-Item Env:OYYO_DEMO_KEY -ErrorAction SilentlyContinue;[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer);$DemoKey.Dispose()}
 if($DecryptExit -ne 0){throw 'Demo-key verification failed. Nothing was installed.'}
 New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
 Expand-Archive -LiteralPath $Archive -DestinationPath $InstallDir
 & (Join-Path $InstallDir 'Install-OYYO.ps1')
 if(-not $?){throw 'OYYO was extracted but registration did not complete. Review the error above.'}
 Write-Host 'Installed. Open OYYO from your Desktop or Start menu.'
}finally{
 # Only remove this installer-created temporary directory, never the installation or user data.
 $Resolved=[IO.Path]::GetFullPath($TempRoot)
 $Allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($Resolved.StartsWith($Allowed,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($Resolved).StartsWith('oyyo-install-')){Remove-Item -LiteralPath $Resolved -Recurse -Force -ErrorAction SilentlyContinue}
}
