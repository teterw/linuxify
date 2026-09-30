# linuxify command line: `linuxify <command>`, also run by the `theme` shortcut.
# Works from PowerShell (via the profile functions) and from cmd (via Clink aliases).
. (Join-Path $PSScriptRoot 'core.ps1')

$e = [char]27
$cmd = if ($args.Count) { [string]$args[0] } else { 'help' }
$rest = @($args | Select-Object -Skip 1)

function Show-Help {
    $b = "$e[1m"; $r = "$e[0m"; $c = "$e[96m"
    @"
${b}linuxify$r $($Linuxify.Version) - Linux-style cmd and PowerShell

  ${c}theme$r                  pick a theme with the arrow keys (live preview)
  ${c}theme$r <name>           switch theme directly
  ${c}theme list$r             list themes
  ${c}linuxify fetch$r on|off  show fastfetch when a terminal opens
  ${c}linuxify icons$r on|off  file icons in ls (needs a Nerd Font)
  ${c}linuxify update$r        update to the latest version
  ${c}linuxify uninstall$r     remove linuxify
  ${c}ls$r ${c}ll$r ${c}la$r ${c}lt$r            list / long / all / tree

"@
}

function Write-Swatches($theme) {
    if (-not $theme.palette) { return "$e[0m(uses your terminal's own colors)" }
    $s = ''
    for ($i = 0; $i -lt 8; $i++)  { $s += "$e[4${i}m   " }
    $s += "$e[0m "
    for ($i = 0; $i -lt 8; $i++)  { $s += "$e[10${i}m   " }
    "$s$e[0m"
}

function Get-Preview($theme) {
    $r = "$e[0m"
    $prompt = Get-LxPrompt $theme.style $true
    @(
        "$prompt" + "ls"
        "$e[1;34mDocuments$r  $e[1;34mDownloads$r  $e[1;34mProjects$r  $e[1;32msetup.exe$r  notes.txt  $e[33mphoto.png$r"
        "$prompt" + "git commit -m $e[33m`"hello`"$r"
        (Write-Swatches $theme)
    ) -join "`n" -split "`n"
}

function Set-Theme($name, [switch]$Quiet) {
    $theme = Get-LxTheme $name
    if (-not $theme) {
        Write-Host "Unknown theme '$name'. Themes: $((Get-LxThemes).name -join ', ')" -ForegroundColor Red
        return
    }
    $cfg = Read-LxConfig
    $cfg.theme = $theme.name
    Write-LxConfig $cfg
    if (Test-LxPaletteTerminal) { [Console]::Write((Get-LxPaletteReset) + (Get-LxPaletteSeq $theme)) }
    if (-not $Quiet) { Write-Host "Theme set to $($theme.title)." }
}

function Show-ThemeList {
    $current = (Read-LxConfig).theme
    foreach ($t in Get-LxThemes) {
        $mark = if ($t.name -eq $current) { "$e[92m*$e[0m" } else { ' ' }
        "{0} {1,-12} {2}" -f $mark, $t.name, $t.desc
    }
}

function Get-PickerLines($themes, [int]$sel, [int]$width) {
    $lines = @("$e[1mChoose a theme$e[0m  $e[90m(Up/Down to move, Enter to apply, Esc to cancel)$e[0m", '')
    for ($i = 0; $i -lt $themes.Count; $i++) {
        $t = $themes[$i]
        $desc = $t.desc
        $room = $width - 25
        if ($desc.Length -gt $room) { $desc = $desc.Substring(0, [Math]::Max(0, $room - 3)) + '...' }
        if ($i -eq $sel) { $lines += "  $e[1;92m> {0,-18}$e[0m {1}" -f $t.title, $desc }
        else             { $lines += "    {0,-18} $e[90m{1}$e[0m" -f $t.title, $desc }
    }
    $lines += ''
    $lines += Get-Preview $themes[$sel]
    $lines += ''
    $lines
}

function Invoke-ThemePicker {
    $themes = Get-LxThemes
    $cfg = Read-LxConfig
    $orig = [Math]::Max(0, [array]::IndexOf(@($themes.name), $cfg.theme))
    $sel = $orig
    $live = Test-LxPaletteTerminal
    $drawn = 0
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $lines = Get-PickerLines $themes $sel ([Console]::WindowWidth)

            $out = ''
            if ($drawn) { $out += "$e[$($drawn)A$e[0J" }  # move back up and clear the previous frame
            $out += ($lines -join "`n") + "`n"
            if ($live) { $out = (Get-LxPaletteReset) + (Get-LxPaletteSeq $themes[$sel]) + $out }
            [Console]::Write($out)
            $drawn = ($lines -join "`n").Split("`n").Count

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $sel = ($sel - 1 + $themes.Count) % $themes.Count }
                'DownArrow' { $sel = ($sel + 1) % $themes.Count }
                'K'         { $sel = ($sel - 1 + $themes.Count) % $themes.Count }
                'J'         { $sel = ($sel + 1) % $themes.Count }
                'Enter'     { Set-Theme $themes[$sel].name; return }
                { $_ -in 'Escape', 'Q' } {
                    if ($live) { [Console]::Write((Get-LxPaletteReset) + (Get-LxPaletteSeq $themes[$orig])) }
                    Write-Host 'Cancelled.'
                    return
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

function Set-Toggle($key, $value) {
    if ($value -notin 'on', 'off') { Write-Host "Usage: linuxify $key on|off" -ForegroundColor Red; return }
    $cfg = Read-LxConfig
    $cfg[$key] = $value
    Write-LxConfig $cfg
    Write-Host "$key is now $value."
}

switch ($cmd) {
    'theme' {
        if ($rest.Count -eq 0) {
            if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { Show-ThemeList } else { Invoke-ThemePicker }
        } elseif ($rest[0] -eq 'list') {
            Show-ThemeList
        } else {
            Set-Theme $rest[0]
        }
    }
    'fetch'   { Set-Toggle 'fetch' $rest[0] }
    'icons'   { Set-Toggle 'icons' $rest[0] }
    'update'  {
        Invoke-RestMethod "https://raw.githubusercontent.com/$($Linuxify.Repo)/main/install.ps1" | Invoke-Expression
    }
    'uninstall' { & (Join-Path $Linuxify.Home 'uninstall.ps1') }
    'version' { $Linuxify.Version }
    default   { Show-Help }
}
