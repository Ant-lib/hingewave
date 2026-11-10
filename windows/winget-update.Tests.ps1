# Pester 5 tests for WingetSubmission.psm1. Runs in CI on the Windows runner:
#   Invoke-Pester -Path windows/winget-update.Tests.ps1 -CI

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "WingetSubmission.psm1") -Force
    $script:base = "https://github.com/Ant-lib/hingewave/releases/download/v0.2.4"

    function New-Pr([string]$Login, [int]$Number) {
        [pscustomobject]@{
            user     = [pscustomobject]@{ login = $Login }
            html_url = "https://github.com/microsoft/winget-pkgs/pull/$Number"
        }
    }

    function New-Manifest([string[]]$Urls) {
        $lines = @("PackageIdentifier: Ant-lib.Hingewave", "PackageVersion: 0.2.4", "Installers:")
        foreach ($url in $Urls) { $lines += "- Architecture: x64"; $lines += "  InstallerUrl: $url" }
        $lines -join "`n"
    }

    function Test-Existing([AllowNull()] [string]$Manifest, [object[]]$Prs = @()) {
        Resolve-ExistingSubmission -PublishedManifest $Manifest -OpenPullRequests $Prs -ReleaseBase $script:base -Login "Ant-lib"
    }
}

Describe "Resolve-ExistingSubmission" {
    Context "nothing exists yet" {
        It "returns none when there is no manifest and no open PR" {
            Test-Existing $null | Should -Be "none"
        }
        It "returns none when the PR list is null" {
            Resolve-ExistingSubmission -PublishedManifest $null -OpenPullRequests $null -ReleaseBase $script:base -Login "Ant-lib" |
                Should -Be "none"
        }
    }

    Context "the version is already on winget-pkgs master" {
        It "returns published when every installer comes from our release" {
            Test-Existing (New-Manifest @("$script:base/hingewave-x64.exe", "$script:base/hingewave-arm64.exe")) | Should -Be "published"
        }
        It "throws when an installer comes from anywhere else" {
            { Test-Existing (New-Manifest @("$script:base/hingewave-x64.exe", "https://example.com/hingewave-arm64.exe")) } |
                Should -Throw "*outside*example.com*"
        }
        It "throws when the URL only shares a prefix with our tag" {
            { Test-Existing (New-Manifest @("https://github.com/Ant-lib/hingewave/releases/download/v0.2.4.evil/hingewave-x64.exe")) } |
                Should -Throw "*outside*"
        }
        It "throws when the URL is a lookalike repository" {
            { Test-Existing (New-Manifest @("https://github.com/Ant-lib/hingewave-evil/releases/download/v0.2.4/hingewave-x64.exe")) } |
                Should -Throw "*outside*"
        }
        It "throws when the manifest lists no installer URL" {
            { Test-Existing "PackageIdentifier: Ant-lib.Hingewave`nPackageVersion: 0.2.4" } | Should -Throw "*no InstallerUrl*"
        }
        It "ignores open PRs once our manifest is published" {
            Test-Existing (New-Manifest @("$script:base/hingewave-x64.exe")) @(New-Pr "someone-else" 1) | Should -Be "published"
        }
    }

    Context "a PR for the version is open" {
        It "returns open when we opened it" {
            Test-Existing $null @(New-Pr "Ant-lib" 7) | Should -Be "open"
        }
        It "matches the login case-insensitively, as GitHub does" {
            Test-Existing $null @(New-Pr "ant-lib" 7) | Should -Be "open"
        }
        It "throws when someone else opened it, naming the PR" {
            { Test-Existing $null @(New-Pr "someone-else" 9) } | Should -Throw "*did not open*pull/9*"
        }
        It "throws when ours and someone else's are both open" {
            { Test-Existing $null @((New-Pr "Ant-lib" 7), (New-Pr "someone-else" 9)) } | Should -Throw "*pull/9*"
        }
    }
}
