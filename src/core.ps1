# linuxify core: config, themes, palette and prompt rendering.
# Dot-sourced by profile.ps1 and cli.ps1. Keep this file ASCII-only:
# Windows PowerShell 5.1 reads BOM-less scripts as ANSI.

$Linuxify = @{
    Home    = $PSScriptRoot
    Version = '1.0.0'
    Repo    = 'teterw/linuxify'
}

function Read-LxConfig {
    $cfg = @{ theme = 'linuxify'; fetch = 'on'; icons = 'off' }
    $path = Join-Path $Linuxify.Home 'config.txt'
    if (Test-Path -LiteralPath $path) {
        foreach ($line in [IO.File]::ReadAllLines($path)) {
            if ($line -match '^([a-z_]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2] }
        }
    }
    $cfg
}

# config.txt is also read by the Clink script, so derived theme values
# (prompt style, fastfetch logo, palette escape sequence) are stored in it too.
function Write-LxConfig($cfg) {
    $theme = Get-LxTheme $cfg.theme
    if (-not $theme) { $theme = Get-LxTheme 'linuxify'; $cfg.theme = 'linuxify' }
    $cfg.style   = $theme.style
    $cfg.logo    = [string]$theme.logo
    $cfg.palette = Get-LxPaletteSeq $theme
    $lines = foreach ($k in 'theme', 'fetch', 'icons', 'style', 'logo', 'palette') { "$k=$($cfg[$k])" }
    [IO.File]::WriteAllLines((Join-Path $Linuxify.Home 'config.txt'), [string[]]$lines, (New-Object Text.UTF8Encoding $false))
}

function Get-LxThemes {
    $json = [IO.File]::ReadAllText((Join-Path $Linuxify.Home 'themes.json'), [Text.Encoding]::UTF8)
    @(($json | ConvertFrom-Json).themes)
}

function Get-LxTheme([string]$name) {
    Get-LxThemes | Where-Object { $_.name -eq $name } | Select-Object -First 1
}

# Terminals where it's safe to recolor the palette with OSC 4/10/11.
function Test-LxPaletteTerminal {
    ($env:WT_SESSION -or $env:WEZTERM_EXECUTABLE -or $env:ConEmuANSI -eq 'ON') -and $env:TERM_PROGRAM -ne 'vscode'
}

function ConvertTo-LxRgb([string]$hex) {
    $h = $hex.TrimStart('#')
    'rgb:{0}/{1}/{2}' -f $h.Substring(0, 2), $h.Substring(2, 2), $h.Substring(4, 2)
}

function Get-LxPaletteSeq($theme) {
    if (-not $theme -or -not $theme.palette) { return '' }
    $e = [char]27; $st = "$e\"
    $p = $theme.palette
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt 16; $i++) { [void]$sb.Append("$e]4;$i;$(ConvertTo-LxRgb $p.colors[$i])$st") }
    [void]$sb.Append("$e]10;$(ConvertTo-LxRgb $p.fg)$st")
    [void]$sb.Append("$e]11;$(ConvertTo-LxRgb $p.bg)$st")
    [void]$sb.Append("$e]12;$(ConvertTo-LxRgb $p.fg)$st")
    $sb.ToString()
}

function Get-LxPaletteReset {
    $e = [char]27
    "$e]104$e\$e]110$e\$e]111$e\$e]112$e\"
}

function Get-LxGitBranch {
    $loc = Get-Location
    if ($loc.Provider.Name -ne 'FileSystem') { return $null }
    $dir = $loc.ProviderPath
    while ($dir) {
        $git = Join-Path $dir '.git'
        $head = $null
        if (Test-Path -LiteralPath $git -PathType Container) {
            $head = Join-Path $git 'HEAD'
        } elseif (Test-Path -LiteralPath $git -PathType Leaf) {
            # worktrees and submodules: .git is a file containing "gitdir: <path>"
            $line = [IO.File]::ReadAllText($git).Trim()
            if ($line -match '^gitdir:\s*(.+)$') {
                $gd = $Matches[1]
                if (-not [IO.Path]::IsPathRooted($gd)) { $gd = Join-Path $dir $gd }
                $head = Join-Path $gd 'HEAD'
            }
        }
        if ($head -and (Test-Path -LiteralPath $head)) {
            $ref = [IO.File]::ReadAllText($head).Trim()
            if ($ref -match '^ref: refs/heads/(.+)$') { return $Matches[1] }
            return $ref.Substring(0, [Math]::Min(7, $ref.Length))
        }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    $null
}

function Get-LxPath([switch]$Leaf) {
    $loc = Get-Location
    $p = if ($loc.Provider.Name -eq 'FileSystem') { $loc.ProviderPath } else { $loc.Path }
    $home_ = $HOME.TrimEnd('\')
    if ($p -eq $home_) { return '~' }
    if ($Leaf) {
        $leafName = Split-Path $p -Leaf
        if ($leafName) { return $leafName.TrimEnd('\') }
        return $p.TrimEnd('\')
    }
    if ($p.StartsWith($home_ + '\', [StringComparison]::OrdinalIgnoreCase)) { $p = '~' + $p.Substring($home_.Length) }
    $p -replace '\\', '/'
}

# Renders the prompt for a style. $ok = whether the last command succeeded.
function Get-LxPrompt([string]$style, [bool]$ok = $true) {
    $e = [char]27
    $r = "$e[0m"
    $user = $env:USERNAME
    $hostName = $env:COMPUTERNAME.ToLower()
    switch ($style) {
        'debian' {
            return "$e[1;32m$user@$hostName$r`:$e[1;34m$(Get-LxPath)$r`$ "
        }
        'bracket' {
            return "[$user@$hostName $(Get-LxPath -Leaf)]`$ "
        }
        'kali' {
            $g = "$e[32m"; $b = "$e[1;34m"; $w = "$e[1;37m"
            $tl = [char]0x250C; $h = [char]0x2500; $bl = [char]0x2514; $at = [char]0x327F
            return "$g$tl$h$h($b$user$at$hostName$r$g)-[$w$(Get-LxPath)$r$g]$r`n$g$bl$h$b`$$r "
        }
        'arrow' {
            $arrow = [char]0x279C
            $c = if ($ok) { "$e[1;32m" } else { "$e[1;31m" }
            $s = "$c$arrow  $e[36m$(Get-LxPath -Leaf)$r"
            $branch = Get-LxGitBranch
            if ($branch) { $s += " $e[1;34mgit:($e[31m$branch$e[1;34m)$r" }
            return "$s "
        }
        default {
            $s = "$e[92m$user@$hostName$r`:$e[94m$(Get-LxPath)$r"
            $branch = Get-LxGitBranch
            if ($branch) { $s += " $e[95m($branch)$r" }
            $sym = if ($ok) { "$e[92m`$" } else { "$e[91m`$" }
            return "$s $sym$r "
        }
    }
}

function Get-LxEzaArgs($cfg) {
    $a = @('--group-directories-first', '--color=auto')
    if ($cfg.icons -eq 'on') { $a += '--icons=auto' }
    $a
}
