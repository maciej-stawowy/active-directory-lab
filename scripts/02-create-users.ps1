# =============================================================================
# Script:      02-create-users.ps1
# Purpose:     Bulk-create Active Directory user accounts from a CSV file.
#              Each user is placed in the OU corresponding to their department.
# Input:       employees.csv (FirstName,LastName,Department,JobTitle,Office)
# Output:      Console log + lab_passwords.csv with initial passwords
# Idempotent:  Yes — existing users are skipped (not modified).
# Author:      Maciej Stawowy
# Date:        April 2026
# =============================================================================

Import-Module ActiveDirectory

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
$CsvPath        = "C:\LabFiles\employees.csv"
$PasswordCsv    = "C:\LabFiles\lab_passwords.csv"
$DomainSuffix   = "nordwind.local"
$DomainDN       = (Get-ADDomain).DistinguishedName
$UsersBaseDN    = "OU=Users,OU=Nordwind,$DomainDN"

# -----------------------------------------------------------------------------
# Helper: generate random initial password (12 chars, mixed)
# -----------------------------------------------------------------------------
function New-RandomPassword {
    $upper   = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lower   = "abcdefghjkmnpqrstuvwxyz"
    $digits  = "23456789"
    $special = "!@#$%^&*"
    $all     = $upper + $lower + $digits + $special

    # Ensure complexity — at least one of each category
    $pwd = -join @(
        ($upper.ToCharArray()   | Get-Random -Count 1)
        ($lower.ToCharArray()   | Get-Random -Count 1)
        ($digits.ToCharArray()  | Get-Random -Count 1)
        ($special.ToCharArray() | Get-Random -Count 1)
        (1..8 | ForEach-Object { $all.ToCharArray() | Get-Random -Count 1 })
    )
    # Shuffle the result
    -join ($pwd.ToCharArray() | Get-Random -Count $pwd.Length)
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
if (-not (Test-Path $CsvPath)) {
    Write-Host "ERROR: CSV file not found at $CsvPath" -ForegroundColor Red
    Write-Host "Place employees.csv in C:\LabFiles\ and run again." -ForegroundColor Yellow
    return
}

$employees = Import-Csv -Path $CsvPath
Write-Host "Loaded $($employees.Count) employees from CSV." -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# Main loop — create users
# -----------------------------------------------------------------------------
$results = @()

foreach ($emp in $employees) {
    $first   = $emp.FirstName
    $last    = $emp.LastName
    $dept    = $emp.Department
    $title   = $emp.JobTitle
    $office  = $emp.Office

    $sam     = "$first.$last".ToLower()
    $upn     = "$sam@$DomainSuffix"
    $display = "$last, $first"
    $deptOU  = "OU=$dept,$UsersBaseDN"

    Write-Host "`nProcessing: $display ($dept)" -ForegroundColor Cyan

    # Check if department OU exists
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$dept'" -SearchBase $UsersBaseDN -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
        Write-Host "  [ERROR] Department OU '$dept' does not exist. Skipping." -ForegroundColor Red
        continue
    }

    # Idempotency check — skip if user already exists
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Host "  [SKIP]  User '$sam' already exists." -ForegroundColor Yellow
        continue
    }

    # Generate initial password
    $plainPwd  = New-RandomPassword
    $securePwd = ConvertTo-SecureString $plainPwd -AsPlainText -Force

    # Create the user
    try {
        New-ADUser `
            -Name              $display `
            -GivenName         $first `
            -Surname           $last `
            -SamAccountName    $sam `
            -UserPrincipalName $upn `
            -DisplayName       $display `
            -Department        $dept `
            -Title             $title `
            -Office            $office `
            -Path              $deptOU `
            -AccountPassword   $securePwd `
            -ChangePasswordAtLogon $true `
            -Enabled           $true

        Write-Host "  [OK]    Created '$sam' (UPN: $upn)" -ForegroundColor Green

        # Save the initial password to results
        $results += [PSCustomObject]@{
            DisplayName = $display
            Username    = $sam
            UPN         = $upn
            Department  = $dept
            InitialPassword = $plainPwd
        }
    }
    catch {
        Write-Host "  [ERROR] Failed to create '$sam': $($_.Exception.Message)" -ForegroundColor Red
    }
}

# -----------------------------------------------------------------------------
# Save passwords to CSV (for the lab — DO NOT use in production!)
# -----------------------------------------------------------------------------
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $PasswordCsv -NoTypeInformation -Encoding UTF8
    Write-Host "`n[OK] Initial passwords saved to: $PasswordCsv" -ForegroundColor Green
    Write-Host "[!] WARNING: This file contains plaintext passwords." -ForegroundColor Yellow
    Write-Host "[!] In production, distribute via secure channel and delete." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
$totalUsers = (Get-ADUser -Filter * -SearchBase $UsersBaseDN).Count
Write-Host "Total users in OU=Users,OU=Nordwind: $totalUsers" -ForegroundColor White

Write-Host "`nDone." -ForegroundColor Green
