# Problems and Solutions Log

**Environment:** IAM Home Lab — Okta + Microsoft Entra ID + GitHub Enterprise Cloud
**Author:** Grant Creegan
**Repository:** github.com/GrantCreegan/IAM-HomeLab

---

## Purpose

This log documents every meaningful problem encountered during the build of this lab and the solution applied. It exists for two reasons:

1. **Institutional memory.** IAM systems are complex enough that the same problem will resurface months later on a different project. A running log of what broke, why, and how it was fixed is worth more than the polished documentation.
2. **Interview evidence.** These entries are the difference between "I followed a tutorial" and "I built and debugged a real integrated identity environment." Every entry below reflects a real hour or two of debugging with no external help available.

---

## Problem 1: Conditional Access creation blocked by "Entra ID Premium required"

**Symptom:** Attempting to create a Conditional Access policy in a Microsoft 365 Developer tenant returned the message "Create your own policies and target specific conditions like cloud apps, sign-in risk, and device platforms with Microsoft Entra ID Premium." The **New policy** button was greyed out despite the tenant having E5 licenses which are supposed to include Entra ID P2 as a service plan.

**Root Cause:** The Entra ID P2 service plan bundled with E5 Developer licenses did not register as active in the Conditional Access blade. This is a known state in dev tenants where the license bundle is applied but individual service plans read as inactive. The portal was correct that the tenant needed a "recognized" P2 SKU before CA would unlock.

**Solution:** Activated the standalone Entra ID P2 free trial from `admin.microsoft.com` → Billing → Purchase services. This layered a clean P2 SKU on top of the existing E5 licenses. The CA blade unlocked immediately after license propagation.

**Lesson Learned:** In dev tenants, the license bundle listed in the admin center is not always what the individual product blades will honor. Standalone trials of the specific SKU are the workaround when a service plan is technically present but functionally invisible. In a production environment, the equivalent problem would be a license assignment that had not fully propagated across services, which typically resolves in under an hour but can require support engagement.

---

## Problem 2: P2 trial activation kicked off consumer tenant signup instead

**Symptom:** Clicking the trial activation link from within the Conditional Access blade launched a Microsoft signup flow that wanted to create a brand-new tenant tied to the personal Outlook email address, rather than activating the trial inside the existing dev tenant.

**Root Cause:** The Global Administrator of this tenant is a Microsoft personal account (MSA) invited as an external guest (`grant.m.creegan_outlook.com#EXT#@grantmcreeganoutlook.onmicrosoft.com`). When Microsoft's signup pages encounter an MSA, they route to consumer identity workflows that assume the user wants a fresh tenant. The link embedded in the CA blade did not preserve the tenant context.

**Solution:** Instead of clicking the in-blade activation link, went to `admin.microsoft.com` → **Billing** → **Purchase services** → searched for Entra ID P2 → activated the trial from that page. This flow correctly recognized the existing tenant context because it was being initiated from inside the admin center, not from a marketing link.

**Lesson Learned:** MSA-guest admin patterns are fragile at the boundary between consumer and commercial Microsoft identity flows. When a workflow redirects unexpectedly to a consumer signup, the fix is almost always to re-enter the same workflow from a page that is deeper inside the admin center — that context is what tells Microsoft's routing to stay in the commercial stack.

---

## Problem 3: SAML NameID did not match any verified email on personal GitHub account

**Symptom:** First SAML test between Okta and the GitHub Enterprise Cloud Organization failed with a generic "browser did something unexpected" error. Okta's System Log showed the SAML assertion was issued successfully.

**Root Cause:** GitHub SAML matches the IdP-issued NameID against verified emails on the personal GitHub account being authenticated. If no GitHub account has that email verified, SAML succeeds on the Okta side but GitHub cannot resolve the assertion to a user. The Okta admin account and the personal GitHub account had different primary emails.

**Solution:** Added the Okta admin email as a secondary email on the personal GitHub account via `github.com/settings/emails` and verified it via the confirmation link. Retested SAML — GitHub could now match the Okta NameID to a verified email on the GitHub account.

**Lesson Learned:** SCIM creates GitHub users; SAML does not. SAML alone requires the user to already exist on GitHub with a matching verified email. Understanding which protocol handles which lifecycle event is fundamental — this exact question ("what does SAML do that SCIM does not?") comes up in interviews.

---

## Problem 4: Audience URI malformed, breaking SAML with silent errors

**Symptom:** After fixing the email match issue, SAML test still failed with the same generic browser error. Okta System Log again showed successful assertion. Careful inspection of the SAML assertion payload showed the Audience URI as `https://github.com/orgs//organizations/Grant-iam-lab/` — with a double slash and an extra `/organizations/` segment that should not have been there.

**Root Cause:** The Okta app's **GitHub Organization Name** field had been entered as `/organizations/Grant-iam-lab/` instead of the plain org slug `Grant-iam-lab`. Okta builds the Audience URI by templating that field into a URL pattern. The extra slash and path segment broke the value in a way that GitHub rejected but Okta did not warn about.

**Solution:** Edited the Okta app's GitHub Organization Name field to exactly `Grant-iam-lab`, no slashes or extra path. Verified the fix by opening **View SAML setup instructions** in Okta and confirming the new Audience URI matched GitHub's ACS URL.

**Lesson Learned:** When SAML fails with a vague SP-side error but the IdP logs show a successful assertion, the issue is almost always in SP validation: Audience, Destination, or Recipient mismatch. Always check the IdP's SAML assertion output against the SP's expected values byte-for-byte. Also: Okta apps that template URLs from user input are extremely sensitive to leading/trailing whitespace and slashes — the input field trusts the admin to enter the right value with the right formatting.

---

## Problem 5: Trailing slash caused Destination, Recipient, and Audience to all fail

**Symptom:** After fixing the extra path segment in Problem 4, SAML test now returned three specific errors instead of the generic one: "Destination in the SAML response was not valid," "Recipient in the SAML response was not valid," "Audience is invalid."

**Root Cause:** A single trailing slash had been left on the Org Name field. Every SAML URL that Okta templated from that field ended up with one extra character compared to what GitHub expected. Because all three fields (Destination, Recipient, Audience) are constructed from the same input value, all three failed simultaneously.

**Solution:** Removed the trailing slash from the Org Name field.

**Lesson Learned:** SAML URL comparisons are byte-exact. Even a single trailing slash is a validation failure. When multiple SAML fields fail together with mismatch errors, the root cause is almost always a single input value that is templated into all of them.

---

## Problem 6: Okta GitHub integration uses OAuth, not PAT — documentation drift

**Symptom:** The lab guide (based on older Okta documentation) called for generating a Personal Access Token in GitHub, then pasting it into a token field on the Okta app's Provisioning tab. On the actual Provisioning tab, there was no token field — only an **Authenticate with GitHub Enterprise Cloud - Organization** button.

**Root Cause:** The Okta GitHub Enterprise Cloud - Organization integration migrated from static-PAT authentication to an OAuth-based flow. Clicking the Authenticate button triggers an OAuth handshake that Okta then stores as the API credential for SCIM. The PAT approach still works for direct GitHub API calls but is not the current integration path for Okta.

**Solution:** Used the OAuth authenticate flow. Revoked the unused classic PAT afterward for security hygiene — no reason to leave a token with `admin:org` scope active if nothing is using it.

**Lesson Learned:** Documentation drift is a real operational risk. Always cross-reference the guide against the actual UI. Also: revoke unused credentials with admin scopes as a habit, even in a lab. In production this same discipline prevents the classic "we discovered a five-year-old GitHub PAT with owner permissions still active" audit finding.

---

## Problem 7: PAT "Configure SSO" option missing until enforcement was enabled

**Symptom:** After generating a classic PAT with the correct scopes, the token appeared in `github.com/settings/tokens` but the **Configure SSO** option next to it (needed to authorize the token for use with a SAML-protected org) did not appear.

**Root Cause:** SAML SSO had been enabled on the Org but not **required**. GitHub only surfaces the Configure SSO option for PATs when SAML is actively enforced on the target Org — not when it is merely configured.

**Solution:** Enabled the setting **Require SAML SSO authentication for all members of the Grant-iam-lab organization**. The Configure SSO option appeared on the PAT immediately after enforcement was toggled on.

**Lesson Learned:** In GitHub, SAML SSO "enabled" and "enforced" are two different states, and downstream features respect that difference. This applies beyond PATs — it affects GitHub Apps, OAuth apps, and any other credential path that touches SAML-protected resources. When a SAML-related feature appears to be missing, always check whether enforcement is actually on.

---

## Problem 8: Connect-MgGraph silently fails for MSA guest admin

**Symptom:** `Connect-MgGraph` opened a browser window that either never appeared or returned a generic "InteractiveBrowserCredential authentication failed:" error with no additional detail. The Web Account Manager (WAM) integration used by default on Windows was silently failing.

**Root Cause:** WAM is optimized for native Entra accounts. It does not cleanly handle the MSA-guest-admin pattern used by this tenant (`grant.m.creegan@outlook.com` invited as an external guest with the `#EXT#` UPN format). Additionally, without an explicit `-TenantId` parameter, the SDK tried to resolve the home tenant from the MSA's consumer identity stack rather than the dev tenant, adding a second failure point.

**Solution:** Connected with both `-UseDeviceCode` (to bypass WAM entirely and use browser-based device code flow) and an explicit `-TenantId` (to force the SDK to authenticate against the dev tenant specifically):

```powershell
Connect-MgGraph -TenantId '<tenant-guid>' -Scopes '<scopes>' -UseDeviceCode
```

**Lesson Learned:** Authentication patterns that work for native cloud admins often fail for MSA-guest-admin setups. Device code flow with explicit tenant ID is the universal fallback and should be the first thing tried when default `Connect-MgGraph` fails silently. This is a common gotcha for anyone running against a Microsoft 365 Developer tenant since that program creates admins as MSA guests by default.

---

## Problem 9: Device code marked expired within seconds

**Symptom:** Codes generated by `-UseDeviceCode` were rejected as expired on the device login page even when entered within 30 seconds of generation. Happened three times in a row before it was diagnosed.

**Root Cause:** Multiple sequential `Connect-MgGraph` attempts had each generated their own codes. Browser tabs were holding stale codes from earlier attempts. Entering an earlier code into a later browser session produced an immediate "expired" rejection.

**Solution:** Closed all device login browser tabs, disconnected any partial session with `Disconnect-MgGraph`, ran a fresh Connect, and entered the new code immediately. Kept PowerShell focused during the browser flow so the session did not time out.

**Lesson Learned:** Device code authentication is single-use and short-lived. The combination of multiple in-flight codes and cached browser tabs creates failure modes that read as "expired" but are actually "wrong code for this session." Clean session state matters — treat each failed auth attempt as an opportunity to close every related browser tab before retrying.

---

## Problem 10: Bulk user creation rejected all UPNs

**Symptom:** `New-BulkUsers.ps1` returned `[Request_BadRequest]: The domain portion of the userPrincipalName property is invalid. You must use one of the verified domain names in your organization.` for all three test users in the input CSV.

**Root Cause:** The CSV used `@grantcreegan.dev` UPNs, but that custom domain was not verified in the Entra tenant. Graph enforces strict domain ownership for user creation — an unverified domain cannot be used in any UPN, even in test data.

**Solution:** Switched the CSV to use `@grantmcreeganoutlook.onmicrosoft.com`, which is the always-available default verified domain that ships with every Entra tenant.

**Lesson Learned:** Entra strictly enforces UPN domain ownership via DNS-verified domains. The `.onmicrosoft.com` domain is the always-available fallback when custom domain verification is incomplete or pending. In a production environment, completing domain verification via TXT or MX records is a Phase 1 prerequisite for any user-creation automation.

---

## Problem 11: Break-glass account appeared in stale account report

**Symptom:** The first version of `Get-StaleAccounts.ps1` correctly identified users with no sign-in activity as stale — but the break-glass account was in that list. An administrator following the report as a deactivation worklist could have deactivated the very account designed to be the recovery path for federation and Conditional Access outages.

**Root Cause:** Break-glass accounts are intentionally inactive. From a sign-in activity perspective they look identical to a truly stale account — never signed in — but the operational meaning is opposite. One should be removed; the other must be preserved.

**Solution:** Added an explicit `$excludeUPNs` allowlist near the top of the script. Excluded accounts are reported in their own bucket (not silently skipped) so a reviewer can see the exclusion logic was applied deliberately.

**Lesson Learned:** Identity automation has high blast radius. A script that "cleans up inactive accounts" must understand that some accounts are inactive *by design*. The correct pattern is explicit allowlisting of exceptions with the exclusions visible in output. Silent skipping is worse than no skipping because it hides the logic from auditors. This is the same design principle behind break-glass exclusions in Conditional Access — same accounts, same rationale, applied across two different control layers.

---

## Problem 12: Git commit failed with "unable to auto-detect email address"

**Symptom:** First attempt to `git commit` in the newly cloned repo failed with `fatal: unable to auto-detect email address (got 'grant@DESKTOP-65CFQRE.(none)')`. The commit was never created.

**Root Cause:** Git had never been configured with a global user identity on this workstation. Git requires an author name and email on every commit and refuses to auto-generate one from the hostname because the resulting metadata would be meaningless.

**Solution:** Set the identity globally:

```powershell
git config --global user.email "grantcreegan01@gmail.com"
git config --global user.name "Grant Creegan"
```

**Lesson Learned:** Git identity is one of the first-time-setup items that only bites when it bites. In corporate environments the identity is usually pre-configured by the IT department in a starter image. On a fresh personal workstation, running the `git config --global` commands before the first commit is a permanent fix — you never think about it again after that.

---

## What This Log Demonstrates

Reading through these entries, several patterns emerge that are worth noting explicitly.

**Vague errors almost always have specific root causes.** "Browser did something unexpected," "InteractiveBrowserCredential authentication failed," and "Something went wrong" are the surface-level messages. The real causes were audience URI templates, MSA guest routing, and stale browser sessions respectively. When an error is generic, the debugging discipline is to instrument the request and inspect the actual payload — the assertion body, the API response, the log entry — rather than trust the surface message.

**MSA guest admin patterns are consistently fragile.** Problems 2, 3 (partial), and 8 all trace back to Microsoft's identity flows not handling the MSA-guest-admin pattern well. In a production environment the equivalent workaround is to create a native admin account inside the tenant and use that for administrative work, keeping personal MSAs separate from tenant administration.

**Design decisions matter more than working code.** The break-glass exclusion in Problem 11 is not a bug fix — the script worked before the exclusion was added. It was a design decision that reflected an understanding of why break-glass accounts exist. That kind of thinking is what separates automation that is safe to run from automation that is one execution away from causing an incident.

**Documentation drift is a real category of problem.** Problem 6 exists because the lab guide predated Okta's shift from PAT-based to OAuth-based GitHub integration. In a real job, the same class of problem shows up constantly as vendor UIs change faster than internal runbooks are maintained. The habit of verifying documentation against current UI is worth building early.

---

*This log will continue to accumulate entries as the lab is extended. See the documentation in `/docs/` for context on what was built, and the main README for the overall project overview.*
