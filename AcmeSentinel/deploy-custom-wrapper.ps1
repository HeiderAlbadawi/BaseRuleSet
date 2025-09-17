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

# temp folder for merged rules
$TempOutputRoot = Join-Path $env:TEMP "sentinel-build"
if (-not (Test-Path $TempOutputRoot)) { New-Item -Path $TempOutputRoot -ItemType Directory -Force | Out-Null }

function Load-JsonFile([string]$path) {
    try { return Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Failed to parse JSON file $path : $_" }
}

# iterate custom rules
$customJsonFiles = Get-ChildItem -Path $SentinelPath -Filter Custom-*.json -File -ErrorAction SilentlyContinue
foreach ($cf in $customJsonFiles) {
    Write-Host "[Info] Processing custom rule: $($cf.Name)"
    $ruleJson = Load-JsonFile $cf.FullName

    # check for tuning file
    $ruleBaseName = $cf.BaseName
    $tuningPath1 = Join-Path $SentinelPath ("Tuning-" + $ruleBaseName + ".txt")
    $tuningPath2 = Join-Path $SentinelPath ("Tuned-" + $ruleBaseName + ".txt")
    $appendKql = $null
    if (Test-Path $tuningPath1) { $appendKql = Get-Content -Path $tuningPath1 -Raw }
    elseif (Test-Path $tuningPath2) { $appendKql = Get-Content -Path $tuningPath2 -Raw }

    if ($appendKql -and $ruleJson.resources.Count -ge 1) {
        $props = $ruleJson.resources[0].properties
        if ($props -and $props.query) {
            Write-Host "[Info] Appending tuning to $ruleBaseName"
            $props.query = $props.query.TrimEnd() + "`r`n" + $appendKql.Trim()
        }
    }

    # write merged JSON to temp folder
    $outFile = Join-Path $TempOutputRoot $cf.Name
    $ruleJson | ConvertTo-Json -Depth 50 | Out-File -FilePath $outFile -Encoding utf8

    # deploy to Sentinel
    try {
        $deploymentName = "sentinel-deploy-custom-$($ruleBaseName)-$(Get-Random)"
        $paramObj = @{ "workspace" = $WorkspaceName }
        Write-Host "[Info] Deploying $ruleBaseName to workspace $WorkspaceName"
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName `
            -TemplateFile $outFile -TemplateParameterObject $paramObj -ErrorAction Stop | Out-Host
        Write-Host "[Success] Deployed custom rule $ruleBaseName"
    } catch {
        Write-Host "[Error] Deployment failed for $ruleBaseName: $_"
    }
}

Write-Host "[Info] Custom rules deployment complete."
