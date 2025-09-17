<#
deploy-custom-wrapper.ps1
Wrapper to apply KQL tuning from TXT files to existing Sentinel rules
#>

param(
    [Parameter(Mandatory=$true)][string]$BaseRulesPath,    # Folder containing original JSON rules
    [Parameter(Mandatory=$true)][string]$TuningPath,       # Folder containing TXT tuning files (KQL)
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$WorkspaceName
)

# Temp folder for merged rules
$TempOutputRoot = Join-Path $env:TEMP "sentinel-build"
if (-not (Test-Path $TempOutputRoot)) { 
    New-Item -Path $TempOutputRoot -ItemType Directory -Force | Out-Null 
}

function Load-JsonFile([string]$path) {
    try { return Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Failed to parse JSON file $path : $_" }
}

# Get all original JSON rules
$originalJsonFiles = Get-ChildItem -Path $BaseRulesPath -Filter "*.json" -File -ErrorAction SilentlyContinue
if (-not $originalJsonFiles) {
    Write-Warning "[Warning] No JSON rules found in $BaseRulesPath"
}

foreach ($cf in $originalJsonFiles) {
    $ruleBaseName = $cf.BaseName
    Write-Host "[Info] Processing rule: $ruleBaseName"

    $ruleJson = Load-JsonFile $cf.FullName

    # Check for corresponding tuning TXT file
    $tuningFile1 = Join-Path $TuningPath ("Tuning-" + $ruleBaseName + ".txt")
    $tuningFile2 = Join-Path $TuningPath ("Tuned-" + $ruleBaseName + ".txt")
    $appendKql = $null
    if (Test-Path $tuningFile1) { $appendKql = Get-Content -Path $tuningFile1 -Raw }
    elseif (Test-Path $tuningFile2) { $appendKql = Get-Content -Path $tuningFile2 -Raw }

    if ($appendKql -and $ruleJson.resources.Count -ge 1) {
        $props = $ruleJson.resources[0].properties
        if ($props -and $props.query) {
            Write-Host "[Info] Appending KQL tuning to $ruleBaseName"
            $props.query = $props.query.TrimEnd() + "`r`n" + $appendKql.Trim()
        }
    }

    # Write merged JSON to temp folder
    $outFile = Join-Path $TempOutputRoot $cf.Name
    $ruleJson | ConvertTo-Json -Depth 50 | Out-File -FilePath $outFile -Encoding utf8

    # Deploy merged JSON to Sentinel
    try {
        $deploymentName = "sentinel-deploy-$($ruleBaseName)-$(Get-Random)"
        $paramObj = @{ "workspace" = $WorkspaceName }
        Write-Host "[Info] Deploying $ruleBaseName to workspace $WorkspaceName"
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName `
            -TemplateFile $outFile -TemplateParameterObject $paramObj -ErrorAction Stop | Out-Host
        Write-Host "[Success] Deployed tuning for $ruleBaseName"
    } catch {
        Write-Host "[Error] Deployment failed for ${ruleBaseName}: ${($_.Exception.Message)}"
    }
}

Write-Host "[Info] All tuning deployments complete."
