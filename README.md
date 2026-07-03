# IAM Home Lab

**Federation, provisioning, and identity governance across Okta, Microsoft Entra ID, and GitHub Enterprise Cloud — built end to end, documented in full.**

---

## Overview

This lab implements a working enterprise identity architecture and demonstrates the daily operational tasks of an IAM engineer: federation between identity providers, automated user lifecycle provisioning, conditional access policy design, and administrative automation via the Microsoft Graph API. Every component was built from scratch, every configuration decision is documented, and every real bug encountered during the build is logged in the [Problems and Solutions log](./PROBLEMS-AND-SOLUTIONS.md).

The purpose of this lab is not to reproduce a production identity system — that would take a team of engineers and a real budget. The purpose is to demonstrate hands-on understanding of the protocols, patterns, and design decisions that make up modern identity infrastructure: SAML federation, SCIM provisioning, Conditional Access, break-glass access, and Graph API automation.

---

## Architecture

```
                          ┌──────────────────────┐
                          │      Okta            │
                          │  (Workforce IdP,     │
                          │   source of truth)   │
                          └──────┬───────┬───────┘
                                 │       │
                    SAML 2.0     │       │  SCIM 2.0 (OAuth)
                                 ▼       ▼
                    ┌────────────────┐  ┌──────────────────────┐
                    │  Entra ID      │  │  GitHub Enterprise   │
                    │  (federated)   │  │  Cloud Organization  │
                    │                │  │  (SAML enforced)     │
                    │  + Conditional │  │                      │
                    │    Access      │  │  Users provisioned   │
                    │  + P2 features │  │  via SCIM lifecycle  │
                    └────────┬───────┘  └──────────────────────┘
                             │
                        Microsoft Graph API
                             │
                             ▼
                    ┌──────────────────────┐
                    │  PowerShell 7        │
                    │  Automation Scripts  │
                    │  (Joiner / Leaver /  │
                    │   Audit / Policy)    │
                    └──────────────────────┘
```

Okta acts as the workforce identity provider. Users authenticate to Entra ID via federated SAML 2.0. GitHub Enterprise Cloud enforces SAML SSO and consumes SCIM 2.0 provisioning from Okta over an OAuth-authorized channel. PowerShell scripts running against Microsoft Graph automate common lifecycle and audit operations against the Entra tenant.

---

## What Was Built

- **Federated identity** between Okta and Microsoft Entra ID via SAML 2.0, with successful sign-in traces logged in both directions
- **SCIM 2.0 provisioning** from Okta into GitHub Enterprise Cloud, with the full Joiner-Leaver lifecycle demonstrated end to end
- **Three Conditional Access policies** implementing MFA enforcement, legacy authentication blocking, and geographic report-only detection, with break-glass account exclusion
- **A dedicated break-glass account** with documented usage protocol and monitoring approach
- **Four PowerShell automation scripts** covering bulk user creation, stale account detection, access review export, and Conditional Access policy audit — all built against the Microsoft Graph SDK
- **A comprehensive Problems and Solutions log** documenting 12 real issues encountered during the build (SAML audience URI templating, MSA guest admin authentication patterns, SCIM enforcement dependencies, and more)

---

## Skills Demonstrated

- SAML 2.0 federation configuration and debugging
- SCIM 2.0 provisioning configuration with OAuth-authorized integrations
- Conditional Access policy design with break-glass discipline
- Microsoft Graph API scripting via PowerShell 7 and the Graph PowerShell SDK
- Identity lifecycle automation (Joiner-Mover-Leaver patterns)
- Access review and stale account audit workflows
- Real-world SAML debugging (byte-exact URL validation, audience mismatch resolution)
- Documentation practice for compliance-oriented environments (SOC 2, ISO 27001, HIPAA control language)
- Version control and portfolio presentation via Git and GitHub

---

## Tech Stack

- **Identity Providers:** Okta Workforce Identity, Microsoft Entra ID (with P2 features)
- **Service Providers:** Microsoft Entra ID (as federated SP), GitHub Enterprise Cloud
- **Protocols:** SAML 2.0, SCIM 2.0, OAuth 2.0
- **APIs:** Microsoft Graph
- **Automation:** PowerShell 7, Microsoft Graph PowerShell SDK v2
- **Version Control:** Git, GitHub

---

## Repository Structure

```
IAM-HomeLab/
├── README.md                            ← You are here
├── PROBLEMS-AND-SOLUTIONS.md            ← 12 documented real issues and resolutions
├── docs/
│   ├── security/
│   │   └── conditional-access-gap-analysis.md
│   ├── scim/
│   │   └── scim-provisioning.md
│   └── powershell/
│       └── powershell-automation.md
├── scripts/                             ← Four PowerShell automation scripts + sample CSV
│   ├── New-BulkUsers.ps1
│   ├── Get-StaleAccounts.ps1
│   ├── Export-AccessReview.ps1
│   ├── Get-CAPolicyAudit.ps1
│   └── new-users.csv
└── screenshots/                         ← Visual evidence organized by phase
    ├── phase-1-tenant-setup/
    ├── phase-2-users/
    ├── phase-3-federation/
    ├── phase-4-conditional-access/
    ├── phase-5-scim/
    └── phase-6-powershell/
```

---

## Key Documents

- **[Conditional Access Gap Analysis](./docs/security/conditional-access-gap-analysis.md)** — Threat coverage of the deployed CA policies, gaps against a mature Zero Trust posture, the report-only policy risk analysis, and the break-glass continuity design
- **[SCIM Provisioning Documentation](./docs/scim/scim-provisioning.md)** — Architecture of the Okta → GitHub SAML + SCIM integration, Joiner and Leaver demonstrations, attribute mapping approach, and real debugging encountered
- **[PowerShell Automation Documentation](./docs/powershell/powershell-automation.md)** — Purpose of each of the four scripts, the Graph SDK patterns used, and the design decisions that make the automation safe to run (including break-glass exclusion logic)
- **[Problems and Solutions Log](./PROBLEMS-AND-SOLUTIONS.md)** — Every real problem encountered during the build, with symptom, root cause, solution, and lesson learned

---

## What This Lab Does NOT Do

Being explicit about scope is more useful than pretending the lab is more than it is.

- **This is not a production identity system.** It runs on trial licenses across all three platforms and would expire without renewal. Screenshots and documentation are the durable artifacts.
- **This is not device compliance.** No Intune enrollment, no compliant device requirements in the CA policies. That is one of the largest gaps and is explicitly acknowledged in the gap analysis.
- **This is not risk-based Conditional Access.** Entra ID Protection signals are available (via P2) but no policy currently consumes them. Same for adaptive session controls.
- **This is not Privileged Identity Management.** Admin roles are permanent (always-active) rather than just-in-time via PIM. Another explicitly acknowledged gap.
- **This is not multi-app SCIM.** SCIM is demonstrated with GitHub as the target; extending it to Slack, Salesforce, or other apps follows the same pattern but was not built out.

---

## What I Would Build Next

A short list of the next-layer improvements, in the order I would implement them in a real environment:

1. **Intune device compliance and CA policies that require managed devices** — closes the largest gap in the current CA posture
2. **Risk-based Conditional Access** — consume the Identity Protection signals already available via P2
3. **Privileged Identity Management** — remove standing admin assignments, require just-in-time elevation with justification
4. **A second break-glass account** with credentials stored separately, to eliminate the single-credential dependency for tenant recovery
5. **Access reviews on a quarterly cadence**, exported via the `Export-AccessReview.ps1` script and distributed to designated reviewers
6. **Service principal authentication for the PowerShell scripts**, enabling unattended execution via Azure Automation or a similar runner
7. **A second SCIM target** to demonstrate the pattern generalizes beyond GitHub (Slack or Salesforce would be natural choices)

---

## About

Built by Grant Creegan as a demonstration portfolio for identity-focused IT roles. Background in M365 administration and web operations in a healthcare compliance environment. Currently pursuing the SC-300 Identity and Access Administrator certification.

Feedback and questions welcome via GitHub issues or direct contact.
