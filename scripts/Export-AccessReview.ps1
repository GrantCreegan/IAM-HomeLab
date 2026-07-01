<#
.SYNOPSIS
    Exports a comprehensive access review snapshot of all Entra ID users.
.DESCRIPTION
    Generates a CSV report listing every user, their account state, group
    memberships, and directory role assignments. Used as input to quarterly
    access certification reviews (SOC 2, ISO 27001, HIPAA control).
.NOTES
    Requires: Connect-MgGraph with User.Read.All, Group.Read.All,
              Directory.Read.All, RoleManagement.Read.Directory scopes
    Author: Grant Creegan
#>

Write-Host "Building access review snapshot..." -ForegroundColor Cyan

# Get all users
$users = Get-MgUser -All -Property "Id,DisplayName,UserPrincipalName,AccountEnabled,Department,JobTitle,CreatedDateTime,UserType"
Write-Host "Loaded $($users.Count) users" -ForegroundColor Cyan

# Get all directory role assignments at once (more efficient than per-user lookup)
Write-Host "Loading directory role assignments..." -ForegroundColor Cyan
$roleAssignments = @{}
$roles = Get-MgDirectoryRole -All
foreach ($role in $roles) {
    $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All
    foreach ($member in $members) {
        if (-not $roleAssignments.ContainsKey($member.Id)) {
            $roleAssignments[$member.Id] = @()
        }
        $roleAssignments[$member.Id] += $role.DisplayName
    }
}
Write-Host "Loaded $($roles.Count) directory roles" -ForegroundColor Cyan

# Build the access review record for each user
$accessReview = @()
$counter = 0
foreach ($user in $users) {
    $counter++
    Write-Progress -Activity "Building access review" -Status "$($user.DisplayName)" -PercentComplete (($counter / $users.Count) * 100)

    # Get group memberships
    $groups = Get-MgUserMemberOf -UserId $user.Id -All | Where-Object { $_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.group" }
    $groupNames = ($groups | ForEach-Object { $_.AdditionalProperties.displayName }) -join "; "

    # Get role assignments from the lookup table
    $userRoles = if ($roleAssignments.ContainsKey($user.Id)) { $roleAssignments[$user.Id] -join "; " } else { "" }

    $accessReview += [PSCustomObject]@{
        DisplayName     = $user.DisplayName
        UPN             = $user.UserPrincipalName
        AccountEnabled  = $user.AccountEnabled
        UserType        = $user.UserType
        Department      = $user.Department
        JobTitle        = $user.JobTitle
        CreatedDate     = $user.CreatedDateTime
        GroupMemberships = $groupNames
        DirectoryRoles  = $userRoles
        HasAdminRole    = if ($userRoles) { $true } else { $false }
    }
}
Write-Progress -Activity "Building access review" -Completed

# Display summary
$adminCount = ($accessReview | Where-Object { $_.HasAdminRole }).Count
$enabledCount = ($accessReview | Where-Object { $_.AccountEnabled }).Count
$guestCount = ($accessReview | Where-Object { $_.UserType -eq "Guest" }).Count

Write-Host "`n=== Access Review Summary ===" -ForegroundColor Cyan
Write-Host "Total users:           $($users.Count)" -ForegroundColor White
Write-Host "Enabled accounts:      $enabledCount" -ForegroundColor Green
Write-Host "Disabled accounts:     $($users.Count - $enabledCount)" -ForegroundColor Yellow
Write-Host "Users with admin roles: $adminCount" -ForegroundColor Yellow
Write-Host "Guest users:           $guestCount" -ForegroundColor Yellow

# Display admin holders
if ($adminCount -gt 0) {
    Write-Host "`n=== Users With Directory Roles ===" -ForegroundColor Yellow
    $accessReview | Where-Object { $_.HasAdminRole } | Format-Table DisplayName, UPN, DirectoryRoles -AutoSize -Wrap
}

# Export the full review
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath | Out-Null }

$exportPath = "$logPath\access-review-$timestamp.csv"
$accessReview | Export-Csv -Path $exportPath -NoTypeInformation
Write-Host "`nAccess review exported: $exportPath" -ForegroundColor Cyan