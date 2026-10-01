# linuxify window settings for Windows Terminal: transparency, blur, font, cursor, retro effect.
# Dot-sourced after core.ps1 by cli.ps1 and uninstall.ps1. Keep this file ASCII-only.
# Settings go into "profiles" > "defaults" in Windows Terminal's settings.json, so they apply
# to every tab. The file is edited as text instead of being parsed and rewritten, so its
# formatting, comments and everything else in it stay exactly as they were.

$LxTermBackupPath = Join-Path $env:LOCALAPPDATA 'linuxify\terminal-backup.txt'

# --- JSON with comments, edited in place ---

# Strings, comments, punctuation, and bare words (numbers, true, false, null)
$LxJsonTokenPattern = '"(?:[^"\\]|\\.)*"|//[^\n]*|/\*[\s\S]*?\*/|[{}\[\]:,]|[^\s{}\[\]:,"/]+'

# Parses JSON into nodes that remember where they are in the text (End is just past the node):
#   @{ Kind = 'object'; Start; End; Members = list of @{ Key; KeyStart; Node } }
#   @{ Kind = 'array';  Start; End; Items }
#   @{ Kind = 'value';  Start; End }
function ConvertFrom-LxJsonc([string]$text) {
    $tokens = New-Object Collections.Generic.List[object]
    foreach ($m in [regex]::Matches($text, $LxJsonTokenPattern)) { if ($m.Value[0] -ne '/') { $tokens.Add($m) } }
    $st = @{ T = $tokens; I = 0 }
    Read-LxJsonNode $st
}

function Read-LxJsonNode($st) {
    if ($st.I -ge $st.T.Count) { throw 'the file ends too early' }
    $t = $st.T[$st.I]; $st.I++
    if ($t.Value -eq '{') {
        $members = New-Object Collections.ArrayList
        while ($true) {
            if ($st.I -ge $st.T.Count) { throw "a '{' is never closed" }
            $k = $st.T[$st.I]
            if ($k.Value -eq '}') { break }
            if ($k.Value[0] -ne '"' -or $st.I + 1 -ge $st.T.Count -or $st.T[$st.I + 1].Value -ne ':') {
                throw "unexpected '$($k.Value)' at character $($k.Index)"
            }
            $st.I += 2
            $node = Read-LxJsonNode $st
            [void]$members.Add(@{ Key = $k.Value.Substring(1, $k.Length - 2); KeyStart = $k.Index; Node = $node })
            if ($st.I -lt $st.T.Count -and $st.T[$st.I].Value -eq ',') { $st.I++ }
        }
        $st.I++
        return @{ Kind = 'object'; Start = $t.Index; End = $k.Index + 1; Members = $members }
    }
    if ($t.Value -eq '[') {
        $items = New-Object Collections.ArrayList
        while ($true) {
            if ($st.I -ge $st.T.Count) { throw "a '[' is never closed" }
            $close = $st.T[$st.I]
            if ($close.Value -eq ']') { break }
            [void]$items.Add((Read-LxJsonNode $st))
            if ($st.I -lt $st.T.Count -and $st.T[$st.I].Value -eq ',') { $st.I++ }
        }
        $st.I++
        return @{ Kind = 'array'; Start = $t.Index; End = $close.Index + 1; Items = $items }
    }
    if ($t.Value -in '}', ']', ':', ',') { throw "unexpected '$($t.Value)' at character $($t.Index)" }
    @{ Kind = 'value'; Start = $t.Index; End = $t.Index + $t.Length }
}

function Find-LxJsonMember($node, [string]$key) {
    $found = $null
    # like most JSON readers, a repeated key means the last one counts
    if ($node.Kind -eq 'object') { foreach ($m in $node.Members) { if ($m.Key -ceq $key) { $found = $m } } }
    $found
}

function Get-LxJsonNodeAt($node, [string[]]$path) {
    foreach ($key in $path) {
        $m = Find-LxJsonMember $node $key
        if (-not $m) { return $null }
        $node = $m.Node
    }
    $node
}

function Get-LxJsonText([string]$text, $node) { $text.Substring($node.Start, $node.End - $node.Start) }

# The value at $path (e.g. 'profiles', 'defaults', 'opacity') as JSON text, or $null if it isn't there.
function Get-LxJsonRaw([string]$text, [string[]]$path) {
    $node = Get-LxJsonNodeAt (ConvertFrom-LxJsonc $text) $path
    if ($node) { Get-LxJsonText $text $node } else { $null }
}

# Returns $text with the value at $path set to $raw (JSON text), or removed when $raw is $null.
# Objects missing along the way are created.
function Set-LxJsonRaw([string]$text, [string[]]$path, $raw) {
    $node = ConvertFrom-LxJsonc $text
    if ($node.Kind -ne 'object') { throw "it doesn't start with '{'" }
    $depth = 0
    for (; $depth -lt $path.Count - 1; $depth++) {
        $m = Find-LxJsonMember $node $path[$depth]
        if (-not $m) { break }
        if ($m.Node.Kind -ne 'object') { throw "`"$($path[$depth])`" isn't an object (an old settings format?)" }
        $node = $m.Node
    }
    $m = $null
    if ($depth -eq $path.Count - 1) { $m = Find-LxJsonMember $node $path[$depth] }
    if ($m) {
        if ($null -eq $raw) { return Remove-LxJsonMember $text $node $m }
        return $text.Substring(0, $m.Node.Start) + $raw + $text.Substring($m.Node.End)
    }
    if ($null -eq $raw) { return $text }
    Add-LxJsonMember $text $node $path[$depth] @($path | Select-Object -Skip ($depth + 1)) $raw
}

function Get-LxLineIndent([string]$text, [int]$pos) {
    $start = if ($pos -gt 0) { $text.LastIndexOf([char]10, $pos - 1) + 1 } else { 0 }
    $i = $start
    while ($i -lt $text.Length -and ($text[$i] -eq ' ' -or $text[$i] -eq "`t")) { $i++ }
    $text.Substring($start, $i - $start)
}

# "key": value, creating any objects still missing on the way: "font": { "face": "X" }
function Format-LxJsonMember([string]$key, [string[]]$rest, [string]$raw, [string]$indent, [string]$unit, [string]$nl) {
    $value = $raw
    if ($rest.Count) {
        $inner = $indent + $unit
        $value = '{' + $nl + $inner + (Format-LxJsonMember $rest[0] @($rest | Select-Object -Skip 1) $raw $inner $unit $nl) + $nl + $indent + '}'
    }
    '"' + $key + '": ' + $value
}

function Add-LxJsonMember([string]$text, $obj, [string]$key, [string[]]$rest, [string]$raw) {
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $um = [regex]::Match($text, '\n([ \t]+)"')
    $unit = if ($um.Success) { $um.Groups[1].Value } else { '    ' }
    if ($obj.Members.Count) {
        $first = $obj.Members[0]
        $last = $obj.Members[$obj.Members.Count - 1]
        if ($text.Substring($obj.Start, $first.KeyStart - $obj.Start).Contains("`n")) {
            $indent = Get-LxLineIndent $text $last.KeyStart
            $add = ",$nl$indent" + (Format-LxJsonMember $key $rest $raw $indent $unit $nl)
        } else {
            $add = ', ' + (Format-LxJsonMember $key $rest $raw '' '' ' ')
        }
        return $text.Insert($last.Node.End, $add)
    }
    $outer = Get-LxLineIndent $text $obj.Start
    $indent = $outer + $unit
    $body = '{' + $nl + $indent + (Format-LxJsonMember $key $rest $raw $indent $unit $nl) + $nl + $outer + '}'
    $text.Substring(0, $obj.Start) + $body + $text.Substring($obj.End)
}

function Remove-LxJsonMember([string]$text, $obj, $m) {
    $idx = $obj.Members.IndexOf($m)
    if ($obj.Members.Count -eq 1) { return $text.Substring(0, $obj.Start + 1) + $text.Substring($obj.End - 1) }
    if ($idx -gt 0) { $from = $obj.Members[$idx - 1].Node.End; $to = $m.Node.End }
    else { $from = $m.KeyStart; $to = $obj.Members[1].KeyStart }
    $text.Remove($from, $to - $from)
}

function ConvertTo-LxJsonString([string]$s) { '"' + $s.Replace('\', '\\').Replace('"', '\"') + '"' }
function ConvertFrom-LxJsonString([string]$raw) { if ($raw -match '^"(.*)"$') { [regex]::Unescape($Matches[1]) } }

# --- Windows Terminal's settings.json (found by Get-LxTermFiles in core.ps1) ---

# A setting from "profiles" > "defaults" (e.g. 'opacity', or 'font', 'face') as JSON text, or $null if unset
function Get-LxTermRaw([string[]]$key) {
    $file = Get-LxTermFiles | Select-Object -First 1
    if (-not $file) { return $null }
    try { Get-LxJsonRaw ([IO.File]::ReadAllText($file)) (@('profiles', 'defaults') + $key) } catch { $null }
}

# Sets a setting in "profiles" > "defaults", or removes it (with $null) along with any
# object that leaves empty, like "font": {}
function Set-LxTermText([string]$text, [string[]]$key, $raw) {
    $path = @('profiles', 'defaults') + $key
    $text = Set-LxJsonRaw $text $path $raw
    if ($null -eq $raw) {
        for ($n = $path.Count - 1; $n -gt 2; $n--) {
            $parent = $path[0..($n - 1)]
            $node = Get-LxJsonNodeAt (ConvertFrom-LxJsonc $text) $parent
            if (-not $node -or $node.Kind -ne 'object' -or $node.Members.Count) { break }
            $text = Set-LxJsonRaw $text $parent $null
        }
    }
    $text
}

# Sets a setting (or removes it, with $null) in every settings.json. Windows Terminal applies it
# right away. Returns whether any file changed.
function Set-LxTermRaw([string[]]$key, $raw) {
    $changed = $false
    foreach ($file in Get-LxTermFiles) {
        $text = [IO.File]::ReadAllText($file)
        try { $new = Set-LxTermText $text $key $raw }
        catch { Write-Host "Couldn't change $file`: $($_.Exception.Message)" -ForegroundColor Red; continue }
        if ($new -ceq $text) { continue }
        Save-LxTermBackup $file $text $key
        Save-LxTermFile $file $new
        $changed = $true
    }
    $changed
}

# Before the first change: a copy of the whole file next to it, plus each setting's original
# value in terminal-backup.txt, so `linuxify uninstall` can put them back.
function Save-LxTermBackup([string]$file, [string]$text, [string[]]$key) {
    $copy = "$file.linuxify-backup"
    if (-not (Test-Path -LiteralPath $copy)) { Copy-Item -LiteralPath $file $copy }
    $id = "$file`t$($key -join '/')`t"
    $lines = @(if (Test-Path -LiteralPath $LxTermBackupPath) { [IO.File]::ReadAllLines($LxTermBackupPath) })
    if ($lines | Where-Object { $_.StartsWith($id) }) { return }
    $old = try { Get-LxJsonRaw $text (@('profiles', 'defaults') + $key) } catch { $null }
    $old = if ($null -eq $old) { '' } else { $old -replace '\s*\r?\n\s*', ' ' }
    $dir = Split-Path $LxTermBackupPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::AppendAllText($LxTermBackupPath, "$id$old`r`n", (New-Object Text.UTF8Encoding $false))
}

function Save-LxTermFile([string]$file, [string]$text) {
    $bytes = [IO.File]::ReadAllBytes($file)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $enc = New-Object Text.UTF8Encoding $bom
    # write a new file and swap it in, so Windows Terminal never reads a half-written one
    $tmp = "$file.linuxify-tmp"
    [IO.File]::WriteAllText($tmp, $text, $enc)
    try { [IO.File]::Replace($tmp, $file, [NullString]::Value) }
    catch {
        [IO.File]::WriteAllText($file, $text, $enc)
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }
}

# Puts back every value linuxify changed (for uninstall). Returns whether there was anything to do.
function Restore-LxTerminal {
    if (-not (Test-Path -LiteralPath $LxTermBackupPath)) { return $false }
    foreach ($line in [IO.File]::ReadAllLines($LxTermBackupPath)) {
        $f = $line.Split([char]9, 3)
        if ($f.Count -lt 3 -or -not (Test-Path -LiteralPath $f[0])) { continue }
        $text = [IO.File]::ReadAllText($f[0])
        $raw = if ($f[2]) { $f[2] } else { $null }
        try { $new = Set-LxTermText $text $f[1].Split('/') $raw } catch { continue }
        if ($new -cne $text) { Save-LxTermFile $f[0] $new }
    }
    Remove-Item -LiteralPath $LxTermBackupPath
    $true
}

# Names of the profiles that set this themselves, so the default doesn't reach them
function Get-LxTermOverrides([string[]]$key) {
    $file = Get-LxTermFiles | Select-Object -First 1
    if (-not $file) { return }
    $text = [IO.File]::ReadAllText($file)
    try { $list = Get-LxJsonNodeAt (ConvertFrom-LxJsonc $text) @('profiles', 'list') } catch { return }
    if (-not $list -or $list.Kind -ne 'array') { return }
    $legacy = @{ 'font/face' = 'fontFace'; 'font/size' = 'fontSize' }[$key -join '/']
    foreach ($p in $list.Items) {
        if ($p.Kind -ne 'object') { continue }
        $hidden = Get-LxJsonNodeAt $p @('hidden')
        if ($hidden -and (Get-LxJsonText $text $hidden) -eq 'true') { continue }
        if ((Get-LxJsonNodeAt $p $key) -or ($legacy -and (Find-LxJsonMember $p $legacy))) {
            $name = Get-LxJsonNodeAt $p @('name')
            if ($name) { ConvertFrom-LxJsonString (Get-LxJsonText $text $name) }
        }
    }
}

# --- What linuxify offers ---

function Get-LxCursors {
    @(
        [pscustomobject]@{ name = 'bar';        id = 'bar';              title = 'Bar';               desc = 'thin line (the default)' }
        [pscustomobject]@{ name = 'block';      id = 'filledBox';        title = 'Block';             desc = 'like the Linux console' }
        [pscustomobject]@{ name = 'underscore'; id = 'underscore';       title = 'Underscore';        desc = '' }
        [pscustomobject]@{ name = 'box';        id = 'emptyBox';         title = 'Empty box';         desc = '' }
        [pscustomobject]@{ name = 'double';     id = 'doubleUnderscore'; title = 'Double underscore'; desc = '' }
        [pscustomobject]@{ name = 'vintage';    id = 'vintage';          title = 'Vintage';           desc = 'thick underscore, like old terminals' }
    )
}

# Current window settings, with Windows Terminal's defaults filled in
function Get-LxWindow {
    $w = @{ Found = $false; Transparency = 0; Blur = $false; Font = ''; Size = 0; Cursor = 'bar'; Retro = $false }
    $file = Get-LxTermFiles | Select-Object -First 1
    if (-not $file) { return $w }
    $w.Found = $true
    $text = [IO.File]::ReadAllText($file)
    try { $d = Get-LxJsonNodeAt (ConvertFrom-LxJsonc $text) @('profiles', 'defaults') } catch { $d = $null }
    if (-not $d) { return $w }
    $get = { param([string[]]$k) $n = Get-LxJsonNodeAt $d $k; if ($n) { Get-LxJsonText $text $n } }
    $v = & $get 'opacity'
    if ($v -match '^\d+(\.\d+)?$') { $w.Transparency = [Math]::Max(0, 100 - [int][double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture)) }
    $w.Blur = (& $get 'useAcrylic') -eq 'true'
    $v = & $get 'font', 'face'
    if ($v) { $w.Font = ConvertFrom-LxJsonString $v }
    $v = & $get 'font', 'size'
    if ($v -match '^\d+(\.\d+)?$') { $w.Size = [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture) }
    $v = ConvertFrom-LxJsonString (& $get 'cursorShape')
    if ($v) { $w.Cursor = $v }
    $w.Retro = (& $get 'experimental.retroTerminalEffect') -eq 'true'
    $w
}

# Installed fixed-width fonts, the kind that look right in a terminal
function Get-LxMonoFonts {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object Drawing.Bitmap 1, 1
    $g = [Drawing.Graphics]::FromImage($bmp)
    $fmt = [Drawing.StringFormat]::GenericTypographic
    $names = New-Object Collections.Generic.List[string]
    try {
        foreach ($fam in (New-Object Drawing.Text.InstalledFontCollection).Families) {
            # skip symbol fonts, vertical CJK (@...) and the rare-character CJK extensions (...-ExtB)
            if ($fam.Name -match '^@|Wingdings|Webdings|Marlett|Symbol|MDL2|Icons|Emoji|MT Extra|-Ext[A-Z]$') { continue }
            if (-not $fam.IsStyleAvailable([Drawing.FontStyle]::Regular)) { continue }
            $font = New-Object Drawing.Font $fam, 20, ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
            $narrow = $g.MeasureString('iiiiiiiiii', $font, 10000, $fmt).Width
            $wide = $g.MeasureString('WWWWWWWWWW', $font, 10000, $fmt).Width
            $font.Dispose()
            if ($narrow -gt 0 -and [Math]::Abs($narrow - $wide) -lt 1) { $names.Add($fam.Name) }
        }
    } finally { $g.Dispose(); $bmp.Dispose() }
    # each weight shows up as its own family (Cascadia Code Light...); keep just the main one
    $all = @{}
    foreach ($n in $names) { $all[$n] = $true }
    $names | Where-Object {
        -not ($_ -match '^(.+?) (Thin|ExtraLight|UltraLight|Light|SemiLight|DemiLight|Medium|SemiBold|DemiBold|ExtraBold|UltraBold|Black|Heavy)$' -and $all.ContainsKey($Matches[1]))
    } | Sort-Object
}
