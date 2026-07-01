# SCIM Provisioning: Okta → GitHub Enterprise Cloud

**Environment:** IAM Home Lab — Okta + GitHub Enterprise Cloud Organization
**Author:** Grant Creegan
**Tenant:** trial-4487000.okta.com / GitHub Org `Grant-iam-lab`
**Date:** [insert date]

---

## 1. Purpose

This document describes the SCIM provisioning integration built between Okta and a GitHub Enterprise Cloud (GHEC) Organization. SCIM (System for Cross-domain Identity Management) is the protocol that automates the Joiner-Mover-Leaver (JML) lifecycle between identity systems. This is one of the most heavily weighted skills in IAM hiring — failure to deprovision leavers in a timely manner is consistently among the top findings in security audits.

This lab proves end-to-end automated provisioning and deprovisioning between a workforce IdP (Okta) and a downstream SaaS application (GitHub) with SAML SSO enforced.

## 2. Architecture

```
[Okta - source of truth for identity]
        │
        │  1. SAML 2.0 (authentication)
        │  2. SCIM 2.0 over REST (provisioning)
        ▼
[GitHub Enterprise Cloud Organization]
```

**Okta's role:** Authoritative identity source. Users are created, updated, and deactivated in Okta. Okta pushes lifecycle changes to GitHub via the SCIM API.

**GitHub's role:** Service provider. Trusts Okta-issued SAML assertions for sign-in. Accepts SCIM API calls authorized via OAuth to create invitations, update users, and revoke access.

**Two protocols, one app:** SAML handles *authentication* (the user proving who they are when signing in). SCIM handles *provisioning* (the lifecycle events that put the user in the app in the first place and remove them at the end). Both protocols point at the same GitHub Organization but serve different functions. Conflating them is a common interview red flag.

## 3. Configuration Summary

### SAML SSO
- **Identity Provider:** Okta (trial-4487000.okta.com)
- **Service Provider:** GitHub Org `Grant-iam-lab`
- **NameID format:** EmailAddress
- **SAML signature method:** RSA-SHA256
- **SAML SSO Enforcement:** Required for all Org members
- **PAT SSO Authorization:** Required for any token making API calls to the Org

### SCIM Provisioning
- **Authentication method:** OAuth 2.0 (via Okta-managed token, not a static PAT)
- **Supported lifecycle operations:**
  - Create Users — new Okta assignment triggers a GitHub Org invitation
  - Update User Attributes — Okta attribute changes propagate to GitHub
  - Deactivate Users — Okta deactivation or unassignment removes GitHub access

### Attribute Mapping
The Okta GitHub Enterprise Cloud — Organization app uses default attribute mappings: Okta `email` → GitHub `userName` and primary email. Default mappings cover 99% of real deployments; custom mappings come into play only when an organization uses non-standard identity attributes from an HRIS source.

## 4. The Joiner Process — Demonstrated

The Joiner flow proves automated onboarding works end to end.

**Trigger:** Assigning an Okta user to the GitHub Enterprise Cloud — Organization app in Okta.

**Observed result within ~30 seconds:**
1. Okta System Log records a `application.provision.user.lifecycle.create` event with Result: SUCCESS.
2. GitHub Org Pending Invitations page shows a new invitation for the user.
3. The user receives an email invitation to join the GitHub Org. On accepting, they are added as a member with the role assigned by the Okta mapping.

**Why this matters operationally:** Without SCIM, every new hire would require a manual step — someone in IT logs into GitHub, types in the new hire's email, picks their role, sends the invite. Multiply by every SaaS app the company uses, and onboarding becomes a multi-day ticket queue. SCIM collapses that to a single Okta assignment.

## 5. The Leaver Process — Demonstrated

The Leaver flow is the more security-relevant of the two and is what auditors care about.

**Trigger:** Deactivating the same Okta user (Directory → People → Deactivate).

**Observed result within ~30 seconds:**
1. Okta System Log records a `application.provision.user.lifecycle.deactivate` event with Result: SUCCESS.
2. The user is removed from the GitHub Org (or their pending invitation is canceled).

**Why this matters operationally:** Manual offboarding is unreliable. When an employee leaves, IT is supposed to revoke access in every SaaS app the same day. In practice this often takes days or weeks, and sometimes never happens at all. Former-employee accounts retaining access to source code repositories, customer data, or production systems is one of the most common causes of post-employment security incidents. SCIM-driven offboarding closes that gap by tying access revocation to a single source-of-truth event in the IdP.

## 6. Real Problems Encountered and Solved

The configuration was not trivial. Several real-world IAM debugging scenarios emerged during the build.

### Problem 1: SAML test failed with generic browser error despite Okta logging success

**Symptom:** GitHub returned "browser did something unexpected" on SAML test. Okta System Log showed the SAML assertion was issued successfully.

**Root Cause:** The Audience URI in Okta's SAML assertion was malformed — `https://github.com/orgs//organizations/Grant-iam-lab/` instead of `https://github.com/orgs/Grant-iam-lab`. The GitHub Organization Name field in the Okta app had been entered as `/organizations/Grant-iam-lab/` instead of just the org slug. Okta builds the Audience URI by plugging that field into a URL template, so the extra path segments and slashes broke the value.

**Solution:** Edited the Okta app's GitHub Organization Name field to the exact org slug with no slashes or path segments. Verified by checking the **View SAML setup instructions** page and confirming the new Audience URI matched GitHub's expected ACS URL.

**Lesson Learned:** When SAML fails with a vague service-provider error but the IdP logs show a successful assertion, the failure is almost always in SP-side validation: audience, destination, or recipient mismatch. The fix is always exact-string matching. SAML protocol validation is unforgiving — a single extra character breaks the handshake.

### Problem 2: Audience, Destination, and Recipient all mismatched by one trailing slash

**Symptom:** After fixing the Org Name field, the SAML test threw three errors simultaneously: invalid Destination, invalid Recipient, invalid Audience.

**Root Cause:** A single trailing slash on the Org Name field caused all three SAML URL fields to be off by one character from what GitHub expected.

**Solution:** Removed the trailing slash.

**Lesson Learned:** SAML URL comparisons are byte-exact. Tools that template URLs from user input are especially fragile to leading/trailing whitespace and slashes. In production, this is the kind of bug that only surfaces in test environments and is caught by the test step — which is exactly why "test before save" is a fundamental SAML deployment discipline.

### Problem 3: GitHub OAuth integration replaces the documented PAT flow

**Symptom:** Generated a classic Personal Access Token per the guide. Opened Okta's Provisioning tab. There was no field to paste the token.

**Root Cause:** The Okta GitHub Enterprise Cloud — Organization integration has migrated from static-PAT authentication to an OAuth-based flow. Clicking **Authenticate with GitHub Enterprise Cloud — Organization** triggers an OAuth handshake that Okta then uses for SCIM API calls. The PAT becomes unnecessary.

**Solution:** Used the OAuth flow. Revoked the unused classic PAT for hygiene.

**Lesson Learned:** Documentation drifts from current product state. Always cross-reference the actual UI against the doc you are following. Also: unused credentials with admin scopes should be revoked, not left dormant — even in a lab, this is the right habit to build.

### Problem 4: Personal GitHub email did not match Okta email for SAML test

**Symptom:** Early SAML test failed because the email in the personal GitHub account being used to test did not match the email Okta was sending as NameID.

**Root Cause:** GitHub SAML matches the IdP-issued NameID against verified emails on the personal GitHub account being authenticated. If no GitHub account has that email verified, SAML succeeds on the Okta side but GitHub cannot match the assertion to a user.

**Solution:** Added the Okta admin email as a verified secondary email on the personal GitHub account.

**Lesson Learned:** SCIM creates GitHub users; SAML does not. SAML alone requires the user to already exist on GitHub with a matching verified email. Understanding which protocol handles which lifecycle event is fundamental to debugging this kind of failure.

## 7. Gaps and Production Considerations

This lab demonstrates the SCIM lifecycle end to end but does not implement every control a production environment would require:

- **No group-based assignment.** Users are assigned to the GitHub app individually. In production, assignment would be driven by Okta group membership tied to HR system data (e.g., "all members of the Engineering group are assigned to the GitHub app").
- **No just-in-time role elevation.** All provisioned users land with a default Member role. Privileged GitHub roles (Owner, Billing Manager) are not granted dynamically based on identity attributes.
- **No SCIM event monitoring or alerting.** Failed provisioning events are visible in the Okta System Log but no alert fires. A production deployment would forward provisioning failures to a SIEM or notification channel.
- **Single source of truth.** Okta is treated as authoritative for identity, but no HRIS is upstream of it. A production environment typically has Workday or BambooHR as the upstream source, with Okta consuming HRIS changes and pushing them downstream to apps like GitHub.

## 8. Conclusion

This lab implements the foundational identity automation pattern: HRIS-style source of truth (Okta) → SCIM → downstream SaaS application (GitHub). The Joiner and Leaver flows were demonstrated end-to-end with screenshots captured for both Okta-side events and GitHub-side outcomes.

The most valuable output is not the working integration itself but the four documented problems and their solutions. SAML and SCIM debugging is real production IAM work; the ability to read an IdP log, identify whether a failure is on the IdP side or SP side, and locate the exact field driving the bug is the skill that separates an IAM engineer from someone who watched a setup video.

---

*This document is part of the IAM Home Lab portfolio. See the project README for full architecture and the Problems-and-Solutions log for additional issues encountered during build.*
