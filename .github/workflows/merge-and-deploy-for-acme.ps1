<#
custom-rules-deploy.ps1
Deploys custom + merged Sentinel rules for Acme.
Usage in workflow: pwsh -File ./custom-rules-deploy.ps1 `
    -BaseRulesPath "${{ github.workspace }}/BaseRules" `
    -SentinelPath "${{ github.workspace }}/AcmeSentinel" `
    -ResourceGroupName "training_jordan" `
    -WorkspaceName "acmesentinel"
#>

param(
    [Parameter(Mandatory=$true)][string]$BaseRulesPath,
    [Parameter(Mandatory=$true)][string]$SentinelPath,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$WorkspaceName,
    [string]$TempOutputRoot = "$env:RUNNER_TEMP\sentinel-build"
)

# Ensure temp folder exists
if (-not (Test-Path $TempOutputRoot)) { New-Item -Path $TempOutputRoot -ItemType Directory -Force | Out-Null }

Write-Host "[Info] BaseRulesPath: $BaseRulesPath"
Write-Host "[Info] SentinelPath: $SentinelPath"
Write-Host "[Info] TempOutputRoot: $TempOutputRoot"

# --- Helper: safe JSON load ---
function Load-JsonFile([string]$path) {
    try { return Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Failed to parse JSON file $path : $_" }
}

# --- Merge base rules + tuning ---
$baseFiles = Get-ChildItem -Path $BaseRulesPath -Filter *.json -File -ErrorAction SilentlyContinue
foreach ($bf in $baseFiles) {
    Write-Host "[Info] Processing base rule: $($bf.Name)"
    $baseJson = Load-JsonFile $bf.FullName

    if (-not $baseJson.resources -or $baseJson.resources.Count -lt 1) { continue }
    $props = $baseJson.resources[0].properties
    if (-not $props -or -not $props.query) { continue }

    $ruleBaseName = $bf.BaseName
    $tuningPath1 = Join-Path $SentinelPath ("Tuning-" + $ruleBaseName + ".txt")
    $tuningPath2 = Join-Path $SentinelPath ("Tuned-" + $ruleBaseName + ".txt")
    $appendKql = $null
    if (Test-Path $tuningPath1) { $appendKql = Get-Content -Path $tuningPath1 -Raw }
    elseif (Test-Path $tuningPath2) { $appendKql = Get-Content -Path $tuningPath2 -Raw }

    if ($appendKql) {
        $props.query = $props.query.TrimEnd() + "`r`n" + $appendKql.Trim()
    }

    $outFile = Join-Path $TempOutputRoot $bf.Name
    $baseJson | ConvertTo-Json -Depth 50 | Out-File -FilePath $outFile -Encoding utf8
}

# --- Deploy custom JSON rules ---
$customJsonFiles = Get-ChildItem -Path $SentinelPath -Filter Custom-*.json -File -ErrorAction SilentlyContinue
foreach ($cf in $customJsonFiles) {
    Write-Host "[Info] Copying custom rule: $($cf.Name)"
    Copy-Item -Path $cf.FullName -Destination $TempOutputRoot -Force
}

# --- Call original Sentinel deploy script ---
$originalDeployPs1 = Join-Path $SentinelPath "azure-sentinel-deploy-7d51fe0d-6917-4bfc-9f7c-c65e230510f0.ps1"

if (-not (Test-Path $originalDeployPs1)) {
    throw "[Error] Original deploy script not found: $originalDeployPs1"
}

Write-Host "[Info] Deploying all merged + custom rules via original deploy script..."
& pwsh -File $originalDeployPs1 `
    -directory $TempOutputRoot `
    -workspaceName $WorkspaceName `
    -resourceGroupName $ResourceGroupName
if ($LASTEXITCODE -ne 0) {
    throw "[Error] Original deploy script failed with exit code $LASTEXITCODE"
}

Write-Host "[Success] Custom + merged rules deployed successfully!"
