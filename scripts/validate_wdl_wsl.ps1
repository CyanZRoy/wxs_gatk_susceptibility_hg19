param(
    [string]$Wdl = "workflow.wdl"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$target = if ([System.IO.Path]::IsPathRooted($Wdl)) { $Wdl } else { Join-Path $repositoryRoot $Wdl }
$windowsPath = (Resolve-Path -LiteralPath $target -ErrorAction Stop).Path
$wslPath = (& wsl.exe --distribution Ubuntu-24.04 --exec wslpath -u $windowsPath).Trim()
if ($LASTEXITCODE -ne 0 -or -not $wslPath) {
    throw "Could not convert the WDL path for WSL: $windowsPath"
}

& wsl.exe --distribution Ubuntu-24.04 --exec java -jar /opt/cromwell/81/womtool-81.jar validate $wslPath
exit $LASTEXITCODE
