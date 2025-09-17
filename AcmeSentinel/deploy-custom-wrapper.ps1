<#
deploy-tuning-wrapper.ps1
Wrapper to deploy KQL tuning (whitelists) from AcmeSentinel into BaseRules
#>

param(
    [Parameter(Mandatory=$true)][string]$BaseRulesPath,       # Folder with original JSON rules
    [Parameter(Mandatory=$true)][string]$TuningPath,         # Folder with TXT KQL tuning files
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$WorkspaceName
)

# temp folder for merged rules
$TempOutputRoot = Join-Path $env:TEMP "sentinel-tuning-build"
if (-not (Test-Path $TempOutputRoot)) { New-Item -Path $TempOutputRoot -ItemType Directory -Force | Out-Null }

function Load-JsonFile([string]$path) {
    try { return Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Failed to parse JSON file $path : $_" }
}

# Get all tuning files (TXT)
$tuningFiles = Get-ChildItem -Path $TuningPath -Filter *.txt -File -ErrorAction SilentlyContinue
if (-not $tuningFiles) {
    Write-Warning "[Warning] No tuning TXT files found in $TuningPath"
    exit 0
}

foreach ($tf in $tuningFiles) {
    $ruleBaseName = $tf.BaseName
    Write-Host "[Info] Processing tuning for rule: $ruleBaseName"

    # Find the corresponding JSON in BaseRules
    $baseJsonFile = Get-ChildItem -Path $BaseRulesPath -Filter "Custom-$ruleBaseName.json" -File -ErrorAction SilentlyContinue
    if (-not $baseJsonFile) {
        Write-Warning "[Warning] Base rule JSON not found for $ruleBaseName in $BaseRulesPath"
        continue
    }

    # Load JSON
    $ruleJson = Load-JsonFile $baseJsonFile.FullName

    # Load tuning KQL
    $tuningKql = Get-Content -Path $tf.FullName -Raw
    if ($tuningKql -and $ruleJson.resources.Count -ge 1) {
        $props = $ruleJson.resources[0].properties
        if ($props -and $props.query) {
            Write-Host "[Info] Appending tuning KQL to $ruleBaseName"
            $props.query = $props.query.TrimEnd() + "`r`n" + $tuningKql.Trim()
        }
    }

    # Save merged JSON to temp folder
    $outFile = Join-Path $TempOutputRoot $baseJsonFile.Name
    $ruleJson | ConvertTo-Json -Depth 50 | Out-File -FilePath $outFile -Encoding utf8

    # Deploy merged JSON
    try {
        $deploymentName = "sentinel-deploy-tuning-$($ruleBaseName)-$(Get-Random)"
        $paramObj = @{ "workspace" = $WorkspaceName }
        Write-Host "[Info] Deploying $ruleBaseName with tuning to workspace $WorkspaceName"
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName `
            -TemplateFile $outFile -TemplateParameterObject $paramObj -ErrorAction Stop | Out-Host
        Write-Host "[Success] Deployed $ruleBaseName with tuning"
    } catch {
        Write-Host "[Error] Deployment failed for ${ruleBaseName}: ${($_.Exception.Message)}"
    }
}

Write-Host "[Info] Tuning deployment complete."
