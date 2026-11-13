# The gate runner from PowerShell: runs factory/core/verify.sh with Git Bash in the
# current directory, passing every argument through and returning its exit code.
# Run from the project root:
#   .\factory\core\verify.ps1 [--twice] [step...]
# Set FACTORY_BASH to use another bash. On Windows it never uses the bash on PATH
# (that is WSL).

$bash = $env:FACTORY_BASH
if (-not $bash) {
	if ($env:OS -eq 'Windows_NT') {
		$bash = 'C:\Program Files\Git\bin\bash.exe'
	} else {
		$bash = 'bash'
	}
}
if (($env:OS -eq 'Windows_NT') -and -not (Test-Path -LiteralPath $bash)) {
	[Console]::Error.WriteLine("verify.ps1: Git Bash not found at '$bash'. Set FACTORY_BASH.")
	exit 2
}

$runner = (Join-Path $PSScriptRoot 'verify.sh').Replace('\', '/')
& $bash $runner @args
exit $LASTEXITCODE
