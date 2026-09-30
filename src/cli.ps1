# linuxify command line: `linuxify <command>`, also run by the `theme` shortcut.
# Works from PowerShell (via the profile functions) and from cmd (via Clink aliases).
. (Join-Path $PSScriptRoot 'core.ps1')

$e = [char]27
$AnsiPattern = "$e\[[0-9;?]*[A-Za-z]"
$cmd = if ($args.Count) { [string]$args[0] } else { 'help' }
$rest = @($args | Select-Object -Skip 1)

# Reads one key press. Tests swap this out to drive the pickers.
$LxReadKey = { [Console]::ReadKey($true) }

function Show-Help {
    $b = "$e[1m"; $r = "$e[0m"; $c = "$e[96m"
    @"
${b}linuxify$r $($Linuxify.Version) - Linux-style cmd and PowerShell

  ${c}theme$r                   menu: colors, prompt, fastfetch logo, toggles
  ${c}theme colors$r [name]     pick a color theme (live preview)
  ${c}theme prompt$r [name]     pick a prompt style
  ${c}theme logo$r [name]       pick the fastfetch logo
  ${c}theme list$r              list every color theme, prompt and logo
  ${c}linuxify fetch$r on|off   show fastfetch when a terminal opens
  ${c}linuxify icons$r on|off   file icons in ls (needs a Nerd Font)
  ${c}linuxify update$r         update to the latest version
  ${c}linuxify uninstall$r      remove linuxify
  ${c}ls$r ${c}ll$r ${c}la$r ${c}lt$r             list / long / all / tree
  ${c}Ctrl+F$r                  accept the grey suggestion while typing

"@
}

# --- Text helpers (ANSI-aware width) ---

function Get-LxVisibleLength([string]$s) { ($s -replace $AnsiPattern, '').Length }

function Format-LxPad([string]$s, [int]$width) {
    $s + (' ' * [Math]::Max(0, $width - (Get-LxVisibleLength $s)))
}

# Cuts a line to $max visible characters without breaking color codes.
function Limit-LxLine([string]$s, [int]$max) {
    if ((Get-LxVisibleLength $s) -le $max) { return $s }
    $sb = New-Object Text.StringBuilder
    $n = 0; $i = 0
    while ($i -lt $s.Length -and $n -lt $max) {
        $m = [regex]::Match($s.Substring($i), "^$AnsiPattern")
        if ($m.Success) { [void]$sb.Append($m.Value); $i += $m.Length; continue }
        [void]$sb.Append($s[$i]); $i++; $n++
    }
    [void]$sb.Append("$e[0m")
    $sb.ToString()
}

function Get-LxWindowSize {
    try { @([Console]::WindowWidth, [Console]::WindowHeight) } catch { @(100, 30) }
}

# --- Previews ---

function Get-LxSwatches($color) {
    $s = ''
    if ($color -and $color.palette) {
        # true color, so the preview is right even where the palette can't change live
        foreach ($i in 0..15) {
            $h = $color.palette.colors[$i].TrimStart('#')
            $s += "$e[48;2;$([Convert]::ToInt32($h.Substring(0,2),16));$([Convert]::ToInt32($h.Substring(2,2),16));$([Convert]::ToInt32($h.Substring(4,2),16))m   "
            if ($i -eq 7) { $s += "$e[0m " }
        }
    } else {
        for ($i = 0; $i -lt 8; $i++) { $s += "$e[4${i}m   " }
        $s += "$e[0m "
        for ($i = 0; $i -lt 8; $i++) { $s += "$e[10${i}m   " }
    }
    "$s$e[0m"
}

# A fake session in the given prompt style: prompt, ls output, a colored command.
function Get-LxSample([string]$promptStyle, $color) {
    $r = "$e[0m"
    $p = (Get-LxPrompt $promptStyle $true) -split "`n"
    $lead = @($p | Select-Object -SkipLast 1)
    $last = $p[-1]
    $lines = @()
    $lines += $lead
    $lines += $last + 'ls'
    $lines += "$e[1;34mDocuments$r  $e[1;34mDownloads$r  $e[1;34mProjects$r  $e[1;32msetup.exe$r  notes.txt  $e[33mphoto.png$r"
    $lines += $lead
    $lines += $last + "$e[92mgit$r commit $e[96m-m$r $e[33m`"hello world`"$r"
    if ($color) { $lines += ''; $lines += Get-LxSwatches $color }
    $lines
}

function Get-LxLogoPreview($logo, [hashtable]$cache) {
    if ($cache.ContainsKey($logo.name)) { return $cache[$logo.name] }
    $ff = Get-Command fastfetch -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ff) {
        $lines = @('', "$e[90m(fastfetch isn't installed)$e[0m")
    } elseif ($logo.id -eq 'none') {
        $lines = @('', "$e[90m(no logo, just the system info)$e[0m")
    } else {
        $a = @('-s', 'none', '--pipe', 'false')
        if ($logo.id) { $a = @('--logo', $logo.id) + $a }
        # fastfetch prints UTF-8; PowerShell decodes captured output with the console encoding
        $prev = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
            $lines = @(& $ff.Source @a 2>$null | ForEach-Object { $_.TrimEnd("`r") })
        } finally { [Console]::OutputEncoding = $prev }
        while ($lines.Count -and -not ($lines[-1] -replace $AnsiPattern, '').Trim()) { $lines = @($lines | Select-Object -SkipLast 1) }
    }
    $cache[$logo.name] = $lines
    $lines
}

# --- Picker ---

# Arrow-key list. Returns the chosen index, or -1 if cancelled.
#   Items   : objects with .title (and .desc, shown unless -Side)
#   Preview : scriptblock that gets the selected index and returns lines to show
#   OnMove  : scriptblock run when the selection changes (for live colors)
#   Side    : show the preview beside the list instead of below it
# The picker erases itself when it returns, so pickers can be stacked.
function Invoke-LxPicker {
    param([string]$Title, [object[]]$Items, [int]$Selected = 0, [scriptblock]$Preview, [scriptblock]$OnMove,
          [switch]$Side, [string]$Hint = 'Up/Down move  Enter select  Esc back')
    $sel = [Math]::Max(0, [Math]::Min($Selected, $Items.Count - 1))
    $top = 0; $drawn = 0; $moved = -1
    $titleW = ($Items | ForEach-Object { $_.title.Length } | Measure-Object -Maximum).Maximum + 1
    try { [Console]::CursorVisible = $false } catch { }
    # [Console]::Write encodes with the console code page (often 437), which turns arrow and box glyphs into '?'
    $prevEncoding = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch { }
    try {
        while ($true) {
            if ($OnMove -and $sel -ne $moved) { & $OnMove $sel; $moved = $sel }
            $W, $H = Get-LxWindowSize
            $W -= 1; $H -= 1
            $pv = @(if ($Preview) { & $Preview $sel })
            $header = @("$e[1m$Title$e[0m  $e[90m$($sel + 1)/$($Items.Count)   $Hint$e[0m", '')
            $avail = if ($Side) { $H - $header.Count } else { $H - $header.Count - $pv.Count - 1 }
            $rows = [Math]::Max(3, [Math]::Min($Items.Count, $avail))
            $rows = [Math]::Min($rows, $Items.Count)
            if ($sel -lt $top) { $top = $sel }
            if ($sel -ge $top + $rows) { $top = $sel - $rows + 1 }

            $list = for ($i = $top; $i -lt $top + $rows; $i++) {
                $it = $Items[$i]
                $more = ' '
                if ($i -eq $top -and $top -gt 0) { $more = '^' }
                if ($i -eq $top + $rows - 1 -and $i -lt $Items.Count - 1) { $more = 'v' }
                $name = $it.title.PadRight($titleW)
                if ($i -eq $sel) {
                    $line = "$e[90m$more$e[0m $e[1;92m> $name$e[0m"
                    if (-not $Side -and $it.desc) { $line += " $($it.desc)" }
                } else {
                    $line = "$e[90m$more$e[0m   $name"
                    if (-not $Side -and $it.desc) { $line += " $e[90m$($it.desc)$e[0m" }
                }
                $line
            }
            if ($Side) {
                $pvRows = [Math]::Min($pv.Count, [Math]::Max($rows, $avail))
                $n = [Math]::Max(@($list).Count, $pvRows)
                $body = for ($r = 0; $r -lt $n; $r++) {
                    $l = if ($r -lt @($list).Count) { @($list)[$r] } else { '' }
                    $p = if ($r -lt $pvRows) { $pv[$r] } else { '' }
                    (Format-LxPad $l ($titleW + 5)) + '  ' + $p
                }
            } else {
                $body = @($list) + '' + $pv
            }
            $frame = @(@($header) + @($body) | ForEach-Object { Limit-LxLine $_ $W })

            $out = ''
            if ($drawn) { $out += "$e[$($drawn)A" }
            $out += "`r$e[0J" + ($frame -join "`n") + "`n"
            [Console]::Write($out)
            $drawn = $frame.Count

            $k = & $LxReadKey
            $count = $Items.Count
            switch ($k.Key) {
                'UpArrow'    { $sel = ($sel - 1 + $count) % $count }
                'DownArrow'  { $sel = ($sel + 1) % $count }
                'PageUp'     { $sel = [Math]::Max(0, $sel - $rows) }
                'PageDown'   { $sel = [Math]::Min($count - 1, $sel + $rows) }
                'Home'       { $sel = 0 }
                'End'        { $sel = $count - 1 }
                { $_ -in 'Enter', 'Spacebar', 'RightArrow' } { return $sel }
                { $_ -in 'Escape', 'LeftArrow', 'Backspace' } { return -1 }
                default {
                    # typing a letter jumps to the next item starting with it
                    $ch = [string]$k.KeyChar
                    if ($ch -match '^[a-z0-9]$') {
                        for ($j = 1; $j -le $count; $j++) {
                            $idx = ($sel + $j) % $count
                            if ($Items[$idx].title.StartsWith($ch, [StringComparison]::OrdinalIgnoreCase)) { $sel = $idx; break }
                        }
                    }
                }
            }
        }
    } finally {
        if ($drawn) { [Console]::Write("$e[$($drawn)A`r$e[0J") }
        try { [Console]::CursorVisible = $true } catch { }
        try { [Console]::OutputEncoding = $prevEncoding } catch { }
    }
}

# --- Setters ---

function Save-LxSetting([string]$key, [string]$value) {
    $cfg = Read-LxConfig
    $cfg[$key] = $value
    Write-LxConfig $cfg
}

function Resolve-LxName($list, [string]$name) {
    $list | Where-Object { $_.name -eq $name -or $_.title -eq $name -or ($_.id -and $_.id -eq $name) } | Select-Object -First 1
}

function Set-LxColors([string]$name) {
    $c = if ($name -eq 'linuxify') { Get-LxColor 'default' } else { Resolve-LxName (Get-LxColors) $name }
    if (-not $c) { Write-Host "Unknown color theme '$name'. Try: $((Get-LxColors).name -join ', ')" -ForegroundColor Red; return }
    Save-LxSetting 'colors' $c.name
    Set-LxPalette $c
    Write-Host "Colors: $($c.title)"
}

function Set-LxPromptStyle([string]$name) {
    $p = Resolve-LxName (Get-LxPrompts) $name
    if (-not $p) { Write-Host "Unknown prompt '$name'. Try: $((Get-LxPrompts).name -join ', ')" -ForegroundColor Red; return }
    Save-LxSetting 'prompt' $p.name
    Write-Host "Prompt: $($p.title)"
}

function Set-LxLogo([string]$name) {
    $l = Resolve-LxName (Get-LxLogos) $name
    if (-not $l) { Write-Host "Unknown logo '$name'. Try: $((Get-LxLogos).name -join ', ')" -ForegroundColor Red; return }
    Save-LxSetting 'logo' $l.name
    Write-Host "fastfetch logo: $($l.title)"
}

function Set-Toggle($key, $value) {
    if ($value -notin 'on', 'off') { Write-Host "Usage: linuxify $key on|off" -ForegroundColor Red; return }
    Save-LxSetting $key $value
    Write-Host "$key is now $value."
}

# --- Pickers ---

function Select-LxColors {
    $colorList = Get-LxColors
    $colorCfg = Read-LxConfig
    $start = [array]::IndexOf(@($colorList.name), $colorCfg.colors)
    $i = Invoke-LxPicker -Title 'Colors' -Items $colorList -Selected $start `
        -Preview { param($i) Get-LxSample $colorCfg.prompt $colorList[$i] } `
        -OnMove { param($i) Set-LxPalette $colorList[$i] }
    if ($i -lt 0) { Set-LxPalette (Get-LxColor $colorCfg.colors); return }
    Save-LxSetting 'colors' $colorList[$i].name
}

function Select-LxPromptStyle {
    $promptList = Get-LxPrompts
    $promptCfg = Read-LxConfig
    $start = [array]::IndexOf(@($promptList.name), $promptCfg.prompt)
    $i = Invoke-LxPicker -Title 'Prompt' -Items $promptList -Selected $start `
        -Preview { param($i) Get-LxSample $promptList[$i].name $null }
    if ($i -ge 0) { Save-LxSetting 'prompt' $promptList[$i].name }
}

function Select-LxLogoStyle {
    $logoList = Get-LxLogos
    $logoCfg = Read-LxConfig
    $logoCache = @{}
    $start = [array]::IndexOf(@($logoList.name), $logoCfg.logo)
    $i = Invoke-LxPicker -Title 'fastfetch logo' -Items $logoList -Selected $start -Side `
        -Preview { param($i) Get-LxLogoPreview $logoList[$i] $logoCache }
    if ($i -ge 0) { Save-LxSetting 'logo' $logoList[$i].name }
}

function Invoke-LxMenu {
    $menuSel = 0
    while ($true) {
        $menuCfg = Read-LxConfig
        $pd = Get-LxPromptDef $menuCfg.prompt
        $menuItems = @(
            [pscustomobject]@{ key = 'colors'; title = 'Colors';               desc = (Get-LxColor $menuCfg.colors).title }
            [pscustomobject]@{ key = 'prompt'; title = 'Prompt';               desc = "$($pd.title)  $e[90m$($pd.desc)$e[0m" }
            [pscustomobject]@{ key = 'logo';   title = 'fastfetch logo';       desc = (Get-LxLogo $menuCfg.logo).title }
            [pscustomobject]@{ key = 'fetch';  title = 'fastfetch at startup'; desc = $menuCfg.fetch }
            [pscustomobject]@{ key = 'icons';  title = 'Icons in ls';          desc = "$($menuCfg.icons)  $e[90m(needs a Nerd Font)$e[0m" }
        )
        $menuSel = Invoke-LxPicker -Title 'linuxify theme' -Items $menuItems -Selected $menuSel -Hint 'Up/Down move  Enter change  Esc done' `
            -Preview { param($i) Get-LxSample $menuCfg.prompt (Get-LxColor $menuCfg.colors) }
        if ($menuSel -lt 0) { break }
        switch ($menuItems[$menuSel].key) {
            'colors' { Select-LxColors }
            'prompt' { Select-LxPromptStyle }
            'logo'   { Select-LxLogoStyle }
            'fetch'  { Save-LxSetting 'fetch' $(if ($menuCfg.fetch -eq 'on') { 'off' } else { 'on' }) }
            'icons'  { Save-LxSetting 'icons' $(if ($menuCfg.icons -eq 'on') { 'off' } else { 'on' }) }
        }
    }
    $final = Read-LxConfig
    Write-Host ("Colors: {0}   Prompt: {1}   Logo: {2}   fastfetch at startup: {3}" -f
        (Get-LxColor $final.colors).title, (Get-LxPromptDef $final.prompt).title, (Get-LxLogo $final.logo).title, $final.fetch)
}

function Show-LxList {
    $cfg = Read-LxConfig
    $sections = @(
        @{ Title = 'Colors  (theme colors <name>)'; List = Get-LxColors;  Current = $cfg.colors }
        @{ Title = 'Prompts (theme prompt <name>)'; List = Get-LxPrompts; Current = $cfg.prompt }
        @{ Title = 'Logos   (theme logo <name>)';   List = Get-LxLogos;   Current = $cfg.logo }
    )
    foreach ($s in $sections) {
        "$e[1m$($s.Title)$e[0m"
        foreach ($t in $s.List) {
            $mark = if ($t.name -eq $s.Current) { "$e[92m*$e[0m" } else { ' ' }
            $desc = if ($t.desc) { $t.desc } else { $t.title }
            "  {0} {1,-12} {2}" -f $mark, $t.name, $desc
        }
        ''
    }
}

function Test-LxInteractive { -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) }

function Invoke-LxTheme([string[]]$a) {
    $sub = if ($a.Count) { $a[0] } else { '' }
    $arg = if ($a.Count -gt 1) { $a[1..($a.Count - 1)] -join ' ' } else { '' }
    switch -regex ($sub) {
        '^$'          { if (Test-LxInteractive) { Invoke-LxMenu } else { Show-LxList }; return }
        '^list$'      { Show-LxList; return }
        '^colou?rs?$' { if ($arg) { Set-LxColors $arg } elseif (Test-LxInteractive) { Select-LxColors } else { Show-LxList }; return }
        '^prompts?$'  { if ($arg) { Set-LxPromptStyle $arg } elseif (Test-LxInteractive) { Select-LxPromptStyle } else { Show-LxList }; return }
        '^logos?$'    { if ($arg) { Set-LxLogo $arg } elseif (Test-LxInteractive) { Select-LxLogoStyle } else { Show-LxList }; return }
        default {
            # `theme dracula` still works as a shortcut for colors
            if (Get-LxColor $sub) { Set-LxColors $sub } else { Write-Host "Unknown theme '$sub'. Run 'theme list' to see them all." -ForegroundColor Red }
        }
    }
}

switch ($cmd) {
    'theme'   { Invoke-LxTheme $rest }
    'colors'  { Invoke-LxTheme (@('colors') + $rest) }
    'prompt'  { Invoke-LxTheme (@('prompt') + $rest) }
    'logo'    { Invoke-LxTheme (@('logo') + $rest) }
    'fetch'   { Set-Toggle 'fetch' $rest[0] }
    'icons'   { Set-Toggle 'icons' $rest[0] }
    'update'  {
        Invoke-RestMethod "https://raw.githubusercontent.com/$($Linuxify.Repo)/main/install.ps1" | Invoke-Expression
    }
    'uninstall' { & (Join-Path $Linuxify.Home 'uninstall.ps1') }
    'version' { $Linuxify.Version }
    default   { Show-Help }
}
