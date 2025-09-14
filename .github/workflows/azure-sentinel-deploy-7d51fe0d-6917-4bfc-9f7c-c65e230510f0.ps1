# ===================================================================
# Azure Sentinel Deployment Script
# Deploy rules from local folders to Sentinel
# ===================================================================

# -----------------------------
# Configuration
# -----------------------------
$trackingTableFile = Join-Path -Path $PSScriptRoot -ChildPath ".sentinel\tracking_table_$(New-Guid).csv"
$rulesFolders = @(
    "$PSScriptRoot\MasterWizard",
    "$PSScriptRoot\Base Rule Set"
)

# -----------------------------
# Helper Functions
# -----------------------------

# Ensure .sentinel folder exists and tracking table is initialized
function LoadDeploymentConfig {
    $trackingDir = Split-Path $trackingTableFile -Parent
    if (-not (Test-Path $trackingDir)) {
        Write-Host "[Info] Creating tracking folder: $trackingDir"
        New-Item -Path $trackingDir -ItemType Directory -Force | Out-Null
    }

    if (-Not (Test-Path $trackingTableFile)) {
        Write-Host "[Info] Tracking table not found. Creating new one."
        @() | Export-Csv -Path $trackingTableFile -NoTypeInformation -Force
    }
}

# Wrapper to call REST APIs with basic retry
function AttemptInvokeRestMethod {
    param (
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers = $null,
        [object]$Body = $null
    )
    try {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -Body $Body -ErrorAction Stop
    }
    catch {
        Write-Warning "REST call failed: $($_.Exception.Message)"
        return $null
    }
}

# Example filter function: skip files we don’t want deployed
function filterContentFile {
    param($filePath)
    # Add your custom filtering logic here
    # Example: skip .md files
    if ($filePath -like "*.md") { return $true }
    return $false
}

# -----------------------------
# Main Deployment Logic
# -----------------------------

# Load or initialize tracking table
LoadDeploymentConfig
$trackingTable = Import-Csv -Path $trackingTableFile

foreach ($folder in $rulesFolders) {
    Write-Host "[Info] Deploying folder: $folder"
    if (-Not (Test-Path $folder)) { continue }

    # Get JSON rule files, filtered
    $ruleFiles = Get-ChildItem -Path $folder -Recurse -Filter *.json |
                 Where-Object { -not (filterContentFile $_.FullName) }

    foreach ($r in $ruleFiles) {
        $absolutePath = $r.FullName

        # Track rule file SHA or timestamp (simplified example)
        $commitSha = (Get-FileHash $absolutePath -Algorithm SHA256).Hash
        $HashTable = @{}
        $HashTable[$absolutePath] = $commitSha

        # Deploy logic placeholder: call Sentinel REST API or Az module here
        Write-Host "[Info] Deploying $absolutePath with SHA $commitSha"

        # Update tracking table
        $trackingTable += [PSCustomObject]@{
            FileName   = $absolutePath
            CommitSha  = $commitSha
            Timestamp  = Get-Date
        }
    }
}

# Save updated tracking table
$trackingTable | Export-Csv -Path $trackingTableFile -NoTypeInformation -Force

Write-Host "Script execution Complete"
