<#
.SYNOPSIS
    Bulk-creates Entra ID users from a CSV file.
.DESCRIPTION
    Reads new-users.csv and creates each user via Microsoft Graph.
    Each user is created with a temporary password and forced to change it at first sign-in.
.NOTES
    Requires: Connect-MgGraph with User.ReadWrite.All scope
    Author: Grant Creegan
#>

# Input file path - relative to script location
$csvPath = Join-Path $PSScriptRoot "new-users.csv"

# Verify input file exists
if (-not (Test-Path $csvPath)) {
    Write-Error "Input file not found: $csvPath"
    exit 1
}

# Import the CSV
$users = Import-Csv -Path $csvPath
Write-Host "Loaded $($users.Count) users from CSV" -ForegroundColor Cyan

# Track success/failure
$created = @()
$failed = @()

# Process each user
foreach ($user in $users) {
    Write-Host "Creating user: $($user.UserPrincipalName)..." -NoNewline

    # Build the password profile - random temporary password, must change on first login
    $passwordProfile = @{
        Password = "TempP@ssw0rd-$(Get-Random -Maximum 9999)"
        ForceChangePasswordNextSignIn = $true
    }

    try {
        $newUser = New-MgUser `
            -DisplayName $user.DisplayName `
            -UserPrincipalName $user.UserPrincipalName `
            -MailNickname $user.MailNickname `
            -Department $user.Department `
            -JobTitle $user.JobTitle `
            -AccountEnabled `
            -PasswordProfile $passwordProfile `
            -ErrorAction Stop

        Write-Host " SUCCESS" -ForegroundColor Green
        $created += [PSCustomObject]@{
            UPN = $user.UserPrincipalName
            DisplayName = $user.DisplayName
            TempPassword = $passwordProfile.Password
        }
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
        $failed += [PSCustomObject]@{
            UPN = $user.UserPrincipalName
            Error = $_.Exception.Message
        }
    }
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Created: $($created.Count)" -ForegroundColor Green
Write-Host "Failed: $($failed.Count)" -ForegroundColor Red

# Export results to a log file
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath | Out-Null }

if ($created.Count -gt 0) {
    $created | Export-Csv -Path "$logPath\created-users-$timestamp.csv" -NoTypeInformation
    Write-Host "Created users log: $logPath\created-users-$timestamp.csv" -ForegroundColor Cyan
}
if ($failed.Count -gt 0) {
    $failed | Export-Csv -Path "$logPath\failed-users-$timestamp.csv" -NoTypeInformation
    Write-Host "Failed users log: $logPath\failed-users-$timestamp.csv" -ForegroundColor Yellow
}