#!/bin/bash

# Tenant Creation Script for Detection Engineering Base Rule Set
# This script creates a new tenant with workflow, PowerShell script, and directory structure
# 
# Usage: Run this script from ~/gittt/migrating/ directory
#        ./create-tenant.sh
#
# Location: ~/gittt/migrating/create-tenant.sh (outside the git repository)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="/home/kali/gittt/migrating/Detection-Engineering-Base-Rule-Set"
WORKFLOWS_DIR="${BASE_DIR}/.github/workflows"
TENANTS_DIR="${BASE_DIR}/Tenants"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Tenant Creation Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to validate input
validate_not_empty() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}Error: This field cannot be empty!${NC}"
        return 1
    fi
    return 0
}

# Function to validate GUID format
validate_guid() {
    if [[ ! $1 =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        echo -e "${RED}Error: Invalid GUID format! Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx${NC}"
        return 1
    fi
    return 0
}

# Collect tenant information
echo -e "${YELLOW}Please provide the following information for the new tenant:${NC}"
echo ""

# Tenant Name
while true; do
    read -p "Tenant Name (e.g., SPS, ACME, FolioMetrics): " TENANT_NAME
    if validate_not_empty "$TENANT_NAME"; then
        # Keep original case as provided by user
        break
    fi
done

# Subscription ID Secret Name
while true; do
    read -p "Subscription ID Secret Name (e.g., ${TENANT_NAME}_SUBS_ID): " SUBS_SECRET
    if validate_not_empty "$SUBS_SECRET"; then
        break
    fi
done

# Workspace Name
while true; do
    read -p "Workspace Name (e.g., ${TENANT_NAME,,}-sentinel): " WORKSPACE_NAME
    if validate_not_empty "$WORKSPACE_NAME"; then
        break
    fi
done

# Resource Group Name
while true; do
    read -p "Resource Group Name (e.g., rgsentinel): " RESOURCE_GROUP
    if validate_not_empty "$RESOURCE_GROUP"; then
        break
    fi
done

# Workspace ID
while true; do
    read -p "Workspace ID (GUID format): " WORKSPACE_ID
    if validate_not_empty "$WORKSPACE_ID" && validate_guid "$WORKSPACE_ID"; then
        break
    fi
done

# Generate Source Control ID (random GUID)
SOURCE_CONTROL_ID=$(python3 -c "import uuid; print(str(uuid.uuid4()).lower())")

echo ""
echo -e "${YELLOW}Summary of inputs:${NC}"
echo -e "Tenant Name: ${GREEN}$TENANT_NAME${NC}"
echo -e "Subscription Secret: ${GREEN}$SUBS_SECRET${NC}"
echo -e "Workspace Name: ${GREEN}$WORKSPACE_NAME${NC}"
echo -e "Resource Group: ${GREEN}$RESOURCE_GROUP${NC}"
echo -e "Workspace ID: ${GREEN}$WORKSPACE_ID${NC}"
echo -e "Source Control ID: ${GREEN}$SOURCE_CONTROL_ID${NC}"
echo ""

read -p "Continue with tenant creation? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo -e "${RED}Tenant creation cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Creating tenant files...${NC}"

# Check if files already exist
if [[ -f "${WORKFLOWS_DIR}/${TENANT_NAME}.yml" ]]; then
    echo -e "${RED}Error: Workflow file ${TENANT_NAME}.yml already exists!${NC}"
    exit 1
fi

if [[ -f "${WORKFLOWS_DIR}/${TENANT_NAME}.ps1" ]]; then
    echo -e "${RED}Error: PowerShell script ${TENANT_NAME}.ps1 already exists!${NC}"
    exit 1
fi

if [[ -d "${TENANTS_DIR}/${TENANT_NAME}" ]]; then
    echo -e "${RED}Error: Tenant directory ${TENANT_NAME} already exists!${NC}"
    exit 1
fi

# Create the YAML workflow file
echo -e "${YELLOW}Creating workflow file: ${TENANT_NAME}.yml${NC}"

cat > "${WORKFLOWS_DIR}/${TENANT_NAME}.yml" << EOF
name: Deploy Content to ${TENANT_NAME} (${WORKSPACE_ID})
# Workflow for ${TENANT_NAME} tenant - BaseRulesDeployment and CustomerRulesDeployment

on:
  push:
    branches: [ main ]
    paths:
    - 'Tenants/${TENANT_NAME}/**'
    - 'BaseRuleSet/**'
    - '!.github/workflows/**'  # this filter prevents other workflow changes from triggering this workflow
      # workflow_dispatch:

jobs:

  BaseRulesDeployment:
    runs-on: windows-latest
    env:
      resourceGroupName: '${RESOURCE_GROUP}'
      workspaceName: '${WORKSPACE_NAME}'
      workspaceId: '${WORKSPACE_ID}'
      directory: '\${{ github.workspace }}/BaseRuleSet'
      cloudEnv: 'AzureCloud'
      contentTypes: 'AnalyticsRule'
      branch: 'main'
      sourceControlId: '${SOURCE_CONTROL_ID}'
      rootDirectory: '\${{ github.workspace }}'
      githubAuthToken: \${{ secrets.GITHUB_TOKEN }}
      smartDeployment: 'true'
      updateOnlyMode: 'true'
      subscriptionId: \${{ secrets.${SUBS_SECRET} }}
    permissions:
      contents: write
      id-token: write # Require write permission to Fetch an OIDC token.

    steps:
    - name: Login to Azure (Attempt 1)
      continue-on-error: true
      id: login1
      uses: azure/login@v2
      with:
        client-id: \${{ secrets.AZURE_SENTINEL_CLIENTID_6ad70202274c4d05b7d3867422638828 }}
        tenant-id: \${{ secrets.AZURE_SENTINEL_TENANTID_6ad70202274c4d05b7d3867422638828 }}
        subscription-id: \${{ secrets.WIZARDCYBER_SUBS_ID }}
        environment: 'AzureCloud'
        audience: api://AzureADTokenExchange
        enable-AzPSSession: true

    - name: Wait 30 seconds if login attempt 1 failed
      if: \${{ steps.login1.outcome=='failure' }}
      run: powershell Start-Sleep -s 30

    - name: Login to Azure (Attempt 2)
      continue-on-error: true
      id: login2
      uses: azure/login@v2
      if: \${{ steps.login1.outcome=='failure' }}
      with:
        client-id: \${{ secrets.AZURE_SENTINEL_CLIENTID_6ad70202274c4d05b7d3867422638828 }}
        tenant-id: \${{ secrets.AZURE_SENTINEL_TENANTID_6ad70202274c4d05b7d3867422638828 }}
        subscription-id: \${{ secrets.WIZARDCYBER_SUBS_ID }}
        environment: 'AzureCloud'
        audience: api://AzureADTokenExchange
        enable-AzPSSession: true

    - name: Wait 30 seconds if login attempt 2 failed
      if: \${{ steps.login2.outcome=='failure' }}
      run: powershell Start-Sleep -s 30

    - name: Login to Azure (Attempt 3)
      continue-on-error: false
      id: login3
      uses: azure/login@v2
      if: \${{ steps.login2.outcome=='failure'  }}
      with:
        client-id: \${{ secrets.AZURE_SENTINEL_CLIENTID_6ad70202274c4d05b7d3867422638828 }}
        tenant-id: \${{ secrets.AZURE_SENTINEL_TENANTID_6ad70202274c4d05b7d3867422638828 }}
        subscription-id: \${{ secrets.WIZARDCYBER_SUBS_ID }}
        environment: 'AzureCloud'
        audience: api://AzureADTokenExchange
        enable-AzPSSession: true

    - name: Checkout
      uses: actions/checkout@v3
      with:
        fetch-depth: 2 # Fetch current and previous commit to detect changes

    - name: Get changed files
      id: changed-files
      shell: pwsh
      run: |
        # Get list of NEW JSON files in BaseRuleSet/ directory (added for first time)
        \$newFiles = git diff --name-only --diff-filter=A HEAD~1 HEAD -- 'BaseRuleSet/*.json'
        \$newFilesString = \$newFiles -join ','
        echo "new_files=\$newFilesString" >> \$env:GITHUB_OUTPUT
        echo "New files: \$newFilesString"
        
        # Get list of MODIFIED JSON files in BaseRuleSet/ directory (already existed, now changed)
        \$modifiedFiles = git diff --name-only --diff-filter=MR HEAD~1 HEAD -- 'BaseRuleSet/*.json'
        \$modifiedFilesString = \$modifiedFiles -join ','
        echo "modified_files=\$modifiedFilesString" >> \$env:GITHUB_OUTPUT
        echo "Modified files: \$modifiedFilesString"
        
        # Get list of DELETED JSON files in BaseRuleSet/ directory
        \$deletedFiles = git diff --name-only --diff-filter=D HEAD~1 HEAD -- 'BaseRuleSet/*.json'
        \$deletedFilesString = \$deletedFiles -join ','
        echo "deleted_files=\$deletedFilesString" >> \$env:GITHUB_OUTPUT
        echo "Deleted files: \$deletedFilesString"
        
        # Combine new and modified for total changed files
        \$allChangedFiles = @()
        if (![string]::IsNullOrWhiteSpace(\$newFilesString)) { \$allChangedFiles += \$newFiles }
        if (![string]::IsNullOrWhiteSpace(\$modifiedFilesString)) { \$allChangedFiles += \$modifiedFiles }
        \$changedFilesString = \$allChangedFiles -join ','
        echo "changed_files=\$changedFilesString" >> \$env:GITHUB_OUTPUT
        
        # Check if BaseRuleSet files changed
        if (![string]::IsNullOrWhiteSpace(\$changedFilesString) -or ![string]::IsNullOrWhiteSpace(\$deletedFilesString)) {
          echo "baseruleset_changed=true" >> \$env:GITHUB_OUTPUT
        } else {
          echo "baseruleset_changed=false" >> \$env:GITHUB_OUTPUT
        }
        
        # If no specific rule files changed or deleted, we don't need to deploy anything
        if ([string]::IsNullOrWhiteSpace(\$changedFilesString) -and [string]::IsNullOrWhiteSpace(\$deletedFilesString)) {
          echo "No JSON rule files changed or deleted, skipping deployment"
          echo "skip_deployment=true" >> \$env:GITHUB_OUTPUT
        } else {
          echo "skip_deployment=false" >> \$env:GITHUB_OUTPUT
        }
      
    - name: Deploy Content to Microsoft Sentinel
      if: steps.changed-files.outputs.skip_deployment == 'false' && steps.changed-files.outputs.baseruleset_changed == 'true'
      uses: azure/powershell@v2
      with:
        azPSVersion: 'latest'
        inlineScript: |
          # Set changed files as environment variable for the PowerShell script
          \$env:CHANGED_FILES = "\${{ steps.changed-files.outputs.changed_files }}"
          \$env:NEW_FILES = "\${{ steps.changed-files.outputs.new_files }}"
          \$env:MODIFIED_FILES = "\${{ steps.changed-files.outputs.modified_files }}"
          \$env:DELETED_FILES = "\${{ steps.changed-files.outputs.deleted_files }}"
          \${{ github.workspace }}//.github/workflows/${TENANT_NAME}.ps1
  

  CustomerRulesDeployment:
    runs-on: windows-latest
    env:
      resourceGroupName: '${RESOURCE_GROUP}'
      workspaceName: '${WORKSPACE_NAME}'
      workspaceId: '${WORKSPACE_ID}'
      directory: '\${{ github.workspace }}/Tenants/${TENANT_NAME}'
      cloudEnv: 'AzureCloud'
      contentTypes: 'AnalyticsRule'
      branch: 'main'
      sourceControlId: '${SOURCE_CONTROL_ID}'
      rootDirectory: '\${{ github.workspace }}'
      githubAuthToken: \${{ secrets.GITHUB_TOKEN }}
      smartDeployment: 'true'
      subscriptionId: \${{ secrets.${SUBS_SECRET} }}
    permissions:
      contents: write
      id-token: write # Require write permission to Fetch an OIDC token.

    steps:
    - name: Login to Azure (Attempt 1)
      continue-on-error: true
      id: login1
      uses: azure/login@v2
      with:
        client-id: \${{ secrets.AZURE_SENTINEL_CLIENTID_6ad70202274c4d05b7d3867422638828 }}
        tenant-id: \${{ secrets.AZURE_SENTINEL_TENANTID_6ad70202274c4d05b7d3867422638828 }}
        subscription-id: \${{ secrets.WIZARDCYBER_SUBS_ID }}
        environment: 'AzureCloud'
        audience: api://AzureADTokenExchange
        enable-AzPSSession: true

    - name: Wait 30 seconds if login attempt 1 failed
      if: \${{ steps.login1.outcome=='failure' }}
      run: powershell Start-Sleep -s 30

    - name: Login to Azure (Attempt 2)
      continue-on-error: true
      id: login2
      uses: azure/login@v2
      if: \${{ steps.login1.outcome=='failure' }}
      with:
        client-id: \${{ secrets.AZURE_SENTINEL_CLIENTID_6ad70202274c4d05b7d3867422638828 }}
        tenant-id: \${{ secrets.AZURE_SENTINEL_TENANTID_6ad70202274c4d05b7d3867422638828 }}
        subscription-id: \${{ secrets.WIZARDCYBER_SUBS_ID }}
        environment: 'AzureCloud'
        audience: api://AzureADTokenExchange
        enable-AzPSSession: true

    - name: Wait 30 seconds if login attempt 2 failed
      if: \${{ steps.login2.outcome=='failure' }}
      run: powershell Start-Sleep -s 30

    - name: Login to Azure (Attempt 3)
      continue-on-error: false
      id: login3
      uses: azure/login@v2
      if: \${{ steps.login2.outcome=='failure'  }}
      with:
        client-id: \${{ secrets.AZURE_SENTINEL_CLIENTID_6ad70202274c4d05b7d3867422638828 }}
        tenant-id: \${{ secrets.AZURE_SENTINEL_TENANTID_6ad70202274c4d05b7d3867422638828 }}
        subscription-id: \${{ secrets.WIZARDCYBER_SUBS_ID }}
        environment: 'AzureCloud'
        audience: api://AzureADTokenExchange
        enable-AzPSSession: true

    - name: Checkout
      uses: actions/checkout@v3
      with:
        fetch-depth: 2 # Fetch current and previous commit to detect changes

    - name: Get changed files
      id: changed-files
      shell: pwsh
      run: |
        # Get list of NEW JSON files in ${TENANT_NAME}/ directory (added for first time)
        \$newFiles = git diff --name-only --diff-filter=A HEAD~1 HEAD -- 'Tenants/${TENANT_NAME}/*.json'
        \$newFilesString = \$newFiles -join ','
        echo "new_files=\$newFilesString" >> \$env:GITHUB_OUTPUT
        echo "New files: \$newFilesString"
        
        # Get list of MODIFIED OR RENAMED JSON files in ${TENANT_NAME}/ directory
        \$modifiedFiles = git diff --name-only --diff-filter=MR HEAD~1 HEAD -- 'Tenants/${TENANT_NAME}/*.json'
        \$modifiedFilesString = \$modifiedFiles -join ','
        echo "modified_files=\$modifiedFilesString" >> \$env:GITHUB_OUTPUT
        echo "Modified files: \$modifiedFilesString"
        
        # Get list of deleted JSON files in ${TENANT_NAME}/ directory
        \$deletedFiles = git diff --name-only --diff-filter=D HEAD~1 HEAD -- 'Tenants/${TENANT_NAME}/*.json'
        \$deletedFilesString = \$deletedFiles -join ','
        echo "deleted_files=\$deletedFilesString" >> \$env:GITHUB_OUTPUT
        echo "Deleted files: \$deletedFilesString"
        
        # Combine new and modified for total changed files
        \$allChangedFiles = @()
        if (![string]::IsNullOrWhiteSpace(\$newFilesString)) { \$allChangedFiles += \$newFiles }
        if (![string]::IsNullOrWhiteSpace(\$modifiedFilesString)) { \$allChangedFiles += \$modifiedFiles }
        \$changedFilesString = \$allChangedFiles -join ','
        echo "changed_files=\$changedFilesString" >> \$env:GITHUB_OUTPUT
        
        # Check if ${TENANT_NAME} files changed
        \$${TENANT_NAME}Changed = git diff --name-only --diff-filter=AMR HEAD~1 HEAD -- 'Tenants/${TENANT_NAME}/**' | Where-Object { \$_ -like '*.json' }
        if (\$${TENANT_NAME}Changed) {
          echo "${TENANT_NAME}_changed=true" >> \$env:GITHUB_OUTPUT
        } else {
          echo "${TENANT_NAME}_changed=false" >> \$env:GITHUB_OUTPUT
        }
        
        # If no specific rule files changed or deleted, we don't need to deploy anything
        if ([string]::IsNullOrWhiteSpace(\$changedFilesString) -and [string]::IsNullOrWhiteSpace(\$deletedFilesString)) {
          echo "No JSON rule files changed or deleted, skipping deployment"
          echo "skip_deployment=true" >> \$env:GITHUB_OUTPUT
        } else {
          echo "skip_deployment=false" >> \$env:GITHUB_OUTPUT
        }
      
    - name: Deploy Content to Microsoft Sentinel
      if: steps.changed-files.outputs.skip_deployment == 'false' && steps.changed-files.outputs.${TENANT_NAME}_changed == 'true'
      uses: azure/powershell@v2
      with:
        azPSVersion: 'latest'
        inlineScript: |
          # Set changed files as environment variable for the PowerShell script
          \$env:CHANGED_FILES = "\${{ steps.changed-files.outputs.changed_files }}"
          \$env:NEW_FILES = "\${{ steps.changed-files.outputs.new_files }}"
          \$env:MODIFIED_FILES = "\${{ steps.changed-files.outputs.modified_files }}"
          \$env:DELETED_FILES = "\${{ steps.changed-files.outputs.deleted_files }}"
          \${{ github.workspace }}//.github/workflows/${TENANT_NAME}.ps1
EOF

echo -e "${GREEN}✓ Created ${TENANT_NAME}.yml${NC}"

# Create the PowerShell script by copying from an existing one
echo -e "${YELLOW}Creating PowerShell script: ${TENANT_NAME}.ps1${NC}"

# Use SPS.ps1 as template since it's the most recent
if [[ -f "${WORKFLOWS_DIR}/SPS.ps1" ]]; then
    cp "${WORKFLOWS_DIR}/SPS.ps1" "${WORKFLOWS_DIR}/${TENANT_NAME}.ps1"
elif [[ -f "${WORKFLOWS_DIR}/GARANCIA.ps1" ]]; then
    cp "${WORKFLOWS_DIR}/GARANCIA.ps1" "${WORKFLOWS_DIR}/${TENANT_NAME}.ps1"
else
    echo -e "${RED}Error: No template PowerShell script found!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Created ${TENANT_NAME}.ps1${NC}"

# Create the tenant directory
echo -e "${YELLOW}Creating tenant directory: Tenants/${TENANT_NAME}${NC}"
mkdir -p "${TENANTS_DIR}/${TENANT_NAME}"

# Create a temporary placeholder file
echo "temp" > "${TENANTS_DIR}/${TENANT_NAME}/temp.txt"

echo -e "${GREEN}✓ Created Tenants/${TENANT_NAME} directory with temp file${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Tenant Creation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Files created:${NC}"
echo -e "  • ${WORKFLOWS_DIR}/${TENANT_NAME}.yml"
echo -e "  • ${WORKFLOWS_DIR}/${TENANT_NAME}.ps1"
echo -e "  • ${TENANTS_DIR}/${TENANT_NAME}/temp.txt"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Add the ${SUBS_SECRET} secret to your GitHub repository"
echo -e "  2. Replace temp.txt with actual detection rules (.json files)"
echo -e "  3. Commit and push the changes to trigger the workflow"
echo ""
echo -e "${BLUE}Tenant Configuration:${NC}"
echo -e "  Tenant Name: ${TENANT_NAME}"
echo -e "  Subscription Secret: ${SUBS_SECRET}"
echo -e "  Workspace Name: ${WORKSPACE_NAME}"
echo -e "  Resource Group: ${RESOURCE_GROUP}"
echo -e "  Workspace ID: ${WORKSPACE_ID}"
echo ""
echo -e "${GREEN}Done!${NC}"