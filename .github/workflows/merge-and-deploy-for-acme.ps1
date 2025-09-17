<#
merge-and-deploy.ps1
Usage (workflow): pwsh -File .\merge-and-deploy.ps1 `
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

# Ensure output dir exists
if (-not (Test-Path $TempOutputRoot)) { New-Item -Path $TempOutputRoot -ItemType Directory -Force | Out-Null }

Write-Host "[Info] BaseRulesPath: $BaseRulesPath"
Write-Host "[Info] SentinelPath: $SentinelPath"
Write-Host "[Info] TempOutputRoot: $TempOutputRoot"

function Load-JsonFile([string]$path) {
    try { return Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Failed to parse JSON file $path : $_" }
}

# 1️⃣ Merge base rules with tuning
$baseFiles = Get-ChildItem -Path $BaseRulesPath -Filter *.json -File -ErrorAction SilentlyContinue
foreach ($bf in $baseFiles) {
    Write-Host "[Info] Processing base rule: $($bf.Name)"
    $baseJson = Load-JsonFile $bf.FullName

    if (-not $baseJson.resources -or $baseJson.resources.Count -lt 1) {
        Write-Warning "Skipping $($bf.Name) — no resources[]"
        continue
    }

    $props = $baseJson.resources[0].properties
    if (-not $props -or -not $props.query) {
        Write-Warning "Skipping $($bf.Name) — no properties.query"
        continue
    }

    $ruleBaseName = $bf.BaseName
    $tuningPath1 = Join-Path $SentinelPath ("Tuning-" + $ruleBaseName + ".txt")
    $tuningPath2 = Join-Path $SentinelPath ("Tuned-" + $ruleBaseName + ".txt")
    $appendKql = $null
    if (Test-Path $tuningPath1) { $appendKql = Get-Content -Path $tuningPath1 -Raw }
    elseif (Test-Path $tuningPath2) { $appendKql = Get-Content -Path $tuningPath2 -Raw }

    if ($appendKql) {
        Write-Host "[Info] Found tuning for $ruleBaseName — appending to query"
        $props.query = $props.query.TrimEnd() + "`r`n" + $appendKql.Trim()
    } else {
        Write-Host "[Info] No tuning for $ruleBaseName"
    }

    $outFile = Join-Path $TempOutputRoot $bf.Name
    $baseJson | ConvertTo-Json -Depth 50 | Out-File -FilePath $outFile -Encoding utf8
}

# 2️⃣ Deploy custom rules
$customJsonFiles = Get-ChildItem -Path $SentinelPath -Filter Custom-*.json -File -ErrorAction SilentlyContinue
foreach ($cf in $customJsonFiles) {
    Write-Host "[Info] Deploying sentinel-custom rule: $($cf.Name)"
    $outFile = Join-Path $TempOutputRoot $cf.Name
    Copy-Item -Path $cf.FullName -Destination $outFile -Force
}

# 3️⃣ Call original Sentinel deploy script (smart deployment, CSV tracking, metadata)
$originalDeployPs1 = Join-Path $SentinelPath "azure-sentinel-deploy-7d51fe0d-6917-4bfc-9f7c-c65e230510f0.ps1"
if (-not (Test-Path $originalDeployPs1)) { throw "[Error] Cannot find sentinel deployment script at $originalDeployPs1" }

Write-Host "[Info] Deploying all merged + custom rules using $originalDeployPs1"

# Pass temp output folder as SentinelPath so the original script deploys everything we prepared
& pwsh -File $originalDeployPs1 `
    -directory $TempOutputRoot `
    -workspaceName $WorkspaceName `
    -resourceGroupName $ResourceGroupName

Write-Host "[Info] Merge-and-deploy script completed."
