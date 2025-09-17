param(
    [string]$BaseRulesPath  = "$env:GITHUB_WORKSPACE\BaseRules",
    [string]$SentinelPath   = "$env:GITHUB_WORKSPACE\AcmeSentinel",
    [string]$ResourceGroupName = "training_jordan",
    [string]$WorkspaceName = "acmesentinel"
)

# Path to your original deploy script
$ps1Path = Join-Path $SentinelPath "azure-sentinel-deploy-7d51fe0d-6917-4bfc-9f7c-c65e230510f0.ps1"

Write-Host "[Info] Running original sentinel deploy script for custom rules"
& $ps1Path `
    -BaseRulesPath $BaseRulesPath `
    -SentinelPath $SentinelPath `
    -ResourceGroupName $ResourceGroupName `
    -WorkspaceName $WorkspaceName
