# Runs one of linuxify's Linux commands for cmd.exe:  lx.ps1 <command> [args...]
# The Clink script rewrites e.g. `dir | grep foo` into `dir | powershell ... lx.ps1 grep foo`.
$LxForceLinux = $true
$Linuxify = @{}
# aliases win over functions, so drop the ones that would hide rm, cd and pwd
foreach ($a in 'cd', 'pwd', 'rm') { Remove-Item "Alias:$a" -Force -ErrorAction SilentlyContinue }
. (Join-Path $PSScriptRoot 'commands.ps1')

$name = [string]$args[0]
$rest = @($args | Select-Object -Skip 1)
$global:LASTEXITCODE = 0
if ([Console]::IsInputRedirected) { $input | & $name @rest } else { & $name @rest }
exit $global:LASTEXITCODE
