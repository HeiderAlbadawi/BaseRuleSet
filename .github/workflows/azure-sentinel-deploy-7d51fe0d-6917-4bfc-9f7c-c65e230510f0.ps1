## Globals ##
$CloudEnv = $Env:cloudEnv
$ResourceGroupName = $Env:resourceGroupName
$WorkspaceName = $Env:workspaceName
$WorkspaceId = $Env:workspaceId
$RootDirectory = $Env:rootDirectory
$Directories = $Env:directories -split ',' # now supports multiple directories
$ContentTypes = $Env:contentTypes
$SourceControlId = $Env:sourceControlId
$GitHubAuthToken = $Env:githubAuthToken
$GitHubRepository = $Env:GITHUB_REPOSITORY
$BranchName = $Env:branch
$SmartDeployment = $Env:smartDeployment
$NewResourceBranch = "$BranchName-sentinel-deployment"
$CsvPath = "$RootDirectory\.sentinel\tracking_table_$SourceControlId.csv"
$ConfigPath = "$RootDirectory\sentinel-deployment.config"

$Global:LocalCsvTableFinal = @{}
$Global:UpdatedCsvTable = @{}
$Global:ParameterFileMapping = @{}
$Global:PrioritizedContentFiles = @()
$Global:ExcludeContentFiles = @()

$ContentTypeMapping = @{
    "AnalyticsRule"=@("Microsoft.OperationalInsights/workspaces/providers/alertRules","Microsoft.OperationalInsights/workspaces/providers/alertRules/actions")
    "AutomationRule"=@("Microsoft.OperationalInsights/workspaces/providers/automationRules")
    "HuntingQuery"=@("Microsoft.OperationalInsights/workspaces/savedSearches")
    "Parser"=@("Microsoft.OperationalInsights/workspaces/savedSearches")
    "Playbook"=@("Microsoft.Web/connections","Microsoft.Logic/workflows","Microsoft.Web/customApis")
    "Workbook"=@("Microsoft.Insights/workbooks")
}
$ResourceTypes = $ContentTypes.Split(",") | ForEach-Object { $ContentTypeMapping[$_] } | ForEach-Object { $_.ToLower() }

$MaxRetries = 3
$SecondsBetweenAttempts = 5

# --- Helper Functions ---

function RelativePathWithSlash($absolutePath) {
    return $absolutePath.Replace($RootDirectory + "\", "").Replace("\", "/")
}

function AbsolutePathWithSlash($relativePath) {
    return Join-Path -Path $RootDirectory -ChildPath $relativePath
}

function ConvertTableToString {
    $output = "FileName,CommitSha`n"
    $Global:UpdatedCsvTable.GetEnumerator() | ForEach-Object {
        $key = RelativePathWithSlash $_.Key
        $output += "{0},{1}`n" -f $key, $_.Value
    }
    return $output
}

function ReadCsvToTable {
    if (-not (Test-Path $CsvPath)) { return @{} }
    $csvTable = Import-Csv -Path $CsvPath
    $HashTable = @{}
    foreach ($r in $csvTable) {
        $key = AbsolutePathWithSlash $r.FileName
        $HashTable[$key] = $r.CommitSha
    }
    return $HashTable
}

function PushCsvToRepo {
    if (-not (Test-Path "$RootDirectory\.sentinel")) { New-Item -ItemType Directory -Path "$RootDirectory\.sentinel" | Out-Null }

    $Content = ConvertTableToString
    $RelativeCsvPath = RelativePathWithSlash $CsvPath

    if (-not (git ls-remote --heads "https://github.com/$GitHubRepository" $NewResourceBranch)) {
        git switch --orphan $NewResourceBranch
        git commit --allow-empty -m "Initial commit on orphan branch"
        git push -u origin $NewResourceBranch
    } else {
        git fetch
        git checkout $NewResourceBranch
    }

    $Content | Out-File -FilePath $RelativeCsvPath -Encoding utf8
    git add $RelativeCsvPath
    git commit -m "Modified tracking table"
    git push -u origin $NewResourceBranch
    git checkout $BranchName
}

function GetGitTree {
    $BranchResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/$GitHubRepository/branches/$BranchName" -Headers @{ Authorization = "Bearer $GitHubAuthToken" }
    $TreeUrl = "https://api.github.com/repos/$GitHubRepository/git/trees/$($BranchResponse.commit.sha)?recursive=true"
    return Invoke-RestMethod -Uri $TreeUrl -Headers @{ Authorization = "Bearer $GitHubAuthToken" }
}

function GetCommitShaTable($TreeResponse) {
    $ShaTable = @{}
    $SupportedExtensions = @(".json", ".bicep", ".bicepparam")
    $TreeResponse.tree | ForEach-Object {
        $TruePath = AbsolutePathWithSlash $_.path
        if (([System.IO.Path]::GetExtension($_.path) -in $SupportedExtensions) -or ($TruePath -eq $ConfigPath)) {
            $ShaTable[$TruePath] = $_.sha
        }
    }
    return $ShaTable
}

function SmartDeployment($FullDeploymentFlag, $RemoteShaTable, $Path) {
    $Skip = $false
    if (-not $FullDeploymentFlag) {
        $ExistingSha = $Global:LocalCsvTableFinal[$Path]
        $RemoteSha = $RemoteShaTable[$Path]
        $Skip = ($ExistingSha -and $ExistingSha -eq $RemoteSha)
    }
    return $Skip
}

function DeployDirectory($Directory, $RemoteShaTable, $FullDeploymentFlag) {
    if (-not (Test-Path $Directory)) { Write-Host "[Warning] $Directory not found, skipping"; return }
    Get-ChildItem -Path $Directory -Recurse -Include *.json, *.bicep | ForEach-Object {
        $FilePath = $_.FullName
        $Skip = SmartDeployment $FullDeploymentFlag $RemoteShaTable $FilePath
        if (-not $Skip) {
            Write-Host "[Info] Deploying $FilePath"
            # Insert your actual deployment logic here
        } else {
            Write-Host "[Info] Skipping $FilePath (unchanged)"
        }
        $Global:UpdatedCsvTable[$FilePath] = $RemoteShaTable[$FilePath]
    }
}

# --- Main ---

function Main {
    git config --global user.email "donotreply@microsoft.com"
    git config --global user.name "Sentinel"

    if (Test-Path $CsvPath) { $Global:LocalCsvTableFinal = ReadCsvToTable }

    $Tree = GetGitTree
    $RemoteShaTable = GetCommitShaTable $Tree

    $FullDeploymentFlag = $SmartDeployment -eq "false"

    foreach ($Dir in $Directories) {
        $FullPath = Join-Path $RootDirectory $Dir.Trim()
        DeployDirectory $FullPath $RemoteShaTable $FullDeploymentFlag
    }

    PushCsvToRepo
}

Main
