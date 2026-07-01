<#
.SYNOPSIS
    Audits all Conditional Access policies in the Entra tenant.
.DESCRIPTION
    Exports a summary of every CA policy: name, state, included/excluded users,
    targeted apps, conditions (locations, client apps, platforms), and grant controls.
    Used for compliance reviews and change tracking of the identity perimeter.
.NOTES
    Requires: Connect-MgGraph with Policy.Read.All scope
    Requires: Entra ID P1 or P2 license for CA policies to exist
    Author: Grant Creegan
#>

Write-Host "Auditing Conditional Access policies..." -ForegroundColor Cyan

# Get all CA policies
$policies = Get-MgIdentityConditionalAccessPolicy -All
Write-Host "Loaded $($policies.Count) policies`n" -ForegroundColor Cyan

if ($policies.Count -eq 0) {
    Write-Host "No Conditional Access policies found in this tenant." -ForegroundColor Yellow
    exit 0
}

$audit = @()

foreach ($policy in $policies) {
    # Resolve included users (could be "All", specific GUIDs, or roles)
    $includeUsers = if ($policy.Conditions.Users.IncludeUsers) { $policy.Conditions.Users.IncludeUsers -join "; " } else { "" }
    $excludeUsers = if ($policy.Conditions.Users.ExcludeUsers) { $policy.Conditions.Users.ExcludeUsers -join "; " } else { "" }
    $includeGroups = if ($policy.Conditions.Users.IncludeGroups) { $policy.Conditions.Users.IncludeGroups -join "; " } else { "" }
    $excludeGroups = if ($policy.Conditions.Users.ExcludeGroups) { $policy.Conditions.Users.ExcludeGroups -join "; " } else { "" }

    # Target apps
    $includeApps = if ($policy.Conditions.Applications.IncludeApplications) { $policy.Conditions.Applications.IncludeApplications -join "; " } else { "" }
    $excludeApps = if ($policy.Conditions.Applications.ExcludeApplications) { $policy.Conditions.Applications.ExcludeApplications -join "; " } else { "" }

    # Conditions
    $clientApps = if ($policy.Conditions.ClientAppTypes) { $policy.Conditions.ClientAppTypes -join "; " } else { "" }
    $platforms = if ($policy.Conditions.Platforms.IncludePlatforms) { $policy.Conditions.Platforms.IncludePlatforms -join "; " } else { "" }
    $locationsInclude = if ($policy.Conditions.Locations.IncludeLocations) { $policy.Conditions.Locations.IncludeLocations -join "; " } else { "" }
    $locationsExclude = if ($policy.Conditions.Locations.ExcludeLocations) { $policy.Conditions.Locations.ExcludeLocations -join "; " } else { "" }

    # Grant controls
    $grantOperator = $policy.GrantControls.Operator
    $builtInControls = if ($policy.GrantControls.BuiltInControls) { $policy.GrantControls.BuiltInControls -join "; " } else { "" }

    $audit += [PSCustomObject]@{
        Name              = $policy.DisplayName
        State             = $policy.State
        CreatedDate       = $policy.CreatedDateTime
        ModifiedDate      = $policy.ModifiedDateTime
        IncludeUsers      = $includeUsers
        ExcludeUsers      = $excludeUsers
        IncludeGroups     = $includeGroups
        ExcludeGroups     = $excludeGroups
        IncludeApps       = $includeApps
        ExcludeApps       = $excludeApps
        ClientAppTypes    = $clientApps
        Platforms         = $platforms
        LocationsInclude  = $locationsInclude
        LocationsExclude  = $locationsExclude
        GrantOperator     = $grantOperator
        GrantControls     = $builtInControls
    }
}

# Summary by state
$enabled = ($audit | Where-Object { $_.State -eq "enabled" }).Count
$disabled = ($audit | Where-Object { $_.State -eq "disabled" }).Count
$reportOnly = ($audit | Where-Object { $_.State -eq "enabledForReportingButNotEnforced" }).Count

Write-Host "=== Policy State Summary ===" -ForegroundColor Cyan
Write-Host "On (enforced):  $enabled" -ForegroundColor Green
Write-Host "Report-only:    $reportOnly" -ForegroundColor Yellow
Write-Host "Off:            $disabled" -ForegroundColor Gray
Write-Host ""

# Display compact table
Write-Host "=== Conditional Access Policies ===" -ForegroundColor Cyan
$audit | Format-Table Name, State, GrantControls -AutoSize -Wrap

# Export full audit
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath | Out-Null }

$exportPath = "$logPath\ca-policy-audit-$timestamp.csv"
$audit | Export-Csv -Path $exportPath -NoTypeInformation
Write-Host "Full audit exported: $exportPath" -ForegroundColor Cyan