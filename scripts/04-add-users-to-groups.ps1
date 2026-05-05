# =============================================================================
# Script:      04-add-users-to-groups.ps1
# Purpose:     Apply the AGDLP model end-to-end:
#                Step 1 — Add users (A) to global groups (G) by department
#                Step 2 — Nest global groups (G) into domain local groups (DL)
# Idempotent:  Yes — Add-ADGroupMember errors on duplicate are caught.
# Author:      [Your name]
# Date:        April 2026
# =============================================================================

Import-Module ActiveDirectory

$DomainDN    = (Get-ADDomain).DistinguishedName
$UsersBaseDN = "OU=Users,OU=Nordwind,$DomainDN"

# -----------------------------------------------------------------------------
# Helper: idempotent group membership
# -----------------------------------------------------------------------------
function Add-MemberIfNotPresent {
    param(
        [string]$GroupName,
        [string]$MemberSam
    )
    $isMember = Get-ADGroupMember -Identity $GroupName -Recursive |
                Where-Object { $_.SamAccountName -eq $MemberSam }

    if ($isMember) {
        Write-Host "    [SKIP] '$MemberSam' already in '$GroupName'" -ForegroundColor Yellow
    }
    else {
        try {
            Add-ADGroupMember -Identity $GroupName -Members $MemberSam -ErrorAction Stop
            Write-Host "    [OK]   Added '$MemberSam' to '$GroupName'" -ForegroundColor Green
        }
        catch {
            Write-Host "    [ERROR] Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# -----------------------------------------------------------------------------
# STEP 1 — Add users to GLOBAL groups (the "A → G" in AGDLP)
# -----------------------------------------------------------------------------
Write-Host "`n=== STEP 1: Users -> Global groups (A -> G) ===" -ForegroundColor Cyan

$Departments = @("Management","IT","Accounting","Sales","Logistics","Warehouse","HR")

foreach ($dept in $Departments) {
    $deptOU = "OU=$dept,$UsersBaseDN"
    $globalGroup = "G_${dept}_Users"

    Write-Host "`n  Department: $dept -> $globalGroup" -ForegroundColor White

    $users = Get-ADUser -Filter * -SearchBase $deptOU -ErrorAction SilentlyContinue
    if (-not $users) {
        Write-Host "    [WARN] No users found in $deptOU" -ForegroundColor Yellow
        continue
    }

    foreach ($u in $users) {
        Add-MemberIfNotPresent -GroupName $globalGroup -MemberSam $u.SamAccountName
    }
}

# -----------------------------------------------------------------------------
# STEP 2 — Nest GLOBAL groups into DOMAIN LOCAL groups (the "G -> DL" in AGDLP)
# Mapping: which department gets access to which resource
# -----------------------------------------------------------------------------
Write-Host "`n=== STEP 2: Global -> Domain Local (G -> DL) ===" -ForegroundColor Cyan

$NestingMap = @(
    # Each department -> their own departmental file share
    @{ Global = "G_Sales_Users";      DomainLocal = "DL_FS01_Sales_Modify" }
    @{ Global = "G_Logistics_Users";  DomainLocal = "DL_FS01_Logistics_Modify" }
    @{ Global = "G_HR_Users";         DomainLocal = "DL_FS01_HR_Modify" }
    @{ Global = "G_Accounting_Users"; DomainLocal = "DL_FS01_Accounting_Modify" }
    @{ Global = "G_Management_Users"; DomainLocal = "DL_FS01_Management_Modify" }

    # IT department -> Full Control on IT share
    @{ Global = "G_IT_Users";         DomainLocal = "DL_FS01_IT_FullControl" }

    # All departments -> Read access to Public share
    @{ Global = "G_Management_Users"; DomainLocal = "DL_FS01_Public_Read" }
    @{ Global = "G_IT_Users";         DomainLocal = "DL_FS01_Public_Read" }
    @{ Global = "G_Accounting_Users"; DomainLocal = "DL_FS01_Public_Read" }
    @{ Global = "G_Sales_Users";      DomainLocal = "DL_FS01_Public_Read" }
    @{ Global = "G_Logistics_Users";  DomainLocal = "DL_FS01_Public_Read" }
    @{ Global = "G_Warehouse_Users";  DomainLocal = "DL_FS01_Public_Read" }
    @{ Global = "G_HR_Users";         DomainLocal = "DL_FS01_Public_Read" }
)

foreach ($map in $NestingMap) {
    $g  = $map.Global
    $dl = $map.DomainLocal

    Write-Host "`n  $g -> $dl" -ForegroundColor White

    # Check if already nested
    $globalGroupObj = Get-ADGroup -Identity $g -ErrorAction SilentlyContinue
    if (-not $globalGroupObj) {
        Write-Host "    [ERROR] Global group '$g' not found." -ForegroundColor Red
        continue
    }

    $isMember = Get-ADGroupMember -Identity $dl -ErrorAction SilentlyContinue |
                Where-Object { $_.SamAccountName -eq $globalGroupObj.SamAccountName }

    if ($isMember) {
        Write-Host "    [SKIP] '$g' already nested in '$dl'" -ForegroundColor Yellow
    }
    else {
        try {
            Add-ADGroupMember -Identity $dl -Members $g -ErrorAction Stop
            Write-Host "    [OK]   Nested '$g' into '$dl'" -ForegroundColor Green
        }
        catch {
            Write-Host "    [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------
Write-Host "`n=== VERIFICATION: Sample chain (jan.kowalski) ===" -ForegroundColor Cyan
$user = Get-ADUser -Identity "jan.kowalski" -Properties MemberOf -ErrorAction SilentlyContinue
if ($user) {
    Write-Host "User: $($user.Name)"
    Write-Host "Direct group memberships (should include G_Management_Users):"
    $user.MemberOf | ForEach-Object {
        $gName = (Get-ADGroup $_).Name
        Write-Host "  - $gName"
    }
    Write-Host "`nTransitive (effective) access — what 'jan.kowalski' can reach via nested groups:"
    Get-ADPrincipalGroupMembership -Identity "jan.kowalski" |
        Select-Object Name, GroupScope |
        Sort-Object GroupScope, Name |
        Format-Table -AutoSize
}

Write-Host "Done." -ForegroundColor Green
