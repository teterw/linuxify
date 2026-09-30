# linuxify installer
#   irm https://raw.githubusercontent.com/teterw/linuxify/main/install.ps1 | iex
# Safe to re-run: it updates in place and keeps your theme settings.
# Everything is wrapped in a function so `exit`/errors never close your shell when piped into iex.

function Install-Linuxify {
    $ErrorActionPreference = 'Stop'
    $repo = 'teterw/linuxify'
    $dest = Join-Path $env:LOCALAPPDATA 'linuxify'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
    function Info($msg) { Write-Host "    $msg" }
    function Warn($msg) { Write-Host "    ! $msg" -ForegroundColor Yellow }
    function Refresh-Path {
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path', 'User')
    }
    # Runs a script in Windows PowerShell 5.1 (its PSReadLine and execution policy are separate from pwsh 7).
    # -EncodedCommand avoids 5.1's mangling of quotes in native command arguments.
    function Invoke-WinPS([string]$script) {
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$ProgressPreference = 'SilentlyContinue'`n" + $script))
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $enc
    }

    if ($env:OS -ne 'Windows_NT') { Write-Host 'linuxify is for Windows.' -ForegroundColor Red; return }

    # --- 1. Get the files (local checkout, or download from GitHub) ---
    Step 'Getting linuxify'
    $tmp = $null
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'src\core.ps1'))) {
        $src = $PSScriptRoot
        Info "from local folder $src"
    } else {
        $tmp = Join-Path $env:TEMP "linuxify-$stamp"
        New-Item -ItemType Directory -Force $tmp | Out-Null
        $zip = Join-Path $tmp 'linuxify.zip'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
        Expand-Archive $zip -DestinationPath $tmp -Force
        $src = Join-Path $tmp 'linuxify-main'
        Info "downloaded from github.com/$repo"
    }

    # --- 2. Tools: Clink (cmd), eza (ls), fastfetch ---
    Step 'Installing tools'
    Refresh-Path
    $haveWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    function Find-Clink {
        $auto = (Get-ItemProperty 'HKCU:\Software\Microsoft\Command Processor' -ErrorAction SilentlyContinue).AutoRun
        $dirs = @()
        if ($auto -match '"?([^"]*?)\\clink\.bat"?') { $dirs += $Matches[1] }
        $dirs += "${env:ProgramFiles(x86)}\clink", "$env:ProgramFiles\clink", "$env:LOCALAPPDATA\Programs\clink"
        foreach ($d in $dirs) {
            foreach ($exe in 'clink_x64.exe', 'clink_x86.exe') {
                $p = Join-Path $d $exe
                if (Test-Path $p) { return $p }
            }
        }
        $null
    }
    $tools = @(
        @{ Name = 'Clink';     Id = 'chrisant996.Clink';       Found = { [bool](Find-Clink) } },
        @{ Name = 'eza';       Id = 'eza-community.eza';       Found = { [bool](Get-Command eza -ErrorAction SilentlyContinue) } },
        @{ Name = 'fastfetch'; Id = 'Fastfetch-cli.Fastfetch'; Found = { [bool](Get-Command fastfetch -ErrorAction SilentlyContinue) } }
    )
    foreach ($t in $tools) {
        if (& $t.Found) { Info "$($t.Name): already installed"; continue }
        if (-not $haveWinget) { Warn "$($t.Name): winget not found, install '$($t.Id)' manually"; continue }
        Info "$($t.Name): installing..."
        winget install --id $t.Id -e --source winget --silent --accept-source-agreements --accept-package-agreements | Out-Null
        Refresh-Path
        if (& $t.Found) { Info "$($t.Name): installed" } else { Warn "$($t.Name): install failed (winget exit $LASTEXITCODE)" }
    }

    # PSReadLine 2.0 (bundled with Windows PowerShell 5.1) has no as-you-type suggestions
    $rlVersion = Invoke-WinPS '(Get-Module PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()'
    if ([version]$rlVersion -lt [version]'2.3') {
        Info "PSReadLine ${rlVersion}: updating (for Windows PowerShell)..."
        Invoke-WinPS @'
            try {
                if (-not (Get-PackageProvider NuGet -ListAvailable -ErrorAction SilentlyContinue | Where-Object Version -ge 2.8.5.201)) {
                    Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
                }
                Install-Module PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber -ErrorAction Stop
                'ok'
            } catch { "fail: $_" }
'@ | ForEach-Object { if ($_ -ne 'ok') { Warn "PSReadLine update skipped ($_). Colors still work, suggestions won't." } else { Info 'PSReadLine: updated' } }
    } else {
        Info "PSReadLine ${rlVersion}: ok"
    }

    # --- 3. Copy linuxify files (keep config.txt) ---
    Step "Copying files to $dest"
    New-Item -ItemType Directory -Force $dest, (Join-Path $dest 'clink') | Out-Null
    Copy-Item (Join-Path $src 'src\*') $dest -Recurse -Force
    Copy-Item (Join-Path $src 'uninstall.ps1') $dest -Force
    # Rewrite config so derived theme values match the current themes.json
    Invoke-WinPS ". '$($dest.Replace("'", "''"))\core.ps1'; Write-LxConfig (Read-LxConfig)"

    # --- 4. PowerShell profiles (5.1 and 7) ---
    Step 'Hooking into PowerShell'
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $profiles = @(Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    if ((Get-Command pwsh -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $docs 'PowerShell'))) {
        $profiles += Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
    }
    $block = @'
# >>> linuxify >>>
if (Test-Path "$env:LOCALAPPDATA\linuxify\profile.ps1") { . "$env:LOCALAPPDATA\linuxify\profile.ps1" }
# <<< linuxify <<<
'@
    $created = Join-Path $dest 'created-profiles.txt'
    foreach ($p in $profiles) {
        if (Test-Path $p) {
            $text = [IO.File]::ReadAllText($p)
            if ($text -match '(?s)# >>> linuxify >>>.*?# <<< linuxify <<<') { Info "$p (already hooked)"; continue }
            Copy-Item $p "$p.linuxify-backup-$stamp"
            Info "backed up $p"
            $text = $text.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
        } else {
            New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
            Add-Content $created $p
            $text = $block + "`r`n"
        }
        [IO.File]::WriteAllText($p, $text, (New-Object Text.UTF8Encoding $true))
        Info "hooked $p"
    }

    # Profiles don't run under the default 'Restricted' policy
    # (checked for Windows PowerShell; pwsh 7 already defaults to RemoteSigned)
    Invoke-WinPS @'
        $gpo = @((Get-ExecutionPolicy -Scope MachinePolicy), (Get-ExecutionPolicy -Scope UserPolicy)) -ne 'Undefined'
        $user = Get-ExecutionPolicy -Scope CurrentUser
        $effective = if ($user -ne 'Undefined') { $user } else { Get-ExecutionPolicy -Scope LocalMachine }
        if ($gpo) { "warn:execution policy is set by Group Policy ($gpo), profiles may not load" }
        elseif ($effective -in 'Undefined', 'Restricted', 'AllSigned') {
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            'info:execution policy for your user set to RemoteSigned (needed to load profiles)'
        }
'@ | ForEach-Object { if ($_ -like 'warn:*') { Warn $_.Substring(5) } elseif ($_ -like 'info:*') { Info $_.Substring(5) } }

    # --- 5. cmd via Clink ---
    Step 'Hooking into cmd (Clink)'
    $clink = Find-Clink
    if ($clink) {
        $auto = (Get-ItemProperty 'HKCU:\Software\Microsoft\Command Processor' -ErrorAction SilentlyContinue).AutoRun
        if ($auto -notmatch 'clink') {
            & $clink autorun install | Out-Null
            $auto = (Get-ItemProperty 'HKCU:\Software\Microsoft\Command Processor' -ErrorAction SilentlyContinue).AutoRun
            Info 'Clink set to start with cmd'
        }
        $profArgs = @()
        if ($auto -match '--profile\s+"([^"]+)"|--profile\s+(\S+)') {
            $dir = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
            # Clink quirk: a leading ~\ in --profile means %LOCALAPPDATA%, not the home folder
            $profArgs = @('--profile', ($dir -replace '^~(?=[\\/])', $env:LOCALAPPDATA))
        }
        Set-Content (Join-Path $dest 'clink-profile.txt') ($profArgs -join "`n")

        & $clink @profArgs installscripts (Join-Path $dest 'clink') | Out-Null

        # Remember the user's current values once so uninstall can put them back
        $settings = [ordered]@{
            'color.executable'   = 'bright green'
            'color.doskey'       = 'bright green'
            'color.cmd'          = 'bright green'
            'color.unrecognized' = 'bright red'
            'color.flag'         = 'bright cyan'
            'color.suggestion'   = 'bright black'
            'autosuggest.enable' = 'true'
            'autosuggest.inline' = 'true'    # grey suggestion after the cursor (off by default since Clink 1.9)
            'cmd.get_errorlevel' = 'true'
            'clink.logo'         = 'none'
        }
        $backup = Join-Path $dest 'clink-backup.txt'
        $saved = @(if (Test-Path $backup) { Get-Content $backup })
        $missing = @($settings.Keys | Where-Object { $k = $_; -not ($saved | Where-Object { $_ -like "$k=*" }) })
        if ($missing) {
            $all = & $clink @profArgs set 2>$null
            $lines = foreach ($k in $missing) {
                $line = $all | Where-Object { $_ -match "^$([regex]::Escape($k))\s" } | Select-Object -First 1
                $val = if ($line) { ($line -replace "^$([regex]::Escape($k))\s+", '').Trim() } else { '' }
                "$k=$val"
            }
            Set-Content $backup ($saved + $lines)
        }
        foreach ($k in $settings.Keys) { & $clink @profArgs set $k $settings[$k] | Out-Null }
        Info 'Clink configured'
    } else {
        Warn 'Clink not found, so cmd was skipped (PowerShell still works)'
    }

    if ($tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host ''
    Write-Host 'linuxify installed!' -ForegroundColor Green
    Write-Host 'Open a new cmd or PowerShell window, then try:  theme   ls   ll   fastfetch   linuxify'
}

Install-Linuxify
