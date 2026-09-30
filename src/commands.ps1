# linuxify Linux commands and shell habits for PowerShell.
# Dot-sourced by profile.ps1, and by lx.ps1 which runs them for cmd.exe.
# Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less scripts as ANSI).

$LxE = [char]27
$LxCommandsPath = $PSCommandPath

# --- Helpers ---

# Splits Linux-style arguments: -abc, -n 5, -n5, --long, --long=value, and -- to end options.
# $WithValue lists the short flags that take a value. -NumberFlag turns -20 into n=20 (head/tail).
function Split-LxArgs([object[]]$Argv, [string]$WithValue = '', [switch]$NumberFlag) {
    $flags = @{}
    $rest = New-Object Collections.Generic.List[object]
    $end = $false
    for ($i = 0; $i -lt $Argv.Count; $i++) {
        $a = $Argv[$i]
        # PowerShell parses a bare -20 as the number -20
        if ($NumberFlag -and -not $end -and ($a -is [int] -or $a -is [long]) -and $a -lt 0) { $flags['n'] = [string](-$a); continue }
        $s = [string]$a
        if ($end -or $a -isnot [string] -or $s -notmatch '^-.') { $rest.Add($a); continue }
        if ($s -eq '--') { $end = $true; continue }
        if ($s -match '^--([^=]+)(=(.*))?$') { $flags[$Matches[1]] = $(if ($Matches[2]) { $Matches[3] } else { $true }); continue }
        if ($NumberFlag -and $s -match '^-(\d+)$') { $flags['n'] = $Matches[1]; continue }
        $chars = $s.Substring(1)
        for ($j = 0; $j -lt $chars.Length; $j++) {
            $c = [string]$chars[$j]
            if ($WithValue.Contains($c)) {
                $v = $chars.Substring($j + 1)
                if (-not $v -and $i + 1 -lt $Argv.Count) { $i++; $v = [string]$Argv[$i] }
                $flags[$c] = $v
                break
            }
            $flags[$c] = $true
        }
    }
    @{ Flags = $flags; Rest = $rest }
}

# Errors: real stderr for cmd (so 2>nul works); in PowerShell a plain red line
# instead of Write-Error's multi-line block (hide it with *>$null).
function Write-LxError([string]$msg) {
    if ($LxForceLinux -and -not $Linuxify.Version) { [Console]::Error.WriteLine($msg) } else { Write-Host $msg -ForegroundColor Red }
}

# True when the Linux version of a built-in PowerShell command should run: typed at the
# prompt (scripts keep the normal PowerShell behavior) and not using PowerShell-style
# parameters like -Force or -Recurse.
function Test-LxLinuxCall($invocation, [object[]]$argv, [string]$cmdlet) {
    if ($LxForceLinux) { return $true }
    if ($invocation.CommandOrigin -ne 'Runspace') { return $false }
    $params = @((Get-Command $cmdlet).Parameters.Keys)
    foreach ($a in $argv) {
        if ($a -is [string] -and $a -match '^-([A-Za-z]{2,})$') {
            $name = $Matches[1]
            if ($params | Where-Object { $_ -like "$name*" }) { return $false }
        }
    }
    $true
}

# Whether output should be colored: going to the screen, not into a pipe or file.
function Test-LxColorOut($invocation) {
    -not [Console]::IsOutputRedirected -and $invocation.PipelinePosition -eq $invocation.PipelineLength
}

# Pipeline input as text lines (objects are formatted like they'd show on screen).
function Get-LxInputLines {
    # (skips the blank line PowerShell puts above tables)
    $started = $false
    $input | Out-String -Stream -Width 4096 | ForEach-Object {
        if ($started -or $_.Trim()) { $started = $true; $_.TrimEnd() }
    }
}

function Get-LxFullPath([string]$path) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
}

# Paths as typed, with wildcards expanded like a Linux shell would.
function Resolve-LxPaths([object[]]$paths, [string]$cmd, [switch]$Quiet) {
    foreach ($p in $paths) {
        $p = [string]$p
        if (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p -Force; continue }
        if ($p -match '[*?\[]') {
            $found = @(Get-Item -Path $p -Force -ErrorAction SilentlyContinue)
            if ($found) { $found; continue }
        }
        if (-not $Quiet) { Write-LxError "${cmd}: cannot access '$p': No such file or directory" }
        $global:LASTEXITCODE = 1
    }
}

function Get-LxDisplayPath($item) {
    $rel = $item.FullName
    $cwd = (Get-Location).ProviderPath.TrimEnd('\') + '\'
    if ($rel.StartsWith($cwd, [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($cwd.Length) }
    $rel -replace '\\', '/'
}

# 1536 -> 1.5K (df -h style) or 1.5Ki (free -h style)
function Format-LxSize([double]$bytes, [switch]$Iec) {
    $units = 'B', 'K', 'M', 'G', 'T', 'P'
    $i = 0
    while ($bytes -ge 1024 -and $i -lt $units.Count - 1) { $bytes /= 1024; $i++ }
    $u = $units[$i]
    if ($Iec -and $i -gt 0) { $u += 'i' }
    if ($i -eq 0) { return "$([Math]::Round($bytes))$(if ($Iec) { 'B' })" }
    if ($bytes -lt 10) { return ('{0:0.0}{1}' -f $bytes, $u) }
    '{0:0}{1}' -f $bytes, $u
}

# --- Linux commands ---

function which {
    $p = Split-LxArgs $args
    $all = $p.Flags.a
    $global:LASTEXITCODE = 0
    foreach ($name in $p.Rest) {
        $cmds = @(Get-Command ([string]$name) -All -ErrorAction SilentlyContinue)
        if (-not $all) { $cmds = @($cmds | Select-Object -First 1) }
        if (-not $cmds) { Write-LxError "which: no $name in ($($env:Path))"; $global:LASTEXITCODE = 1; continue }
        foreach ($c in $cmds) {
            switch ($c.CommandType) {
                'Application'    { $c.Source }
                'ExternalScript' { $c.Source }
                'Alias'          { "${name}: aliased to $($c.Definition)" }
                'Function'       { "${name}: shell function" }
                'Cmdlet'         { "${name}: PowerShell cmdlet ($($c.ModuleName))" }
                default          { "${name}: $($c.CommandType)" }
            }
        }
    }
}

function touch {
    $p = Split-LxArgs $args
    $global:LASTEXITCODE = 0
    foreach ($name in $p.Rest) {
        $full = Get-LxFullPath ([string]$name)
        if (Test-Path -LiteralPath $full) {
            $now = Get-Date
            $item = Get-Item -LiteralPath $full -Force
            $item.LastWriteTime = $now
            $item.LastAccessTime = $now
        } elseif (-not $p.Flags.c) {
            if (-not (Test-Path -LiteralPath (Split-Path $full -Parent))) {
                Write-LxError "touch: cannot touch '$name': No such file or directory"; $global:LASTEXITCODE = 1; continue
            }
            [IO.File]::Create($full).Dispose()
        }
    }
}

function head {
    $p = Split-LxArgs $args 'n' -NumberFlag
    $n = if ($p.Flags.n) { [int]$p.Flags.n } else { 10 }
    $global:LASTEXITCODE = 0
    if (-not $p.Rest.Count) {
        if (-not $MyInvocation.ExpectingInput) { Write-LxError 'head: missing file (or pipe something in)'; $global:LASTEXITCODE = 1; return }
        $input | Get-LxInputLines | Select-Object -First $n
        return
    }
    $files = @(Resolve-LxPaths $p.Rest 'head')
    foreach ($f in $files) {
        if ($files.Count -gt 1) { "==> $($f.Name) <==" }
        Get-Content -LiteralPath $f.FullName -TotalCount $n
        if ($files.Count -gt 1 -and $f -ne $files[-1]) { '' }
    }
}

function tail {
    $p = Split-LxArgs $args 'n' -NumberFlag
    $spec = if ($p.Flags.n) { [string]$p.Flags.n } else { '10' }
    $fromStart = $spec.StartsWith('+')
    $n = [int]$spec.TrimStart('+')
    $global:LASTEXITCODE = 0
    if (-not $p.Rest.Count) {
        if (-not $MyInvocation.ExpectingInput) { Write-LxError 'tail: missing file (or pipe something in)'; $global:LASTEXITCODE = 1; return }
        $lines = @($input | Get-LxInputLines)
        if ($fromStart) { $lines | Select-Object -Skip ([Math]::Max(0, $n - 1)) } else { $lines | Select-Object -Last $n }
        return
    }
    $files = @(Resolve-LxPaths $p.Rest 'tail')
    foreach ($f in $files) {
        if ($files.Count -gt 1) { "==> $($f.Name) <==" }
        if ($fromStart) {
            Get-Content -LiteralPath $f.FullName | Select-Object -Skip ([Math]::Max(0, $n - 1))
        } elseif ($p.Flags.f -and $files.Count -eq 1) {
            Get-Content -LiteralPath $f.FullName -Tail $n -Wait   # Ctrl+C to stop
        } else {
            Get-Content -LiteralPath $f.FullName -Tail $n
        }
    }
}

function grep {
    $p = Split-LxArgs $args 'em'
    $f = $p.Flags
    $rest = $p.Rest
    $global:LASTEXITCODE = 1
    $pattern = $f.e
    if (-not $pattern) {
        if (-not $rest.Count) { Write-LxError "usage: grep [-ivnclLrwFoqs] [-m NUM] PATTERN [FILE...]"; $global:LASTEXITCODE = 2; return }
        $pattern = [string]$rest[0]
        $rest.RemoveAt(0)
    }
    if ($f.F) { $pattern = [regex]::Escape($pattern) }
    if ($f.w) { $pattern = "(?<!\w)(?:$pattern)(?!\w)" }
    $opts = [Text.RegularExpressions.RegexOptions]::None
    if ($f.i) { $opts = $opts -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase }
    try { $re = New-Object Text.RegularExpressions.Regex $pattern, $opts }
    catch { Write-LxError "grep: invalid pattern: $pattern"; $global:LASTEXITCODE = 2; return }

    $color = (Test-LxColorOut $MyInvocation) -and $f.color -ne 'never'
    $recursive = $f.r -or $f.R
    $maxCount = if ($f.m) { [int]$f.m } else { [int]::MaxValue }

    # Sources: files (and folders with -r), or piped text
    $sources = New-Object Collections.Generic.List[object]
    if (-not $rest.Count -and $recursive) { $rest.Add('.') }
    if ($rest.Count) {
        foreach ($item in Resolve-LxPaths $rest 'grep' -Quiet:([bool]$f.s)) {
            if ($item.PSIsContainer) {
                if ($recursive) { Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $sources.Add($_) } }
                elseif (-not $f.s) { Write-LxError "grep: $($item.Name): Is a directory" }
            } else { $sources.Add($item) }
        }
    } elseif ($MyInvocation.ExpectingInput) {
        $sources.Add([pscustomobject]@{ Lines = @($input | Get-LxInputLines); Name = '(standard input)' })
    } else {
        Write-LxError 'grep: no input (give a file, use -r, or pipe something in)'; $global:LASTEXITCODE = 2; return
    }
    $showName = ($f.H -or $sources.Count -gt 1 -or $recursive) -and -not $f.h

    $cName = if ($color) { "$LxE[35m" } else { '' }; $cNum = if ($color) { "$LxE[32m" } else { '' }
    $cSep = if ($color) { "$LxE[36m" } else { '' };  $cHit = if ($color) { "$LxE[01;31m" } else { '' }
    $r0 = if ($color) { "$LxE[0m" } else { '' }

    foreach ($src in $sources) {
        if ($src -is [IO.FileInfo]) {
            $name = Get-LxDisplayPath $src
            # binary files: report a match instead of printing garbage
            $buf = New-Object byte[] 8000
            try { $fs = [IO.File]::OpenRead($src.FullName); $read = $fs.Read($buf, 0, $buf.Length); $fs.Dispose() }
            catch { if (-not $f.s) { Write-LxError "grep: ${name}: Permission denied" }; continue }
            if ([Array]::IndexOf($buf, [byte]0, 0, $read) -ge 0) {
                if ($src.Length -lt 50MB -and $re.IsMatch([IO.File]::ReadAllText($src.FullName, [Text.Encoding]::GetEncoding(28591))) -xor [bool]$f.v) {
                    $global:LASTEXITCODE = 0
                    if ($f.q) { return }
                    if ($f.l) { "$cName$name$r0" } elseif (-not $f.c -and -not $f.L) { "Binary file $name matches" }
                }
                continue
            }
            $lines = [IO.File]::ReadLines($src.FullName)
        } else {
            $name = $src.Name
            $lines = $src.Lines
        }
        $count = 0; $num = 0
        foreach ($line in $lines) {
            $num++
            $hit = $re.IsMatch($line) -xor [bool]$f.v
            if (-not $hit) { continue }
            $count++
            $global:LASTEXITCODE = 0
            if ($f.q) { return }
            if ($f.l -or $f.L) { break }
            if (-not $f.c) {
                $prefix = ''
                if ($showName) { $prefix += "$cName$name$r0$cSep`:$r0" }
                if ($f.n) { $prefix += "$cNum$num$r0$cSep`:$r0" }
                if ($f.o -and -not $f.v) {
                    foreach ($m in $re.Matches($line)) { "$prefix$cHit$($m.Value)$r0" }
                } elseif ($color -and -not $f.v) {
                    $prefix + $re.Replace($line, { param($m) "$cHit$($m.Value)$r0" })
                } else {
                    "$prefix$line"
                }
            }
            if ($count -ge $maxCount) { break }
        }
        if ($f.l -and $count) { "$cName$name$r0" }
        if ($f.L -and -not $count) { "$cName$name$r0" }
        if ($f.c) { if ($showName) { "$cName$name$r0$cSep`:$r0$count" } else { "$count" } }
    }
}

function wc {
    $p = Split-LxArgs $args
    $f = $p.Flags
    $show = @(if ($f.l) { 'l' }; if ($f.w) { 'w' }; if ($f.m) { 'm' }; if ($f.c) { 'c' })
    if (-not $show) { $show = 'l', 'w', 'c' }
    $global:LASTEXITCODE = 0
    $rows = New-Object Collections.Generic.List[object]
    if ($p.Rest.Count) {
        foreach ($item in Resolve-LxPaths $p.Rest 'wc') {
            if ($item.PSIsContainer) { Write-LxError "wc: $($item.Name): Is a directory"; continue }
            $text = [IO.File]::ReadAllText($item.FullName)
            $rows.Add(@{ l = ([regex]::Matches($text, "`n")).Count; w = ([regex]::Matches($text, '\S+')).Count
                         m = $text.Length; c = $item.Length; name = (Get-LxDisplayPath $item) })
        }
    } elseif ($MyInvocation.ExpectingInput) {
        $lines = @($input | Get-LxInputLines)
        $text = ($lines -join "`n") + $(if ($lines.Count) { "`n" })
        $rows.Add(@{ l = $lines.Count; w = ([regex]::Matches($text, '\S+')).Count; m = $text.Length
                     c = [Text.Encoding]::UTF8.GetByteCount($text); name = '' })
    } else {
        Write-LxError 'wc: missing file (or pipe something in)'; $global:LASTEXITCODE = 1; return
    }
    if ($rows.Count -gt 1) {
        $total = @{ name = 'total' }
        foreach ($k in 'l', 'w', 'm', 'c') { $total[$k] = ($rows | ForEach-Object { $_[$k] } | Measure-Object -Sum).Sum }
        $rows.Add($total)
    }
    $width = [Math]::Max(1, (($rows | ForEach-Object { foreach ($k in $show) { "$($_[$k])".Length } }) | Measure-Object -Maximum).Maximum)
    foreach ($r in $rows) {
        (($show | ForEach-Object { "$($r[$_])".PadLeft($width) }) -join ' ') + $(if ($r.name) { " $($r.name)" })
    }
}

function df {
    $p = Split-LxArgs $args
    $human = $p.Flags.h -or $p.Flags.H
    $withType = $p.Flags.T
    $rows = New-Object Collections.Generic.List[object]
    $header = @('Filesystem')
    if ($withType) { $header += 'Type' }
    $header += $(if ($human) { 'Size' } else { '1K-blocks' }), 'Used', 'Avail', 'Use%', 'Mounted on'
    $rows.Add($header)
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady) { continue }
        $label = try { $d.VolumeLabel } catch { '' }
        if (-not $label) { $label = "$($d.DriveType)" }
        $size = [double]$d.TotalSize; $avail = [double]$d.AvailableFreeSpace; $used = $size - [double]$d.TotalFreeSpace
        $pct = if ($size) { '{0}%' -f [Math]::Ceiling($used / $size * 100) } else { '-' }
        $fmt = if ($human) { { param($b) Format-LxSize $b } } else { { param($b) [string][Math]::Round($b / 1024) } }
        $row = @($label)
        if ($withType) { $row += $d.DriveFormat }
        $row += (& $fmt $size), (& $fmt $used), (& $fmt $avail), $pct, $d.Name
        $rows.Add($row)
    }
    $cols = $rows[0].Count
    $w = foreach ($c in 0..($cols - 1)) { ($rows | ForEach-Object { "$($_[$c])".Length } | Measure-Object -Maximum).Maximum }
    foreach ($r in $rows) {
        $cells = for ($c = 0; $c -lt $cols; $c++) {
            # text columns left-aligned, numbers right-aligned
            if ($c -eq 0 -or $c -eq $cols - 1 -or ($withType -and $c -eq 1)) { "$($r[$c])".PadRight($w[$c]) } else { "$($r[$c])".PadLeft($w[$c]) }
        }
        ($cells -join ' ').TrimEnd()
    }
}

function free {
    $p = Split-LxArgs $args
    $f = $p.Flags
    $os = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory
    $total = [double]$os.TotalVisibleMemorySize * 1024
    $avail = [double]$os.FreePhysicalMemory * 1024
    $swapTotal = 0.0; $swapUsed = 0.0
    foreach ($pf in @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)) {
        $swapTotal += [double]$pf.AllocatedBaseSize * 1MB; $swapUsed += [double]$pf.CurrentUsage * 1MB
    }
    $fmt = if ($f.h) { { param($b) Format-LxSize $b -Iec } }
           elseif ($f.b) { { param($b) [string][Math]::Round($b) } }
           elseif ($f.m) { { param($b) [string][Math]::Round($b / 1MB) } }
           elseif ($f.g) { { param($b) [string][Math]::Round($b / 1GB) } }
           else { { param($b) [string][Math]::Round($b / 1KB) } }
    $rows = @(
        , @('', 'total', 'used', 'available')
        , @('Mem:', (& $fmt $total), (& $fmt ($total - $avail)), (& $fmt $avail))
        , @('Swap:', (& $fmt $swapTotal), (& $fmt $swapUsed), (& $fmt ($swapTotal - $swapUsed)))
    )
    foreach ($r in $rows) { $r[0].PadRight(6) + (($r[1..3] | ForEach-Object { $_.PadLeft(12) }) -join '') }
}

function uptime {
    $p = Split-LxArgs $args
    $boot = (Get-CimInstance Win32_OperatingSystem -Property LastBootUpTime).LastBootUpTime
    if ($p.Flags.s) { return $boot.ToString('yyyy-MM-dd HH:mm:ss') }
    $up = (Get-Date) - $boot
    if ($p.Flags.p) {
        $parts = @()
        if ($up.Days -ge 7)  { $w = [Math]::Floor($up.Days / 7); $parts += "$w week$(if ($w -ne 1) { 's' })" }
        if ($up.Days % 7)    { $parts += "$($up.Days % 7) day$(if ($up.Days % 7 -ne 1) { 's' })" }
        if ($up.Hours)       { $parts += "$($up.Hours) hour$(if ($up.Hours -ne 1) { 's' })" }
        if ($up.Minutes -or -not $parts) { $parts += "$($up.Minutes) minute$(if ($up.Minutes -ne 1) { 's' })" }
        return 'up ' + ($parts -join ', ')
    }
    $span = if ($up.Days) { "$($up.Days) day$(if ($up.Days -ne 1) { 's' }), $($up.Hours):$('{0:00}' -f $up.Minutes)" } else { "$($up.Hours):$('{0:00}' -f $up.Minutes)" }
    ' {0} up {1}' -f (Get-Date).ToString('HH:mm:ss'), $span
}

function open {
    if (-not $args.Count) { Write-LxError 'open: missing file, folder or URL'; return }
    foreach ($a in $args) {
        $s = [string]$a
        if (Test-Path -LiteralPath $s) { Invoke-Item -LiteralPath $s } else { Start-Process $s }
    }
}
function xdg-open { open @args }

function mkdir {
    if (-not (Test-LxLinuxCall $MyInvocation $args 'New-Item')) { return New-Item -ItemType Directory @args }
    $p = Split-LxArgs $args 'm'
    $global:LASTEXITCODE = 0
    if (-not $p.Rest.Count) { Write-LxError 'mkdir: missing operand'; $global:LASTEXITCODE = 1; return }
    foreach ($name in $p.Rest) {
        $full = Get-LxFullPath ([string]$name)
        if (Test-Path -LiteralPath $full) {
            if (-not $p.Flags.p) { Write-LxError "mkdir: cannot create directory '$name': File exists"; $global:LASTEXITCODE = 1 }
            continue
        }
        if (-not $p.Flags.p -and -not (Test-Path -LiteralPath (Split-Path $full -Parent))) {
            Write-LxError "mkdir: cannot create directory '$name': No such file or directory"; $global:LASTEXITCODE = 1; continue
        }
        [void][IO.Directory]::CreateDirectory($full)
        if ($p.Flags.v) { "mkdir: created directory '$name'" }
    }
}

function rm {
    if (-not (Test-LxLinuxCall $MyInvocation $args 'Remove-Item')) { return Remove-Item @args }
    $p = Split-LxArgs $args
    $f = $p.Flags
    $recursive = $f.r -or $f.R
    $targets = $p.Rest.ToArray()   # @() on this list throws "Argument types do not match" in 5.1
    if (-not $targets.Count -and $MyInvocation.ExpectingInput) {
        $targets = @($input | ForEach-Object { if ($_ -is [IO.FileSystemInfo]) { $_.FullName } else { [string]$_ } })
    }
    $global:LASTEXITCODE = 0
    if (-not $targets.Count) { if (-not $f.f) { Write-LxError 'rm: missing operand' }; return }
    # never delete a drive root, the home folder or Windows itself
    $protected = @($HOME, $env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:USERPROFILE) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    foreach ($item in Resolve-LxPaths $targets 'rm' -Quiet:([bool]$f.f)) {
        $full = $item.FullName.TrimEnd('\')
        $shown = [string]$item.FullName
        if ($full -match '^[A-Za-z]:$' -or $protected -contains $full) {
            Write-LxError "rm: refusing to remove '$shown' (drive root, home or system folder)"; $global:LASTEXITCODE = 1; continue
        }
        if ($item.PSIsContainer -and -not $recursive) {
            $empty = -not (Get-ChildItem -LiteralPath $full -Force | Select-Object -First 1)
            if (-not ($f.d -and $empty)) { Write-LxError "rm: cannot remove '$($item.Name)': Is a directory"; $global:LASTEXITCODE = 1; continue }
        }
        if ($f.i) {
            $kind = if ($item.PSIsContainer) { 'directory' } else { 'regular file' }
            $answer = Read-Host "rm: remove $kind '$($item.Name)'?"
            if ($answer -notmatch '^[yY]') { continue }
        }
        try {
            Remove-Item -LiteralPath $full -Recurse:$recursive -Force -ErrorAction Stop
            if ($f.v) { "removed '$($item.Name)'" }
        } catch {
            Write-LxError "rm: cannot remove '$($item.Name)': $($_.Exception.Message)"; $global:LASTEXITCODE = 1
        }
    }
}

function pwd {
    if ($args.Count -or -not (Test-LxLinuxCall $MyInvocation $args 'Get-Location')) { return Get-Location @args }
    (Get-Location).Path
}

function export {
    if (-not $args.Count) {
        Get-ChildItem env: | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }
        return
    }
    foreach ($a in $args) {
        if ([string]$a -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { Set-Item -LiteralPath "env:$($Matches[1])" -Value $Matches[2] }
        elseif (-not (Test-Path -LiteralPath "env:$a")) { Write-LxError "export: '$a': not a NAME=value pair" }
    }
}

function unset {
    foreach ($a in $args) { Remove-Item -LiteralPath "env:$a" -ErrorAction SilentlyContinue }
}

# env               list environment variables
# env A=1 B=2 cmd   run cmd with extra variables, then put them back
function env {
    $vars = [ordered]@{}
    $i = 0
    while ($i -lt $args.Count -and [string]$args[$i] -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { $vars[$Matches[1]] = $Matches[2]; $i++ }
    if ($i -ge $args.Count) {
        foreach ($k in $vars.Keys) { Set-Item -LiteralPath "env:$k" -Value $vars[$k] }
        Get-ChildItem env: | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }
        return
    }
    $saved = @{}
    foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); Set-Item -LiteralPath "env:$k" -Value $vars[$k] }
    try {
        $cmd = $args[$i]; $rest = @($args | Select-Object -Skip ($i + 1))
        & $cmd @rest
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
}

function killall {
    $force = $false; $quiet = $false; $names = @()
    for ($i = 0; $i -lt $args.Count; $i++) {
        $a = $args[$i]
        if (($a -is [int] -and $a -eq -9) -or [string]$a -in '-9', '-KILL', '-SIGKILL') { $force = $true }
        elseif ([string]$a -eq '-s' -and $i + 1 -lt $args.Count) { $i++; if ([string]$args[$i] -match '^(9|KILL|SIGKILL)$') { $force = $true } }
        elseif ([string]$a -eq '-q') { $quiet = $true }
        else { $names += ([string]$a -replace '\.exe$', '') }
    }
    $global:LASTEXITCODE = 0
    if (-not $names) { Write-LxError 'usage: killall [-9] [-q] NAME...'; $global:LASTEXITCODE = 1; return }
    foreach ($n in $names) {
        $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
        if (-not $procs) { if (-not $quiet) { Write-LxError "${n}: no process found" }; $global:LASTEXITCODE = 1; continue }
        # like SIGTERM: ask windowed apps to close; with -9 (or no windows) end them outright
        $windowed = @($procs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
        if (-not $force -and $windowed) {
            foreach ($pr in $windowed) { [void]$pr.CloseMainWindow() }
        } else {
            foreach ($pr in $procs) {
                try { Stop-Process -Id $pr.Id -Force -ErrorAction Stop }
                catch { if (-not $quiet) { Write-LxError "killall: $n($($pr.Id)): Operation not permitted" }; $global:LASTEXITCODE = 1 }
            }
        }
    }
}

# sudo runs a command as administrator. Uses Windows 11's built-in sudo when it's there,
# otherwise opens an elevated window.
# The script the elevated PowerShell runs: linuxify's commands loaded (so `sudo rm -rf x`
# works), then the command, with arguments quoted so they arrive unchanged.
function Get-LxSudoScript([object[]]$argv) {
    $line = ($argv | ForEach-Object {
        $s = [string]$_
        if ($s -match '^[\w\-\.:\\/=,@+]+$') { $s } else { "'" + $s.Replace("'", "''") + "'" }
    }) -join ' '
    $path = $LxCommandsPath.Replace("'", "''")
    "`$LxForceLinux = `$true; foreach (`$a in 'cd', 'pwd', 'rm') { Remove-Item `"Alias:`$a`" -Force -ErrorAction SilentlyContinue }; . '$path'; $line"
}

function sudo {
    if (-not $args.Count) { Write-LxError 'usage: sudo COMMAND [ARGS...]'; return }
    $sudoExe = Join-Path $env:windir 'System32\sudo.exe'
    $first = Get-Command ([string]$args[0]) -ErrorAction SilentlyContinue | Select-Object -First 1
    $shell = (Get-Process -Id $PID).Path
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-LxSudoScript $args)))
    $mode = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' -ErrorAction SilentlyContinue).Enabled
    if ((Test-Path $sudoExe) -and $mode -and $mode -ne 1) {
        # inline mode: output appears right here, like Linux
        if ($first.CommandType -eq 'Application') { & $sudoExe @args; return }
        & $sudoExe $shell -NoLogo -NoProfile -EncodedCommand $enc
    } elseif ((Test-Path $sudoExe) -and $mode -eq 1) {
        # "new window" mode: keep that window open so the output can be read
        & $sudoExe $shell -NoLogo -NoProfile -NoExit -EncodedCommand $enc
    } else {
        Start-Process $shell -Verb RunAs -ArgumentList '-NoLogo', '-NoProfile', '-NoExit', '-EncodedCommand', $enc
    }
}

# --- Shell habits ---

# cd -  goes back to the previous folder; cd with nothing goes home.
function cd {
    if (-not $args.Count) { Set-Location $HOME; return }
    if ($args.Count -eq 1 -and [string]$args[0] -eq '-') {
        if (-not $Linuxify.OldPwd) { Write-LxError 'cd: OLDPWD not set'; return }
        Set-Location -LiteralPath $Linuxify.OldPwd
        (Get-Location).Path
        return
    }
    Set-Location @args
}

# Called from the prompt: remembers the previous folder however it changed.
function Update-LxDirHistory {
    $here = (Get-Location).Path
    if ($Linuxify.LastDir -and $Linuxify.LastDir -ne $here) { $Linuxify.OldPwd = $Linuxify.LastDir }
    $Linuxify.LastDir = $here
}

function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }
function ..... { Set-Location ..\..\..\.. }

function mkcd {
    if ($args.Count -ne 1) { Write-LxError 'usage: mkcd DIR'; return }
    [void][IO.Directory]::CreateDirectory((Get-LxFullPath ([string]$args[0])))
    Set-Location -LiteralPath ([string]$args[0])
}

# !! (last command) and !$ (its last argument), expanded when Enter is pressed.
function Expand-LxHistory([string]$line) {
    if ($line -notmatch '!!|!\$') { return $line }
    $items = try { [Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems() } catch { $null }
    if (-not $items -or -not $items.Count) { return $line }
    $last = $items[$items.Count - 1].CommandLine
    $tokens = $null; $errs = $null
    [void][Management.Automation.Language.Parser]::ParseInput($last, [ref]$tokens, [ref]$errs)
    $lastArg = ($tokens | Where-Object { $_.Kind -notin 'EndOfInput', 'NewLine' } | Select-Object -Last 1).Text
    # leave anything inside 'single quotes' alone
    [regex]::Replace($line, "('[^']*')|!!|!\$", {
        param($m)
        if ($m.Groups[1].Success) { $m.Value } elseif ($m.Value -eq '!!') { $last } else { $lastArg }
    })
}

# Don't shadow real GNU tools if they're installed (for example from Git or MSYS2)
if (-not $LxForceLinux) {
    foreach ($name in 'which', 'touch', 'head', 'tail', 'grep', 'wc', 'df', 'free', 'uptime', 'killall', 'env') {
        if (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue) { Remove-Item "function:$name" }
    }
}
