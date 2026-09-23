# SharePoint Openflow Demo — Retail Store Ops

Retail stores generate hundreds of PDFs a week on SharePoint — inspections, work orders, incident reports, planogram audits. They sit there until something goes wrong. This demo makes them queryable.

**SharePoint → Openflow (Cortex Connect) → Cortex Search + AI_CLASSIFY → AI_EXTRACT → Iceberg → Structured Search**

## What it does

1. **Openflow Cortex Connect** syncs documents from SharePoint into Snowflake, chunks + OCR's them, and creates an ACL-aware Cortex Search service automatically
2. **AI_CLASSIFY** reads each document from the stage and routes it by type (inspection, maintenance, incident, planogram)
3. **AI_EXTRACT** pulls structured fields using type-specific schemas
4. **Dynamic Iceberg tables** reshape the raw extraction into queryable tables — one per document type
5. **Two Cortex Search services**: connector's built-in (raw docs + ACLs) and `STORE_OPS_SEARCH` (structured findings, filterable by store/type/severity)
6. **Live add**: drop a new PDF in SharePoint, it flows through the entire pipeline with zero manual steps

## Prerequisites

- Snowflake account with Openflow enabled (ORGADMIN must accept Openflow ToS once per org)
- `OPENFLOW_ADMIN` role with `CREATE OPENFLOW DEPLOYMENT ON ACCOUNT` (or an existing shared deployment)
- SharePoint site: `https://oceancloudtech.sharepoint.com/sites/openflowdemo`
- Microsoft Entra app registration (`snowflake-openflow-sharepoint`, Client ID `bf21144d-ff46-4f2a-a85a-5b7121da63a3`) with:
  - `Sites.Selected` permission (with `fullcontrol` on the site — see Step 5b)
  - `GroupMember.Read.All` permission (for ACL group resolution)
  - `User.ReadBasic.All` permission (for resolving user emails)
  - A client secret
  - A certificate + private key uploaded (required for ACL/group resolution)
- PowerShell with [PnP.PowerShell](https://pnp.github.io/powershell/) module (`Install-Module PnP.PowerShell`)

## Setup

### Step 1: Snowflake roles and privileges

Run in Snowsight as **ACCOUNTADMIN**:

```
snowflake/00_account_setup.sql
```

Creates `OF_SHAREPOINT_ADMIN` and `OF_SHAREPOINT_RUNTIME_ROLE`, grants them to SYSADMIN and your user.

### Step 2: Database, warehouse, schemas

```
snowflake/01_demo_objects.sql
```

Creates `OF_SHAREPOINT` database (Iceberg v3), `OF_SHAREPOINT_WH` warehouse (SMALL), `DOCS` and `OPENFLOW` schemas, and the `DEMO_EVENTS` event table.

### Step 3: Openflow deployment and runtime

```
snowflake/02_openflow_deployment.sql
```

Creates the shared `OF_DEPLOYMENT` (5-10 min first time, no-op if it exists), the `OF_SHAREPOINT_EAI` external access integration for M365 egress, and `OF_SHAREPOINT_RUNTIME`. Waits for ACTIVE status.

### Step 4: Connector grants

```
snowflake/03_connector_grants.sql
```

Grants `OF_SHAREPOINT_RUNTIME_ROLE` access to the database, schema, and warehouse so the connector can create its tables.

### Step 5: SharePoint setup

**5a. Upload seed documents:**

```bash
pwsh -File sharepoint/upload_seed.ps1
```

Uploads 95 seed PDFs to SharePoint, creating folders automatically. Opens a browser for sign-in.

**5b. Grant the Entra app fullcontrol on the site** (required for `Sites.Selected`):

```bash
pwsh -Command 'Connect-PnPOnline -Url "https://oceancloudtech.sharepoint.com/sites/openflowdemo" -Interactive -ClientId "6868ac5b-6e83-4918-8ca8-1cecbf42ceaa"; Grant-PnPAzureADAppSitePermission -AppId "bf21144d-ff46-4f2a-a85a-5b7121da63a3" -DisplayName "snowflake-openflow-sharepoint" -Permissions FullControl -Site "https://oceancloudtech.sharepoint.com/sites/openflowdemo"'
```

**5c. Set up ACL groups** (optional — only needed if demoing the permissions story):

```bash
pwsh -File sharepoint/setup_groups.ps1
```

Creates 4 SharePoint groups (StoreOps-Management, Facilities, Safety, Merchandising) with folder-level permissions and adds `dale@oceancloudtech.com` to all groups.

### Step 6: Install the SharePoint connector (Openflow UI)

1. Snowsight → Ingestion → Openflow → Launch Openflow
2. Open the `OF_SHAREPOINT_RUNTIME` runtime canvas
3. Install connector: **Microsoft SharePoint (Cortex Connect)**
4. Right-click the **canvas background** (not a processor) → **Configure** → **Properties** tab
5. Set the connector parameters:

**SharePoint connection (all connectors):**

| Parameter | Value |
|-----------|-------|
| SharePoint Site URL | `https://oceancloudtech.sharepoint.com/sites/openflowdemo` |
| SharePoint Client ID | `bf21144d-ff46-4f2a-a85a-5b7121da63a3` |
| SharePoint Client Secret | *(Entra app client secret — sensitive, set in parameter context)* |
| SharePoint Tenant ID | `cc43eda7-53cf-4c89-8150-957c3653364d` |
| Sharepoint Site Domain | `oceancloudtech.sharepoint.com` |

**ACL / group resolution (required when Site Groups = true):**

| Parameter | Value |
|-----------|-------|
| SharePoint Application Private Key | *(contents of `keys/key.pem`)* |
| SharePoint Application Certificate | *(contents of `keys/cert.pem`)* |

**Snowflake destination:**

| Parameter | Value |
|-----------|-------|
| Destination Database | `OF_SHAREPOINT` |
| Destination Schema | `DOCS` |
| Snowflake Authentication | `SNOWFLAKE_MANAGED` |
| Snowflake Role | `OF_SHAREPOINT_RUNTIME_ROLE` |
| Snowflake Warehouse | `OF_SHAREPOINT_WH` |
| Snowflake Cortex Search Service User Role | `OF_SHAREPOINT_RUNTIME_ROLE` |
| Document Library Name | `Documents` |
| File Extensions To Ingest | `pdf,xlsx` |
| Site Groups Enabled | `true` |

Leave **Snowflake Account Identifier**, **Snowflake Private Key**, and **Snowflake Username** blank — `SNOWFLAKE_MANAGED` auth handles these.

6. Right-click canvas → Enable all Controller Services (ignore `StandardPrivateKeyService` validation warning — it's for Snowflake key-pair auth which `SNOWFLAKE_MANAGED` doesn't use)
7. Right-click process group → Start
8. Wait for docs to appear:

```sql
SELECT COUNT(DISTINCT METADATA:id::STRING) AS docs FROM OF_SHAREPOINT.DOCS.DOCS_CHUNKS;
SELECT COUNT(*) AS files FROM OF_SHAREPOINT.DOCS.FILE_HASHES;
```

The connector creates these tables automatically:

| Table | Description |
|-------|-------------|
| `DOCS_CHUNKS` | Chunked + OCR'd text per document |
| `FILE_HASHES` | Maps doc IDs to stage file paths |
| `DOCUMENTS` stage | Raw PDFs keyed by SharePoint doc ID |
| `DOCS_PERMS` | Per-document user permissions |
| `DOCS_GROUPS` | Document-to-group mappings |
| `PERMS_GROUPS` | Group membership with resolved emails |
| `DOC_GROUP_PERMS` | Resolved group permissions per doc (dynamic table) |
| `CORTEX_SEARCH_SERVICE` | ACL-aware Cortex Search over raw chunks |

### Step 7: AI pipeline

```
snowflake/04_ai_pipeline.sql
```

Adds structured extraction on top of the connector's output:

- `TASK_CLASSIFY_DOCS` (root, every 2 min) — AI_CLASSIFY on new documents from the stage
- 4 child extract tasks — AI_EXTRACT with type-specific schemas
- 4 dynamic Iceberg tables — structured output per document type
- `STORE_OPS_SEARCH` — Cortex Search over structured findings (filterable by store, doc type, severity)

Allow ~7 minutes for the first task cycle + dynamic table refresh.

**Verify:**

```sql
SELECT DOC_TYPE, COUNT(*) FROM OF_SHAREPOINT.DOCS.DOC_CLASSIFY_RAW GROUP BY 1;
SELECT DOC_TYPE, COUNT(*) FROM OF_SHAREPOINT.DOCS.DOC_EXTRACT_RAW GROUP BY 1;
SELECT * FROM OF_SHAREPOINT.DOCS.INSPECTION_FINDINGS LIMIT 10;
SELECT * FROM OF_SHAREPOINT.DOCS.MAINTENANCE_ORDERS LIMIT 10;
```

**Query the connector's built-in Cortex Search (raw docs + ACLs):**

```sql
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'OF_SHAREPOINT.DOCS.CORTEX_SEARCH_SERVICE',
        '{
            "query": "refrigeration issues",
            "columns": ["full_name", "chunk"],
            "filter": {"@contains": {"user_emails": "dale@oceancloudtech.com"}},
            "limit": 3
        }'
    )
)['results'] AS results;
```

### Step 8: Semantic view + Cortex Agent

```
snowflake/05_agent.sql
```

Creates:

- **`STORE_OPS_ANALYTICS`** — Semantic view over the 4 structured tables with 6 verified queries, cross-table relationships on `STORE_NUMBER`, and metrics (finding counts, open order counts, non-compliant counts)
- **`STORE_OPS_AGENT`** — Cortex Agent with two tools:
  - **Analyst** (semantic view) — for analytical questions that need SQL ("which stores have the most critical findings")
  - **Search** (connector's `CORTEX_SEARCH_SERVICE`) — for raw document retrieval with ACLs ("what did the inspector say about refrigeration at store 4421")

> **Cortex Agent gotcha — default role & warehouse:**
> Cortex Agents ignores your session role and warehouse. It always uses your user's **DEFAULT_ROLE** and **DEFAULT_WAREHOUSE**. The default role must have USAGE on the agent, its database/schema, and a warehouse — and the default warehouse must be one that role can actually use. The script handles this with grants to `OPENFLOW_ADMIN` and an `ALTER USER CURRENT_USER() SET DEFAULT_WAREHOUSE` statement. If you hit _"missing an execution environment"_ errors, check `DESC USER <you>` and verify the default role has USAGE on the default warehouse.

**Test the agent:**

```sql
SELECT TRY_PARSE_JSON(
    SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'OF_SHAREPOINT.DOCS.STORE_OPS_AGENT',
        '{"messages":[{"role":"user","content":[{"type":"text","text":"Which stores have the most critical inspection findings?"}]}]}',
        TRUE
    )
) AS resp;

SELECT TRY_PARSE_JSON(
    SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'OF_SHAREPOINT.DOCS.STORE_OPS_AGENT',
        '{"messages":[{"role":"user","content":[{"type":"text","text":"What did the inspector find about refrigeration at store #4421?"}]}]}',
        TRUE
    )
) AS resp;

SELECT TRY_PARSE_JSON(
    SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'OF_SHAREPOINT.DOCS.STORE_OPS_AGENT',
        '{"messages":[{"role":"user","content":[{"type":"text","text":"What is going on at store #4421?"}]}]}',
        TRUE
    )
) AS resp;
```

Or test in the Snowsight agent playground: **AI & ML → Agents → Store Ops Agent**.

### Step 9: Live demo

Upload one of the livedemo docs to SharePoint:

```bash
pwsh -Command 'Connect-PnPOnline -Url "https://oceancloudtech.sharepoint.com/sites/openflowdemo" -Interactive -ClientId "6868ac5b-6e83-4918-8ca8-1cecbf42ceaa"; Add-PnPFile -Path "sharepoint/livedemo-docs/Inspections/inspection_4421_food_safety_2026-09-15.pdf" -Folder "Shared Documents/Inspections"'
```

Within ~7 minutes it appears classified, extracted, and structured. Zero-touch.

## Reset and teardown

**`07_reset.sql`** — Drops the AI layer (tasks, dynamic tables, raw tables, `STORE_OPS_SEARCH`, agent, semantic view), keeps connector data and `CORTEX_SEARCH_SERVICE` intact. Re-run `04_ai_pipeline.sql` and `05_agent.sql` to rebuild.

**`99_teardown.sql`** — Drops everything demo-specific. Stop and delete the connector in the Openflow UI first. Run statements one at a time — runtime must be suspended → terminated → dropped before the database. The shared `OF_DEPLOYMENT` is left in place.

## Cleaning up SharePoint

Delete all PDFs and re-upload clean:

```bash
pwsh -Command 'Connect-PnPOnline -Url "https://oceancloudtech.sharepoint.com/sites/openflowdemo" -Interactive -ClientId "6868ac5b-6e83-4918-8ca8-1cecbf42ceaa"; Get-PnPFolderItem -FolderSiteRelativeUrl "Shared Documents" -Recursive | Where-Object { $_.Name -like "*.pdf" } | ForEach-Object { Remove-PnPFile -ServerRelativeUrl $_.ServerRelativeUrl -Force }'
pwsh -File sharepoint/upload_seed.ps1
```

## Repo structure

```
sharepoint/
├── seed-docs/              95 PDFs across 12 stores, 6 months
│   ├── Inspections/        Food safety + health dept (33)
│   ├── Maintenance/        Work orders: refrigeration, HVAC, plumbing, electrical (31)
│   ├── Incidents/          Slip/fall, equipment failure, theft, employee injury (11)
│   └── Planograms/         Shelf compliance audits (20)
├── livedemo-docs/          2 PDFs for the live-add demo moment
├── setup_groups.ps1        Creates SharePoint permission groups
└── upload_seed.ps1         Uploads seed docs to SharePoint

snowflake/
├── 00_account_setup.sql    Roles + privileges (ACCOUNTADMIN)
├── 01_demo_objects.sql     Database, warehouse, schemas, event table
├── 02_openflow_deployment.sql  Shared deployment + demo runtime
├── 03_connector_grants.sql     Runtime role grants
├── 04_ai_pipeline.sql      AI classify/extract tasks + dynamic tables + Cortex Search
├── 05_agent.sql            Semantic view + Cortex Agent
├── store_ops_analytics.sv.yaml  Semantic view YAML source
├── 07_reset.sql            Rebuild AI layer only
└── 99_teardown.sql         Drop everything (except shared deployment)

tools/
└── generate_docs.py        Regenerate seed PDFs (run from repo root)

keys/                       cert.pem + key.pem for Entra app (gitignored)
```

## Snowflake objects

**Connector-created (owned by `OF_SHAREPOINT_RUNTIME_ROLE`):**

| Object | Description |
|--------|-------------|
| `DOCS_CHUNKS` | Chunked + OCR'd document text |
| `FILE_HASHES` | Maps SharePoint doc IDs to stage file paths |
| `DOCUMENTS` stage | Raw PDFs from SharePoint |
| `DOCS_PERMS` | Per-document user permissions |
| `DOCS_GROUPS` | Document-to-group mappings |
| `PERMS_GROUPS` | Group membership with resolved emails |
| `DOC_GROUP_PERMS` | Resolved group permissions (dynamic table) |
| `CORTEX_SEARCH_SERVICE` | ACL-aware Cortex Search over raw chunks |

**AI pipeline (owned by `OF_SHAREPOINT_ADMIN`):**

| Object | Description |
|--------|-------------|
| `DOC_CLASSIFY_RAW` | AI_CLASSIFY output |
| `DOC_EXTRACT_RAW` | AI_EXTRACT output |
| `INSPECTION_FINDINGS` | Dynamic table — one row per finding |
| `MAINTENANCE_ORDERS` | Dynamic table — one row per work order |
| `INCIDENT_REPORTS` | Dynamic table — one row per incident |
| `PLANOGRAM_FINDINGS` | Dynamic table — one row per planogram finding |
| `STORE_OPS_SEARCH` | Cortex Search over structured findings |
| `STORE_OPS_ANALYTICS` | Semantic view over 4 structured tables |
| `STORE_OPS_AGENT` | Cortex Agent (Analyst + Search tools) |

**Infrastructure:**

| Object | Description |
|--------|-------------|
| `OF_SHAREPOINT_ADMIN` | Owns demo objects |
| `OF_SHAREPOINT_RUNTIME_ROLE` | Execute-as identity for the runtime |
| `OF_SHAREPOINT` | Database (Iceberg v3, Snowflake-managed storage) |
| `OF_SHAREPOINT_WH` | Warehouse (SMALL) |
| `OF_SHAREPOINT_EAI` | External access integration (M365 egress) |
| `DEMO_EVENTS` | Event table for runtime telemetry |
| `OF_DEPLOYMENT` | Shared Openflow deployment (owned by OPENFLOW_ADMIN) |
| `OF_SHAREPOINT_RUNTIME` | Demo-specific runtime (Small/S1, 1 node) |

## Demo narrative

> "Your stores generate hundreds of PDFs a week on SharePoint. They sit there. Nobody reads them until something goes wrong."

Store #4421 has a refrigeration failure flagged by a food safety inspection → triggers an emergency work order → a customer slips on a wet floor near produce → the follow-up inspection shows all corrective actions verified. The data tells the story across document types — no manual step.

## SharePoint site

`https://oceancloudtech.sharepoint.com/sites/openflowdemo`
