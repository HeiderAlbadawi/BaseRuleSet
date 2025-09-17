# iterate all JSON rules in SentinelPath
$ruleJsonFiles = Get-ChildItem -Path $SentinelPath -Filter *.json -File -ErrorAction SilentlyContinue
if (-not $ruleJsonFiles) { Write-Warning "[Warning] No JSON rules found in $SentinelPath" }

foreach ($cf in $ruleJsonFiles) {
    Write-Host "[Info] Processing rule: $($cf.Name)"
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
        $deploymentName = "sentinel-deploy-$($ruleBaseName)-$(Get-Random)"
        $paramObj = @{ "workspace" = $WorkspaceName }
        Write-Host "[Info] Deploying $ruleBaseName to workspace $WorkspaceName"
        New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName `
            -TemplateFile $outFile -TemplateParameterObject $paramObj -ErrorAction Stop | Out-Host
        Write-Host "[Success] Deployed rule $ruleBaseName"
    } catch {
        Write-Host "[Error] Deployment failed for ${ruleBaseName}: ${($_.Exception.Message)}"
    }
}
