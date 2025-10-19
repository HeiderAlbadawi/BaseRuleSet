# Sentinel Analytics Rules Deployment Behavior

## 🎯 Smart Deployment System

This repository uses an **intelligent deployment system** that treats NEW and MODIFIED rules differently.

## 📁 Directory Structure

```
BaseRuleSet/                    # Shared baseline rules (Smart deployment)
Tenants/
├── AcmeSentinel/              # Acme-specific rules (Full deployment)
└── TempLaw/                   # TempLaw-specific rules (Full deployment)
```

---

## 🚀 BaseRuleSet/ Deployment Rules (Shared Rules)

### ✨ NEW Rules (Added for First Time)
**When you ADD a new rule to BaseRuleSet/**:

| Tenant Has Rule? | Action | Result |
|------------------|--------|---------|
| ❌ Doesn't exist | ✅ **CREATE** | Rule deployed to tenant |
| ✅ Already exists | ⚠️ **SKIP & WARN** | Duplicate prevented |

**Behavior:** New rules are deployed to ALL tenants. If a rule with the same ID already exists, deployment is SKIPPED with a warning to prevent duplicates.

**Use case:** Rolling out a new detection rule to all tenants.

**Example Log (Success):**
```
[Info] NEW FILE: Rule does not exist in Sentinel - will CREATE new rule
[Info] Deploying BaseRuleSet/New Detection Rule.json
[Info] Deployment result: Deployment attempted
```

**Example Log (Duplicate Detected):**
```
[Warning] NEW FILE: Rule already exists in Sentinel - SKIPPING to prevent duplicate!
[Warning] File: BaseRuleSet/New Detection Rule.json
[Warning] A rule with this ID already exists in the workspace. Cannot create duplicate.
[Info] Deployment result: Rule already exists - cannot create duplicate (NEW file)
```

---

### 🔄 MODIFIED Rules (Existing File Changed)
**When you MODIFY an existing rule in BaseRuleSet/**:

| Tenant Has Rule? | Action | Result |
|------------------|--------|---------|
| ✅ Has rule | ✅ **UPDATE** | Rule updated with changes |
| ❌ Doesn't have it | ⏭️ **SKIP** | No action taken |

**Behavior:** Modified rules only update tenants that already have them deployed. Tenants without the rule are not affected.

**Use case:** Fixing a query bug or tuning a rule that some tenants use.

**Example Log (Update):**
```
[Info] MODIFIED FILE: Rule exists in Sentinel - will UPDATE with changes
[Info] Deploying BaseRuleSet/Existing Rule.json
[Info] Deployment result: Deployment attempted
```

**Example Log (Skip):**
```
[Info] MODIFIED FILE + UPDATE-ONLY MODE: Rule does not exist in Sentinel - skipping (won't create)
[Info] Deployment result: Rule does not exist - skipped (MODIFIED file, update-only mode)
```

---

### 🗑️ DELETED Rules
**When you DELETE a rule from BaseRuleSet/**:

| Tenant Has Rule? | Action | Result |
|------------------|--------|---------|
| ✅ Has rule | 🗑️ **DELETE** | Rule removed from tenant |
| ❌ Doesn't have it | ⏭️ **SKIP** | No action taken |

**Behavior:** Deleted rules are removed from ALL tenants that have them. **Important:** After processing deletions, the deployment phase is **skipped entirely** to prevent unnecessary redeployment of unchanged rules.

**Example Log (Deletion Only):**
```
[Info] Selective deletion mode detected with deleted files: BaseRuleSet/test.json
[Info] Successfully deleted Sentinel rule: a2153ee2-5eca-40bc-8707-8885da613006
[Info] Deletion summary: 1 successful, 0 failed
[Info] Deletion-only mode detected - skipping deployment as only deletions were processed
```

---

## 🏢 Tenants/ Deployment Rules (Tenant-Specific Rules)

### Tenants/AcmeSentinel/ and Tenants/TempLaw/
**Mode:** Full Deployment (Normal behavior)

| Action | Behavior |
|--------|----------|
| **Add new rule** | ✅ **CREATE** in workspace |
| **Modify rule** | ✅ **UPDATE** in workspace |
| **Delete rule** | 🗑️ **DELETE** from workspace |

**No restrictions** - all operations are allowed.

---

## 📊 Complete Behavior Matrix

### BaseRuleSet/ Rules

| File Status | Tenant Has Rule | Action | Reason |
|-------------|----------------|--------|---------|
| **NEW** | ❌ No | ✅ CREATE | Deploy new rule to all tenants |
| **NEW** | ✅ Yes | ⚠️ SKIP | Prevent duplicate (same ID exists) |
| **MODIFIED** | ✅ Yes | ✅ UPDATE | Update existing rule |
| **MODIFIED** | ❌ No | ⏭️ SKIP | Don't force rule on tenants without it |
| **DELETED** | ✅ Yes | 🗑️ DELETE | Remove from workspace |
| **DELETED** | ❌ No | ⏭️ SKIP | Nothing to delete |

### Tenants/* Rules

| File Status | Action | Notes |
|-------------|--------|-------|
| **NEW** | ✅ CREATE | No restrictions |
| **MODIFIED** | ✅ UPDATE | No restrictions |
| **DELETED** | 🗑️ DELETE | No restrictions |

---

## 🔍 How File Status is Detected

The system uses **Git diff filters** to detect file status:

```bash
# NEW files (Added)
git diff --name-only --diff-filter=A HEAD~1 HEAD -- 'BaseRuleSet/*.json'

# MODIFIED files (Modified)
git diff --name-only --diff-filter=M HEAD~1 HEAD -- 'BaseRuleSet/*.json'

# DELETED files (Deleted)
git diff --name-only --diff-filter=D HEAD~1 HEAD -- 'BaseRuleSet/*.json'
```

**Git Diff Filters:**
- `A` = Added (NEW file)
- `M` = Modified (existing file changed)
- `D` = Deleted (file removed)

---

## 🎬 Workflow Triggers

| Change Location | Acme Workflow | TempLaw Workflow | Result |
|----------------|---------------|------------------|---------|
| **BaseRuleSet/**` | ✅ Triggers | ✅ Triggers | Both tenants process (smart logic applies) |
| **Tenants/AcmeSentinel/** | ✅ Triggers | ❌ No | Only Acme affected |
| **Tenants/TempLaw/** | ❌ No | ✅ Triggers | Only TempLaw affected |

---

## 💡 Real-World Scenarios

### Scenario 1: Adding a New Baseline Rule

**Action:** Create `BaseRuleSet/Suspicious PowerShell.json`

**Result:**
- ✅ **Acme**: Rule created (if doesn't exist)
- ✅ **TempLaw**: Rule created (if doesn't exist)
- ⚠️ **Any tenant**: Skipped if rule ID already exists (duplicate prevention)

---

### Scenario 2: Tuning an Existing Rule

**Action:** Modify `BaseRuleSet/User Login Anomaly.json` (reduce false positives)

**Result:**
- If **Acme has the rule**: ✅ Updated
- If **Acme doesn't have it**: ⏭️ Skipped
- If **TempLaw has the rule**: ✅ Updated
- If **TempLaw doesn't have it**: ⏭️ Skipped

---

### Scenario 3: Retiring a Rule

**Action:** Delete `BaseRuleSet/Legacy Detection.json`

**Result:**
- ✅ **Acme**: Rule deleted (if exists)
- ✅ **TempLaw**: Rule deleted (if exists)

---

### Scenario 4: Adding Tenant-Specific Rule

**Action:** Create `Tenants/AcmeSentinel/Custom Acme Rule.json`

**Result:**
- ✅ **Acme**: Rule created
- ⏭️ **TempLaw**: Not affected (rule not in their folder)

---

## ⚠️ Duplicate Prevention

### What Happens?

When adding a NEW file to BaseRuleSet:

1. **Extract Rule ID** from JSON (GUID in the template)
2. **Query Sentinel** to check if rule with that ID exists
3. **If exists**: SKIP deployment with warning
4. **If not exists**: Proceed with creation

### Warning Message:
```
[Warning] NEW FILE: Rule already exists in Sentinel - SKIPPING to prevent duplicate!
[Warning] File: BaseRuleSet/YourRule.json
[Warning] A rule with this ID already exists in the workspace. Cannot create duplicate.
```

### Why This Matters:

Azure Sentinel **doesn't allow** two rules with the same ID. Attempting to create a duplicate would cause deployment failure. This check prevents that.

---

## 🔧 Technical Configuration

### Workflow Environment Variables

**BaseRulesDeployment Job:**
```yaml
env:
  directory: '${{ github.workspace }}/BaseRuleSet'
  smartDeployment: 'true'
  updateOnlyMode: 'true'          # Enable smart NEW vs MODIFIED logic
```

**CustomerRulesDeployment Job:**
```yaml
env:
  directory: '${{ github.workspace }}/Tenants/AcmeSentinel'
  smartDeployment: 'true'
  # updateOnlyMode not set → Full deployment (no restrictions)
```

### Variables Passed to PowerShell:

```powershell
$env:CHANGED_FILES    # All changed files (NEW + MODIFIED)
$env:NEW_FILES        # Only NEW files (git diff --diff-filter=A)
$env:MODIFIED_FILES   # Only MODIFIED files (git diff --diff-filter=M)
$env:DELETED_FILES    # Only DELETED files (git diff --diff-filter=D)
```

---

## 📈 Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| ✅ **Flexible** | New rules deploy everywhere, modified rules respect tenant choice |
| ✅ **Safe** | Duplicate prevention stops accidental rule conflicts |
| ✅ **Efficient** | Only processes what changed (smart deployment) |
| ✅ **Controlled** | Tenants can opt-out by not deploying initial version |
| ✅ **Traceable** | Clear logs show NEW vs MODIFIED behavior |

---

## 🛠️ Best Practices

### 1. Adding a New Shared Rule

```bash
# Step 1: Create JSON in BaseRuleSet/
cp new-rule.json BaseRuleSet/

# Step 2: Commit and push
git add BaseRuleSet/new-rule.json
git commit -m "Add new detection: Suspicious Registry Modification"
git push

# Result: Rule deployed to ALL tenants (if ID doesn't exist)
```

### 2. Tuning an Existing Shared Rule

```bash
# Step 1: Edit the rule in BaseRuleSet/
vi BaseRuleSet/existing-rule.json

# Step 2: Commit and push
git add BaseRuleSet/existing-rule.json
git commit -m "Tune: Reduce false positives in login anomaly rule"
git push

# Result: Only tenants WITH the rule get the update
```

### 3. Adding a Tenant-Specific Rule

```bash
# Step 1: Create in tenant folder
cp custom-rule.json Tenants/AcmeSentinel/

# Step 2: Commit and push
git add Tenants/AcmeSentinel/custom-rule.json
git commit -m "Add Acme-specific compliance rule"
git push

# Result: Only Acme gets the rule
```

---

## 🚨 Troubleshooting

### Problem: "Rule already exists" warning for NEW file

**Cause:** A rule with the same ID already exists in the tenant workspace.

**Solution:**
1. Check if the rule was manually created in Sentinel
2. If duplicate is intentional, change the rule ID in the JSON
3. If it's the same rule, this is expected behavior (preventing duplicate)

### Problem: MODIFIED rule not deploying to any tenant

**Cause:** No tenant has this rule deployed.

**Solution:**
1. This is expected if no tenant uses this rule
2. To deploy to specific tenant, copy to `Tenants/{TenantName}/` temporarily
3. After first deployment, manage from `BaseRuleSet/`

### Problem: Want to force a modified rule onto all tenants

**Solution:**
1. Temporarily change `updateOnlyMode: 'false'` in workflow
2. Commit and push (deploys to all)
3. Change back to `updateOnlyMode: 'true'`
4. Commit and push again

### Problem: Deleted a rule but all rules were redeployed

**Cause:** This was a bug in versions prior to v3.1. When only deletions occurred with no changed files, the system fell back to full deployment mode.

**Solution:** Fixed in v3.1 (2025-10-19). The system now detects deletion-only scenarios and skips the deployment phase entirely after processing deletions.

---

## 📝 Version History

- **v3.1** (2025-10-19): Fixed deletion-only mode to prevent unnecessary full redeployment
- **v3.0** (2025-10-19): Smart NEW vs MODIFIED detection with duplicate prevention
- **v2.0** (2025-10-19): Added update-only mode for BaseRuleSet deployments
- **v1.1** (2025-10-19): Reorganized into Tenants/ directory structure
- **v1.0**: Initial smart deployment with SHA tracking
