# =============================================================================
# Script:      01-create-ou-structure.ps1
# Purpose:     Create the Organizational Unit (OU) structure for nordwind.local
#              as defined in the project design document (section 6).
# Target:      DC01 (nordwind.local)
# Author:      Maciej Stawowy
# Date:        April 2026
# Idempotent:  Yes — safe to run multiple times.
# =============================================================================

# Import the Active Directory module (available on Domain Controllers by default)
Import-Module ActiveDirectory

# Define the domain DN (Distinguished Name)
$DomainDN = (Get-ADDomain).DistinguishedName
Write-Host "Working in domain: $DomainDN" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# Helper function: create OU only if it does not exist (idempotent)
# -----------------------------------------------------------------------------
function New-OUIfNotExists {
    param(
        [string]$Name,
        [string]$Path
    )
    $ouDN = "OU=$Name,$Path"
    if (Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue) {
        Write-Host "  [SKIP] OU '$Name' already exists in $Path" -ForegroundColor Yellow
    }
    else {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "  [OK]   OU '$Name' created in $Path" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# 1. Top-level OU (skip — created via GUI for the demonstration screenshot)
# -----------------------------------------------------------------------------
$NordwindDN = "OU=Nordwind,$DomainDN"
Write-Host "`n[1] Verifying top-level OU 'Nordwind' exists..." -ForegroundColor Cyan
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Nordwind'" -SearchBase $DomainDN -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name "Nordwind" -Path $DomainDN -ProtectedFromAccidentalDeletion $true
    Write-Host "  [OK] Top-level 'Nordwind' OU created" -ForegroundColor Green
} else {
    Write-Host "  [OK] Top-level 'Nordwind' OU already exists" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 2. Second-level OUs under Nordwind
# -----------------------------------------------------------------------------
Write-Host "`n[2] Creating second-level OUs..." -ForegroundColor Cyan
$SecondLevel = @("_Admins", "Users", "Computers", "Groups", "ServiceAccounts")
foreach ($ou in $SecondLevel) {
    New-OUIfNotExists -Name $ou -Path $NordwindDN
}

# -----------------------------------------------------------------------------
# 3. Department OUs under Users (one per company department)
# -----------------------------------------------------------------------------
Write-Host "`n[3] Creating department OUs under Users..." -ForegroundColor Cyan
$UsersDN = "OU=Users,$NordwindDN"
$Departments = @("Management", "IT", "Accounting", "Sales", "Logistics", "Warehouse", "HR")
foreach ($dept in $Departments) {
    New-OUIfNotExists -Name $dept -Path $UsersDN
}

# -----------------------------------------------------------------------------
# 4. Computer category OUs under Computers
# -----------------------------------------------------------------------------
Write-Host "`n[4] Creating computer category OUs..." -ForegroundColor Cyan
$ComputersDN = "OU=Computers,$NordwindDN"
$ComputerCategories = @("Workstations", "Servers")
foreach ($cat in $ComputerCategories) {
    New-OUIfNotExists -Name $cat -Path $ComputersDN
}

# -----------------------------------------------------------------------------
# 5. Group category OUs under Groups
# -----------------------------------------------------------------------------
Write-Host "`n[5] Creating group category OUs..." -ForegroundColor Cyan
$GroupsDN = "OU=Groups,$NordwindDN"
$GroupCategories = @("Security", "Distribution")
foreach ($cat in $GroupCategories) {
    New-OUIfNotExists -Name $cat -Path $GroupsDN
}

# -----------------------------------------------------------------------------
# 6. Verification — list final structure
# -----------------------------------------------------------------------------
Write-Host "`n[6] Final OU structure under Nordwind:" -ForegroundColor Cyan
Get-ADOrganizationalUnit -SearchBase $NordwindDN -Filter * |
    Select-Object Name, DistinguishedName |
    Sort-Object DistinguishedName |
    Format-Table -AutoSize

Write-Host "`nDone." -ForegroundColor Green
