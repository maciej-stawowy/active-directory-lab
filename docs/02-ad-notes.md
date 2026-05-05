# Active Directory — Master Notes

> **Project:** Nordwind Logistics — Active Directory Lab  
> **Author:** Maciej  
> **Last updated:** May 2026  
> **Purpose:** Knowledge base + interview cheat sheet for Junior SysAdmin / IT Support roles

---

## TL;DR — Top 5 things to remember by heart

If you remember nothing else from this document, remember these:

1. **AGDLP** — `Accounts → Global groups → Domain Local groups → Permissions`
2. **Tier model** — every admin has TWO accounts: regular and admin (`adm.*`)
3. **`.local`** is fine in lab, NOT in production — production uses subdomain of registered public domain
4. **DC must have static IP, never DHCP** — and DNS pointing to itself (`127.0.0.1`)
5. **NEVER edit Default Domain Policy** — create your own GPO and link it

---

## 1. Project philosophy — Design First

Every IT project starts with a design document, not with clicking.

- **Junior:** gets ticket "set up server" → starts clicking
- **Senior:** asks "how many users, what permissions, what backup?" → designs first → then clicks

The design document for this project lives in `docs/01-design.md`. The lab implements that design.

---

## 2. Domain naming

### Concepts

- **Domain** — logical name of Windows network (e.g., `nordwind.local`)
- **Forest** — top-level container in AD; can contain multiple domains
- **NetBIOS name** — short domain name, max 15 chars (`NORDWIND`)

### Naming rules

| Context | Use | Avoid |
|---------|-----|-------|
| Lab / sandbox | `nordwind.local` | — |
| Production | `corp.nordwind-logistics.pl` (subdomain of public domain) | `.local`, single-label names |

### Why NOT `.local` in production

- Conflict with mDNS (Apple Bonjour, printer auto-discovery)
- No public CA will issue certificates for `.local` (Let's Encrypt, DigiCert, etc.)
- Cannot be used for modern services (LDAPS with public certs, RDS Gateway, hybrid scenarios)

### Interview answer

> "Because it's a lab. In production I would use a subdomain of a registered public domain to avoid mDNS conflicts and to support certificates from public CAs."

---

## 3. Functional level

Functional Level determines which AD features are available; depends on the OS version of all DCs.

- Pick the highest level supported by all DCs in the forest/domain
- In Nordwind: Server 2016 functional level
- Higher level = more features, but cannot be lowered later (one-way switch)

---

## 4. Network and IP planning

### Subnet planning

- `/24` = `255.255.255.0` = 254 usable IPs
- Always plan IP ranges by role of device

### Nordwind IP allocation plan

| Range | Purpose |
|-------|---------|
| `192.168.10.1` | Gateway / router |
| `192.168.10.10–.19` | Domain Controllers |
| `192.168.10.20–.49` | Servers (file, print, app) |
| `192.168.10.50–.99` | Network devices, printers, workstations (static) |
| `192.168.10.100–.200` | DHCP scope for clients |
| `192.168.10.201–.254` | Reserved |

### Why split a /24 into ranges

1. Easier troubleshooting — `ping 192.168.10.10` and you know it's a DC
2. Easier firewall rules — "servers can talk to DC"
3. Static server IPs don't collide with DHCP clients

### Golden rule

Servers get static IPs outside the DHCP range. Clients get DHCP. Printers — DHCP reservation OR static.

---

## 5. Server naming convention

Pattern: `[ROLE][NN]` — short, role-based, numbered.

| Hostname | Role |
|----------|------|
| `DC01` | Primary Domain Controller |
| `DC02` | Second DC |
| `FS01` | File Server |
| `WEB01` | Web Server |
| `CL01` | Workstation #1 |

Never `boss-pc`, `JanuszPC`, `KOMP-MARYSI-2019`. Never.

---

## 6. Organizational Unit (OU) structure

### What is an OU

An OU is a "folder" inside AD for grouping objects (users, computers, groups).

### Why OUs exist

1. **Permission delegation** — e.g., helpdesk can reset passwords only in `Sales` OU
2. **Group Policy** — different GPOs for different OUs
3. **Visual organization** — without OUs, a 500-user domain is chaos

### Most important rule

An OU reflects management structure, not the company org chart 1:1. Key question: *"will these objects need the same policies/delegations?"* — if yes, one OU.

### Golden rule

Don't create an OU per department "just because". Create an OU only when you need a separate GPO or separate delegation.

### Nordwind OU structure

```
nordwind.local
└── Nordwind
    ├── _Admins              ← underscore sorts to top + flags as sensitive
    ├── Users
    │   ├── Management
    │   ├── IT
    │   ├── Accounting
    │   ├── Sales
    │   ├── Logistics
    │   ├── Warehouse
    │   └── HR
    ├── Computers
    │   ├── Workstations
    │   └── Servers
    ├── Groups
    │   ├── Security
    │   └── Distribution
    └── ServiceAccounts
```

### Default Users and Computers containers

The default Windows containers `CN=Users` and `CN=Computers` are NOT OUs — they are CN containers. You cannot link GPOs to them. That's why we created our own `OU=Users` and `OU=Computers` under Nordwind.

### Interview question

*"Why don't you put users in the default Users container?"*  
"Because it's a CN, not an OU — Group Policy cannot be linked to it. I create dedicated OUs."

---

## 7. User account naming + Tier Model

### Naming conventions

- Logon name (sAMAccountName): `firstname.lastname` — e.g. `jan.kowalski`
- UPN: `jan.kowalski@nordwind.local`
- Display name: `Lastname, Firstname` — for sorted address books
- Privileged accounts: prefix `adm.` — e.g. `adm.jan.kowalski`

### Tier model — KEY SECURITY CONCEPT

Every admin has TWO accounts:

- **Regular account** — `jan.kowalski` — for email, internet, daily work
- **Admin account** — `adm.jan.kowalski` — ONLY for administrative tasks

### Why?

- If admin clicks phishing on regular account, attacker does NOT get Domain Admin rights
- Admin account NEVER reads email or browses internet
- Admin account NEVER logs into a workstation, only directly into infrastructure
- Most pass-the-hash and Kerberoasting attacks rely on admins using admin accounts for daily work

### Interview answer

> "I follow the tier model — separate adm.* accounts that are never used for daily work. Admin accounts never log into workstations, only directly into infrastructure."

---

## 8. AGDLP — the holy grail of AD permissions

### What it stands for

**A**ccounts → **G**lobal groups → **D**omain **L**ocal groups → **P**ermissions

### How it works

| Step | Group type | Named after | Example |
|------|-----------|-------------|---------|
| A | account | the user | `marek.lewandowski` |
| G | global group | a role | `G_Sales_Users` |
| DL | domain local group | a resource | `DL_FS01_Sales_Modify` |
| P | permission | NTFS / share / app | "Modify" on `\\FS01\Sales` |

### The chain

A user is a member of a global group (their role). The global group is a member of a domain local group (the resource). The domain local group has the permission on the resource.

### Why AGDLP

**Junior:** assigns permission directly to a user on a folder.  
After 1 year with 500 users x 200 folders = chaos. No one knows who has access to what.

**Senior:** uses AGDLP.  
- New salesperson: one operation — add to `G_Sales_Users`. Auto-inherits access to all sales resources.  
- Employee leaves: remove from group. All access revoked everywhere.

### Real example from this lab

`marek.lewandowski` <-> `G_Sales_Users` <-> `DL_FS01_Sales_Modify` <-> Modify NTFS on `C:\Shares\Sales`

When Marek opens `\\DC01\Sales` from CL01, the chain is followed transparently. When `magdalena.kaminska` (HR) tries the same path, the chain breaks (she's not in `G_Sales_Users`) and access is denied.

### Interview answer

> "I follow the AGDLP model — accounts go into global groups by role, global groups nest into domain local groups by resource, and only domain local groups receive permissions. I never assign permissions directly to users."

If you remember only one thing from this entire document, let it be AGDLP.

---

## 9. Group scopes — Global vs Domain Local vs Universal

| Scope | Members from | Used in | Naming hint |
|-------|--------------|---------|-------------|
| Global | Same domain | Any trusting domain | "by role" — `G_Sales_Users` |
| Domain Local | Any trusted domain | Only same domain | "by resource" — `DL_FS01_Sales_Modify` |
| Universal | Any domain in forest | Any domain in forest | Cross-domain (advanced) |

### Interview answer

> "Global groups are scoped by role and contain users from the same domain. Domain local groups are scoped by resource and can contain global groups from any trusted domain. In AGDLP, global groups go INSIDE domain local groups, and only domain local groups get permissions."

---

## 10. Group Policy (GPO)

### What it is

GPO = a set of system settings centrally pushed from a DC to computers and users.

### What you can do with GPO

- Enforce password policies
- Map network drives
- Block USB storage
- Deploy wallpapers
- Install certificates
- Restrict Control Panel access
- Distribute logon scripts
- Enforce screen locks

### Where GPOs link

GPOs link to OUs. Rarely to the whole domain. Almost never to a "site".

### Computer Configuration vs User Configuration

A GPO has two halves:

- **Computer Configuration** — applies to the machine (e.g., password policy, USB block)
- **User Configuration** — applies to the logged-in user (e.g., desktop wallpaper, mapped drives)

`gpresult /r` shows what GPOs were applied:
- `gpresult /r /scope:user` — only User Configuration
- `gpresult /r /scope:computer` — only Computer Configuration (requires elevated CMD)

### CRITICAL senior rule

NEVER edit Default Domain Policy or Default Domain Controllers Policy. Create your own GPO and link it.

Reasons:
- Default policies sometimes reset on Windows updates
- The next admin doesn't know what you changed
- Cannot easily roll back

---

## 11. Default Password Policy

| Setting | Default | Recommended (production) |
|---------|---------|--------------------------|
| Min length | 7 chars | 12-14+ chars |
| Complexity | Enabled | Enabled |
| Max age | 42 days | Disabled if 14+ chars (NIST 2024+) |
| History | 24 passwords | 24 passwords |
| Lockout threshold | 0 (disabled!) | 5-10 attempts |
| Lockout duration | 30 min | 15-30 min |

### Complexity rule (often misunderstood)

Password must contain 3 of 4 categories:
- Uppercase letter (A-Z)
- Lowercase letter (a-z)
- Digit (0-9)
- Special character (`!@#$%^&*` etc.)

PLUS: must NOT contain the user's `sAMAccountName` or any 3+ character fragment of the display name.

### Real lab gotcha

Password `Marek2026` was rejected for `marek.lewandowski` because "Marek" is part of the user's name. Used `Wiosna2026!` instead.

---

## 12. Fine-Grained Password Policy (FGPP)

For when you need different password rules for different groups (e.g., stricter for Domain Admins).

- Configured in ADAC (Active Directory Administrative Center) under "Password Settings Container"
- Targets a security group (e.g., `Domain Admins`)
- Higher precedence wins on conflict

Mention FGPP in interviews if asked about advanced password policies.

---

## 13. SMB share + NTFS permissions — defense in depth

A file share has two access layers:

1. **SMB share permissions** = the door to the room (network access)
2. **NTFS permissions** = the lock inside the room (filesystem access)

### Effective permission rule

When a user accesses `\\DC01\Sales`, Windows takes the more restrictive of the two:

```
Effective = MIN(SMB_permission, NTFS_permission)
```

### Senior approach

- Set SMB share permissions broadly (e.g., Authenticated Users: Change)
- Set NTFS permissions strictly (e.g., DL_FS01_Sales_Modify: Modify)
- Rely on NTFS for the actual access control — it works even when accessed locally on the server

### Nordwind lab implementation

```
SMB share "Sales" on DC01:
  Domain Admins: Full
  DL_FS01_Sales_Modify: Change

NTFS on C:\Shares\Sales:
  SYSTEM: FullControl
  Administrators: FullControl
  DL_FS01_Sales_Modify: Modify
```

`BUILTIN\Users` was explicitly removed for zero-trust — only group members get access.

### Interview answer

> "The more restrictive of the two. Best practice is to keep share permissions permissive (Change for the right group) and enforce strict access through NTFS, because NTFS applies even when the file is accessed locally."

---

## 14. VirtualBox networking modes

| Mode | Internet | Sees other VMs | Sees host | Home LAN |
|------|---------|----------------|-----------|----------|
| NAT | YES | NO | NO | NO |
| Bridged | YES | YES | YES | YES |
| Internal | NO | YES | NO | NO (isolated) |
| Host-Only | NO | YES | YES | NO |

For an AD lab: Internal Network. Bridged would let DC01's "rogue DHCP" hand out IPs on the home network and break the roommate's Netflix.

---

## 15. DNS in AD

### Why DC must use itself as DNS

A Domain Controller is also a DNS server for its domain. The DC's primary DNS must point to `127.0.0.1` (loopback) — it asks itself about `nordwind.local`.

Asking an external DNS (like `8.8.8.8`) about an internal domain makes no sense.

### Why clients must use DC as DNS

Clients need to find the domain via SRV records like `_ldap._tcp.dc._msdcs.nordwind.local`. Only the DC's DNS knows these records. So `CL01`'s DNS must point to `192.168.10.10` (DC01).

### Interview answer

> "Active Directory uses DNS SRV records to locate domain controllers. Without correct DNS resolution, clients cannot find the domain — login, GPO, and Kerberos all fail. The first troubleshooting step for any 'AD doesn't work' issue is verifying DNS."

---

## 16. Out of Scope (intentional gaps)

These were intentionally NOT included in the lab to keep it focused:

- Multi-site replication (second DC in branch office)
- Read-Only Domain Controller (RODC)
- Public Key Infrastructure (AD CS)
- Hybrid identity with Entra ID (Azure AD Connect)
- Backup & disaster recovery (System State backup of DC)
- DHCP Server role (clients use static IPs in lab)
- Dedicated File Server (FS01) — share is on DC01 for lab simplicity

### Why list this in a portfolio

Showing what you consciously skipped is more impressive than listing what you did. It proves architectural awareness.

---

## 17. PowerShell cheat sheet for AD

### Domain & forest info

```powershell
Get-ADDomain
Get-ADForest
Get-ADDomainController
```

### User management

```powershell
# Create
New-ADUser -Name "Lastname, Firstname" -SamAccountName "user.name" `
    -UserPrincipalName "user.name@nordwind.local" `
    -Path "OU=Sales,OU=Users,OU=Nordwind,DC=nordwind,DC=local" `
    -AccountPassword (ConvertTo-SecureString "Pass123!" -AsPlainText -Force) `
    -Enabled $true

# Reset password
Set-ADAccountPassword -Identity "user.name" -Reset `
    -NewPassword (ConvertTo-SecureString "NewPass123!" -AsPlainText -Force)

# Force change at next logon, or disable that requirement
Set-ADUser -Identity "user.name" -ChangePasswordAtLogon $true
Set-ADUser -Identity "user.name" -ChangePasswordAtLogon $false

# Lookup
Get-ADUser -Identity "user.name" -Properties *
Get-ADUser -Filter "Department -eq 'Sales'" | Select Name, SamAccountName

# Group membership (transitive)
Get-ADPrincipalGroupMembership -Identity "user.name"
```

### Group management

```powershell
New-ADGroup -Name "G_Sales_Users" -GroupScope Global -GroupCategory Security `
    -Path "OU=Security,OU=Groups,OU=Nordwind,DC=nordwind,DC=local" `
    -Description "Sales department users"

Add-ADGroupMember -Identity "G_Sales_Users" -Members "marek.lewandowski"
Get-ADGroupMember -Identity "G_Sales_Users" -Recursive
```

### OU management

```powershell
New-ADOrganizationalUnit -Name "Sales" `
    -Path "OU=Users,OU=Nordwind,DC=nordwind,DC=local" `
    -ProtectedFromAccidentalDeletion $true

Get-ADOrganizationalUnit -Filter * -SearchBase "..." | Select Name, DistinguishedName
```

### Computer / domain join

```powershell
Rename-Computer -NewName "CL01" -Force -Restart
Add-Computer -DomainName "nordwind.local" -Credential (Get-Credential) -Restart -Force
```

### Network configuration

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.10.10 `
    -PrefixLength 24 -DefaultGateway 192.168.10.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1
```

### Health checks

```powershell
dcdiag /test:connectivity
dcdiag /test:dns
repadmin /showrepl
Get-Service ADWS, NTDS, DNS, KDC | Format-Table Name, Status
```

### File share

```powershell
New-SmbShare -Name "Sales" -Path "C:\Shares\Sales" -FullAccess "NORDWIND\Domain Admins"
Grant-SmbShareAccess -Name "Sales" -AccountName "NORDWIND\DL_FS01_Sales_Modify" `
    -AccessRight Change -Force
Get-SmbShareAccess -Name "Sales"
Get-Acl "C:\Shares\Sales" | Select -ExpandProperty Access
```

### Group Policy

```powershell
# CMD-side
gpupdate /force
gpresult /r
gpresult /r /scope:user
gpresult /r /scope:computer       # requires elevated
gpresult /h C:\report.html

# PowerShell-side
Get-GPO -All
Get-GPResultantSetOfPolicy -ReportType Html -Path C:\rsop.html
```

---

## 18. VirtualBox tips

### Keyboard

| Action | Key |
|--------|-----|
| Ctrl+Alt+Del in VM | Right Ctrl + Delete (or menu Machine -> Insert Ctrl-Alt-Del) |
| Release mouse from VM | Right Ctrl (host key) |
| Full screen toggle | Right Ctrl + F |

### Common issues

- **Test-Connection -Quiet returns "Generic failure"** in Internal Network — known PowerShell bug. Workaround: run `Add-Computer` directly without precheck.
- **Mouse "captured" in VM** — install Guest Additions (Devices -> Insert Guest Additions CD).
- **Resolution stuck at 1024x768** — Guest Additions not installed.
- **Clipboard not working** — Devices -> Shared Clipboard -> Bidirectional + restart VM.

---

## 19. AD troubleshooting checklist (OSI bottom-up)

1. **Layer 1-2:** Is the VM running? Is "Cable Connected" checked in VBox?
2. **Layer 3:** `ipconfig` — correct IP? Same subnet on both ends?
3. **Layer 3:** `ping <other-VM>` — can they reach each other?
4. **Layer 4:** `Test-NetConnection -Port 53` (DNS), `-Port 88` (Kerberos), `-Port 389` (LDAP)
5. **Layer 7 DNS:** `Resolve-DnsName nordwind.local` — does DNS resolve?
6. **Layer 7 auth:** `klist` — any Kerberos tickets? Time skew within 5 minutes?
7. **GPO:** `gpresult /r /scope:computer` (elevated) — is the policy actually applying?

### The senior mantra

"What changed?" — first question to ask whenever something stops working.

---

## 20. Lessons learned (real lab incidents)

### Incident 1: Lost local Administrator password

- **Cause:** Polish (214) keyboard layout selected during Server install. After install, layout reset, password un-typeable.
- **Fix:** Reinstalled Server with English (US) keyboard. Polish layout configured via Settings post-install.
- **Lesson:** Always use English (US) keyboard during Windows installation.

### Incident 2: PowerShell script failed with "missing terminator" error

- **Cause:** Script edited in Notepad on Polish Windows; smart quotes (`'`) replaced straight quotes (`'`).
- **Fix:** Recreated script content directly in PowerShell ISE.
- **Lesson:** Edit `.ps1` files in PowerShell ISE or VS Code. Avoid Notepad as a copy buffer.

### Incident 3: Test-Connection failed despite ping working

- **Cause:** `Test-Connection -Quiet` returns Generic failure in VirtualBox Internal Network.
- **Fix:** Bypassed the precheck and ran `Add-Computer` directly. Domain join succeeded.
- **Lesson:** Scripted automation is great, but know the underlying single-line commands.

### Incident 4: Password reset rejected by complexity rules

- **Cause:** Tried `Marek2026` for `marek.lewandowski`. AD rejects passwords containing the user's name.
- **Fix:** Used `Wiosna2026!`.
- **Lesson:** AD's complexity rule includes "must not contain account name fragments".

### Incident 5: gpresult returned "does not have RSOP data"

- **Cause:** `gpresult /r` was run as Administrator inspecting Marek's policy. Administrator never logged into CL01, so no user-scope RSoP data.
- **Fix:** Ran `gpresult /r /scope:computer` (elevated) — Computer Configuration policies appeared correctly.
- **Lesson:** Match the policy scope (`/scope:computer` vs `/scope:user`) to where the GPO settings live.

---

## 21. Interview cheat sheet — questions guaranteed to come up

| Question | Key answer |
|----------|-----------|
| How do you assign permissions in AD? | AGDLP |
| How do you secure admin accounts? | Tier model, separate `adm.*` accounts |
| Why not `.local` in production? | mDNS conflict, no public certificates |
| Difference: global vs domain local groups? | Global = by role; Domain Local = by resource |
| Why are OUs important? | GPO + delegation |
| What is forest functional level? | Determines available features; pick highest supported |
| Why DC's DNS = 127.0.0.1? | DC hosts the zone for its own domain |
| Where do you set password policy? | A dedicated GPO linked to domain root, never editing Default Domain Policy |
| Share vs NTFS — which wins? | The more restrictive of the two |
| First step when AD breaks? | Check DNS resolution |
| What's `gpresult /r /scope:computer`? | Show only Computer Config GPOs; requires elevation |
| What is RSoP? | Resultant Set of Policy — what GPOs effectively apply |
| Default password complexity? | Min 7 chars + 3 of 4 categories + no user name fragments |
| Default lockout threshold? | 0 (disabled!) — must be set explicitly |

---

## 22. Self-test — answer these without looking

1. Forest, domain, NetBIOS — what's each?
2. Why don't we use `.local` in production?
3. Why split a `/24` subnet into ranges?
4. What's the rule for server hostnames?
5. Why do OUs exist?
6. What's the tier model and why?
7. Explain AGDLP with an example.
8. What's a GPO and where does it link?
9. Why Internal Network instead of Bridged in VirtualBox?
10. What does "Out of Scope" in a design doc mean?
11. Default password policy — three rules?
12. Why does DC have DNS = 127.0.0.1?
13. SMB share permission vs NTFS — which wins?
14. What do `gpresult /r /scope:user` and `/scope:computer` show?
15. What's the AD troubleshooting first step?

If you answer 12+ from memory — you're ready for the interview.

---

*End of master notes.*
