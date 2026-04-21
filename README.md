# ZSD_SO_BACKLOG — SAP Sales Order Backlog & Delivery Monitor

> **Student:** Reva Sahu | **Roll No.:** 23053292 | **B.Tech 2023–2027**  
> **Module:** SAP SD — Sales & Distribution (ABAP Workbench) | **Submission:** April 2026

---

## Overview

`ZSD_SO_BACKLOG` is a custom ABAP executable program built in the SAP ABAP Workbench (SE38) that provides a **single, live, colour-coded, drill-down enabled ALV report** for monitoring open Sales Order backlogs in SAP SD.

It eliminates the need for manual multi-transaction exports and Excel VLOOKUPs by delivering a consolidated, interactive dashboard with automated delivery delay classification.

---

## Problem Statement

Standard SAP SD transactions like **VA05** (List of Sales Orders) and **VL10C** (Delivery Due List) only provide partial views:

- VA05 lacks delivery schedule details
- VL10C excludes orders not yet dispatched to the warehouse
- No automated delay classification exists in standard reports
- Sales coordinators spend **2–3 hours/day** manually exporting and cross-referencing data across transactions

**ZSD_SO_BACKLOG** solves all of the above in a single screen.

---

## Key Features

| Feature | Description |
|---|---|
| **Open Order Backlog View** | Fetches open sales order line items from VBAK/VBAP, enriched with confirmed delivery dates from VBEP |
| **Delivery Delay Classification** | Classifies each line into: `Confirmed`, `At Risk` (1–7 days), `Overdue` (1–14 days), `Critical` (>14 days) |
| **Customer & Material Filters** | Selection screen with ranges for VKORG, KUNNR, MATNR, AUDAT, VDATU — all with F4 help |
| **Drill-Down to VA03** | Double-click any row to open the full Sales Order in VA03 with order/item pre-populated |
| **Subtotals by Sales Org** | ALV subtotals grouped by VKORG and KUNNR showing total open value and pending quantity |
| **Colour-Coded Status Icons** | Green / Yellow / Red / Failure icons for instant visual triage |
| **Excel & PDF Export** | One-click export from the standard ALV toolbar (XXL for Excel, PDF download) |
| **Authority Check** | `AUTHORITY-CHECK OBJECT 'V_VBAK_VKO'` enforced at selection screen level |
| **Layout Personalisation** | ALV variants saved per user via the standard grid variant mechanism |

---

## Technical Architecture

The program is split into five clearly separated layers:

```
┌─────────────────────────────────────────────────────┐
│  SELECTION SCREEN LAYER  (ZSDSO_SEL / ZSDSO_PAI)   │
│  AT SELECTION-SCREEN — validation, F4, auth-check   │
├─────────────────────────────────────────────────────┤
│  DATA RETRIEVAL LAYER  (GET_OPEN_ORDERS)            │
│  Single multi-table SELECT: VBAK + VBAP + VBEP + KNA1│
├─────────────────────────────────────────────────────┤
│  PROCESSING LAYER  (COMPUTE_DELAY)                  │
│  Delay days, open value, status label, icon, colour │
├─────────────────────────────────────────────────────┤
│  PRESENTATION LAYER  (BUILD_FIELDCAT / DISPLAY_GRID)│
│  CL_GUI_ALV_GRID inside CL_GUI_DOCKING_CONTAINER   │
├─────────────────────────────────────────────────────┤
│  EVENT LAYER  (LCL_EVENT_HANDLER)                   │
│  ON_DOUBLE_CLICK → VA03 | ON_TOOLBAR_CLICK → Refresh│
└─────────────────────────────────────────────────────┘
```

### Include Structure

| Include | Contents |
|---|---|
| `ZSDSO_TOP` | Types, global data, constants |
| `ZSDSO_SEL` | Selection screen definition |
| `ZSDSO_PAI` | AT SELECTION-SCREEN events |
| `ZSDSO_CLS` | Local class `LCL_SO_BACKLOG` + `LCL_EVENT_HANDLER` |
| `ZSDSO_OUT` | ALV output call in START-OF-SELECTION |

---

## Database Tables Used

| Table | Purpose |
|---|---|
| `VBAK` | Sales Order Header |
| `VBAP` | Sales Order Item |
| `VBEP` | Sales Order Schedule Lines |
| `KNA1` | Customer Master (Name) |

---

## Technology Stack

| Component | Tool / Version | Role |
|---|---|---|
| ABAP Workbench | SE38 / SE80 | Development, syntax check, activation |
| ABAP Objects (OOP) | ABAP 7.40+ | Local class encapsulation |
| ALV Grid Control | `CL_GUI_ALV_GRID` | Interactive output grid |
| Docking Container | `CL_GUI_DOCKING_CONTAINER` | Screen-independent ALV hosting |
| Data Dictionary | SE11 | Structure, domain, data element |
| Message Class | SE91 / `ZSD_MSG` | Centralised error messages |
| Transport Tools | SE09 / STMS | DEV → QA → PRD transport |
| Runtime Analysis | SAT / SE30 | Performance profiling |

---

## Repository Structure

```
ZSD_SO_BACKLOG/
│
├── README.md                   ← This file
└── ZSD_SO_BACKLOG.abap         ← Full ABAP source code
```

---

## Development Lifecycle (13 Phases)

1. **Requirement Gathering** — Functional spec with Sales Ops team
2. **Data Dictionary (SE11)** — Structure `ZSTR_SO_BACKLOG`, domain `ZDO_DLVRY_STATUS`, data element `ZDE_DELAY_DAYS`
3. **Message Class (SE91)** — `ZSD_MSG` with 3 messages
4. **Program Shell (SE38)** — Executable program + include structure
5. **Selection Screen** — Filters with F4 help
6. **Local Class Skeleton** — `LCL_SO_BACKLOG` + `LCL_EVENT_HANDLER`
7. **Data Retrieval** — Multi-table SELECT with open-quantity compute
8. **Delay Computation** — Status + icon + colour enrichment
9. **Field Catalogue** — ALV column definitions with hotspot on VBELN
10. **ALV Grid & Events** — Docking container, grid wiring, VA03 drill-down
11. **Subtotals & Toolbar** — Group totals + custom Refresh button `ZB01`
12. **Testing (SE38 / SAT)** — Unit, volume (15,000 lines), regression
13. **Transport (SE09 / STMS)** — DEV → QA → PRD with UAT sign-off

---

## How to Deploy

1. In **SE38**, create program `ZSD_SO_BACKLOG` (Type: Executable, Package: `ZSD_DEV`)
2. Create the include programs listed above and paste the corresponding code
3. In **SE11**, create:
   - Structure `ZSTR_SO_BACKLOG`
   - Domain `ZDO_DLVRY_STATUS` with fixed values: `CONFIRMED`, `AT_RISK`, `OVERDUE`, `CRITICAL`
   - Data element `ZDE_DELAY_DAYS`
4. In **SE91**, create message class `ZSD_MSG` with messages 001–003
5. Activate all objects
6. Add to transport via **SE09** and promote through **STMS**

---

## Delay Classification Logic

| Delay (Days) | Status | Icon | Row Colour |
|---|---|---|---|
| ≤ 0 (future) | Confirmed | 🟢 `ICON_LED_GREEN` | None |
| 1 – 7 | At Risk | 🟡 `ICON_LED_YELLOW` | Yellow (`53`) |
| 8 – 14 | Overdue | 🔴 `ICON_LED_RED` | Red (`21`) |
| > 14 | Critical | ❌ `ICON_FAILURE` | Red (`21`) |

---

## Future Improvements

### Near-Term
- Replace multi-table JOIN with `FOR ALL ENTRIES` for 50,000+ order performance
- Add "Critical Only" filter checkbox
- Background job variant with daily email summary to sales manager

### Medium-Term
- Join with `LIKP/LIPS` and `VBRK/VBRP` for full order-to-cash lifecycle view
- Cross-reference with MD04 (MRP) for production/procurement dates
- Rolling 90-day Customer Risk Score from delivery history

### Long-Term (S/4HANA / Fiori)
- Migrate SELECTs to CDS Consumption Views using SAP standard analytical views
- Build Fiori Elements List Report over OData V4 service
- CDS Analytical View for SAP Analytics Cloud (SAC) executive dashboards
- Migrate auth checks to SAP BTP Role Collections with SSO

---


**Reva Sahu**  
Roll No. 23053292 | B.Tech 2023–2027  
Individual Project — April 2026
