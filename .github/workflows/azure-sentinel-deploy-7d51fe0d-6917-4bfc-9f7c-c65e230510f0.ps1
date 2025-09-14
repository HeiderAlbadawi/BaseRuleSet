# ----------------------------------------------
# Azure Sentinel Deployment Script - Full Rewrite
# ----------------------------------------------

## Globals ##
$CloudEnv = $Env:cloudEnv
$ResourceGroupName = $Env:resourceGroupName
$WorkspaceName = $Env:workspaceName
$WorkspaceId = $Env:workspaceId
$Directory = $Env:directory
$contentTypes = $Env:contentTypes
$sourceControlId = $Env:sourceControlId
$rootDirectory = $Env:rootDirectory
$githubAuthToken = $Env:githubAuthToken
$githubRepository = $Env:GITHUB_REPOSITORY
$branchName = $Env:branch
$smartDeployment = $Env:smartDeployment
$newResourceBranch = "$branchName-sentinel-deployment"
$csvPath = "$rootDirectory\.sentinel\tracking_table_$sourceControlId.csv"
$global:localCsvTablefinal = @{}
$global:updatedCsvTable = @{}

$MaxRetries = 3
$secondsBetweenAttempts = 5
$supportedExtensions = @(".json", ".bicep", ".bicepparam")

# ------------------------
# Utility Functions
# ------------------------

function RelativePath($absolutePath) {
    return $absolutePath.Replace("$rootDirectory\", "").Replace("\", "/")
}

function AbsolutePath($relativePath) {
    return Join-Path -Path $rootDirectory -ChildPath $relativePath
}

function ConvertTableToString {
    $output = "FileName,CommitSha`n"
    $global:updatedCsvTable.GetEnumerator() | ForEach-Object {
        $key = RelativePath $_.Key
        $output += "$key,$($_.Value)`n"
    }
    return $output
}

function GetGithubTree {
    $branchResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/$githubRepository/branches/$branchName" -Headers @{Authorization = "Bearer $githubAuthToken"}
    $treeUrl = "https://api.github.com/repos/$githubRepository/git/trees/$($branchResponse.commit.sha)?recursive=true"
    $getTreeResponse = Invoke-RestMethod -Uri $treeUrl -Headers @{Authorization = "Bearer $githubAuthToken"}
    return $getTreeResponse
}

function GetCommitShaTable($getTreeResponse) {
    $shaTable = @{}
    $getTreeResponse.tree | ForEach-Object {
        if ($supportedExtensions -contains ([System.IO.Path]::GetExtension($_.path))) {
            $shaTable[AbsolutePath $_.path] = $_.sha
        }
    }
    return $shaTable
}

function ReadCsvToTable {
    if (-not (Test-Path $csvPath)) { return @{} }
    $csvTable = Import-Csv -Path $csvPath
    $HashTable = @{}
    foreach($r in $csvTable) {
        $HashTable[AbsolutePath $r.FileName] = $r.CommitSha
    }
    return $HashTable
}

function PushCsvToRepo {
    $content = ConvertTableToString
    $relativeCsvPath = RelativePath $csvPath

    if (-not (Test-Path ".sentinel")) {
        New-Item -ItemType Directory -Path ".sentinel" | Out-Null
    }

    $branchExists = git ls-remote --heads "https://github.com/$githubRepository" $newResourceBranch | Measure-Object | Select-Object -ExpandProperty Count
    if ($branchExists -eq 0) {
        git switch --orphan $newResourceBranch
        git commit --allow-empty -m "Initial commit on orphan branch"
        git push -u origin $newResourceBranch
    } else {
        git fetch
        git checkout $newResourceBranch
    }

    Write-Output $content > $csvPath
    git add $csvPath
    git commit -m "Updated tracking table"
    git push -u origin $newResourceBranch
    git checkout $branchName
}

function SmartDeploy($fullDeploymentFlag, $path, $remoteShaTable) {
    $skip = $false
    if (-not $fullDeploymentFlag) {
        $existingSha = $global:localCsvTablefinal[$path]
        $remoteSha = $remoteShaTable[$path]
        $skip = ($existingSha -and $existingSha -eq $remoteSha)
    }

    if (-not $skip) {
        Write-Host "[Info] Deploying $path"
        $ext = [System.IO.Path]::GetExtension($path)
        try {
            if ($ext -eq ".json") {
                $content = Get-Content -Path $path -Raw | ConvertFrom-Json
                # Example: Deploy analytics rule
                New-AzSentinelAlertRule -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -RuleId $content.Name -Rule $content
            } elseif ($ext -eq ".bicep") {
                New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $path -ErrorAction Stop
            }
        } catch {
            Write-Host "[Error] Deployment failed for $path : $_"
        }
    } else {
        Write-Host "[Info] Skipping $path (unchanged)"
    }
    $global:updatedCsvTable[$path] = $remoteShaTable[$path]
}

function DeployFolder($folder, $fullDeploymentFlag, $remoteShaTable) {
    if (-not (Test-Path $folder)) {
        Write-Host "[Warning] $folder not found, skipping..."
        return
    }

    Get-ChildItem -Path $folder -Recurse -Include *.json, *.bicep | ForEach-Object {
        SmartDeploy $fullDeploymentFlag $_.FullName $remoteShaTable
    }
}

# ------------------------
# Main
# ------------------------

git config --global user.email "donotreply@microsoft.com"
git config --global user.name "Sentinel"

# Load previous CSV tracking
$global:localCsvTablefinal = ReadCsvToTable

# Load GitHub tree and get commit SHAs
$tree = GetGithubTree
$remoteShaTable = GetCommitShaTable $tree

# Determine full deployment
$fullDeploymentFlag = $false
$existingConfigSha = $global:localCsvTablefinal[AbsolutePath "sentinel-deployment.config"]
$remoteConfigSha = $remoteShaTable[AbsolutePath "sentinel-deployment.config"]
if ($existingConfigSha -ne $remoteConfigSha -or $smartDeployment -eq "false") {
    $fullDeploymentFlag = $true
}

# Deploy MasterWizard folder first
DeployFolder "$rootDirectory\MasterWizard" $fullDeploymentFlag $remoteShaTable

# Deploy Base Rule Set folder
DeployFolder "$rootDirectory\Base Rule Set" $fullDeploymentFlag $remoteShaTable

# Push updated CSV
PushCsvToRepo

Write-Host "Deployment complete."
