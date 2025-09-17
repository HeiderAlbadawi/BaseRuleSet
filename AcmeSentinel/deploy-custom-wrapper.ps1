<#
deploy-custom-wrapper.ps1
Wrapper to call the main Azure Sentinel deploy script for custom rules
#>

param(
    [Parameter(Mandatory=$true)][string]$BaseRulesPath,
    [Parameter(Mandatory=$true)][string]$SentinelPath,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$WorkspaceName
)

# Ensure the main deploy script path (in .github/workflows)
$ps1Path = Join-Path $env:GITHUB_WORKSPACE ".github\workflows\azure-sentinel-deploy-7d51fe0d-6917-4bfc-9f7c-c65e230510f0.ps1"

if (-not (Test-Path $ps1Path)) {
    throw "[ERROR] Deploy script not found at path: $ps1Path"
}

$ps1FullPath = Resolve-Path $ps1Path
Write-Host "[Info] Running deploy script: $ps1FullPath"

# Call the main deploy script, passing all mandatory parameters
& $ps1FullPath `
    -BaseRulesPath $BaseRulesPath `
    -SentinelPath $SentinelPath `
    -ResourceGroupName $ResourceGroupName `
    -WorkspaceName $WorkspaceName
