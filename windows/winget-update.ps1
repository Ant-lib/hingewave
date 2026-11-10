# Submits a Hingewave release to winget, or dry-runs that submission.
#
#   pwsh windows/winget-update.ps1 -Tag v0.2.4 -Submit        open the update PR on microsoft/winget-pkgs
#   pwsh windows/winget-update.ps1 -Tag v0.2.3 -OutDir <dir>  write the manifests to <dir> and check them, submit nothing
#
# Uses a pinned wingetcreate, checked against the hash Microsoft publishes beside it.
# -Submit needs a classic GitHub token with the public_repo scope in WINGET_CREATE_GITHUB_TOKEN.
# wingetcreate does not support fine-grained tokens, and its --token flag can end up in logs,
# so the token only travels in the environment.
param(
    [Parameter(Mandatory)] [string]$Tag,
    [string]$Repository = "Ant-lib/hingewave",
    [switch]$Submit,
    [string]$OutDir
)
$ErrorActionPreference = "Stop"

$WingetCreateUrl = "https://github.com/microsoft/winget-create/releases/download/v1.12.13.0/wingetcreate.exe"
$WingetCreateSha256 = "24042BD37915805615E6CF969AC57C6439124C3FE85823327F5F3FB24BD9FFEA"
$PackageId = "Ant-lib.Hingewave"

if ($Tag -notmatch '^v(\d+\.\d+\.\d+)$') { throw "tag '$Tag' is not of the form v1.2.3" }
$version = $Matches[1]
if ($Submit -and $OutDir) { throw "pass -Submit or -OutDir, not both" }
if (-not $Submit -and -not $OutDir) { throw "pass -Submit to open the PR, or -OutDir for a dry run" }
if ($Submit -and -not $env:WINGET_CREATE_GITHUB_TOKEN) { throw "-Submit needs WINGET_CREATE_GITHUB_TOKEN" }

$tmp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$exe = Join-Path $tmp "wingetcreate.exe"
Invoke-WebRequest -Uri $WingetCreateUrl -OutFile $exe
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash
if ($hash -ne $WingetCreateSha256) { throw "wingetcreate.exe hash mismatch: got $hash" }

$base = "https://github.com/$Repository/releases/download/$Tag"
$cmd = @("update", $PackageId, "--version", $version, "--no-open",
    "--urls", "$base/hingewave-x64.exe|x64", "$base/hingewave-arm64.exe|arm64")
if ($Submit) { $cmd += "--submit" } else { $cmd += @("--out", $OutDir) }

# wingetcreate is a console app, so the call operator waits and $LASTEXITCODE is real.
# Hingewave itself is a WinExe, where it is not; see the render check in the workflows.
& $exe @cmd
if ($LASTEXITCODE -ne 0) { throw "wingetcreate exited with $LASTEXITCODE" }
if ($Submit) { return }

# Dry run: the manifest wingetcreate generated must carry the same installer hashes as the
# checksum file the release workflow published, and the version from the tag.
$sumsFile = Join-Path $tmp "SHA256SUMS-windows.txt"
Invoke-WebRequest -Uri "$base/SHA256SUMS-windows.txt" -OutFile $sumsFile
$installer = Get-ChildItem $OutDir -Recurse -Filter "$PackageId.installer.yaml" | Select-Object -First 1
if (-not $installer) { throw "wingetcreate wrote no installer manifest under $OutDir" }
$manifest = Get-Content $installer.FullName -Raw
if ($manifest -notmatch "PackageVersion: $([regex]::Escape($version))\b") { throw "installer manifest is not for version $version" }
$checked = 0
foreach ($line in Get-Content $sumsFile) {
    if (-not $line.Trim()) { continue }
    $sha, $name = $line.Trim() -split '\s+', 2
    if ($manifest -notmatch "InstallerSha256: $sha\b") { throw "installer manifest lacks the hash for $name ($sha)" }
    $checked++
}
if ($checked -ne 2) { throw "expected 2 installer hashes in SHA256SUMS-windows.txt, found $checked" }
Write-Host "dry run ok: $($installer.FullName) matches SHA256SUMS-windows.txt for $Tag"
