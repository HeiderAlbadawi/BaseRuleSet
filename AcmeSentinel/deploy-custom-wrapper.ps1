<#
deploy-custom-wrapper.ps1
Wrapper to call the main Azure Sentinel deploy script for custom rules,
and inject KQL from Tuning files into the JSON before deployment
#>

param(
    [Parameter(Mandatory=$true)][string]$BaseRulesPath,
    [Parameter(Mandatory=$true)][string]$SentinelPath,
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$WorkspaceName
)

# Paths
$ps1Path = Join-Path $env:GITHUB_WORKSPACE ".github\workflows\azure-sentinel-deploy-7d51fe0d-6917-4bfc-9f7c-c65e230510f0.ps1"
if (-not (Test-Path $ps1Path)) { throw "[ERROR] Deploy script not found at $ps1Path" }
$ps1FullPath = Resolve-Path $ps1Path

# Temp folder for modified JSON
$tempDir = Join-Path $env:TEMP "sentinel-temp"
if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory | Out-Null }

# Function to safely load JSON
function Load-Json([string]$path) { Get-Content $path -Raw | ConvertFrom-Json }

# Inject KQL from Tuning-*.txt into Custom-*.json rules
$customJsonFiles = Get-ChildItem -Path $SentinelPath -Filter "Custom-*.json" -File
foreach ($file in $customJsonFiles) {

    Write-Host "[Info] Processing custom rule: $($file.Name)"
    $json = Load-Json $file.FullName

    if ($json.resources -and $json.resources.Count -ge 1 -and $json.resources[0].properties.query) {
        # Look for tuning files
        $ruleBase = $file.BaseName
        $tuningFile1 = Join-Path $SentinelPath ("Tuning-" + $ruleBase + ".txt")
        $tuningFile2 = Join-Path $SentinelPath ("Tuned-" + $ruleBase + ".txt")
        $appendKql = $null
        if (Test-Path $tuningFile1) { $appendKql = Get-Content $tuningFile1 -Raw }
        elseif (Test-Path $tuningFile2) { $appendKql = Get-Content $tuningFile2 -Raw }

        if ($appendKql) {
            Write-Host "[Info] Appending KQL from tuning file to $ruleBase"
            $json.resources[0].properties.query = $json.resources[0].properties.query.TrimEnd() + "`r`n" + $appendKql.Trim()
        } else { Write-Host "[Info] No tuning file found for $ruleBase" }
    }

    # Save modified JSON to temp folder
    $outPath = Join-Path $tempDir $file.Name
    $json | ConvertTo-Json -Depth 50 | Out-File -FilePath $outPath -Encoding utf8
}

# Set the wrapper to point to temp folder for deployment
$wrapperSentinelPath = $tempDir

Write-Host "[Info] Running deploy script: $ps1FullPath"
& $ps1FullPath `
    -BaseRulesPath $BaseRulesPath `
    -SentinelPath $wrapperSentinelPath `
    -ResourceGroupName $ResourceGroupName `
    -WorkspaceName $WorkspaceName
