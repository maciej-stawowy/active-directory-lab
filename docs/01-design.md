# Active Directory Lab — Design Document

**Project:** Nordwind Logistics — Active Directory Infrastructure  
**Author:** [Twoje imię i nazwisko]  
**Date:** April 2026  
**Version:** 1.0

---

## 1. Project Overview

This document describes the design of a Windows Server 2022 Active Directory environment for **Nordwind Logistics Sp. z o.o.**, a fictional Polish logistics company used as a sandbox for hands-on system administration practice.

The goal is to deploy a production-style infrastructure that mirrors the realities of a small-to-medium business (40 users), demonstrating planning, security awareness, and adherence to best practices — not just technical execution.

---

## 2. Company Profile (Fictional)

| Attribute       | Value                                                |
|-----------------|------------------------------------------------------|
| Company name    | Nordwind Logistics Sp. z o.o.                        |
| Industry        | Freight forwarding & logistics                       |
| Headquarters    | Poznań, Poland                                       |
| Branch office   | Warehouse near Wrocław                               |
| Employees       | ~40                                                  |
| Departments     | Management, IT, Accounting, Sales, Logistics, Warehouse, HR |

---

## 3. Active Directory Design

### 3.1 Domain Naming

- **Forest root domain:** `nordwind.local`
- **NetBIOS name:** `NORDWIND`

**Rationale:** The `.local` TLD is used because this is an internal, non-internet-routable domain for lab purposes. In a real production environment a publicly owned, registered domain would be used (e.g. `corp.nordwind-logistics.pl`) to avoid future conflicts with public DNS and to support modern services such as certificate issuance from public CAs.

### 3.2 Forest & Domain Functional Level

- **Forest functional level:** Windows Server 2016
- **Domain functional level:** Windows Server 2016

**Rationale:** Server 2016 functional level is the highest currently supported and unlocks features such as Privileged Access Management. It does not require all DCs to run a specific newer OS, which gives flexibility for future expansion.

---

## 4. Network Design

### 4.1 IP Addressing

| Item                 | Value                  |
|----------------------|------------------------|
| Subnet               | `192.168.10.0/24`      |
| Default gateway      | `192.168.10.1`         |
| DNS server (primary) | `192.168.10.10` (DC01) |

### 4.2 IP Allocation Plan

| Range                          | Purpose                          |
|--------------------------------|----------------------------------|
| `192.168.10.1`                 | Gateway (router / NAT)           |
| `192.168.10.10 – 192.168.10.19`| Domain Controllers               |
| `192.168.10.20 – 192.168.10.49`| Servers (file, print, app)       |
| `192.168.10.50 – 192.168.10.99`| Network devices, printers        |
| `192.168.10.100 – 192.168.10.200`| DHCP scope for clients         |
| `192.168.10.201 – 192.168.10.254`| Reserved                       |

**Rationale:** Splitting the subnet into ranges by role makes troubleshooting and firewall rules far easier. A /24 (254 hosts) is more than enough for 40 users plus servers and devices.

---

## 5. Server Naming Convention

Pattern: `[ROLE][NN]`

| Hostname | Role                       | IP              |
|----------|----------------------------|-----------------|
| `DC01`   | Primary Domain Controller  | `192.168.10.10` |
| `FS01`   | File Server (future)       | `192.168.10.20` |
| `CL01`   | Windows 10/11 client (lab) | DHCP            |

**Rationale:** Short, role-based names are easier to type and recognize in logs than descriptive ones. Numbering allows for clean horizontal scaling (`DC02`, `FS02`).

---

## 6. Organizational Unit (OU) Structure

```
nordwind.local
└── Nordwind
    ├── _Admins              (privileged accounts — separated from regular users)
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

**Rationale:**
- The top-level `Nordwind` OU separates company objects from default AD containers, which makes Group Policy targeting cleaner.
- `_Admins` is prefixed with an underscore to sort it to the top and visually flag it as sensitive.
- Department OUs under `Users` allow per-department GPOs (e.g. stricter password policy for HR).
- `ServiceAccounts` is separated because service accounts have different lifecycle and security requirements than user accounts.

---

## 7. User Account Naming Convention

- **Logon name (sAMAccountName):** `firstname.lastname` — e.g. `jan.kowalski`
- **UPN:** `jan.kowalski@nordwind.local`
- **Display name:** `Kowalski, Jan` (lastname-first for sorted address books)
- **Privileged accounts:** prefixed with `adm.` — e.g. `adm.jan.kowalski`

**Rationale:** Separating regular and admin accounts is a fundamental security control (tier model). An admin should sign in to their daily workstation with a regular account, and only elevate to `adm.*` when performing administrative tasks.

---

## 8. Security Group Strategy — AGDLP

The infrastructure follows Microsoft's recommended **AGDLP** model:

> **A**ccounts → **G**lobal groups → **D**omain **L**ocal groups → **P**ermissions

- Users are placed into Global groups by **role** (`G_Sales_Users`).
- Global groups are nested into Domain Local groups by **resource** (`DL_FileServer_Sales_RW`).
- Permissions on resources are granted only to Domain Local groups.

**Rationale:** This model scales cleanly. When a new sales hire arrives, IT only adds them to one global group and they inherit access to every relevant resource — no per-folder ACL editing.

---

## 9. Group Policy Plan (Phase 1)

| GPO Name                   | Linked to        | Purpose                                  |
|----------------------------|------------------|------------------------------------------|
| `GPO-Password-Policy`      | Domain root      | Min length 12, complexity, lockout       |
| `GPO-Workstation-Lockscreen` | Workstations OU | Auto-lock after 10 minutes idle         |
| `GPO-Map-Drives`           | Users OU         | Map departmental network drives          |
| `GPO-Disable-USB-Storage`  | Warehouse OU     | Block USB mass storage on shared PCs     |
| `GPO-Desktop-Wallpaper`    | Users OU         | Corporate wallpaper                      |

---

## 10. Lab Topology

```
┌─────────────────────────────────────────────────┐
│                VirtualBox Host                  │
│                                                 │
│   ┌─────────────────┐      ┌─────────────────┐  │
│   │      DC01       │      │      CL01       │  │
│   │  Windows Srv 22 │      │   Windows 10    │  │
│   │  192.168.10.10  │      │     DHCP        │  │
│   │   (AD DS, DNS,  │      │    (domain      │  │
│   │     DHCP)       │      │     member)     │  │
│   └─────────────────┘      └─────────────────┘  │
│            │                        │           │
│            └────────┬───────────────┘           │
│             Internal Network "NordwindLAN"      │
└─────────────────────────────────────────────────┘
```

---

## 11. Out of Scope (Phase 1)

The following are intentionally not included in this phase, but documented as a roadmap:

- Multi-site replication (second DC in the warehouse branch)
- Read-Only Domain Controller (RODC)
- Public Key Infrastructure (AD CS)
- Hybrid identity with Entra ID (Azure AD Connect)
- Backup & disaster recovery procedures

---

## 12. Success Criteria

The lab will be considered complete when:

1. ✅ `DC01` is operational with AD DS, DNS, and DHCP roles healthy.
2. ✅ The OU structure described in §6 is in place.
3. ✅ At least 10 user accounts and 5 security groups are created and follow the conventions in §7–§8.
4. ✅ `CL01` is successfully joined to `nordwind.local` and a domain user can log on.
5. ✅ At least three GPOs from §9 are linked, deployed, and verifiably working on `CL01`.
6. ✅ All steps are documented with screenshots in the project repository.

---

*End of design document.*
