param(
    [string]$Repository = "",
    [string]$Ref = "main",
    [int]$ReliabilityIterations = 5,
    [switch]$IncludeDistributionEvidence,
    [switch]$FailIfNotPass = $true,
    [switch]$Watch,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($ReliabilityIterations -lt 1) {
    throw "ReliabilityIterations must be >= 1"
}

function Resolve-Repository {
    param([string]$ExplicitRepository)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRepository)) {
        return $ExplicitRepository
    }

    $remoteUrl = (& git remote get-url origin 2>$null)
    if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
        throw "Repository not provided and no git remote 'origin' found. Pass -Repository <owner/repo>."
    }

    if ($remoteUrl -match 'github.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(\.git)?$') {
        return ("{0}/{1}" -f $Matches.owner, $Matches.repo)
    }

    throw "Unable to parse GitHub repository from origin URL: $remoteUrl"
}

$resolvedRepo = Resolve-Repository -ExplicitRepository $Repository

$distributionValue = if ($IncludeDistributionEvidence) { 'true' } else { 'false' }
$failValue = if ($FailIfNotPass) { 'true' } else { 'false' }

$args = @(
    'workflow', 'run', 'CI',
    '--repo', $resolvedRepo,
    '--ref', $Ref,
    '-f', 'run_release_candidate_evidence_pack=true',
    '-f', 'release_candidate_include_distribution_evidence=' + $distributionValue,
    '-f', 'release_candidate_fail_if_not_pass=' + $failValue,
    '-f', 'integration_reliability_iterations=' + $ReliabilityIterations
)

Write-Host "Dispatching mission-critical CI evidence gate..."
Write-Host ("- repo={0}" -f $resolvedRepo)
Write-Host ("- ref={0}" -f $Ref)
Write-Host ("- integration_reliability_iterations={0}" -f $ReliabilityIterations)
Write-Host ("- release_candidate_include_distribution_evidence={0}" -f $distributionValue)
Write-Host ("- release_candidate_fail_if_not_pass={0}" -f $failValue)

if ($DryRun) {
    Write-Host ("Dry-run command: gh {0}" -f ($args -join ' '))
    return
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) not found. Install gh and authenticate with 'gh auth login'."
}

& gh @args

Write-Host "Workflow dispatched."
Write-Host "Recent runs:"
& gh run list --repo $resolvedRepo --workflow CI --limit 3

if ($Watch) {
    $latestRun = (& gh run list --repo $resolvedRepo --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId')
    if (-not [string]::IsNullOrWhiteSpace($latestRun)) {
        Write-Host ("Watching run: {0}" -f $latestRun)
        & gh run watch $latestRun --repo $resolvedRepo --exit-status
    }
}
