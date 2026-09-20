/* =============================================================================
   02_connector_grants.sql — Run BEFORE starting the Openflow connector
   -----------------------------------------------------------------------------
   Run as OPENFLOW_DEMO_ADMIN.

   Grants so the Openflow SharePoint connector can create its objects
   (stage, DOC_METADATA, ACL tables) in the SHAREPOINT_DOCS schema.
   ============================================================================= */

USE ROLE OPENFLOW_DEMO_ADMIN;
USE DATABASE OPENFLOW_DEMO;
USE SCHEMA SHAREPOINT_DOCS;
USE WAREHOUSE OPENFLOW_DEMO_INGEST_WH;

/* Runtime role needs access to the database, schema, and warehouse */
GRANT USAGE ON DATABASE OPENFLOW_DEMO
    TO ROLE OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME;

GRANT USAGE ON SCHEMA OPENFLOW_DEMO.SHAREPOINT_DOCS
    TO ROLE OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME;

GRANT CREATE TABLE,
      CREATE DYNAMIC TABLE,
      CREATE STAGE,
      CREATE SEQUENCE,
      CREATE CORTEX SEARCH SERVICE
    ON SCHEMA OPENFLOW_DEMO.SHAREPOINT_DOCS
    TO ROLE OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME;

GRANT USAGE, OPERATE ON WAREHOUSE OPENFLOW_DEMO_INGEST_WH
    TO ROLE OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME;

/* Grants BACK to us — without these, tasks fail silently.

   The connector creates DOC_METADATA and the DOCUMENTS stage as the runtime
   role, so it OWNS them. OPENFLOW_DEMO_ADMIN owns the schema but that conveys
   nothing over objects another role created inside it. FUTURE TABLES covers
   anything the connector adds later. */
USE ROLE ACCOUNTADMIN;

GRANT SELECT ON ALL TABLES    IN SCHEMA OPENFLOW_DEMO.SHAREPOINT_DOCS
    TO ROLE OPENFLOW_DEMO_ADMIN;
GRANT SELECT ON FUTURE TABLES IN SCHEMA OPENFLOW_DEMO.SHAREPOINT_DOCS
    TO ROLE OPENFLOW_DEMO_ADMIN;
GRANT READ ON STAGE OPENFLOW_DEMO.SHAREPOINT_DOCS.DOCUMENTS
    TO ROLE OPENFLOW_DEMO_ADMIN;

USE ROLE OPENFLOW_DEMO_ADMIN;

/* -----------------------------------------------------------------------------
   Connector configuration reference — entered in the Openflow UI.

   VARIANT: Microsoft SharePoint (Simple Ingest, document ACLs)

   Source
     SharePoint Site URL            https://oceancloudtech.sharepoint.com/sites/openflowdemo
     SharePoint Client ID           <<from Entra app registration>>
     SharePoint Client Secret       <<SHAREPOINT_CLIENT_SECRET>>
     SharePoint Tenant ID           cc43eda7-53cf-4c89-8150-957c3653364d
     Sharepoint Site Domain         oceancloudtech.sharepoint.com
     Sharepoint Application Certificate  <<keys/cert.pem>>
     Sharepoint Application Private Key  <<keys/key.pem>>

   Destination
     Destination Database           OPENFLOW_DEMO
     Destination Schema             SHAREPOINT_DOCS
     Snowflake Authentication       SNOWFLAKE_MANAGED
     Snowflake Role                 OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME
     Snowflake Warehouse            OPENFLOW_DEMO_INGEST_WH

   Ingestion
     Sharepoint Document Library    Documents
     File Extensions To Ingest      pdf,xlsx
     Sharepoint Site Groups Enabled true

   SharePoint folders:
     Inspections/   — food safety, health dept, sanitation
     Maintenance/   — work orders (HVAC, refrigeration, plumbing)
     Incidents/     — slip/fall, equipment failure, theft
     Planograms/    — shelf compliance audits

   NOW: start the connector in Openflow UI, wait for 10 rows in DOC_METADATA,
   then run 03_ai_pipeline.sql.
   -------------------------------------------------------------------------- */

/* Verify after connector's first run: */
SHOW STAGES IN SCHEMA OPENFLOW_DEMO.SHAREPOINT_DOCS;
SHOW TABLES IN SCHEMA OPENFLOW_DEMO.SHAREPOINT_DOCS;
SELECT COUNT(*) FROM DOC_METADATA;
SELECT FILE_ID, FILE_NAME FROM DOC_METADATA ORDER BY FILE_NAME;
