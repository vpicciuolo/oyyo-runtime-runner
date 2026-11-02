param([string]$InstallDir=(Join-Path $env:LOCALAPPDATA 'OYYO\runtime'),[switch]$Preview,[switch]$Update,[string]$CurrentInstallDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
trap { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'OYYO installation',0,16) | Out-Null; break }

$ProgressPreference='SilentlyContinue'
if(-not [Environment]::Is64BitOperatingSystem){throw 'OYYO requires Windows x64.'}
$Manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
$NodeCommand=Get-Command node -ErrorAction SilentlyContinue
$NodeBin=if($NodeCommand){$NodeCommand.Source}else{Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'}
if(-not(Test-Path -LiteralPath $NodeBin)){throw 'Install and open Codex first. OYYO needs its local Node runtime or Node.js 22 or later.'}
$NodeMajor=[int]((& $NodeBin --version).TrimStart('v').Split('.')[0]);if($NodeMajor -lt 22){throw 'Node.js 22 or later is required.'}
$PreviousConfig=$null
if($Update){
 if(-not $CurrentInstallDirectory){throw 'The current OYYO installation was not identified.'}
 $ConfigPath=Join-Path $CurrentInstallDirectory 'plugins\oyyo\config.local.json'
 if(-not(Test-Path -LiteralPath $ConfigPath)){throw 'The current OYYO settings were not found. Update stopped to protect your data.'}
 $PreviousConfig=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
 if(-not $PreviousConfig.dataDir){throw 'The existing OYYO data directory is missing from its settings.'}
 if($Manifest.version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid update version.'}
 $InstallDir=Join-Path $env:LOCALAPPDATA ('OYYO\versions\'+$Manifest.version+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
}
$Existing=Join-Path $InstallDir 'Install-OYYO.ps1'
if((Test-Path -LiteralPath $Existing) -and -not $Preview){Start-Process -FilePath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'OYYO.lnk');return}
$Url=[uri]$Manifest.url
if($Url.Scheme -ne 'https' -or $Url.Host -ne 'github.com' -or -not $Url.AbsolutePath.StartsWith('/vpicciuolo/oyyo-runtime-runner/releases/download/')){throw 'Unexpected package source.'}
$Form=New-Object Windows.Forms.Form
$Form.Text=if($Preview){'OYYO installer preview'}elseif($Update){'Update OYYO'}else{'Install OYYO'}
$Form.ClientSize=New-Object Drawing.Size(520,365)
$Form.StartPosition='CenterScreen';$Form.FormBorderStyle='FixedDialog';$Form.MaximizeBox=$false;$Form.MinimizeBox=$false
$Form.BackColor=[Drawing.Color]::FromArgb(25,28,32);$Form.ForeColor=[Drawing.Color]::White
$Form.Font=New-Object Drawing.Font('Segoe UI',10)
$IconFile=Join-Path $PSScriptRoot 'oyyo.ico';if(Test-Path -LiteralPath $IconFile){$Form.Icon=New-Object Drawing.Icon($IconFile)}
$Title=New-Object Windows.Forms.Label;$Title.Text='Your OYYO workspace, ready in a few steps.';$Title.Location=New-Object Drawing.Point(24,22);$Title.Size=New-Object Drawing.Size(470,48);$Title.Font=New-Object Drawing.Font('Segoe UI',16);$Form.Controls.Add($Title)
$Hint=New-Object Windows.Forms.Label;$Hint.Text=if($Update){'Enter your demo key to update. Your models, chats, memory and settings will stay in their existing data folder.'}else{'Enter your demo key. OYYO handles the installation and adds Desktop and Start menu shortcuts.'};$Hint.Location=New-Object Drawing.Point(24,82);$Hint.Size=New-Object Drawing.Size(470,46);$Form.Controls.Add($Hint)
$KeyBox=New-Object Windows.Forms.TextBox;$KeyBox.UseSystemPasswordChar=$true;$KeyBox.MaxLength=64;$KeyBox.Location=New-Object Drawing.Point(24,140);$KeyBox.Size=New-Object Drawing.Size(470,30);$KeyBox.AccessibleName='OYYO demo key';$Form.Controls.Add($KeyBox)
$Privacy=New-Object Windows.Forms.Label;$Privacy.Text='64 characters. Your key stays on this computer and is not sent to GitHub.';$Privacy.Location=New-Object Drawing.Point(24,178);$Privacy.Size=New-Object Drawing.Size(470,35);$Privacy.ForeColor=[Drawing.Color]::Silver;$Form.Controls.Add($Privacy)
$Consent=New-Object Windows.Forms.CheckBox;$Consent.Text='Allow an OYYO-only script exception for the shortcuts. No system-wide security setting changes.';$Consent.Location=New-Object Drawing.Point(24,220);$Consent.Size=New-Object Drawing.Size(470,48);$Consent.Checked=$false;$Form.Controls.Add($Consent)
$Install=New-Object Windows.Forms.Button;$Install.Text=if($Preview){'Preview only'}elseif($Update){'Update OYYO'}else{'Install OYYO'};$Install.Location=New-Object Drawing.Point(330,292);$Install.Size=New-Object Drawing.Size(164,44);$Install.Enabled=$false;$Install.DialogResult='OK';$Form.Controls.Add($Install)
$Cancel=New-Object Windows.Forms.Button;$Cancel.Text='Cancel';$Cancel.Location=New-Object Drawing.Point(210,292);$Cancel.Size=New-Object Drawing.Size(108,44);$Cancel.DialogResult='Cancel';$Form.Controls.Add($Cancel)
$KeyBox.Add_TextChanged({$Install.Enabled=($KeyBox.Text -match '^[a-fA-F0-9]{64}$') -and $Consent.Checked})
$Consent.Add_CheckedChanged({$Install.Enabled=($KeyBox.Text -match '^[a-fA-F0-9]{64}$') -and $Consent.Checked})
$Install.ForeColor=[Drawing.Color]::Black;$Install.BackColor=[Drawing.Color]::FromArgb(182,240,215);$Install.UseVisualStyleBackColor=$false
$Cancel.ForeColor=[Drawing.Color]::Black
$Form.AcceptButton=$Install;$Form.CancelButton=$Cancel
$Result=$Form.ShowDialog()
if($Result -ne 'OK' -or $Preview){$KeyBox.Clear();$Form.Dispose();return}
$DemoKey=ConvertTo-SecureString -String $KeyBox.Text -AsPlainText -Force
$AllowLauncherException=$Consent.Checked;$KeyBox.Clear();$Form.Dispose()
$ProgressForm=New-Object Windows.Forms.Form;$ProgressForm.Text='Installing OYYO';$ProgressForm.ClientSize=New-Object Drawing.Size(440,120);$ProgressForm.StartPosition='CenterScreen';$ProgressForm.ControlBox=$false
$Status=New-Object Windows.Forms.Label;$Status.Text='Downloading and checking your OYYO package...';$Status.Location=New-Object Drawing.Point(20,20);$Status.Size=New-Object Drawing.Size(400,35);$ProgressForm.Controls.Add($Status)
$Bar=New-Object Windows.Forms.ProgressBar;$Bar.Location=New-Object Drawing.Point(20,65);$Bar.Size=New-Object Drawing.Size(400,22);$ProgressForm.Controls.Add($Bar)
$ProgressForm.Show();[Windows.Forms.Application]::DoEvents()
$TempRoot=Join-Path ([IO.Path]::GetTempPath()) ('oyyo-install-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempRoot | Out-Null
try {
 $Encrypted=Join-Path $TempRoot 'package.oyyo'
 $Archive=Join-Path $TempRoot 'package.zip'
 Write-Host 'Downloading the encrypted OYYO package...'
 $Curl=Join-Path $env:WINDIR 'System32\curl.exe'
 $Download=Start-Process -FilePath $Curl -ArgumentList @('--location','--fail','--retry','2','--connect-timeout','20','--output',('"'+$Encrypted+'"'),('"'+$Manifest.url+'"')) -PassThru -WindowStyle Hidden
 while(-not $Download.HasExited){if(Test-Path -LiteralPath $Encrypted){$Bar.Value=[Math]::Min(99,[int]((Get-Item -LiteralPath $Encrypted).Length*100/$Manifest.sizeBytes))};[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100}
 $Download.WaitForExit();if($Download.ExitCode -ne 0){throw 'The download failed. Check your connection and reopen the installer.'}
 $Status.Text='Checking your key and installing OYYO...';$Bar.Value=100;[Windows.Forms.Application]::DoEvents()
 if((Get-FileHash -LiteralPath $Encrypted -Algorithm SHA256).Hash.ToLower() -ne $Manifest.sha256){throw 'Package checksum mismatch. Installation stopped.'}
 $Pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($DemoKey)
 try{$env:OYYO_DEMO_KEY=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer);& $NodeBin (Join-Path $PSScriptRoot 'decrypt.mjs') $Encrypted $Archive $Manifest.sha256;$DecryptExit=$LASTEXITCODE}
 finally{Remove-Item Env:OYYO_DEMO_KEY -ErrorAction SilentlyContinue;[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer);$DemoKey.Dispose()}
 if($DecryptExit -ne 0){throw 'Demo-key verification failed. Nothing was installed.'}
 New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
 Expand-Archive -LiteralPath $Archive -DestinationPath $InstallDir
 if($Update){& (Join-Path $InstallDir 'Install-OYYO.ps1') -AllowLauncherException:$AllowLauncherException -DataDir $PreviousConfig.dataDir -ExistingConfig $ConfigPath}
 else{& (Join-Path $InstallDir 'Install-OYYO.ps1') -AllowLauncherException:$AllowLauncherException}
 if(-not $?){throw 'OYYO was extracted but registration did not complete. Review the error above.'}
 $ProgressForm.Close()
 if($Update){[Windows.Forms.MessageBox]::Show('The update is installed. OYYO will switch to it when no work is running. Your previous application files and data were retained. If Codex still uses the previous plugin, restart Codex.','OYYO update ready') | Out-Null;Start-Process -FilePath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'OYYO.lnk')}
 else{Start-Process -FilePath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'OYYO.lnk')}
}finally{
 if($ProgressForm){$ProgressForm.Dispose()}
 # Only remove this installer-created temporary directory, never the installation or user data.
 $Resolved=[IO.Path]::GetFullPath($TempRoot)
 $Allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($Resolved.StartsWith($Allowed,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($Resolved).StartsWith('oyyo-install-')){Remove-Item -LiteralPath $Resolved -Recurse -Force -ErrorAction SilentlyContinue}
}
