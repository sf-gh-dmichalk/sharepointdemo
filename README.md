# SharePoint Openflow Demo — Retail Store Ops

Retail stores generate hundreds of PDFs a week on SharePoint — inspections, work orders, incident reports, planogram audits. They sit there until something goes wrong. This demo makes them queryable.

**SharePoint → Openflow → AI_CLASSIFY → AI_EXTRACT → Iceberg → Dynamic Tables**

## What it does

1. **Openflow** syncs documents from a SharePoint site into Snowflake automatically
2. **AI_CLASSIFY** reads each document and routes it by type (inspection, maintenance, incident, planogram)
3. **AI_EXTRACT** pulls structured fields using type-specific schemas
4. **Dynamic Iceberg tables** reshape the raw extraction into queryable tables — one per document type
5. **Live add**: drop a new PDF in SharePoint, it flows through the entire pipeline with zero manual steps

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
├── 00_account_setup.sql    Roles + privileges
├── 01_demo_objects.sql     OPENFLOW_DEMO database, warehouses, Iceberg settings
├── 02_openflow_deployment.sql  Gen 2 deployment, EAI, runtime (SQL)
├── 03_connector_grants.sql     Grants for the runtime role
├── 04_ai_pipeline.sql      AI classify + extract task, 4 dynamic tables
├── 05_reset.sql            Rebuild AI layer, keep ingested docs
└── 99_teardown.sql         Drop everything

tools/
└── generate_docs.py        Regenerate seed PDFs

keys/                       cert.pem + key.pem (gitignored)
```

## Snowflake objects created

| Object | Type | Purpose |
|--------|------|---------|
| `OPENFLOW_DEMO` | Database | Iceberg-enabled, Snowflake-managed storage |
| `SHAREPOINT_DOCS` | Schema | All connector + AI objects |
| `OPENFLOW` | Schema | Gen 2 deployment + runtime objects |
| `OPENFLOW_DEMO_WH` | Warehouse (XS) | Interactive queries |
| `OPENFLOW_DEMO_INGEST_WH` | Warehouse (S) | Connector + AI_EXTRACT |
| `DOC_EXTRACT_RAW` | Iceberg table | Raw AI_CLASSIFY + AI_EXTRACT output |
| `INSPECTION_FINDINGS` | Dynamic Iceberg table | One row per inspection finding |
| `MAINTENANCE_ORDERS` | Dynamic Iceberg table | One row per work order |
| `INCIDENT_REPORTS` | Dynamic Iceberg table | One row per incident |
| `PLANOGRAM_FINDINGS` | Dynamic Iceberg table | One row per planogram finding |
| `TASK_CLASSIFY_AND_EXTRACT` | Task (2 min) | Anti-join: classify + extract new docs |
| `OPENFLOW_DEMO_DEPLOYMENT` | Openflow deployment | Gen 2 |
| `OPENFLOW_DEMO_RUNTIME` | Openflow runtime | Small/S1, 1 node |
| `EAI_OPENFLOW_SHAREPOINT` | External access integration | Egress to M365 |

## Cortex AI features used

- **AI_CLASSIFY** — auto-routes documents by type (no rules engine)
- **AI_EXTRACT** — type-specific structured extraction with confidence scores
- **Dynamic Iceberg Tables** — incremental reshape into queryable output

## Demo narrative

> "Your stores generate hundreds of PDFs a week on SharePoint. They sit there. Nobody reads them until something goes wrong."

Store #4421 has a refrigeration failure flagged by a food safety inspection → triggers an emergency work order → later a customer slips on a wet floor near produce → the follow-up inspection shows all corrective actions verified. The data tells the story across document types — no manual step.

**Live add**: upload the 8/12 follow-up inspection to SharePoint. Within ~7 minutes it's classified, extracted, and appears in `INSPECTION_FINDINGS` showing the cooler repair was verified. The story closes itself.

## Setup order

1. Run `00_account_setup.sql` through `02_openflow_deployment.sql`
2. `pwsh sharepoint/upload_seed.ps1` — upload docs to SharePoint
3. Run `03_connector_grants.sql`
4. Install + start SharePoint connector in Openflow UI
5. Wait for 10 rows in `DOC_METADATA`
6. Run `04_ai_pipeline.sql`

## SharePoint site

`https://oceancloudtech.sharepoint.com/sites/openflowdemo`

GitHub: `https://github.com/sf-gh-dmichalk/sharepointdemo`
