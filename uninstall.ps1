# linuxify uninstaller
#   linuxify uninstall
#   or: irm https://raw.githubusercontent.com/teterw/linuxify/main/uninstall.ps1 | iex
# Removes linuxify's hooks and files. Clink, eza, fastfetch and PSReadLine stay installed.

function Uninstall-Linuxify {
    $dest = Join-Path $env:LOCALAPPDATA 'linuxify'
    function Info($msg) { Write-Host "    $msg" }

    Write-Host '==> Removing linuxify' -ForegroundColor Cyan

    # PowerShell profiles: remove only our marker block
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $created = @()
    if (Test-Path "$dest\created-profiles.txt") { $created = @(Get-Content "$dest\created-profiles.txt") }
    foreach ($p in (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
                   (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')) {
        if (-not (Test-Path $p)) { continue }
        $text = [IO.File]::ReadAllText($p)
        $new = [regex]::Replace($text, '(?s)(\r?\n)*# >>> linuxify >>>.*?# <<< linuxify <<<(\r?\n)?', '')
        if ($new -eq $text) { continue }
        if ($new.Trim() -eq '' -and $created -contains $p) {
            Remove-Item $p
            Info "removed $p (linuxify created it)"
        } else {
            [IO.File]::WriteAllText($p, $new.TrimEnd() + "`r`n", (New-Object Text.UTF8Encoding $true))
            Info "unhooked $p"
        }
    }

    # Clink: unregister our scripts and restore the settings we changed
    $auto = (Get-ItemProperty 'HKCU:\Software\Microsoft\Command Processor' -ErrorAction SilentlyContinue).AutoRun
    $clink = $null
    $dirs = @()
    if ($auto -match '"?([^"]*?)\\clink\.bat"?') { $dirs += $Matches[1] }
    $dirs += "${env:ProgramFiles(x86)}\clink", "$env:ProgramFiles\clink", "$env:LOCALAPPDATA\Programs\clink"
    foreach ($d in $dirs) { foreach ($exe in 'clink_x64.exe', 'clink_x86.exe') { if (-not $clink -and (Test-Path "$d\$exe")) { $clink = "$d\$exe" } } }
    if ($clink) {
        $profArgs = @()
        if (Test-Path "$dest\clink-profile.txt") { $profArgs = @(Get-Content "$dest\clink-profile.txt" | Where-Object { $_ }) }
        & $clink @profArgs uninstallscripts "$dest\clink" | Out-Null
        if (Test-Path "$dest\clink-backup.txt") {
            foreach ($line in Get-Content "$dest\clink-backup.txt") {
                if ($line -notmatch '^([^=]+)=(.*)$') { continue }
                $val = if ($Matches[2]) { $Matches[2] } else { 'clear' }
                & $clink @profArgs set $Matches[1] $val | Out-Null
            }
        }
        Info 'unhooked cmd (Clink settings restored)'
    }

    # Windows Terminal: put back the window settings linuxify changed (transparency, font...)
    if (Test-Path "$dest\terminal.ps1") {
        . "$dest\terminal.ps1"
        if (Restore-LxTerminal) { Info 'restored your Windows Terminal settings' }
    }

    # Reset colors in this terminal
    if ($env:WT_SESSION) { $e = [char]27; [Console]::Write("$e]104$e\$e]110$e\$e]111$e\$e]112$e\") }

    Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
    Info "deleted $dest"

    Write-Host ''
    Write-Host 'linuxify removed. Open a new terminal to see the change.' -ForegroundColor Green
    Write-Host 'Clink, eza and fastfetch are still installed. To remove them too:'
    Write-Host '    winget uninstall chrisant996.Clink; winget uninstall eza-community.eza; winget uninstall Fastfetch-cli.Fastfetch'
}

Uninstall-Linuxify
