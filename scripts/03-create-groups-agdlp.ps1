# =============================================================================
# Script:      03-create-groups-agdlp.ps1
# Purpose:     Create security groups following the AGDLP model:
#                - Global groups (G_*)         — by ROLE   (e.g. department)
#                - Domain Local groups (DL_*)  — by RESOURCE (e.g. file share)
# Output:      Groups in OU=Security,OU=Groups,OU=Nordwind
# Idempotent:  Yes.
# Author:      [Your name]
# Date:        April 2026
# =============================================================================

Import-Module ActiveDirectory

$DomainDN     = (Get-ADDomain).DistinguishedName
$SecurityOU   = "OU=Security,OU=Groups,OU=Nordwind,$DomainDN"

# -----------------------------------------------------------------------------
# Helper: idempotent group creation
# -----------------------------------------------------------------------------
function New-ADGroupIfNotExists {
    param(
        [string]$Name,
        [ValidateSet("Global","DomainLocal","Universal")]
        [string]$Scope,
        [string]$Path,
        [string]$Description
    )
    if (Get-ADGroup -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue) {
        Write-Host "  [SKIP] Group '$Name' already exists." -ForegroundColor Yellow
    }
    else {
        New-ADGroup -Name $Name -GroupScope $Scope -GroupCategory Security -Path $Path -Description $Description
        Write-Host "  [OK]   Group '$Name' ($Scope) created." -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# 1. GLOBAL GROUPS — by role / department (the "G" in AGDLP)
# -----------------------------------------------------------------------------
Write-Host "`n[1] Creating GLOBAL groups (by role)..." -ForegroundColor Cyan
$Departments = @("Management","IT","Accounting","Sales","Logistics","Warehouse","HR")
foreach ($dept in $Departments) {
    $name = "G_${dept}_Users"
    $desc = "All users from $dept department (role-based global group)"
    New-ADGroupIfNotExists -Name $name -Scope Global -Path $SecurityOU -Description $desc
}

# -----------------------------------------------------------------------------
# 2. DOMAIN LOCAL GROUPS — by resource (the "DL" in AGDLP)
#    Naming: DL_<Resource>_<Permission>
#    Even though we don't have a real file server yet, we create the groups
#    to demonstrate the model. They will hold permissions on \\FS01\<Share>.
# -----------------------------------------------------------------------------
Write-Host "`n[2] Creating DOMAIN LOCAL groups (by resource)..." -ForegroundColor Cyan

$DomainLocalGroups = @(
    # Department file shares — Modify access
    @{ Name = "DL_FS01_Sales_Modify";      Desc = "Modify access to \\FS01\Sales (department share)" }
    @{ Name = "DL_FS01_Logistics_Modify";  Desc = "Modify access to \\FS01\Logistics (department share)" }
    @{ Name = "DL_FS01_HR_Modify";         Desc = "Modify access to \\FS01\HR (department share)" }
    @{ Name = "DL_FS01_Accounting_Modify"; Desc = "Modify access to \\FS01\Accounting (department share)" }
    @{ Name = "DL_FS01_Management_Modify"; Desc = "Modify access to \\FS01\Management (department share)" }

    # Cross-department read access (e.g., everyone can read company-wide announcements)
    @{ Name = "DL_FS01_Public_Read";       Desc = "Read access to \\FS01\Public (all employees)" }

    # IT-specific resource access
    @{ Name = "DL_FS01_IT_FullControl";    Desc = "Full Control on \\FS01\IT (IT department resources)" }
)

foreach ($g in $DomainLocalGroups) {
    New-ADGroupIfNotExists -Name $g.Name -Scope DomainLocal -Path $SecurityOU -Description $g.Desc
}

# -----------------------------------------------------------------------------
# 3. Verification
# -----------------------------------------------------------------------------
Write-Host "`n[3] Final group inventory in OU=Security,OU=Groups,OU=Nordwind:" -ForegroundColor Cyan
Get-ADGroup -Filter * -SearchBase $SecurityOU |
    Select-Object Name, GroupScope, GroupCategory |
    Sort-Object GroupScope, Name |
    Format-Table -AutoSize

Write-Host "Done." -ForegroundColor Green
