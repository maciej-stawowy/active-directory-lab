# =============================================================================
# Script:      05-cl01-prepare-and-join.ps1
# Purpose:     Prepare CL01 (Windows 10/11 client) and join it to nordwind.local
#              - Set static IP + DNS pointing to DC01
#              - Rename computer to CL01
#              - Test connectivity to DC
#              - Join domain
#              - Schedule reboot
# Run as:      Local Administrator on CL01
# Author:      Maciej Stawowy
# Date:        April 2026
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
$NewHostname    = "CL01"
$ClientIP       = "192.168.10.50"
$PrefixLength   = 24
$Gateway        = "192.168.10.1"
$DNS_Primary    = "192.168.10.10"   # DC01
$DomainName     = "nordwind.local"
$DomainAdmin    = "NORDWIND\Administrator"

# -----------------------------------------------------------------------------
# Step 1 - Show current state
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=== CURRENT STATE ===" -ForegroundColor Cyan
Write-Host "Hostname:     $(hostname)"
Write-Host "Domain/Group: $((Get-CimInstance Win32_ComputerSystem).Domain)"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" } |
    Select-Object InterfaceAlias, IPAddress, PrefixLength | Format-Table -AutoSize

# -----------------------------------------------------------------------------
# Step 2 - Set static IP and DNS
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=== STEP 1: Setting static IP and DNS ===" -ForegroundColor Cyan

$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if (-not $adapter) {
    Write-Host "[ERROR] No active network adapter found." -ForegroundColor Red
    return
}
Write-Host "Active adapter: $($adapter.Name)"

# Remove existing IPs (idempotency)
Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.PrefixOrigin -ne "WellKnown" } |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } |
    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

# Set new IP
New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
                 -IPAddress $ClientIP `
                 -PrefixLength $PrefixLength `
                 -DefaultGateway $Gateway -ErrorAction Stop | Out-Null

Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DNS_Primary

Write-Host "[OK] IP set to $ClientIP / DNS set to $DNS_Primary" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Step 3 - Connectivity test
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=== STEP 2: Connectivity test to DC01 ===" -ForegroundColor Cyan
$ping = Test-Connection -ComputerName $DNS_Primary -Count 2 -Quiet
if ($ping) {
    Write-Host "[OK] DC01 reachable at $DNS_Primary" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Cannot reach DC01 at $DNS_Primary" -ForegroundColor Red
    Write-Host "Check that DC01 is running and Internal Network is set to NordwindLAN." -ForegroundColor Yellow
    return
}

# DNS test
Write-Host "Resolving $DomainName ..."
try {
    $dnsResult = Resolve-DnsName -Name $DomainName -ErrorAction Stop
    Write-Host "[OK] DNS resolves $DomainName" -ForegroundColor Green
    $dnsResult | Select-Object Name, IPAddress | Format-Table -AutoSize
} catch {
    Write-Host "[ERROR] DNS resolution failed for $DomainName" -ForegroundColor Red
    Write-Host "Check DNS server on DC01." -ForegroundColor Yellow
    return
}

# -----------------------------------------------------------------------------
# Step 4 - Rename computer
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=== STEP 3: Rename computer to $NewHostname ===" -ForegroundColor Cyan

if ((hostname) -eq $NewHostname) {
    Write-Host "[SKIP] Hostname is already $NewHostname" -ForegroundColor Yellow
} else {
    Rename-Computer -NewName $NewHostname -Force -ErrorAction Stop
    Write-Host "[OK] Computer renamed. Will take effect after reboot." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# Step 5 - Domain join
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=== STEP 4: Joining domain $DomainName ===" -ForegroundColor Cyan
Write-Host "You will be prompted for domain admin credentials..." -ForegroundColor Yellow

$cred = Get-Credential -UserName $DomainAdmin -Message "Enter password for $DomainAdmin"

try {
    Add-Computer -DomainName $DomainName -Credential $cred -Force -ErrorAction Stop
    Write-Host "[OK] Joined domain $DomainName" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Domain join failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# -----------------------------------------------------------------------------
# Step 6 - Reboot prompt
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=== ALL STEPS COMPLETED ===" -ForegroundColor Green
Write-Host ""
Write-Host "Reboot is required to apply hostname change and complete domain join." -ForegroundColor Yellow
Write-Host "After reboot, log in as: NORDWIND\<username> (e.g., NORDWIND\marek.lewandowski)" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Reboot now? (Y/N)"
if ($confirm -eq "Y" -or $confirm -eq "y") {
    Write-Host "Restarting in 5 seconds..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    Restart-Computer -Force
} else {
    Write-Host "Remember to reboot manually with: Restart-Computer -Force" -ForegroundColor Yellow
}
