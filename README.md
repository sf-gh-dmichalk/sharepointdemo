# SharePoint Openflow Demo — Retail Store Ops

Retail stores generate hundreds of PDFs a week on SharePoint — inspections, work orders, incident reports, planogram audits. They sit there until something goes wrong. This demo makes them queryable.

**SharePoint → Openflow → AI_CLASSIFY → AI_EXTRACT → Iceberg → Dynamic Tables**

## What it does

1. **Openflow** syncs documents from a SharePoint site into Snowflake automatically
2. **AI_CLASSIFY** reads each document and routes it by type (inspection, maintenance, incident, planogram)
3. **AI_EXTRACT** pulls structured fields using type-specific schemas
4. **Dynamic Iceberg tables** reshape the raw extraction into queryable tables — one per document type
5. **Live add**: drop a new PDF in SharePoint, it flows through the entire pipeline with zero manual steps

## Prerequisites

- Snowflake account with Openflow enabled (ORGADMIN must accept Openflow ToS once per org)
- `OPENFLOW_ADMIN` role with `CREATE OPENFLOW DEPLOYMENT ON ACCOUNT` (or an existing shared deployment)
- SharePoint site on `oceancloudtech.sharepoint.com` with an Entra app registration (client ID, client secret, cert + key)
- PowerShell with PnP.PowerShell module for uploading seed docs
- The `keys/` directory (gitignored) must contain `cert.pem` and `key.pem` for the Entra app

## Setup — step by step

### Phase 1: Snowflake objects (SQL, run in Snowsight)

**`00_account_setup.sql`** — Run as ACCOUNTADMIN

Creates two roles (`OF_SHAREPOINT_ADMIN`, `OF_SHAREPOINT_RUNTIME_ROLE`), grants them to SYSADMIN and DMICHALK, and sets account-level privileges. Safe to re-run.

**`01_demo_objects.sql`** — Starts as SYSADMIN, switches to OF_SHAREPOINT_ADMIN

Creates the `OF_SHAREPOINT` database (Iceberg-enabled), `OF_SHAREPOINT_WH` warehouse (SMALL), `DOCS` and `OPENFLOW` schemas, event table `DEMO_EVENTS`, and sets Iceberg parameters. Hands ownership to `OF_SHAREPOINT_ADMIN`.

**`02_openflow_deployment.sql`** — Starts as OPENFLOW_ADMIN, switches to OF_SHAREPOINT_ADMIN

Creates the shared `OF_DEPLOYMENT` (no-op if it already exists from another demo — takes 5-10 min on first run), the `OF_SHAREPOINT_EAI` external access integration for M365 egress, and the `OF_SHAREPOINT_RUNTIME` on that deployment. Waits for both deployment and runtime to reach ACTIVE status. Total wait: up to 15 min on first run, seconds on re-run.

**`03_connector_grants.sql`** — Run as OF_SHAREPOINT_ADMIN

Grants the runtime role (`OF_SHAREPOINT_RUNTIME_ROLE`) access to the database, schema, and warehouse so the connector can create its objects.

### Phase 2: SharePoint setup (PowerShell + Openflow UI)

**Upload seed documents:**
```
pwsh -File sharepoint/upload_seed.ps1
```
Uploads 10 PDFs to the `openflowdemo` SharePoint site. Creates the folder structure (Inspections, Maintenance, Incidents, Planograms) automatically.

**Set up permission groups (optional):**
```
pwsh -File sharepoint/setup_groups.ps1
```
Creates 4 SharePoint groups (StoreOps-Management, Facilities, Safety, Merchandising) with folder-level permissions. Only needed if demoing the ACL story.

**Install the SharePoint connector (Openflow UI — gen 1, manual):**

1. Snowsight → Ingestion → Openflow → Launch Openflow
2. Open the `OF_SHAREPOINT_RUNTIME` runtime canvas
3. Install connector: **Microsoft SharePoint (Simple Ingest, document ACLs)**
4. Configure with these values:

| Parameter | Value |
|-----------|-------|
| SharePoint Site URL | `https://oceancloudtech.sharepoint.com/sites/openflowdemo` |
| SharePoint Client ID | *(from Entra app registration)* |
| SharePoint Client Secret | *(from Entra app or CoCo secret `sharepoint_client_secret`)* |
| SharePoint Tenant ID | `cc43eda7-53cf-4c89-8150-957c3653364d` |
| Sharepoint Site Domain | `oceancloudtech.sharepoint.com` |
| Application Certificate | *(contents of `keys/cert.pem`)* |
| Application Private Key | *(contents of `keys/key.pem`)* |
| Destination Database | `OF_SHAREPOINT` |
| Destination Schema | `DOCS` |
| Snowflake Authentication | `SNOWFLAKE_MANAGED` |
| Snowflake Account Identifier | *(blank)* |
| Snowflake Private Key | *(blank)* |
| Snowflake Username | *(blank)* |
| Snowflake Role | `OF_SHAREPOINT_RUNTIME_ROLE` |
| Snowflake Warehouse | `OF_SHAREPOINT_WH` |
| Document Library Name | `Documents` |
| File Extensions To Ingest | `pdf,xlsx` |
| Site Groups Enabled | `true` |

5. On `FetchSharepointFile` processor: confirm **Download PDF/HTML Version = true**
6. Right-click canvas → Enable all Controller Services
7. Right-click process group → Start
8. Wait for 10 rows:
```sql
SELECT COUNT(*) FROM OF_SHAREPOINT.DOCS.DOC_METADATA;
```

### Phase 3: AI pipeline (SQL)

**`04_ai_pipeline.sql`** — Run as OF_SHAREPOINT_ADMIN

Grants SELECT on connector-created tables back to our role (required — tasks have no secondary roles). Creates the classify + extract task graph:

- `TASK_CLASSIFY_DOCS` (root, every 2 min) → AI_CLASSIFY on new documents
- 4 child extract tasks (fire after classify) → AI_EXTRACT with type-specific schemas
- 4 dynamic Iceberg tables reshape raw output into structured tables

Allow ~7 minutes for the first task cycle + dynamic table refresh to complete.

**Verify:**
```sql
SELECT DOC_TYPE, COUNT(*) FROM OF_SHAREPOINT.DOCS.DOC_CLASSIFY_RAW GROUP BY 1;
SELECT DOC_TYPE, COUNT(*) FROM OF_SHAREPOINT.DOCS.DOC_EXTRACT_RAW GROUP BY 1;
SELECT * FROM OF_SHAREPOINT.DOCS.INSPECTION_FINDINGS;
SELECT * FROM OF_SHAREPOINT.DOCS.MAINTENANCE_ORDERS;
```

### Phase 4: Live demo

Upload `sharepoint/livedemo-docs/Inspections/food_safety_inspection_store_4421_2026-08-12.pdf` to the Inspections folder in SharePoint. Within ~7 minutes it appears as classified, extracted, and structured — the follow-up inspection confirms all repairs from the 7/15 findings. Zero-touch.

## Reset and teardown

**`05_reset.sql`** — Drops the AI layer (tasks, dynamic tables, raw tables), keeps connector data. Re-run `04_ai_pipeline.sql` to rebuild.

**`99_teardown.sql`** — Drops everything demo-specific. Run statements one at a time — runtime must be suspended → terminated → dropped before the database. The shared `OF_DEPLOYMENT` is left in place for other demos.

## Repo structure

```
sharepoint/
├── seed-docs/              10 PDFs to upload to SharePoint
│   ├── Inspections/        Food safety, health dept (3)
│   ├── Maintenance/        Work orders: refrigeration, HVAC, plumbing (3)
│   ├── Incidents/          Slip/fall, equipment failure (2)
│   └── Planograms/         Shelf compliance audits (2)
├── livedemo-docs/          2 PDFs for the live-add demo moment
├── setup_groups.ps1        Creates SharePoint permission groups
└── upload_seed.ps1         Uploads seed docs to SharePoint

snowflake/
├── 00_account_setup.sql    Roles + privileges (ACCOUNTADMIN)
├── 01_demo_objects.sql     Database, warehouse, schemas, event table
├── 02_openflow_deployment.sql  Shared deployment + demo runtime
├── 03_connector_grants.sql     Runtime role grants
├── 04_ai_pipeline.sql      AI classify/extract tasks + dynamic tables
├── 05_reset.sql            Rebuild AI layer only
└── 99_teardown.sql         Drop everything (except shared deployment)

tools/
└── generate_docs.py        Regenerate seed PDFs

keys/                       cert.pem + key.pem (gitignored)
```

## Snowflake objects

**Roles** (2 — self-contained, no shared globals)

- `OF_SHAREPOINT_ADMIN` — owns everything in this demo
- `OF_SHAREPOINT_RUNTIME_ROLE` — execute-as identity for the runtime

**Infrastructure**

- `OF_SHAREPOINT` — Database (Iceberg v3, Snowflake-managed storage)
- `DOCS` — Schema for connector + AI objects + event table
- `OPENFLOW` — Schema for runtime object
- `OF_SHAREPOINT_WH` — Warehouse (SMALL)
- `OF_SHAREPOINT_EAI` — External access integration (M365 egress)
- `DEMO_EVENTS` — Event table for runtime telemetry

**Openflow**

- `OF_DEPLOYMENT` — Shared gen 2 deployment (owned by OPENFLOW_ADMIN)
- `OF_SHAREPOINT_RUNTIME` — Demo-specific runtime (Small/S1, 1 node)

**AI pipeline**

- `DOC_CLASSIFY_RAW` — AI_CLASSIFY output
- `DOC_EXTRACT_RAW` — AI_EXTRACT output
- `TASK_CLASSIFY_DOCS` → `TASK_EXTRACT_{INSPECTIONS,MAINTENANCE,INCIDENTS,PLANOGRAMS}`

**Structured output (dynamic Iceberg tables)**

- `INSPECTION_FINDINGS` — One row per finding
- `MAINTENANCE_ORDERS` — One row per work order
- `INCIDENT_REPORTS` — One row per incident
- `PLANOGRAM_FINDINGS` — One row per planogram finding

## Demo narrative

> "Your stores generate hundreds of PDFs a week on SharePoint. They sit there. Nobody reads them until something goes wrong."

Store #4421 has a refrigeration failure flagged by a food safety inspection → triggers an emergency work order → a customer slips on a wet floor near produce → the follow-up inspection shows all corrective actions verified. The data tells the story across document types — no manual step.

## SharePoint site

`https://oceancloudtech.sharepoint.com/sites/openflowdemo`
