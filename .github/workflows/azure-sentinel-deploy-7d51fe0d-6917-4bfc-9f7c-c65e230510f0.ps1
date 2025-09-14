# ===============================================
# Azure Sentinel Deployment Script
# ===============================================

# -----------------------------
# Global variables
# -----------------------------
$rootDirectory = "D:\a\BaseRuleSet\BaseRuleSet"
$branchName = "main-sentinel-deployment"
$trackingTableFile = ".sentinel/tracking_table_7d51fe0d-6917-4bfc-9f7c-c65e230510f0.csv"
$smartDeployment = $true

# -----------------------------
# Function: LoadDeploymentConfig
# -----------------------------
function LoadDeploymentConfig {
    if (-Not (Test-Path $trackingTableFile)) {
        Write-Host "[Info] Tracking table not found. Creating new one."
        @() | Export-Csv -Path $trackingTableFile -NoTypeInformation
    }
}

# -----------------------------
# Function: AttemptInvokeRestMethod
# -----------------------------
function AttemptInvokeRestMethod {
    param(
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$false)][hashtable]$Headers = $null,
        [Parameter(Mandatory=$false)][object]$Body = $null
    )

    $retryCount = 3
    for ($i=0; $i -lt $retryCount; $i++) {
        try {
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -Body $Body
        } catch {
            Write-Warning "Attempt $($i+1) failed: $_"
            Start-Sleep -Seconds 2
        }
    }
    throw "Failed to call $Uri after $retryCount attempts."
}

# -----------------------------
# Function: filterContentFile
# -----------------------------
function filterContentFile {
    param(
        [Parameter(Mandatory=$true)][string]$filePath
    )
    $excludePatterns = @(
        "\.ps1$",
        "\.md$",
        "\.json$"
    )
    foreach ($pattern in $excludePatterns) {
        if ($filePath -match $pattern) { return $true }
    }
    return $false
}

# -----------------------------
# Initialize tracking table
# -----------------------------
LoadDeploymentConfig
$trackingTable = Import-Csv -Path $trackingTableFile

# Convert to hashtable for faster lookup
$HashTable = @{}
foreach ($r in $trackingTable) {
    if ($r.FileName -and $r.CommitSha) {
        $HashTable["$($r.FileName)"] = $r.CommitSha
    }
}

# -----------------------------
# Deploy folders
# -----------------------------
$foldersToDeploy = @(
    "$rootDirectory\MasterWizard",
    "$rootDirectory\Base Rule Set"
)

foreach ($folder in $foldersToDeploy) {
    Write-Host "Deploying folder: $folder"

    $files = Get-ChildItem -Path $folder -Recurse -File | Where-Object { -not (filterContentFile $_.FullName) }

    foreach ($file in $files) {
        $filePath = $file.FullName
        $relativePath = $file.FullName.Substring($rootDirectory.Length + 1)

        # Get Git commit SHA
        $gitSha = git log -n 1 --pretty=format:%H -- $filePath

        # Skip if already deployed
        if ($smartDeployment -and $HashTable.ContainsKey($relativePath) -and $HashTable[$relativePath] -eq $gitSha) {
            Write-Host "[Skipped] $relativePath already deployed"
            continue
        }

        # Deploy the JSON file
        Write-Host "[Info] Deploying $relativePath"
        # Insert actual deployment logic here
        # e.g., Import-AzSentinelAnalyticsRule -Path $filePath

        # Update hashtable
        $HashTable[$relativePath] = $gitSha
    }
}

# -----------------------------
# Save updated tracking table
# -----------------------------
$updatedTable = $HashTable.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{
        FileName = $_.Key
        CommitSha = $_.Value
    }
}

$updatedTable | Export-Csv -Path $trackingTableFile -NoTypeInformation -Force

Write-Host "Script execution Complete"
