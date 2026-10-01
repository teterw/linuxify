# linuxify command line: `linuxify <command>`, also run by the `theme` shortcut.
# Works from PowerShell (via the profile functions) and from cmd (via Clink aliases).
. (Join-Path $PSScriptRoot 'core.ps1')
. (Join-Path $PSScriptRoot 'terminal.ps1')

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
  ${c}linuxify restart$r        reload, like opening a new terminal

${b}Window$r (Windows Terminal, changes every tab right away)
  ${c}theme window$r            menu: transparency, blur, font, cursor, retro
  ${c}theme transparency$r [0-90]   see-through background, in percent
  ${c}theme blur$r on|off       frosted glass behind a transparent background
  ${c}theme font$r [name]       pick the font ('theme font default' to reset)
  ${c}theme fontsize$r [size]   font size
  ${c}theme cursor$r [shape]    bar, block, underscore, box, double, vintage
  ${c}theme retro$r on|off      old CRT look: scanlines and glow

${b}Settings$r
  ${c}linuxify fetch$r on|off   show fastfetch when a terminal opens
  ${c}linuxify icons$r on|off   file icons in ls (needs a Nerd Font)
  ${c}linuxify sudo$r [inline|window|off]   how Windows' sudo runs commands
  ${c}linuxify update$r         update to the latest version
  ${c}linuxify uninstall$r      remove linuxify

${b}Linux commands$r
  ls ll la lt  which  touch  head  tail [-f]  grep  wc  df -h  free -h  uptime
  open  xdg-open  mkdir -p  rm -rf  pwd  export  unset  env  killall  sudo

${b}Shell habits$r
  cd -   cd (home)   ..  ...  ....   mkcd DIR   !! (last command)   !`$ (last argument)
  ${c}Ctrl+F$r accepts the grey suggestion while typing

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

function Test-LxKeyPending { try { [Console]::KeyAvailable } catch { $false } }

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
#   OnMove  : scriptblock run when the selection changes (for live colors and window settings)
#   Side    : show the preview beside the list instead of below it
# The picker erases itself when it returns, so pickers can be stacked.
function Invoke-LxPicker {
    param([string]$Title, [object[]]$Items, [int]$Selected = 0, [scriptblock]$Preview, [scriptblock]$OnMove,
          [switch]$Side, [string]$Hint = 'Up/Down move  Enter select  Esc back')
    $sel = [Math]::Max(0, [Math]::Min($Selected, $Items.Count - 1))
    $top = 0; $drawn = $false; $moved = $sel
    $titleW = ($Items | ForEach-Object { $_.title.Length } | Measure-Object -Maximum).Maximum + 1
    try { [Console]::CursorVisible = $false } catch { }
    # [Console]::Write encodes with the console code page (often 437), which turns arrow and box glyphs into '?'
    $prevEncoding = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch { }
    try {
        while ($true) {
            # while a key is held down, only the last stop gets previewed
            if ($OnMove -and $sel -ne $moved -and -not (Test-LxKeyPending)) { & $OnMove $sel; $moved = $sel }
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

            # Draw, then park the cursor at the top of the frame. If the terminal reflows the text
            # (a new font size), the cursor moves with it, so the next frame still lands in place.
            $out = "`r$e[0J" + ($frame -join "`n")
            if ($frame.Count -gt 1) { $out += "$e[$($frame.Count - 1)A" }
            [Console]::Write($out + "`r")
            $drawn = $true

            $k = & $LxReadKey
            $count = $Items.Count
            switch ($k.Key) {
                'UpArrow'    { $sel = ($sel - 1 + $count) % $count }
                'DownArrow'  { $sel = ($sel + 1) % $count }
                'PageUp'     { $sel = [Math]::Max(0, $sel - $rows) }
                'PageDown'   { $sel = [Math]::Min($count - 1, $sel + $rows) }
                'Home'       { $sel = 0 }
                'End'        { $sel = $count - 1 }
                { $_ -in 'Enter', 'Spacebar', 'RightArrow' } {
                    if ($OnMove -and $sel -ne $moved) { & $OnMove $sel }
                    return $sel
                }
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
        if ($drawn) { [Console]::Write("`r$e[0J") }
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

# Windows 11's built-in sudo: inline (like Linux), new window, or off. Changing it needs admin.
function Set-LxSudo([string]$mode) {
    $exe = Join-Path $env:windir 'System32\sudo.exe'
    if (-not (Test-Path $exe)) {
        Write-Host "This Windows version has no built-in sudo, so linuxify's sudo opens an elevated window instead."
        return
    }
    $modes = @{ inline = 'normal'; on = 'normal'; window = 'forceNewWindow'; off = 'disable' }
    if ($mode) {
        if (-not $modes.ContainsKey($mode)) { Write-Host 'Usage: linuxify sudo [inline|window|off]' -ForegroundColor Red; return }
        Write-Host 'Changing this needs administrator rights, so Windows will ask for permission.'
        try { Start-Process $exe -ArgumentList 'config', '--enable', $modes[$mode] -Verb RunAs -Wait -WindowStyle Hidden }
        catch { Write-Host 'Cancelled.'; return }
    }
    & $exe config
    if (-not $mode) { Write-Host 'Change it with: linuxify sudo inline (like Linux) | window | off' }
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

# --- Window: Windows Terminal settings (terminal.ps1 edits settings.json) ---

function Test-LxTermFound {
    if (@(Get-LxTermFiles).Count) { return $true }
    Write-Host "Windows Terminal's settings weren't found. Transparency, blur, font, cursor and the retro effect are Windows Terminal settings, so open it once first." -ForegroundColor Red
    $false
}

function Format-LxOnOff([bool]$on) { if ($on) { 'on' } else { 'off' } }
function Format-LxFontName($w) { if ($w.Font) { $w.Font } else { 'Cascadia Mono' } }
function Format-LxFontSize($w) { if ($w.Size) { [string]$w.Size } else { '12' } }

function Get-LxCursorDef([string]$id) {
    $c = Get-LxCursors | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if ($c) { $c } else { [pscustomobject]@{ name = $id; id = $id; title = $id } }
}

function Get-LxWindowSummary($w) {
    if (-not $w.Found) { return "$e[90mneeds Windows Terminal$e[0m" }
    $parts = @("$($w.Transparency)% transparent")
    if ($w.Blur) { $parts += 'blur' }
    $parts += "$(Format-LxFontName $w) $(Format-LxFontSize $w)"
    $parts += "$((Get-LxCursorDef $w.Cursor).title.ToLower()) cursor"
    if ($w.Retro) { $parts += 'retro' }
    $parts -join ', '
}

function Get-LxWindowLines {
    $w = Get-LxWindow
    "$e[1mWindow  (theme window, Windows Terminal)$e[0m"
    if (-not $w.Found) { '  Windows Terminal not found'; ''; return }
    "  transparency {0}%   blur {1}   font {2} {3}   cursor {4}   retro {5}" -f $w.Transparency, (Format-LxOnOff $w.Blur),
        (Format-LxFontName $w), (Format-LxFontSize $w), (Get-LxCursorDef $w.Cursor).name, (Format-LxOnOff $w.Retro)
    "  cursors: $((Get-LxCursors).name -join ' ')"
    ''
}

# Under the window pickers: the usual sample, plus where the change shows up
function Get-LxWindowPreview($cfg) {
    $note = if ($env:WT_SESSION) { 'Changes show up right away, in every Windows Terminal tab.' }
            else { "This isn't Windows Terminal, so you'll see the changes next time you use it." }
    @(Get-LxSample $cfg.prompt (Get-LxColor $cfg.colors)) + '' + "$e[90m$note$e[0m"
}

# Profiles with their own value don't get the default, so say which ones
function Show-LxTermOverrides([string[]]$key, [string]$what) {
    $names = @(Get-LxTermOverrides $key)
    if ($names.Count) {
        Write-Host ("Note: these Windows Terminal profiles set their own {0}, so they keep it: {1}" -f $what, ($names -join ', ')) -ForegroundColor Yellow
    }
}

# Changes a Windows Terminal setting. Windows Terminal reloads its settings 0.1-0.2 s later, which
# resets the theme colors in every tab, so wait for that and put them back in this one (other tabs
# do it at their next prompt). A font change also resizes the window; waiting for it lets the
# picker redraw at the new size.
function Set-LxWindowSetting([string[]]$key, $raw) {
    $before = Get-LxWindowSize
    if (-not (Set-LxTermRaw $key $raw) -or -not $env:WT_SESSION) { return }
    for ($n = 0; $n -lt 15; $n++) {
        Start-Sleep -Milliseconds 20
        $now = Get-LxWindowSize
        if ($now[0] -ne $before[0] -or $now[1] -ne $before[1]) { Start-Sleep -Milliseconds 40; break }
    }
    Set-LxPalette (Get-LxColor (Read-LxConfig).colors)
}

function Set-LxTransparency([string]$value) {
    $n = 0
    if (-not [int]::TryParse($value.TrimEnd('%'), [ref]$n) -or $n -lt 0 -or $n -gt 90) {
        Write-Host 'Usage: theme transparency 0-90   (percent, 0 is solid)' -ForegroundColor Red; return
    }
    if (-not (Test-LxTermFound)) { return }
    Set-LxWindowSetting @('opacity') ([string](100 - $n))
    Write-Host "Transparency: $n%"
    Show-LxTermOverrides @('opacity') 'transparency'
}

function Select-LxTransparency {
    $orig = Get-LxTermRaw @('opacity')
    $cfg = Read-LxConfig
    $transItems = @(for ($t = 0; $t -le 90; $t += 5) { [pscustomobject]@{ title = "$t%"; desc = $(if ($t -eq 0) { 'solid' } else { '' }) } })
    $i = Invoke-LxPicker -Title 'Transparency' -Items $transItems -Selected ([int][Math]::Round((Get-LxWindow).Transparency / 5)) `
        -Preview { param($i) Get-LxWindowPreview $cfg } `
        -OnMove { param($i) Set-LxWindowSetting @('opacity') ([string](100 - 5 * $i)) }
    if ($i -lt 0) { Set-LxWindowSetting @('opacity') $orig }
}

function Set-LxTermToggle([string]$what, [string]$value) {
    $keys = @{ blur = 'useAcrylic'; retro = 'experimental.retroTerminalEffect' }
    if ($value -notin 'on', 'off') { Write-Host "Usage: theme $what on|off" -ForegroundColor Red; return }
    if (-not (Test-LxTermFound)) { return }
    Set-LxWindowSetting @($keys[$what]) $(if ($value -eq 'on') { 'true' } else { 'false' })
    Write-Host "$what is now $value."
    if ($what -eq 'blur' -and $value -eq 'on' -and (Get-LxWindow).Transparency -eq 0) {
        Write-Host 'Blur only shows through a transparent background. Try: theme transparency 20'
    }
    Show-LxTermOverrides @($keys[$what]) $what
}

function Get-LxFontItems {
    $items = @([pscustomobject]@{ name = 'default'; title = 'Cascadia Mono'; desc = "Windows Terminal's default" })
    foreach ($f in Get-LxMonoFonts) {
        if ($f -eq 'Cascadia Mono') { continue }
        $desc = if ($f -match 'Nerd Font|\bNF[MP]?\b') { 'Nerd Font: icons in ls work' } else { '' }
        $items += [pscustomobject]@{ name = $f; title = $f; desc = $desc }
    }
    $items
}

function Set-LxFontFace($item) {
    Set-LxWindowSetting @('font', 'face') $(if ($item.name -eq 'default') { $null } else { ConvertTo-LxJsonString $item.name })
}

function Set-LxFont([string]$name) {
    if (-not (Test-LxTermFound)) { return }
    $items = Get-LxFontItems
    $f = if ($name -in 'default', 'reset') { $items[0] } else { $items | Where-Object { $_.name -eq $name } | Select-Object -First 1 }
    if (-not $f) {
        Write-Host "No fixed-width font called '$name' is installed. Run 'theme font' to pick one, or 'theme list' to see yours." -ForegroundColor Red
        return
    }
    Set-LxFontFace $f
    Write-Host "Font: $($f.title)"
    Show-LxTermOverrides @('font', 'face') 'font'
}

function Select-LxFont {
    $orig = Get-LxTermRaw @('font', 'face')
    $cfg = Read-LxConfig
    $fontItems = @(Get-LxFontItems)
    $current = Format-LxFontName (Get-LxWindow)
    $start = 0
    for ($j = 0; $j -lt $fontItems.Count; $j++) { if ($fontItems[$j].title -eq $current) { $start = $j } }
    $i = Invoke-LxPicker -Title 'Font' -Items $fontItems -Selected $start `
        -Preview { param($i) Get-LxWindowPreview $cfg } `
        -OnMove { param($i) Set-LxFontFace $fontItems[$i] }
    if ($i -lt 0) { Set-LxWindowSetting @('font', 'face') $orig }
}

function Set-LxFontSize([string]$value) {
    $n = 0.0
    $ok = [double]::TryParse($value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)
    if (-not $ok -or $n -lt 6 -or $n -gt 72) { Write-Host 'Usage: theme fontsize 6-72   (Windows Terminal starts at 12)' -ForegroundColor Red; return }
    if (-not (Test-LxTermFound)) { return }
    Set-LxWindowSetting @('font', 'size') $n.ToString([Globalization.CultureInfo]::InvariantCulture)
    Write-Host "Font size: $n"
    Show-LxTermOverrides @('font', 'size') 'font size'
}

function Select-LxFontSize {
    $orig = Get-LxTermRaw @('font', 'size')
    $cfg = Read-LxConfig
    $sizes = @(8..20) + 22, 24, 28, 32, 36
    $sizeItems = @(foreach ($s in $sizes) { [pscustomobject]@{ title = "$s"; desc = $(if ($s -eq 12) { 'default' } else { '' }) } })
    $current = [double](Format-LxFontSize (Get-LxWindow))
    $start = 0
    for ($j = 0; $j -lt $sizes.Count; $j++) { if ($sizes[$j] -le $current) { $start = $j } }
    $i = Invoke-LxPicker -Title 'Font size' -Items $sizeItems -Selected $start `
        -Preview { param($i) Get-LxWindowPreview $cfg } `
        -OnMove { param($i) Set-LxWindowSetting @('font', 'size') ([string]$sizes[$i]) }
    if ($i -lt 0) { Set-LxWindowSetting @('font', 'size') $orig }
}

function Set-LxCursor([string]$name) {
    $c = Resolve-LxName (Get-LxCursors) $name
    if (-not $c) { Write-Host "Unknown cursor '$name'. Try: $((Get-LxCursors).name -join ', ')" -ForegroundColor Red; return }
    if (-not (Test-LxTermFound)) { return }
    Set-LxWindowSetting @('cursorShape') (ConvertTo-LxJsonString $c.id)
    Write-Host "Cursor: $($c.title)"
    Show-LxTermOverrides @('cursorShape') 'cursor'
}

function Select-LxCursor {
    $orig = Get-LxTermRaw @('cursorShape')
    $cfg = Read-LxConfig
    $cursorItems = @(Get-LxCursors)
    $start = [array]::IndexOf(@($cursorItems.id), (Get-LxWindow).Cursor)
    $i = Invoke-LxPicker -Title 'Cursor' -Items $cursorItems -Selected $start `
        -Preview { param($i) Get-LxWindowPreview $cfg } `
        -OnMove { param($i) Set-LxWindowSetting @('cursorShape') (ConvertTo-LxJsonString $cursorItems[$i].id) }
    if ($i -lt 0) { Set-LxWindowSetting @('cursorShape') $orig }
}

function Invoke-LxWindowMenu {
    if (-not (Test-LxTermFound)) { return }
    $cfg = Read-LxConfig
    $winSel = 0
    while ($true) {
        $w = Get-LxWindow
        $winItems = @(
            [pscustomobject]@{ key = 'transparency'; title = 'Transparency'; desc = "$($w.Transparency)%" }
            [pscustomobject]@{ key = 'blur';         title = 'Blur';         desc = "$(Format-LxOnOff $w.Blur)  $e[90m(frosted glass behind a transparent background)$e[0m" }
            [pscustomobject]@{ key = 'font';         title = 'Font';         desc = Format-LxFontName $w }
            [pscustomobject]@{ key = 'fontsize';     title = 'Font size';    desc = Format-LxFontSize $w }
            [pscustomobject]@{ key = 'cursor';       title = 'Cursor';       desc = (Get-LxCursorDef $w.Cursor).title }
            [pscustomobject]@{ key = 'retro';        title = 'Retro effect'; desc = "$(Format-LxOnOff $w.Retro)  $e[90m(old CRT monitor: scanlines and glow)$e[0m" }
        )
        $winSel = Invoke-LxPicker -Title 'Window  (Windows Terminal)' -Items $winItems -Selected $winSel -Hint 'Up/Down move  Enter change  Esc back' `
            -Preview { param($i) Get-LxWindowPreview $cfg }
        if ($winSel -lt 0) { break }
        switch ($winItems[$winSel].key) {
            'transparency' { Select-LxTransparency }
            'blur'         { Set-LxWindowSetting @('useAcrylic') $(if ($w.Blur) { 'false' } else { 'true' }) }
            'font'         { Select-LxFont }
            'fontsize'     { Select-LxFontSize }
            'cursor'       { Select-LxCursor }
            'retro'        { Set-LxWindowSetting @('experimental.retroTerminalEffect') $(if ($w.Retro) { 'false' } else { 'true' }) }
        }
    }
    Show-LxTermOverrides @('opacity') 'transparency'
    Show-LxTermOverrides @('font', 'face') 'font'
    Show-LxTermOverrides @('cursorShape') 'cursor'
}

function Invoke-LxMenu {
    $menuSel = 0
    $startLogo = (Read-LxConfig).logo
    while ($true) {
        $menuCfg = Read-LxConfig
        $pd = Get-LxPromptDef $menuCfg.prompt
        $menuItems = @(
            [pscustomobject]@{ key = 'colors'; title = 'Colors';               desc = (Get-LxColor $menuCfg.colors).title }
            [pscustomobject]@{ key = 'prompt'; title = 'Prompt';               desc = "$($pd.title)  $e[90m$($pd.desc)$e[0m" }
            [pscustomobject]@{ key = 'logo';   title = 'fastfetch logo';       desc = (Get-LxLogo $menuCfg.logo).title }
            [pscustomobject]@{ key = 'window'; title = 'Window';               desc = Get-LxWindowSummary (Get-LxWindow) }
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
            'window' { Invoke-LxWindowMenu }
            'fetch'  { Save-LxSetting 'fetch' $(if ($menuCfg.fetch -eq 'on') { 'off' } else { 'on' }) }
            'icons'  { Save-LxSetting 'icons' $(if ($menuCfg.icons -eq 'on') { 'off' } else { 'on' }) }
        }
    }
    $final = Read-LxConfig
    Write-Host ("Colors: {0}   Prompt: {1}   Logo: {2}   fastfetch at startup: {3}" -f
        (Get-LxColor $final.colors).title, (Get-LxPromptDef $final.prompt).title, (Get-LxLogo $final.logo).title, $final.fetch)
    if ($final.logo -ne $startLogo -and $final.fetch -eq 'on') { Write-Host 'Run linuxify restart to see the new logo.' }
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
    Get-LxWindowLines
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
        '^window$'    { if (Test-LxInteractive) { Invoke-LxWindowMenu } else { Get-LxWindowLines }; return }
        '^transparen(cy|t)$' {
            if ($arg) { Set-LxTransparency $arg } elseif ((Test-LxInteractive) -and (Test-LxTermFound)) { Select-LxTransparency } else { Get-LxWindowLines }; return
        }
        '^blur$'      { Set-LxTermToggle 'blur' $arg; return }
        '^retro$'     { Set-LxTermToggle 'retro' $arg; return }
        '^fonts?$'    { if ($arg) { Set-LxFont $arg } elseif ((Test-LxInteractive) -and (Test-LxTermFound)) { Select-LxFont } else { Get-LxWindowLines }; return }
        '^font-?size$' { if ($arg) { Set-LxFontSize $arg } elseif ((Test-LxInteractive) -and (Test-LxTermFound)) { Select-LxFontSize } else { Get-LxWindowLines }; return }
        '^cursors?$'  { if ($arg) { Set-LxCursor $arg } elseif ((Test-LxInteractive) -and (Test-LxTermFound)) { Select-LxCursor } else { Get-LxWindowLines }; return }
        default {
            # `theme dracula` still works as a shortcut for colors
            if (Get-LxColor $sub) { Set-LxColors $sub } else { Write-Host "Unknown theme '$sub'. Run 'theme list' to see them all." -ForegroundColor Red }
        }
    }
}

# What a new terminal does at startup: clear, theme colors, fastfetch. The PowerShell profile and
# the Clink script handle `linuxify restart` themselves (and reload linuxify too); this only runs
# in a shell that was opened before linuxify 1.3.
function Restart-LxTerminal {
    $cfg = Read-LxConfig
    [Console]::Write("$e[H$e[2J$e[3J")
    if (Test-LxPaletteTerminal) { [Console]::Write((Get-LxPaletteReset) + $cfg.palette) }
    $ff = Get-Command fastfetch -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cfg.fetch -eq 'on' -and $ff -and $env:TERM_PROGRAM -ne 'vscode') { & $ff.Source @(Get-LxFetchArgs $cfg) }
}

switch ($cmd) {
    'theme'   { Invoke-LxTheme $rest }
    { $_ -in 'colors', 'prompt', 'logo', 'window', 'transparency', 'blur', 'font', 'fontsize', 'cursor', 'retro' } {
        Invoke-LxTheme (@($cmd) + $rest)
    }
    { $_ -in 'restart', 'reload' } { Restart-LxTerminal }
    'sudo'    { Set-LxSudo $rest[0] }
    'fetch'   { Set-Toggle 'fetch' $rest[0] }
    'icons'   { Set-Toggle 'icons' $rest[0] }
    'update'  {
        Invoke-RestMethod "https://raw.githubusercontent.com/$($Linuxify.Repo)/main/install.ps1" | Invoke-Expression
    }
    'uninstall' { & (Join-Path $Linuxify.Home 'uninstall.ps1') }
    'version' { $Linuxify.Version }
    default   { Show-Help }
}
