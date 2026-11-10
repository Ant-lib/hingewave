# Decides what to do about a winget-pkgs submission that may already exist for a version.
# Pure: the caller fetches the inputs, so the decision is testable without the network
# (windows/winget-update.Tests.ps1).
#
# Anyone can open a winget-pkgs PR, so only a submission that is provably ours counts as
# done. Anything else for this version throws, for a person to look at.

function Resolve-ExistingSubmission {
    param(
        # Installer manifest for this version on winget-pkgs master, or $null if there is none.
        [AllowNull()] [string]$PublishedManifest,
        # Open winget-pkgs PRs whose title names this version: objects with .user.login and .html_url.
        [AllowNull()] [object[]]$OpenPullRequests,
        # https://github.com/<owner>/<repo>/releases/download/<tag>
        [Parameter(Mandatory)] [string]$ReleaseBase,
        # The account that submits, which is the author of our own PRs.
        [Parameter(Mandatory)] [string]$Login
    )

    if ($PublishedManifest) {
        $urls = @([regex]::Matches($PublishedManifest, 'InstallerUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
        if ($urls.Count -eq 0) { throw "the published manifest for this version lists no InstallerUrl" }
        $foreign = @($urls | Where-Object { -not $_.StartsWith("$ReleaseBase/") })
        if ($foreign.Count -gt 0) {
            throw "winget-pkgs already has this version with installers outside $($ReleaseBase): $($foreign -join ', ')"
        }
        return "published"
    }

    $prs = @($OpenPullRequests | Where-Object { $_ })
    $theirs = @($prs | Where-Object { $_.user.login -ne $Login })
    if ($theirs.Count -gt 0) {
        throw "open winget-pkgs PRs for this version that $Login did not open: $(($theirs | ForEach-Object { $_.html_url }) -join ', ')"
    }
    if ($prs.Count -gt 0) { return "open" }
    return "none"
}

Export-ModuleMember -Function Resolve-ExistingSubmission
