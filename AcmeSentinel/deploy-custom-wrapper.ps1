<#
deploy-custom-wrapper.ps1
Wrapper to deploy custom rules with optional tuning
#>

param(
    [Parameter(Mandatory=$true)][string]$BaseRulesPath,
    [Parameter(Mandatory=$true)][string]$SentinelPath,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$WorkspaceName
)

# -----------------------------
# Temp folder for merged rules
# -----------------------------
$TempOutputRoot = Join-Path $env:TEMP "sentinel-build"
if (-not (Test-Path $TempOutputRoot)) {
    New-Item -Path $TempOutputRoot -ItemType Directory -Force | Out-Null
}

# -----------------------------
# Helper to load JSON
# -----------------------------
function Load-JsonFile([string]$path) {
    try { return Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Failed to parse JSON file $path : $_" }
}

# -----------------------------
# Enumerate custom rules
# -----------------------------
$customJsonFiles = Get-ChildItem -Path $SentinelPath -Filter Custom-*.json -File -ErrorAction SilentlyContinue

if (-not $customJsonFiles -or $customJsonFiles.Count -eq 0) {
    Write-Warning "[Warning] No custom JSON rules found in $SentinelPath"
}

foreach ($cf in $customJsonFiles) {
    Write-Host "[Info] Processing custom rule: $($cf.Name)"
    $ruleJson = Load-JsonFile $cf.FullName

    # -----------------------------
    # Check for tuning files
    # -----------------------------
    $ruleBaseName = $cf.BaseName
    $tuningFiles = @(
        Join-Path $SentinelPath ("Tuning-" + $ruleBaseName + ".txt"),
        Join-Path $SentinelPath ("Tuned-" + $ruleBaseName + ".txt")
    )

    $appendKql = $null
    foreach ($tfile in $tuningFiles) {
        if (Test-Path $tfile) {
            $appendKql = Get-Content -Path $tfile -Raw
            break
        }
    }

    if ($appendKql -and $ruleJson.resources.Count -ge 1) {
        $props = $ruleJson.resources[0].properties
        if ($props -and $props.query) {
            Write-Host "[Info] Appending tuning to $ruleBaseName"
            $props.query = $props.query.TrimEnd() + "`r`n" + $appendKql.Trim()
        }
    }

    # -----------------------------
    # Write merged JSON to temp folder
    # -----------------------------
    $outFile = Join-Path $TempOutputRoot $cf.Name
    $ruleJson | ConvertTo-Json -Depth 50 | Out-File -FilePath $outFile -Encoding utf8

    # -----------------------------
    # Deploy to Sentinel
    # -----------------------------
    try {
        $deploymentName = "sentinel-deploy-custom-$($ruleBaseName)-$(Get-Random)"
        $paramObj = @{ "workspace" = $WorkspaceName }

        Write-Host "[Info] Deploying $ruleBaseName to workspace $WorkspaceName"
        Write-Host "[DEBUG] Template file: $outFile"
        Write-Host "[DEBUG] Deployment parameters: $($paramObj | ConvertTo-Json -Compress)"

        # Force deployment: add -ForceDeployment flag if your script supports it
        New-AzResourceGroupDeployment -Name $deploymentName `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $outFile `
            -TemplateParameterObject $paramObj `
            -ErrorAction Stop | Out-Host

        Write-Host "[Success] Deployed custom rule $ruleBaseName"
    }
    catch {
        Write-Host "[Error] Deployment failed for ${ruleBaseName}: $($_.Exception.Message)"
    }
}

Write-Host "[Info] Custom rules deployment complete."
