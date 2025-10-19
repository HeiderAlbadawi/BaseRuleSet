# Sentinel Analytics Rules Deployment Behavior

## Overview
This repository uses a smart deployment system with **update-only mode** for shared baseline rules.

## Directory Structure

```
BaseRuleSet/                    # Shared baseline rules (UPDATE-ONLY)
Tenants/
├── AcmeSentinel/              # Acme-specific rules (CREATE & UPDATE)
└── TempLaw/                   # TempLaw-specific rules (CREATE & UPDATE)
```

## Deployment Rules

### BaseRuleSet/ (Shared Rules)
**Mode:** UPDATE-ONLY

When you modify a rule in `BaseRuleSet/`:
- ✅ **Rule exists in tenant** → Rule will be **UPDATED** with your changes
- ❌ **Rule doesn't exist in tenant** → Deployment **SKIPPED** (no new rule created)

**Use case:** Maintain consistent versions of common rules across tenants that already have them deployed, without forcing rules onto tenants that don't want them.

**Example:**
```
Rule: "Suspicious File Transfer" (ID: 6d9e173f-...)

Scenario 1: Acme HAS the rule, TempLaw HAS the rule
Result: Both tenants get the updated rule ✅

Scenario 2: Acme HAS the rule, TempLaw DOES NOT have the rule
Result: Only Acme gets updated, TempLaw skips deployment ✅

Scenario 3: Neither tenant has the rule
Result: Both tenants skip deployment (rule not created) ✅
```

### Tenants/AcmeSentinel/ and Tenants/TempLaw/ (Tenant-Specific Rules)
**Mode:** CREATE & UPDATE (Normal deployment)

When you modify or add a rule in tenant-specific folders:
- ✅ **Rule exists** → Rule will be **UPDATED**
- ✅ **Rule doesn't exist** → Rule will be **CREATED**

**Use case:** Deploy rules that are specific to a single tenant, including new custom rules.

## Workflow Triggers

### Changes to BaseRuleSet/
- Triggers: **Both** Acme and TempLaw workflows
- Deploys to: **Both** tenants (with update-only mode)

### Changes to Tenants/AcmeSentinel/
- Triggers: **Only** Acme workflow
- Deploys to: **Only** Acme tenant

### Changes to Tenants/TempLaw/
- Triggers: **Only** TempLaw workflow
- Deploys to: **Only** TempLaw tenant

## How It Works Technically

The deployment scripts check if a rule exists by querying Azure Sentinel using the rule's GUID:

1. **Parse JSON** → Extract rule ID from the template
2. **Query Sentinel** → Check if rule with that ID exists in the workspace
3. **Apply Logic:**
   - If `updateOnlyMode=true` (BaseRuleSet jobs) AND rule doesn't exist → **SKIP**
   - If `updateOnlyMode=false` (Tenant-specific jobs) → **DEPLOY** (create or update)
   - If rule exists → **DEPLOY** (update)

## Configuration

Update-only mode is controlled by the `updateOnlyMode` environment variable in workflow files:

### Acme-SentinelDeployment.yml
```yaml
jobs:
  BaseRulesDeployment:
    env:
      directory: '${{ github.workspace }}/BaseRuleSet'
      updateOnlyMode: 'true'  # ← UPDATE-ONLY enabled
  
  CustomerRulesDeployment:
    env:
      directory: '${{ github.workspace }}/Tenants/AcmeSentinel'
      # updateOnlyMode not set → CREATE & UPDATE enabled
```

### TempLaw-SentinelDeployment.yml
```yaml
jobs:
  BaseRulesDeployment:
    env:
      directory: '${{ github.workspace }}/BaseRuleSet'
      updateOnlyMode: 'true'  # ← UPDATE-ONLY enabled
  
  CustomerRulesDeployment:
    env:
      directory: '${{ github.workspace }}/Tenants/TempLaw'
      # updateOnlyMode not set → CREATE & UPDATE enabled
```

## Log Output Examples

### When rule exists (will update):
```
[Info] Checking if rule with ID '6d9e173f-d7ad-4b52-8fbb-15ff99feede7' already exists in Sentinel
[Info] Rule with ID '6d9e173f-...' already exists in Sentinel. Display Name: 'Suspicious File Transfer'
[Info] Rule already exists in Sentinel - will update it with new changes from BaseRuleSet/...
[Info] Deploying BaseRuleSet/Suspicious File Transfer...
```

### When rule doesn't exist (update-only mode):
```
[Info] Checking if rule with ID 'a2c011a6-3986-411a-9e27-286d018e1b65' already exists in Sentinel
[Info] Rule with ID 'a2c011a6-...' does not exist in Sentinel
[Info] UPDATE-ONLY MODE: Rule does not exist in Sentinel - skipping creation (update-only mode enabled)
[Info] Deployment result: Rule does not exist - skipped (update-only mode)
```

### When rule doesn't exist (normal mode - tenant-specific):
```
[Info] Checking if rule with ID 'a2c011a6-3986-411a-9e27-286d018e1b65' already exists in Sentinel
[Info] Rule with ID 'a2c011a6-...' does not exist in Sentinel
[Info] Rule does not exist in Sentinel - will create new rule from Tenants/AcmeSentinel/...
[Info] Deploying Tenants/AcmeSentinel/Custom Rule...
```

## Best Practices

1. **Shared Rules** → Put in `BaseRuleSet/`
   - Rules used by multiple tenants
   - Rules that should stay synchronized
   - Won't force rules on tenants that don't want them

2. **Tenant-Specific Rules** → Put in `Tenants/{TenantName}/`
   - Custom rules for a single tenant
   - Rules that should only exist in one workspace
   - New rules being tested for one tenant

3. **New Baseline Rule** → Add to both:
   - Add JSON to `BaseRuleSet/` (for future updates)
   - Copy JSON to `Tenants/{TenantName}/` for initial deployment
   - After first deployment, manage from `BaseRuleSet/` only

## Troubleshooting

### Problem: Rule in BaseRuleSet not deploying to any tenant
**Cause:** Rule doesn't exist in either tenant (update-only mode skipping)
**Solution:** 
1. Temporarily copy the rule to `Tenants/{TenantName}/`
2. Push and deploy (creates the rule)
3. Remove from `Tenants/` folder
4. Future updates will work from `BaseRuleSet/`

### Problem: Want to force create a BaseRuleSet rule on all tenants
**Solution:** 
1. Edit workflow file (Acme-SentinelDeployment.yml or TempLaw-SentinelDeployment.yml)
2. In `BaseRulesDeployment` job, change: `updateOnlyMode: 'false'`
3. Commit and push
4. After deployment, change back to: `updateOnlyMode: 'true'`

### Problem: Rule getting deployed to wrong tenant
**Check:** 
- Which folder is the rule in?
- Review the `paths:` section in workflow files
- Check GitHub Actions logs to see which workflows triggered

## Version History

- **v2.0** (2025-10-19): Added update-only mode for BaseRuleSet deployments
- **v1.1** (2025-10-19): Reorganized into Tenants/ directory structure
- **v1.0**: Initial smart deployment with selective file detection
