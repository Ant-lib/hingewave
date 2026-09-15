# Builds single-file Hingewave executables for Windows.
#
#   pwsh windows/build.ps1              tests, then publishes hingewave-x64.exe and hingewave-arm64.exe into windows/build/
#   pwsh windows/build.ps1 -SkipTests   publish only
#
# Needs the .NET 8 SDK. The output is self-contained: no .NET install required on the target machine.
param([switch]$SkipTests)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$version = (Get-Content ../VERSION -Raw).Trim()
Write-Host "building Hingewave $version"

if (-not $SkipTests) {
    dotnet test Hingewave.Core.Tests --nologo -v q
    if ($LASTEXITCODE -ne 0) { throw "tests failed" }
}

New-Item -ItemType Directory -Force build | Out-Null
foreach ($rid in "win-x64", "win-arm64") {
    dotnet publish Hingewave.App -c Release -r $rid --self-contained true `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none `
        -o "build/$rid" --nologo
    if ($LASTEXITCODE -ne 0) { throw "publish failed for $rid" }
    $arch = $rid.Replace("win-", "")
    Copy-Item "build/$rid/hingewave.exe" "build/hingewave-$arch.exe" -Force
    Write-Host "wrote build/hingewave-$arch.exe"
}

$lines = Get-ChildItem build/hingewave-*.exe | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower())  $($_.Name)"
}
Set-Content -Path build/SHA256SUMS-windows.txt -Value $lines
Write-Host "wrote build/SHA256SUMS-windows.txt"
