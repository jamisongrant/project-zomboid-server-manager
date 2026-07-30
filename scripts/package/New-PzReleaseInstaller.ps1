param(
    [string]$OutputDir = 'C:\src\project-zomboid-server\dist'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageResult = & (Join-Path $PSScriptRoot 'New-PzReleasePackage.ps1') -OutputDir $OutputDir
$packagePath = Resolve-Path -LiteralPath $packageResult.Package
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$payloadRoot = Join-Path $OutputDir "installer-payload-${stamp}"
$installerPath = Join-Path $OutputDir "PzManagerSetup-${stamp}.exe"
$sedPath = Join-Path $payloadRoot 'PzManagerSetup.sed'

if ($null -eq (Get-Command iexpress.exe -ErrorAction SilentlyContinue)) {
    throw 'iexpress.exe was not found. Build the release zip instead, or run this on Windows.'
}

if (Test-Path -LiteralPath $payloadRoot) {
    Remove-Item -LiteralPath $payloadRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null

Copy-Item -LiteralPath $packagePath.Path -Destination (Join-Path $payloadRoot 'pz-manager.zip') -Force

Set-Content -LiteralPath (Join-Path $payloadRoot 'PzManager-Setup.cmd') -Encoding ASCII -Value @'
@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0PzManager-Setup.ps1" -PackageZip "%~dp0pz-manager.zip"
if errorlevel 1 (
  echo.
  echo Project Zomboid Server Manager setup failed.
  echo.
  pause
)
'@

Set-Content -LiteralPath (Join-Path $payloadRoot 'PzManager-Setup.ps1') -Encoding ASCII -Value @'
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms

$defaultParent = 'C:\src'
if (-not (Test-Path -LiteralPath $defaultParent)) {
    New-Item -ItemType Directory -Path $defaultParent -Force | Out-Null
}

$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = 'Choose where to install Project Zomboid Server Manager.'
$dialog.SelectedPath = $defaultParent
$dialog.ShowNewFolderButton = $true

if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    exit 0
}

$selectedPath = $dialog.SelectedPath
if ([System.IO.Path]::GetFileName($selectedPath) -ieq 'project-zomboid-server-manager') {
    $installDir = $selectedPath
} else {
    $installDir = Join-Path $selectedPath 'project-zomboid-server-manager'
}

if ((Test-Path -LiteralPath $installDir) -and
    @(Get-ChildItem -LiteralPath $installDir -Force -ErrorAction SilentlyContinue).Count -gt 0) {
    $choice = [System.Windows.Forms.MessageBox]::Show(
        "Install folder already exists:`n`n$installDir`n`nUpdate files in this folder?",
        'Project Zomboid Server Manager',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
        exit 0
    }
}

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Expand-Archive -LiteralPath $PackageZip -DestinationPath $installDir -Force

$launcher = Join-Path $installDir 'INSTALL-FIRST.cmd'
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Installer did not find INSTALL-FIRST.cmd after extraction: $launcher"
}

[System.Windows.Forms.MessageBox]::Show(
    "Installed to:`n`n$installDir`n`nThe setup wizard will open next.",
    'Project Zomboid Server Manager',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null

Start-Process -FilePath $launcher -WorkingDirectory $installDir
'@

$escapedPayloadRoot = $payloadRoot.Replace('\', '\\')
$escapedInstallerPath = $installerPath.Replace('\', '\\')

Set-Content -LiteralPath $sedPath -Encoding ASCII -Value @"
[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$escapedInstallerPath
FriendlyName=Project Zomboid Server Manager Setup
AppLaunched=PzManager-Setup.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles

[Strings]
FILE0="pz-manager.zip"
FILE1="PzManager-Setup.cmd"
FILE2="PzManager-Setup.ps1"

[SourceFiles]
SourceFiles0=$escapedPayloadRoot

[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@

& iexpress.exe /N /Q $sedPath
$exitCodeVariable = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
if ($null -ne $exitCodeVariable -and $exitCodeVariable.Value -ne 0) {
    throw "iexpress.exe exited with code $($exitCodeVariable.Value)."
}
for ($attempt = 0; $attempt -lt 20 -and -not (Test-Path -LiteralPath $installerPath); $attempt++) {
    Start-Sleep -Milliseconds 250
}
if (-not (Test-Path -LiteralPath $installerPath)) {
    throw "Installer was not created: $installerPath"
}

[pscustomobject]@{
    Installer = $installerPath
    Package = $packagePath.Path
    Payload = $payloadRoot
}
