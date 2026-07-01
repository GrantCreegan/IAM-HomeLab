# PowerShell Automation for Entra ID Identity Operations

**Environment:** IAM Home Lab — Microsoft Entra ID via Microsoft Graph PowerShell SDK
**Author:** Grant Creegan
**Tenant:** grantmcreeganoutlook.onmicrosoft.com
**Date:** [insert date]

---

## 1. Purpose

This document describes four PowerShell scripts built against the Microsoft Graph API to automate common IAM operations in an Entra ID tenant. The scripts cover the foundational lifecycle and audit tasks every Entra-heavy IAM role involves: bulk user creation, stale account detection, access review export, and Conditional Access policy auditing.

The intent is not to claim these are production-ready tools. They demonstrate fluency with the Graph PowerShell SDK and an understanding of why these operations matter in a real environment — both of which are screened for in IAM hiring interviews.

## 2. Architecture

```
[Local workstation]
PowerShell 7 + Microsoft.Graph SDK
        │
        │  HTTPS (delegated auth via device code flow)
        ▼
[Microsoft Graph API]
        │
        ▼
[Entra ID tenant — grantmcreeganoutlook.onmicrosoft.com]
```

Authentication is delegated and interactive. The signed-in admin's permissions govern what the scripts can do. The Connect-MgGraph cmdlet requests specific OAuth scopes at connection time, and the resulting access token is used implicitly by every Graph cmdlet in the session.

In a production environment the same scripts would be adapted to run unattended via a service principal with certificate-based authentication, scheduled in Azure Automation or a similar runner. That pattern is intentionally outside the scope of this lab — interactive delegated auth is sufficient to demonstrate the underlying skills, and the unattended pattern adds setup complexity without changing the script logic.

## 3. Scripts Overview

| Script | Purpose | Lifecycle Stage |
|---|---|---|
| New-BulkUsers.ps1 | Creates Entra ID users from a CSV input | Joiner |
| Get-StaleAccounts.ps1 | Identifies inactive users for review | Mover / Leaver |
| Export-AccessReview.ps1 | Snapshots every user's roles and group memberships | Mover (periodic review) |
| Get-CAPolicyAudit.ps1 | Audits all Conditional Access policies | Policy governance |

All four scripts share a common pattern: import data via Graph cmdlets, transform into a PSCustomObject collection, display a human-readable summary in the terminal, and export a timestamped CSV to a `logs/` subdirectory for audit retention.

### 3.1 New-BulkUsers.ps1

Reads `new-users.csv` and creates each user via `New-MgUser`. Each account is created enabled, with a randomized temporary password and the `ForceChangePasswordNextSignIn` flag set so the user is required to set their own password at first sign-in.

The script tracks successes and failures separately and writes both to timestamped CSV logs. This is intentional — in a real bulk-create operation, the failure log is the artifact you hand back to the HR or onboarding team so they know which new hires need follow-up.

**Real-world context:** in any organization with more than a handful of hires per week, manually creating accounts in the portal is unsustainable. The CSV-driven bulk approach mirrors how Entra accounts are typically created in environments without a fully automated HRIS-to-IdP integration.

### 3.2 Get-StaleAccounts.ps1

Pulls every user along with their `SignInActivity` property (which requires Entra ID P1 or P2). Compares the last sign-in timestamp against a configurable threshold (default 90 days) and reports users in three buckets: active, stale, and never-signed-in.

**Critical design decision: break-glass accounts are explicitly excluded.** Break-glass accounts are expected to remain unused under normal operations — that is the entire point of their existence. A naive stale-account script that flagged the break-glass for deactivation would create a serious operational risk: the very accounts you rely on to recover from a federation or Conditional Access outage would be deactivated by the automation designed to clean up inactive users.

The script handles this with an explicit `$excludeUPNs` array near the top of the file. Excluded accounts are reported in their own bucket so a reviewer can see they were intentionally skipped — silent skipping would be worse than no skipping at all because it would hide the exclusion logic from auditors.

**Real-world context:** stale account review is a SOC 2, ISO 27001, and HIPAA control. The control language is typically something like "the organization shall review user access at defined intervals and disable accounts that are no longer required." This script generates the evidence that supports that control.

### 3.3 Export-AccessReview.ps1

Builds a comprehensive snapshot of every user's account state, group memberships, and directory role assignments. The output CSV is the kind of artifact that gets distributed to department managers or compliance reviewers during quarterly access certification cycles.

The script optimizes role lookups by fetching all directory role assignments once and building an in-memory lookup table keyed by user object ID, rather than querying per user. This matters for tenants with many users — the per-user query pattern would generate one API call per role per user, which becomes slow and rate-limited quickly.

**Real-world context:** access reviews answer the question "does this person still need this access?" Every regulated organization runs them. The output of this script is the input to that conversation.

### 3.4 Get-CAPolicyAudit.ps1

Exports a structured summary of every Conditional Access policy in the tenant — name, state (On / Off / Report-only), included and excluded users and groups, target applications, conditions (locations, client apps, platforms), and grant controls.

**Real-world context:** CA policies are the heart of the modern identity perimeter. They drift over time as new policies get added and old ones get disabled or forgotten. Auditors will ask "show me every CA policy and its current state, and tell me when each was last modified." Without a script, that is a multi-hour click-through-the-portal task. With this script it is one command.

The script also closes the loop on Phase 4 of this lab — Phase 4 built the policies (CA001, CA002, CA003); this script audits them. The same script would surface any drift if the policies were modified between runs, which makes it a candidate for periodic comparison.

## 4. Demonstrated Capabilities

Across the four scripts, the following Graph SDK patterns are demonstrated:

- **Connection management:** authenticated to the tenant via `Connect-MgGraph` with explicit scope requests, using device code flow to handle the MSA-guest-admin authentication pattern.
- **Bulk operations:** `New-MgUser` in a CSV-driven loop with per-item error handling rather than transactional all-or-nothing.
- **Sign-in activity queries:** using the `SignInActivity` user property, which requires the right scope (`AuditLog.Read.All`) and a P1/P2 license.
- **Role and group resolution:** fetching directory roles, building lookup tables for efficient cross-referencing, traversing user membership via `Get-MgUserMemberOf`.
- **Conditional Access introspection:** reading every property of a CA policy via `Get-MgIdentityConditionalAccessPolicy` and flattening complex nested objects into a tabular report.
- **Output discipline:** every script writes timestamped CSV logs to a `logs/` subdirectory, so historical audit data is preserved across runs without overwriting.

## 5. Real Problems Encountered and Solved

The build was not friction-free. The following are real issues that surfaced during the lab and the solutions applied. These are the entries that distinguish hands-on experience from following a tutorial.

### Problem 1: Connect-MgGraph silently fails for MSA guest admin

**Symptom:** `Connect-MgGraph` defaulted to Web Account Manager (WAM) authentication. The browser prompt either never appeared or returned a generic "InteractiveBrowserCredential authentication failed:" error with no further detail.

**Root Cause:** The tenant's Global Administrator is a Microsoft personal account (MSA) invited as an external guest user (`#EXT#` UPN format). WAM is optimized for native Entra accounts and does not handle MSA-guest-admin patterns cleanly. Additionally, without an explicit `-TenantId` parameter, the SDK attempts to resolve the home tenant from the MSA's consumer identity stack rather than the dev tenant.

**Solution:** Connect with both `-UseDeviceCode` and an explicit `-TenantId`:

```powershell
Connect-MgGraph -TenantId '<tenant-guid>' -Scopes '<scopes>' -UseDeviceCode
```

**Lesson Learned:** Authentication patterns that work for native cloud admins often fail for MSA-guest admin setups. The device code flow with explicit tenant ID is the universal fallback. This is a common gotcha for anyone running a Microsoft 365 Developer tenant, since that program creates admins as MSA guests by default.

### Problem 2: Device code marked expired immediately

**Symptom:** Code generated by `-UseDeviceCode` was rejected as expired within seconds of being copied to the device login page.

**Root Cause:** Multiple sequential `Connect-MgGraph` attempts had each generated their own codes. Browser tabs were holding stale codes from earlier attempts. Pasting an earlier code into a later browser session resulted in immediate rejection.

**Solution:** Close all device login browser tabs, disconnect any partial session with `Disconnect-MgGraph`, run a fresh Connect, and enter the new code immediately without switching focus away from PowerShell during the auth flow.

**Lesson Learned:** Device code authentication is single-use and short-lived. The combination of multiple in-flight codes and cached browser state creates failure modes that read as "expired" but are actually "wrong code for this session." Operational discipline around clean session state matters.

### Problem 3: New-BulkUsers.ps1 rejected all UPNs

**Symptom:** All three users in the test CSV failed with `[Request_BadRequest]: The domain portion of the userPrincipalName property is invalid. You must use one of the verified domain names in your organization.`

**Root Cause:** The CSV used `@grantcreegan.dev` UPNs, but that custom domain was not verified in the Entra tenant. Graph enforces strict domain ownership for user creation.

**Solution:** Switched UPNs to `@grantmcreeganoutlook.onmicrosoft.com`, which is the default verified domain that comes with every tenant.

**Lesson Learned:** Entra strictly enforces UPN domain ownership via DNS-verified domains. The `.onmicrosoft.com` domain is the always-available fallback when custom domain verification is incomplete or pending. In a production environment, completing domain verification is a Phase 1 prerequisite for any user-creation automation.

### Problem 4: Break-glass account appeared in stale-account report

**Symptom:** The first version of `Get-StaleAccounts.ps1` correctly identified accounts with no sign-in activity, but the break-glass account was included in that list. A naive administrator following the script's output as a deactivation worklist would have deactivated the very account designed to be the recovery path for federation outages.

**Root Cause:** Break-glass accounts are intentionally inactive under normal conditions. They look identical to true stale accounts in sign-in activity data, but the operational meaning is opposite — one should be removed, the other must be preserved.

**Solution:** Added an explicit `$excludeUPNs` array near the top of the script. Excluded accounts are reported in their own bucket (not silently skipped), so a reviewer can see the exclusion logic was applied deliberately.

**Lesson Learned:** Identity automation has high blast radius. A script that "cleans up inactive accounts" must understand that some accounts are inactive *by design*. The right pattern is explicit allow-listing of exceptions, with the exclusions visible in the output. Silent skipping is worse than no skipping because it hides the logic from auditors. This is the same design principle behind the break-glass exclusion in Conditional Access policies — same accounts, same rationale, applied across two different control layers.

## 6. Gaps and Production Considerations

The scripts demonstrate the underlying patterns but are not production-grade. A real implementation would add:

- **Service principal authentication.** Replace interactive `Connect-MgGraph` with certificate-based service principal auth so the scripts can run unattended on a schedule. This requires registering an app in Entra, generating a certificate, and assigning Graph API permissions to the app.
- **Scheduling and alerting.** Wrap the scripts in Azure Automation runbooks or a scheduled job runner. Failed executions should notify a SIEM or chat channel.
- **HRIS integration upstream.** `New-BulkUsers.ps1` consumes a static CSV; in production the input would be pulled from Workday, BambooHR, or a similar HRIS via API, with diffing logic to handle joiners, movers, and leavers from the same data source.
- **Approval workflows.** Bulk user creation in production typically requires manager approval. The script would integrate with a workflow tool (Logic Apps, ServiceNow, Power Automate) rather than executing immediately.
- **Group-based access provisioning.** The current scripts handle users but do not assign groups, licenses, or app entitlements. A complete onboarding script would map department/job title attributes to group memberships, ensuring new users get the right access set on day one.
- **Output to SIEM, not just CSV.** Stale account reports, access reviews, and CA audits should be ingested into a SIEM (Sentinel, Splunk) for retention and cross-referencing with other security events, not just dropped as local CSVs.
- **Idempotency.** `New-BulkUsers.ps1` does not check if a user already exists before creating. In production, the script would query first and either skip, update, or hard-fail on duplicates depending on the desired behavior.

## 7. Conclusion

The four scripts in this phase cover the core IAM operations that every Entra-heavy environment runs constantly: bulk creation, stale account review, access certification, and policy audit. The Graph PowerShell SDK is the standard tool for this work, and the scripts demonstrate fluency with both the SDK and the operational thinking behind each task.

The most valuable design decisions are not in the code volume but in the small choices: per-item error handling that produces a failure log, break-glass exclusions that prevent destructive false positives, and timestamped CSV outputs that preserve audit history across runs. These are the details that make automation safe to run in environments where mistakes have real consequences.

---

*This document is part of the IAM Home Lab portfolio. See the project README for full architecture and the Problems-and-Solutions log for additional issues encountered during build.*
