# The done check from PowerShell: the factory's gate runner (factory/core/verify.ps1).
# Run from the project root:
#   .\tools\verify.ps1 [--twice] [--keep-going] [--red] [step...]
& (Join-Path $PSScriptRoot '..\factory\core\verify.ps1') @args
exit $LASTEXITCODE
