## Globals ##
$CloudEnv = $Env:cloudEnv
$ResourceGroupName = $Env:resourceGroupName
$WorkspaceName = $Env:workspaceName
$WorkspaceId = $Env:workspaceId
$Directory = $Env:directory
$contentTypes = $Env:contentTypes
$contentTypeMapping = @{
    "AnalyticsRule"=@("Microsoft.OperationalInsights/workspaces/providers/alertRules", "Microsoft.OperationalInsights/workspaces/providers/alertRules/actions");
    "AutomationRule"=@("Microsoft.OperationalInsights/workspaces/providers/automationRules");
    "HuntingQuery"=@("Microsoft.OperationalInsights/workspaces/savedSearches");
    "Parser"=@("Microsoft.OperationalInsights/workspaces/savedSearches");
    "Playbook"=@("Microsoft.Web/connections", "Microsoft.Logic/workflows", "Microsoft.Web/customApis");
    "Workbook"=@("Microsoft.Insights/workbooks");
}
$sourceControlId = $Env:sourceControlId
$rootDirectory = $Env:rootDirectory
$githubAuthToken = $Env:githubAuthToken
$githubRepository = $Env:GITHUB_REPOSITORY
$branchName = $Env:branch
$smartDeployment = $Env:smartDeployment
$newResourceBranch = $branchName + "-sentinel-deployment"
$csvPath = "$rootDirectory\.sentinel\tracking_table_$sourceControlId.csv"
$configPath = "$rootDirectory\sentinel-deployment.config"
$global:localCsvTablefinal = @{}
$global:updatedCsvTable = @{}
$global:parameterFileMapping = @{}
$global:prioritizedContentFiles = @()
$global:excludeContentFiles = @{}

$guidPattern = '(\b[0-9a-f]{8}\b-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-\b[0-9a-f]{12}\b)'
$namePattern = '([-\w\._\(\)]+)'
$sentinelResourcePatterns = @{
    "AnalyticsRule" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.OperationalInsights/workspaces/$namePattern/providers/Microsoft.SecurityInsights/alertRules/$namePattern"
    "AutomationRule" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.OperationalInsights/workspaces/$namePattern/providers/Microsoft.SecurityInsights/automationRules/$namePattern"
    "HuntingQuery" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.OperationalInsights/workspaces/$namePattern/savedSearches/$namePattern"
    "Parser" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.OperationalInsights/workspaces/$namePattern/savedSearches/$namePattern"
    "Playbook" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.Logic/workflows/$namePattern"
    "Workbook" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.Insights/workbooks/$namePattern"
}

if ([string]::IsNullOrEmpty($contentTypes)) {
    $contentTypes = "AnalyticsRule"
}

# Converting hashtable to CSV string
function ConvertTableToString {
    $output = "FileName,CommitSha`n"
    $global:updatedCsvTable.GetEnumerator() | ForEach-Object {
        $key = (RelativePathWithBackslash $_.Key)
        $output += "{0},{1}`n" -f $key, $_.Value
    }
    return $output
}

$header = @{
    "authorization" = "Bearer $githubAuthToken"
}

function GetGithubTree {
    $branchResponse = AttemptInvokeRestMethod "Get" "https://api.github.com/repos/$githubRepository/branches/$branchName" $null $null 3
    $treeUrl = "https://api.github.com/repos/$githubRepository/git/trees/" + $branchResponse.commit.sha + "?recursive=true"
    $getTreeResponse = AttemptInvokeRestMethod "Get" $treeUrl $null $null 3
    return $getTreeResponse
}

function GetCommitShaTable($getTreeResponse) {
    $shaTable = @{}
    $supportedExtensions = @(".json", ".bicep", ".bicepparam")
    $getTreeResponse.tree | ForEach-Object {
        $truePath = (AbsolutePathWithSlash $_.path)
        if ((([System.IO.Path]::GetExtension($_.path) -in $supportedExtensions)) -or ($truePath -eq $configPath)) {
            $shaTable[$truePath] = $_.sha
        }
    }
    return $shaTable
}

function ReadCsvToTable {
    $csvTable = Import-Csv -Path $csvPath
    $HashTable=@{}
    foreach($r in $csvTable) {
        $key = (AbsolutePathWithSlash $r.FileName)
        $HashTable[$key] = $r.CommitSha
    }
    return $HashTable
}

# Utility path functions
function RelativePathWithBackslash($absolutePath) {
    return $absolutePath.Replace($rootDirectory + "\", "").Replace("\", "/")
}

function AbsolutePathWithSlash($relativePath) {
    return Join-Path -Path $rootDirectory -ChildPath $relativePath
}

# Git CSV push
function PushCsvToRepo {
    $content = ConvertTableToString
    $relativeCsvPath = RelativePathWithBackslash $csvPath
    $resourceBranchExists = git ls-remote --heads "https://github.com/$githubRepository" $newResourceBranch | Measure-Object | Select-Object -ExpandProperty Count

    if ($resourceBranchExists -eq 0) {
        git switch --orphan $newResourceBranch
        git commit --allow-empty -m "Initial commit on orphan branch"
        git push -u origin $newResourceBranch
        New-Item -ItemType "directory" -Path ".sentinel" -Force
    } else {
        git fetch > $null
        git checkout $newResourceBranch
    }

    Write-Output $content > $relativeCsvPath
    git add $relativeCsvPath
    git commit -m "Modified tracking table"
    git push -u origin $newResourceBranch
    git checkout $branchName
}

# Main deployment function simplified
function Deployment($fullDeploymentFlag, $remoteShaTable, $tree) {
    Write-Host "Deploying folder: $Directory"
    if (Test-Path -Path $Directory) {
        $iterationList = @()
        $global:prioritizedContentFiles | ForEach-Object { $iterationList += (AbsolutePathWithSlash $_) }
        Get-ChildItem -Path $Directory -Recurse -Include *.bicep, *.json -Exclude *metadata.json, *.parameters*.json, *.bicepparam, bicepconfig.json |
            Where-Object { $null -eq (filterContentFile $_.FullName) } |
            ForEach-Object { $iterationList += $_.FullName }

        foreach ($path in $iterationList) {
            Write-Host "[Info] Deploying $path"
            if (-not (Test-Path $path)) { continue }

            $templateType = if ($path -like "*.bicep") { "Bicep" } else { "ARM" }
            $templateObject = if ($templateType -eq "Bicep") { bicep build $path --stdout | Out-String | ConvertFrom-Json } else { Get-Content $path | Out-String | ConvertFrom-Json }
            $parameterFile = GetParameterFile $path

            $result = SmartDeployment $fullDeploymentFlag $remoteShaTable $path $parameterFile $templateObject $templateType
            if (-not $result.skip) { $global:updatedCsvTable[$path] = $remoteShaTable[$path] }
        }

        PushCsvToRepo
    } else {
        Write-Host "[Warning] $Directory not found. Nothing to deploy."
    }
}

# Smart deployment check
function SmartDeployment($fullDeploymentFlag, $remoteShaTable, $path, $parameterFile, $templateObject, $templateType) {
    $skip = $false
    $isSuccess = $null
    if (-not $fullDeploymentFlag) {
        $existingSha = $global:localCsvTablefinal[$path]
        $remoteSha = $remoteShaTable[$path]
        $skip = ($existingSha -and $existingSha -eq $remoteSha)
        if ($skip -and $parameterFile) {
            $existingShaParam = $global:localCsvTablefinal[$parameterFile]
            $remoteShaParam = $remoteShaTable[$parameterFile]
            $skip = ($existingShaParam -and $existingShaParam -eq $remoteShaParam)
        }
    }

    if (-not $skip) {
        $deploymentName = "Sentinel_Deployment_" + [guid]::NewGuid()
        $isSuccess = AttemptDeployment $path $parameterFile $deploymentName $templateObject $templateType
    }

    return @{ skip = $skip; isSuccess = $isSuccess }
}

# Main
function main {
    git config --global user.email "donotreply@microsoft.com"
    git config --global user.name "Sentinel"

    if (Test-Path $csvPath) { $global:localCsvTablefinal = ReadCsvToTable }

    LoadDeploymentConfig
    $tree = GetGithubTree
    $remoteShaTable = GetCommitShaTable $tree

    $fullDeploymentFlag = ($smartDeployment -eq "false")
    Deployment $fullDeploymentFlag $remoteShaTable $tree
}

main
