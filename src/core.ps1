# linuxify core: config, themes, palette and prompt rendering.
# Dot-sourced by profile.ps1 and cli.ps1. Keep this file ASCII-only:
# Windows PowerShell 5.1 reads BOM-less scripts as ANSI.

$Linuxify = @{
    Home    = $PSScriptRoot
    Version = '1.3.0'
    Repo    = 'teterw/linuxify'
}

# --- Data (themes.json): colors, prompts, logos ---

function Get-LxData {
    if (-not $Linuxify.Data) {
        $json = [IO.File]::ReadAllText((Join-Path $Linuxify.Home 'themes.json'), [Text.Encoding]::UTF8)
        $Linuxify.Data = $json | ConvertFrom-Json
    }
    $Linuxify.Data
}

function Get-LxColors  { @((Get-LxData).colors) }
function Get-LxPrompts { @((Get-LxData).prompts) }
function Get-LxLogos   { @((Get-LxData).logos) }

function Find-LxItem($list, [string]$name) {
    $list | Where-Object { $_.name -eq $name } | Select-Object -First 1
}
function Get-LxColor([string]$name)  { if ($name -eq 'linuxify') { $name = 'default' }; Find-LxItem (Get-LxColors) $name }
function Get-LxPromptDef([string]$name) { Find-LxItem (Get-LxPrompts) $name }
function Get-LxLogo([string]$name)   { Find-LxItem (Get-LxLogos) $name }

# --- Config (config.txt, also read by the Clink script) ---

function Read-LxConfig {
    $cfg = @{}
    $path = Join-Path $Linuxify.Home 'config.txt'
    if (Test-Path -LiteralPath $path) {
        foreach ($line in [IO.File]::ReadAllLines($path)) {
            if ($line -match '^([a-z_]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2] }
        }
    }
    # 1.0 stored one "theme" that set colors, prompt and logo together
    if ($cfg.theme -and -not $cfg.colors) {
        $cfg.colors = $cfg.theme
        if ($cfg.style) { $cfg.prompt = $cfg.style }
        $cfg.logo = 'windows'
    }
    foreach ($k in 'theme', 'style') { $cfg.Remove($k) }
    $defaults = @{ colors = 'default'; prompt = 'linuxify'; logo = 'windows'; fetch = 'on'; icons = 'off' }
    foreach ($k in $defaults.Keys) { if (-not $cfg[$k]) { $cfg[$k] = $defaults[$k] } }
    if (-not (Get-LxColor $cfg.colors))     { $cfg.colors = 'default' }
    if (-not (Get-LxPromptDef $cfg.prompt)) { $cfg.prompt = 'linuxify' }
    if (-not (Get-LxLogo $cfg.logo))        { $cfg.logo = 'windows' }
    $cfg.colors = (Get-LxColor $cfg.colors).name
    $cfg
}

# Derived values (palette escape sequence, fastfetch logo id) are stored too,
# so the Clink script doesn't need to parse themes.json.
function Write-LxConfig($cfg) {
    $cfg.palette = Get-LxPaletteSeq (Get-LxColor $cfg.colors)
    $cfg.logo_id = (Get-LxLogo $cfg.logo).id
    $lines = foreach ($k in 'colors', 'prompt', 'logo', 'fetch', 'icons', 'logo_id', 'palette') { "$k=$($cfg[$k])" }
    [IO.File]::WriteAllLines((Join-Path $Linuxify.Home 'config.txt'), [string[]]$lines, (New-Object Text.UTF8Encoding $false))
}

# --- Palette ---

# Terminals where it's safe to recolor the palette with OSC 4/10/11.
function Test-LxPaletteTerminal {
    ($env:WT_SESSION -or $env:WEZTERM_EXECUTABLE -or $env:ConEmuANSI -eq 'ON') -and $env:TERM_PROGRAM -ne 'vscode'
}

function ConvertTo-LxRgb([string]$hex) {
    $h = $hex.TrimStart('#')
    'rgb:{0}/{1}/{2}' -f $h.Substring(0, 2), $h.Substring(2, 2), $h.Substring(4, 2)
}

function Get-LxPaletteSeq($color) {
    if (-not $color -or -not $color.palette) { return '' }
    $e = [char]27; $st = "$e\"
    $p = $color.palette
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

# Resets then applies a color theme in the current terminal tab.
function Set-LxPalette($color) {
    if (Test-LxPaletteTerminal) { [Console]::Write((Get-LxPaletteReset) + (Get-LxPaletteSeq $color)) }
}

# The settings.json of each Windows Terminal that's installed (Store, Preview, Canary, or unpackaged)
function Get-LxTermFiles {
    $files = if ($env:LINUXIFY_WT_SETTINGS) { @($env:LINUXIFY_WT_SETTINGS) } else {
        $pkgs = Join-Path $env:LOCALAPPDATA 'Packages'
        @(foreach ($p in 'Microsoft.WindowsTerminal_8wekyb3d8bbwe', 'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe',
                         'Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe') { Join-Path $pkgs "$p\LocalState\settings.json" }) +
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    }
    @($files | Where-Object { Test-Path -LiteralPath $_ })
}

# Windows Terminal resets colors set by escape codes whenever it reloads settings.json (after a
# window option, or a change in its own Settings page). Run at each prompt: while settings.json
# changed less than a second before the theme was last applied, apply it again.
function Update-LxPalette {
    if (-not $Linuxify.TermFiles -or -not $Linuxify.Config.palette) { return }
    $changed = 0
    foreach ($f in $Linuxify.TermFiles) { $t = [IO.File]::GetLastWriteTimeUtc($f).Ticks; if ($t -gt $changed) { $changed = $t } }
    if ($changed -gt $Linuxify.PaletteAt - [TimeSpan]::TicksPerSecond) {
        [Console]::Write($Linuxify.Config.palette)
        $Linuxify.PaletteAt = [DateTime]::UtcNow.Ticks
    }
}

# --- fastfetch ---

function Get-LxFetchArgs($cfg) {
    $id = (Get-LxLogo $cfg.logo).id
    if ($id) { @('--logo', $id) } else { @() }
}

# --- Prompt ---

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

# Current directory as ~/linux/style/path, just its last part (-Leaf),
# or fish-style with parent folders shortened to one letter (-Short).
function Get-LxPath([switch]$Leaf, [switch]$Short) {
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
    $p = $p.TrimEnd('\') -replace '\\', '/'
    if ($Short) {
        $parts = $p.Split('/')
        for ($i = 0; $i -lt $parts.Count - 1; $i++) {
            if ($parts[$i].Length -gt 1 -and $parts[$i] -notmatch ':$') {
                $n = if ($parts[$i].StartsWith('.')) { 2 } else { 1 }
                $parts[$i] = $parts[$i].Substring(0, [Math]::Min($n, $parts[$i].Length))
            }
        }
        $p = $parts -join '/'
    }
    $p
}

# The last characters of each prompt; PSReadLine redraws them in red on a syntax error.
function Get-LxPromptText([string]$style) {
    switch ($style) {
        'arrow'   { ' ' }
        'fish'    { '> ' }
        'pure'    { "$([char]0x276F) " }
        'minimal' { "$([char]0x276F) " }
        'macos'   { '% ' }
        default   { '$ ' }
    }
}

# Renders the prompt for a style. $ok = whether the last command succeeded.
function Get-LxPrompt([string]$style, [bool]$ok = $true) {
    $e = [char]27
    $r = "$e[0m"
    $user = $env:USERNAME
    $hostName = $env:COMPUTERNAME.ToLower()
    $h = [char]0x2500; $tl = [char]0x250C; $bl = [char]0x2514; $chev = [char]0x276F
    switch ($style) {
        'debian' {
            return "$e[1;32m$user@$hostName$r`:$e[1;34m$(Get-LxPath)$r`$ "
        }
        'bracket' {
            return "[$user@$hostName $(Get-LxPath -Leaf)]`$ "
        }
        'kali' {
            $g = "$e[32m"; $b = "$e[1;34m"; $w = "$e[1;37m"
            $at = [char]0x327F
            return "$g$tl$h$h($b$user$at$hostName$r$g)-[$w$(Get-LxPath)$r$g]$r`n$g$bl$h$b`$$r "
        }
        'parrot' {
            $red = "$e[0;31m"
            $x = if ($ok) { '' } else { "[$e[1;93m$([char]0x2717)$red]$h" }
            return "$red$tl$h$x[$r$user$e[1;33m@$e[1;96m$hostName$red]$h[$e[0;32m$(Get-LxPath)$red]$r`n$red$bl$h$h$([char]0x257C) $e[1;33m`$$r "
        }
        'arrow' {
            $c = if ($ok) { "$e[1;32m" } else { "$e[1;31m" }
            $s = "$c$([char]0x279C)  $e[36m$(Get-LxPath -Leaf)$r"
            $branch = Get-LxGitBranch
            if ($branch) { $s += " $e[1;34mgit:($e[31m$branch$e[1;34m)$r" }
            return "$s "
        }
        'fish' {
            return "$e[32m$user$r@$hostName $e[32m$(Get-LxPath -Short)$r> "
        }
        'pure' {
            $s = "$e[34m$(Get-LxPath)$r"
            $branch = Get-LxGitBranch
            if ($branch) { $s += " $e[90m$branch$r" }
            $c = if ($ok) { "$e[35m" } else { "$e[31m" }
            return "$s`n$c$chev$r "
        }
        'minimal' {
            $c = if ($ok) { "$e[32m" } else { "$e[31m" }
            return "$e[1;36m$(Get-LxPath -Leaf)$r $c$chev$r "
        }
        'macos' {
            return "$user@$hostName $(Get-LxPath -Leaf) % "
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
