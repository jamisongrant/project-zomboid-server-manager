Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-FriendlyPassword {
    $bytes = New-Object byte[] 9
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return ('pz-' + [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'x').Replace('/', 'y'))
}

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SetupDefaults {
    $defaults = @{
        RuntimeRoot = 'C:\pz'
        PublicName = 'Project Zomboid Server'
        JoinPassword = (New-FriendlyPassword)
        MaxPlayers = '8'
        MemoryPreset = 'normal'
    }

    try {
        $setupJson = & .\scripts\install\Test-PzSetup.ps1 -Json | Out-String
        $setup = $setupJson | ConvertFrom-Json
        if ($null -ne $setup.defaults) {
            if (-not [string]::IsNullOrWhiteSpace($setup.defaults.runtimeRoot)) { $defaults.RuntimeRoot = [string]$setup.defaults.runtimeRoot }
            if (-not [string]::IsNullOrWhiteSpace($setup.defaults.publicName)) { $defaults.PublicName = [string]$setup.defaults.publicName }
            if (-not [string]::IsNullOrWhiteSpace($setup.defaults.joinPassword)) { $defaults.JoinPassword = [string]$setup.defaults.joinPassword }
            if ($null -ne $setup.defaults.maxPlayers) { $defaults.MaxPlayers = [string]$setup.defaults.maxPlayers }
            $memoryMax = [string]$setup.defaults.memoryMax
            if ($memoryMax -match '8192|8g') { $defaults.MemoryPreset = 'large' }
            elseif ($memoryMax -match '3072|3g') { $defaults.MemoryPreset = 'low' }
        }
    } catch {
        # Defaults are enough for first run if the setup check cannot run yet.
    }

    return $defaults
}

function Add-Label {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$Left,
        [int]$Top
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Left = $Left
    $label.Top = $Top
    $label.Width = 180
    $label.Height = 22
    $Parent.Controls.Add($label)
    return $label
}

function Add-TextBox {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$Left,
        [int]$Top,
        [int]$Width = 360
    )

    $box = New-Object System.Windows.Forms.TextBox
    $box.Text = $Text
    $box.Left = $Left
    $box.Top = $Top
    $box.Width = $Width
    $Parent.Controls.Add($box)
    return $box
}

$defaults = Get-SetupDefaults
$isAdmin = Test-IsAdministrator

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Project Zomboid Server Manager Setup'
$form.Width = 720
$form.Height = 660
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Project Zomboid Server Manager'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$title.Left = 20
$title.Top = 18
$title.Width = 660
$title.Height = 32
$form.Controls.Add($title)

$intro = New-Object System.Windows.Forms.Label
$intro.Text = 'Choose where the heavy runtime files go, pick the basic server settings, then install.'
$intro.Left = 22
$intro.Top = 54
$intro.Width = 650
$intro.Height = 24
$form.Controls.Add($intro)

Add-Label $form 'Runtime folder' 24 96 | Out-Null
$runtimeBox = Add-TextBox $form $defaults.RuntimeRoot 210 92 360
$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Browse...'
$browseButton.Left = 582
$browseButton.Top = 90
$browseButton.Width = 92
$browseButton.Height = 28
$form.Controls.Add($browseButton)

Add-Label $form 'Server display name' 24 136 | Out-Null
$nameBox = Add-TextBox $form $defaults.PublicName 210 132

Add-Label $form 'Join password' 24 176 | Out-Null
$passwordBox = Add-TextBox $form $defaults.JoinPassword 210 172 300
$passwordBox.UseSystemPasswordChar = $true
$showPassword = New-Object System.Windows.Forms.CheckBox
$showPassword.Text = 'Show'
$showPassword.Left = 522
$showPassword.Top = 174
$showPassword.Width = 80
$form.Controls.Add($showPassword)

Add-Label $form 'Max players' 24 216 | Out-Null
$playersBox = Add-TextBox $form $defaults.MaxPlayers 210 212 120

Add-Label $form 'Memory preset' 24 256 | Out-Null
$memoryBox = New-Object System.Windows.Forms.ComboBox
$memoryBox.Left = 210
$memoryBox.Top = 252
$memoryBox.Width = 180
$memoryBox.DropDownStyle = 'DropDownList'
[void]$memoryBox.Items.Add('normal')
[void]$memoryBox.Items.Add('low')
[void]$memoryBox.Items.Add('large')
$memoryBox.SelectedItem = $defaults.MemoryPreset
$form.Controls.Add($memoryBox)

$startServer = New-Object System.Windows.Forms.CheckBox
$startServer.Text = 'Start server after setup'
$startServer.Left = 210
$startServer.Top = 296
$startServer.Width = 260
$startServer.Checked = $true
$form.Controls.Add($startServer)

$reuseServer = New-Object System.Windows.Forms.CheckBox
$reuseServer.Text = 'Reuse existing server files if found'
$reuseServer.Left = 210
$reuseServer.Top = 326
$reuseServer.Width = 280
$reuseServer.Checked = $false
$form.Controls.Add($reuseServer)

$firewall = New-Object System.Windows.Forms.CheckBox
$firewall.Text = 'Install Windows Firewall rules'
$firewall.Left = 210
$firewall.Top = 356
$firewall.Width = 280
$firewall.Enabled = $isAdmin
$firewall.Checked = $isAdmin
$form.Controls.Add($firewall)

$automation = New-Object System.Windows.Forms.CheckBox
$automation.Text = 'Enable scheduled automation'
$automation.Left = 210
$automation.Top = 386
$automation.Width = 280
$automation.Enabled = $isAdmin
$automation.Checked = $isAdmin
$form.Controls.Add($automation)

$adminNote = New-Object System.Windows.Forms.Label
$adminNote.Left = 210
$adminNote.Top = 420
$adminNote.Width = 450
$adminNote.Height = 34
$adminNote.Text = if ($isAdmin) { 'Administrator mode detected. Firewall and automation can be enabled now.' } else { 'Not running as Administrator. Firewall and automation can be enabled later from the admin panel.' }
$form.Controls.Add($adminNote)

$output = New-Object System.Windows.Forms.TextBox
$output.Left = 22
$output.Top = 468
$output.Width = 652
$output.Height = 90
$output.Multiline = $true
$output.ScrollBars = 'Vertical'
$output.ReadOnly = $true
$form.Controls.Add($output)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = 'Install And Open Admin Panel'
$installButton.Left = 412
$installButton.Top = 574
$installButton.Width = 180
$installButton.Height = 34
$form.Controls.Add($installButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'Close'
$closeButton.Left = 600
$closeButton.Top = 574
$closeButton.Width = 74
$closeButton.Height = 34
$form.Controls.Add($closeButton)

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choose the folder for SteamCMD, server files, saves, logs, backups, and staging.'
    $dialog.SelectedPath = $runtimeBox.Text
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $runtimeBox.Text = $dialog.SelectedPath
    }
})

$showPassword.Add_CheckedChanged({
    $passwordBox.UseSystemPasswordChar = -not $showPassword.Checked
})

$closeButton.Add_Click({ $form.Close() })

$installButton.Add_Click({
    $runtime = $runtimeBox.Text.Trim()
    $serverName = $nameBox.Text.Trim()
    $joinPassword = $passwordBox.Text.Trim()
    $players = 8
    if (-not [int]::TryParse($playersBox.Text.Trim(), [ref]$players)) { $players = 8 }
    $players = [Math]::Min(100, [Math]::Max(1, $players))

    if ([string]::IsNullOrWhiteSpace($runtime) -or [string]::IsNullOrWhiteSpace($serverName) -or [string]::IsNullOrWhiteSpace($joinPassword)) {
        [System.Windows.Forms.MessageBox]::Show($form, 'Runtime folder, server name, and join password are required.', 'Missing setup values', 'OK', 'Warning') | Out-Null
        return
    }

    $memory = @{
        low = @('1024m', '3072m')
        normal = @('2048m', '4096m')
        large = @('4096m', '8192m')
    }[[string]$memoryBox.SelectedItem]

    $args = @{
        RuntimeRoot = $runtime
        PublicName = $serverName
        JoinPassword = $joinPassword
        MaxPlayers = $players
        MemoryMin = $memory[0]
        MemoryMax = $memory[1]
    }
    if ($startServer.Checked) { $args.StartServer = $true }
    if ($reuseServer.Checked) { $args.SkipServerInstall = $true }
    if ($firewall.Checked) { $args.InstallFirewallRules = $true }
    if ($automation.Checked) { $args.RegisterAutomation = $true }

    $installButton.Enabled = $false
    $output.Text = 'Installing. This can take several minutes on first run...'
    $form.Refresh()

    try {
        & .\scripts\install\Install-PzManager.ps1 @args *>&1 | ForEach-Object {
            $output.AppendText("`r`n$($_)")
            $form.Refresh()
        }
        $output.AppendText("`r`n`r`nInstall complete. Opening admin panel...")
        Start-Process 'http://127.0.0.1:8787/#setup'
    } catch {
        $output.AppendText("`r`n`r`nERROR: $($_.Exception.Message)")
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Install failed', 'OK', 'Error') | Out-Null
    } finally {
        $installButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
