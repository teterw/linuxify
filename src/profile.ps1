# linuxify PowerShell profile. Loaded from your $PROFILE by a small marker block.
. (Join-Path $PSScriptRoot 'core.ps1')
$Linuxify.Config = Read-LxConfig

# Terminals started before eza/fastfetch were installed have a stale PATH
$wingetLinks = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
if ((Test-Path $wingetLinks) -and ($env:Path -split ';') -notcontains $wingetLinks) { $env:Path += ";$wingetLinks" }
Remove-Variable wingetLinks

# --- Syntax highlighting as you type (PSReadLine) ---
if ($Host.Name -eq 'ConsoleHost' -and (Get-Module PSReadLine -ListAvailable)) {
    Import-Module PSReadLine
    $e = [char]27
    $rl = (Get-Module PSReadLine).Version
    Set-PSReadLineOption -EditMode Windows -HistorySearchCursorMovesToEnd -BellStyle None
    $colors = @{
        Command   = "$e[92m"; Parameter = "$e[96m"; Operator = "$e[95m"; Variable = "$e[93m"
        String    = "$e[33m"; Number    = "$e[35m"; Type     = "$e[36m"; Comment  = "$e[90m"
        Keyword   = "$e[94m"; Member    = "$e[37m"; Error    = "$e[91m"
    }
    if ($rl -ge [version]'2.1') {
        $colors.InlinePrediction = "$e[90m"
        if (-not [Console]::IsOutputRedirected) {
            Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
        }
    }
    Set-PSReadLineOption -Colors $colors
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Remove-Variable e, rl, colors
}

# --- ls like Linux (eza) ---
if (Get-Command eza -CommandType Application -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza @(Get-LxEzaArgs $Linuxify.Config) @args }
    function ll { eza @(Get-LxEzaArgs $Linuxify.Config) -l --git --time-style=long-iso @args }
    function la { eza @(Get-LxEzaArgs $Linuxify.Config) -la --git --time-style=long-iso @args }
    function lt { eza @(Get-LxEzaArgs $Linuxify.Config) --tree --level=2 @args }
}

# --- Prompt ---
function prompt {
    $ok = $?
    if ($Linuxify.PromptStyle -ne $Linuxify.Config.style) {
        # PSReadLine redraws the last characters of the prompt in red on a syntax error
        $Linuxify.PromptStyle = $Linuxify.Config.style
        if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
            Set-PSReadLineOption -PromptText $(if ($Linuxify.PromptStyle -eq 'arrow') { ' ' } else { '$ ' })
        }
    }
    Get-LxPrompt $Linuxify.Config.style $ok
}

# --- Commands ---
function linuxify {
    & (Join-Path $Linuxify.Home 'cli.ps1') @args
    $Linuxify.Config = Read-LxConfig
}
function theme { linuxify theme @args }

# --- Startup: theme colors + fastfetch (interactive terminals only) ---
$lxArgs = [Environment]::GetCommandLineArgs()
$lxScripted = ($lxArgs -match '^-(c|command|f|file|encodedcommand|ec)$') -and -not ($lxArgs -match '^-noexit$')
if ($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected -and -not $lxScripted) {
    if ($Linuxify.Config.palette -and (Test-LxPaletteTerminal)) {
        [Console]::Write($Linuxify.Config.palette)
    }
    if ($Linuxify.Config.fetch -eq 'on' -and -not $env:LINUXIFY_FETCHED -and $env:TERM_PROGRAM -ne 'vscode' -and
        (Get-Command fastfetch -CommandType Application -ErrorAction SilentlyContinue)) {
        $env:LINUXIFY_FETCHED = '1'
        if ($Linuxify.Config.logo) { fastfetch --logo $Linuxify.Config.logo } else { fastfetch }
    }
}
Remove-Variable lxArgs, lxScripted
