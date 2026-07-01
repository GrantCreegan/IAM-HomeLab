# Conditional Access Gap Analysis

**Environment:** IAM Home Lab — Federated Okta + Microsoft Entra ID
**Author:** Grant Creegan
**Tenant:** grantmcreeganoutlook.onmicrosoft.com
**Date:** [insert date]

---

## 1. Purpose

This document analyzes the Conditional Access (CA) posture of the lab tenant after completing Phase 4 of the IAM home lab project. It identifies what the implemented policies protect against, what they do not cover, and what a more mature Zero Trust implementation would add. The intent is not to claim the lab is production-grade, but to demonstrate the thinking required to evaluate a real CA deployment.

## 2. Policies Implemented

| Policy ID | Name | State | Effect |
|---|---|---|---|
| CA001 | Require MFA All Users | On | Forces multifactor authentication on every sign-in for all users except break-glass |
| CA002 | Block Legacy Authentication | On | Blocks Exchange ActiveSync (legacy) and "Other clients" — anything using basic auth that cannot enforce MFA |
| CA003 | Block Non-US Access | Report-Only | Evaluates and logs any sign-in originating outside the United States, but does not enforce |

The break-glass account (`break.glass@grantmcreeganoutlook.onmicrosoft.com`) is excluded from all three policies. This is intentional — see Section 7.

## 3. Threats Currently Mitigated

Together, CA001 and CA002 close the most common identity attack vectors in a Microsoft cloud environment:

- **Credential stuffing and password spray** — even if an attacker obtains a valid username and password from a breach corpus, they cannot complete authentication without a second factor.
- **Phishing for credentials only** — an attacker who phishes a password but not an MFA token is blocked at the MFA challenge.
- **Legacy protocol abuse** — basic authentication over IMAP, POP, SMTP AUTH, and older Exchange ActiveSync clients cannot complete an MFA challenge. CA002 closes that bypass entirely.
- **Unauthenticated sign-in attempts to cloud apps** — CA001's scope is *All cloud apps*, so there is no app-level escape hatch.

This pair of policies is the baseline that every M365 tenant should have. It is not sophisticated, but it eliminates the threats that account for the majority of real-world cloud identity compromises.

## 4. Gaps — What These Policies Do NOT Cover

The implemented policies leave several meaningful gaps:

**Device posture.** Any device — managed, unmanaged, personal, or compromised — can authenticate as long as the user completes MFA. There is no requirement that the device be enrolled in Intune, compliant with a baseline, or even a known device. An attacker on an attacker-controlled machine with a phished MFA token has the same access as the legitimate user on their corporate laptop.

**Risk-based controls.** The tenant has Entra ID P2 (via trial), which means Identity Protection signals are available — but no policy currently consumes them. There is no enforcement on *user risk* (e.g., leaked credentials detected on the dark web) or *sign-in risk* (e.g., atypical travel, anonymous IP, unfamiliar sign-in properties). These are the policies that catch sophisticated attackers who already have credentials and MFA tokens.

**Session controls.** There is no sign-in frequency policy and no persistent-browser-session restriction. Once authenticated, a session can remain valid for the default lifetime (up to 90 days for some token types) without re-evaluation. Token theft attacks — increasingly common with adversary-in-the-middle phishing kits — bypass MFA entirely by stealing a post-authentication token.

**Privileged access.** Admin role assignments are permanent (always-active). There is no Privileged Identity Management (PIM) requirement to elevate just-in-time, no approval workflow for sensitive role activation, and no access review cadence on admin assignments. A compromised admin account is a compromised admin account 24/7.

**App-specific policies.** All cloud apps are treated identically. In a production environment, high-value apps (M365 admin portals, financial systems, HR data) typically warrant stricter controls — e.g., require compliant device, restrict to corporate network, or require phishing-resistant authenticators like FIDO2.

**Guest and external identities.** No specific policies target external users, B2B guests, or service principals. Guest access is often a soft target because guest accounts are easy to forget about during offboarding.

**Geographic restriction.** CA003 is in Report-Only mode, so non-US sign-ins are logged but not blocked. See Section 6.

## 5. What a Full Zero Trust Implementation Would Add

A mature Zero Trust posture treats every access request as untrusted and verifies it explicitly. Building on the current baseline, the next layers would be:

1. **Device compliance enforcement** — require Intune-managed and compliant devices to access corporate data. This single control closes the largest gap in Section 4.
2. **Risk-based Conditional Access** — block or require password reset on high user risk; require MFA or block on high sign-in risk. This consumes the P2 signals already available.
3. **Phishing-resistant MFA for privileged users** — require FIDO2 security keys or Windows Hello for Business on any account holding admin roles. SMS and voice call MFA are explicitly excluded.
4. **PIM for all directory roles** — no permanent admin assignments. Elevation requires justification, optional approval, and MFA at activation. Activation is time-bound.
5. **Session controls** — short sign-in frequency on high-risk apps, sign-in frequency on unmanaged devices, and continuous access evaluation (CAE) where supported.
6. **Application-tiered policies** — a separate policy set for tier-0 apps (admin portals, identity infrastructure) with stricter controls than general productivity apps.
7. **Access reviews** — quarterly reviews of group memberships, role assignments, and guest accounts. This addresses the identity sprawl that accumulates over time.
8. **Token protection** — token binding to a specific device where supported, reducing the value of stolen tokens.

This is a multi-quarter roadmap in a real organization, not a weekend project. The point of listing it is to show awareness of where the baseline ends and where mature identity security begins.

## 6. Report-Only Policy: Risk and Enforcement Path

**Why CA003 is Report-Only:** Setting a "block non-US sign-ins" policy to On in a lab carries a real lockout risk. A legitimate sign-in from a VPN exit node, mobile carrier IP that geolocates outside the US, or an in-progress trip would be blocked immediately. In a single-admin lab with no second pair of eyes, that is a self-inflicted incident.

**The risk of leaving it Report-Only:** A non-US sign-in is not actually blocked. If an attacker successfully phishes credentials and an MFA token from a non-US IP, CA003 will log the event but not stop the access. The control is detective, not preventive.

**The enforcement path in a real environment** would be:

1. Run in Report-Only mode for two to four weeks.
2. Review Sign-In Logs filtered by the CA003 policy to see what it *would* have blocked. Confirm no legitimate users are flagged.
3. Document any expected non-US access (travel, remote employees, contractors abroad) and either add them to the exclusion list or build a more granular policy.
4. Coordinate with leadership and the help desk so they know what is changing and when.
5. Flip to On during a planned change window with rollback documented.

The lab does not need this enforcement, but the gap analysis must acknowledge it.

## 7. Break-Glass Account: Continuity and Risk

The break-glass account is excluded from all three CA policies by design. This is not a security hole — it is a deliberate continuity control.

**Why it exists:** If the MFA service is unavailable (Okta outage, Entra MFA service degradation, expired certificate on the IdP, misconfigured CA policy that locks out all admins), there must be a path back into the tenant. Without a break-glass account, a single misconfigured CA policy can lock an organization out of its own directory with no recovery path short of opening a Microsoft support ticket.

**How it is protected even without CA enforcement:**

- The password is long, randomly generated, and stored offline in physical form (or a dedicated cold storage system in a real environment).
- The account is monitored. Sign-in logs are sent to Log Analytics, and any sign-in event from the break-glass account is treated as a high-severity incident requiring immediate review.
- It is never used for routine work. Any sign-in that is not a documented incident response activity is itself a security event.
- It holds Global Administrator but no other roles, and is not enrolled in any SaaS apps via SCIM. It exists only to restore directory access.

**The trade-off, stated plainly:** the break-glass account is a high-value target precisely because it bypasses CA. The mitigation is offline storage, strict monitoring, and operational discipline around usage. In production this would also be supplemented by a second break-glass account stored separately, to avoid single-point-of-failure on the credential itself.

## 8. Conclusion

The lab's current CA posture closes the most common identity attack vectors but is not a complete control set. The largest remaining gaps are device posture, risk-based enforcement, session controls, and privileged access management. CA003 in Report-Only mode is an intentional and reversible decision, not an oversight. The break-glass exclusion is a continuity control whose risk is mitigated by storage and monitoring rather than by additional CA policies.

The next phase of maturity for this environment would be enrolling devices in Intune, building risk-based policies that consume Identity Protection signals, and converting permanent admin role assignments to PIM-elevated just-in-time access.

---

*This document is part of the IAM Home Lab portfolio. See the project README for full architecture and the Problems-and-Solutions log for issues encountered during build.*
