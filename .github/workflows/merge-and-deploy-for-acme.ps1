<#
merge-and-deploy-for-acme.ps1
Usage (workflow): pwsh -File ./.github/workflows/merge-and-deploy-for-acme.ps1 `
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

# ensure output dir exists
if (-not (Test-Path $TempOutputRoot)) { New-Item -Path $TempOutputRoot -ItemType Directory -Force | Out-Null }

Write-Host "[Info] BaseRulesPath: $BaseRulesPath"
Write-Host "[Info] SentinelPath: $SentinelPath"
Write-Host "[Info] TempOutputRoot: $TempOutputRoot"

# function: safe json load
function Load-JsonFile([string]$path) {
    try { return Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Failed to parse JSON file $path : $_" }
}

# iterate base rules
$baseFiles = Get-ChildItem -Path $BaseRulesPath -Filter *.json -File -ErrorAction SilentlyContinue
foreach ($bf in $baseFiles) {
    Write-Host "[Info] Processing base rule: $($bf.Name)"
    $baseJson = Load-JsonFile $bf.FullName

    # Guard: most templates have resources[0].properties.query
    if (-not $baseJson.resources -or $baseJson.resources.Count -lt 1) {
        Write-Warning "Skipping $($bf.Name) — no resources[]"
        continue
    }
    $props = $baseJson.resources[0].properties
    if (-not $props -or -not $props.query) {
        Write-Warning "Skipping $($bf.Name) — no properties.query"
        continue
    }

    # find tuning file in sentinel folder: Tuning-<RuleBaseName>.txt
    $ruleBaseName = $bf.BaseName
    $tuningPath1 = Join-Path $SentinelPath ("Tuning-" + $ruleBaseName + ".txt")
    $tuningPath2 = Join-Path $SentinelPath ("Tuned-" + $ruleBaseName + ".txt") # in case you used Tuned- prefix
    $appendKql = $null
    if (Test-Path $tuningPath1) { $appendKql = Get-Content -Path $tuningPath1 -Raw }
    elseif (Test-Path $tuningPath2) { $appendKql = Get-Content -Path $tuningPath2 -Raw }

    if ($appendKql) {
        # append safely (preserve original in repo)
        Write-Host "[Info] Found tuning for $ruleBaseName — appending to query"
        # ensure newline separation
        $props.query = $props.query.TrimEnd() + "`r`n" + $appendKql.Trim()
    } else {
        Write-Host "[Info] No tuning for $ruleBaseName"
    }

    # write modified temp template file
    $outFile = Join-Path $TempOutputRoot $bf.Name
    # ConvertTo-Json can change formatting; use depth 50 to avoid truncation
    $baseJson | ConvertTo-Json -Depth 50 | Out-File -FilePath $outFile -Encoding utf8
    Write-Host "[Info] Wrote merged template to $outFile"

    # deploy the temp template to resource group (pass workspace parameter)
    try {
        $deploymentName = "sentinel-deploy-$($ruleBaseName)-$(Get-Random)"
        Write-Host "[Info] Deploying $outFile -> ResourceGroup:$ResourceGroupName (workspace param: $WorkspaceName)"
        # Pass 'workspace' parameter explicitly if template expects it
        $paramObj = @{ "workspace" = $WorkspaceName }

        # Use New-AzResourceGroupDeployment (Az module must be authenticated in workflow)
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName `
            -TemplateFile $outFile -TemplateParameterObject $paramObj -ErrorAction Stop | Out-Host

        Write-Host "[Success] Deployed $ruleBaseName"
    }
    catch {
        Write-Host "[Error] Deployment failed for $ruleBaseName : $_"
        # continue to next rule but surface error
    }
}

# deploy sentinel-specific full JSON rules (if any)
$customJsonFiles = Get-ChildItem -Path $SentinelPath -Filter Custom-*.json -File -ErrorAction SilentlyContinue
foreach ($cf in $customJsonFiles) {
    Write-Host "[Info] Deploying sentinel-custom rule: $($cf.Name)"
    $outFile = Join-Path $TempOutputRoot $cf.Name
    Copy-Item -Path $cf.FullName -Destination $outFile -Force
    try {
        $deploymentName = "sentinel-deploy-custom-$($cf.BaseName)-$(Get-Random)"
        $paramObj = @{ "workspace" = $WorkspaceName }
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName `
            -TemplateFile $outFile -TemplateParameterObject $paramObj -ErrorAction Stop | Out-Host
        Write-Host "[Success] Deployed custom: $($cf.Name)"
    } catch {
        Write-Host "[Error] Custom deployment failed for $($cf.Name): $_"
    }
}

Write-Host "[Info] Merge-and-deploy script completed."
