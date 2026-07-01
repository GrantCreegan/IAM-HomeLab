<#
.SYNOPSIS
    Identifies stale Entra ID user accounts based on sign-in activity.
.DESCRIPTION
    Reports all users whose last interactive sign-in was more than N days ago
    (default 90). Users who have never signed in are also flagged.
    Excludes designated break-glass / emergency access accounts from stale reporting,
    since those accounts are expected to remain unused except during incidents.
.NOTES
    Requires: Connect-MgGraph with User.Read.All and AuditLog.Read.All scopes
    Note: Sign-in activity requires Entra ID P1 or P2 license
    Author: Grant Creegan
#>

param(
    [int]$StaleDays = 90
)

# -----------------------------------------------------------------------------
# Excluded accounts - break-glass / emergency access UPNs are expected to be
# inactive under normal operations. Flagging them as stale would risk an admin
# deactivating them, eliminating the recovery path for CA / IdP outages.
# This is a deliberate exception, documented in the break-glass procedure.
# -----------------------------------------------------------------------------
$excludeUPNs = @(
    "Breakglass@grantmcreeganoutlook.onmicrosoft.com"
)

Write-Host "Querying users and sign-in activity..." -ForegroundColor Cyan
Write-Host "Stale threshold: $StaleDays days" -ForegroundColor Cyan
Write-Host "Excluded UPNs:   $($excludeUPNs.Count)`n" -ForegroundColor Cyan

# Get all users with sign-in activity property
$users = Get-MgUser -All -Property "Id,DisplayName,UserPrincipalName,AccountEnabled,CreatedDateTime,SignInActivity"

$cutoff = (Get-Date).AddDays(-$StaleDays)
$stale = @()
$neverSignedIn = @()
$active = @()
$excluded = @()

foreach ($user in $users) {
    # Skip excluded accounts entirely
    if ($user.UserPrincipalName -in $excludeUPNs) {
        $excluded += [PSCustomObject]@{
            DisplayName = $user.DisplayName
            UPN = $user.UserPrincipalName
            Reason = "Break-glass / emergency access"
        }
        continue
    }

    $lastSignIn = $user.SignInActivity.LastSignInDateTime

    if ($null -eq $lastSignIn) {
        $neverSignedIn += [PSCustomObject]@{
            DisplayName = $user.DisplayName
            UPN = $user.UserPrincipalName
            AccountEnabled = $user.AccountEnabled
            CreatedDate = $user.CreatedDateTime
            LastSignIn = "Never"
            DaysSince = "N/A"
        }
    }
    elseif ($lastSignIn -lt $cutoff) {
        $daysSince = [math]::Round(((Get-Date) - $lastSignIn).TotalDays)
        $stale += [PSCustomObject]@{
            DisplayName = $user.DisplayName
            UPN = $user.UserPrincipalName
            AccountEnabled = $user.AccountEnabled
            CreatedDate = $user.CreatedDateTime
            LastSignIn = $lastSignIn
            DaysSince = $daysSince
        }
    }
    else {
        $active += $user
    }
}

# Display summary
Write-Host "=== Account Activity Summary ===" -ForegroundColor Cyan
Write-Host "Total users:        $($users.Count)" -ForegroundColor White
Write-Host "Active:             $($active.Count)" -ForegroundColor Green
Write-Host "Stale (>$StaleDays days):  $($stale.Count)" -ForegroundColor Yellow
Write-Host "Never signed in:    $($neverSignedIn.Count)" -ForegroundColor Yellow
Write-Host "Excluded (BG):      $($excluded.Count)" -ForegroundColor Gray
Write-Host ""

if ($excluded.Count -gt 0) {
    Write-Host "=== Excluded Accounts (not evaluated) ===" -ForegroundColor Gray
    $excluded | Format-Table DisplayName, UPN, Reason -AutoSize
}

if ($stale.Count -gt 0) {
    Write-Host "=== Stale Accounts (>$StaleDays days) ===" -ForegroundColor Yellow
    $stale | Format-Table DisplayName, UPN, LastSignIn, DaysSince, AccountEnabled -AutoSize
}

if ($neverSignedIn.Count -gt 0) {
    Write-Host "=== Users Who Have Never Signed In ===" -ForegroundColor Yellow
    $neverSignedIn | Format-Table DisplayName, UPN, CreatedDate, AccountEnabled -AutoSize
}

# Export reports
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath | Out-Null }

if ($stale.Count -gt 0) {
    $stale | Export-Csv -Path "$logPath\stale-accounts-$timestamp.csv" -NoTypeInformation
    Write-Host "Stale accounts report:    $logPath\stale-accounts-$timestamp.csv" -ForegroundColor Cyan
}
if ($neverSignedIn.Count -gt 0) {
    $neverSignedIn | Export-Csv -Path "$logPath\never-signed-in-$timestamp.csv" -NoTypeInformation
    Write-Host "Never signed in report:   $logPath\never-signed-in-$timestamp.csv" -ForegroundColor Cyan
}