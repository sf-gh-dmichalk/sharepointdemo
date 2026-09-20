/* =============================================================================
   03_connector_grants.sql — Run BEFORE starting the connector
   -----------------------------------------------------------------------------
   Run as OF_SHAREPOINT_ADMIN.

   After this: install + start the SharePoint connector in Openflow UI,
   wait for 10 rows in DOC_METADATA, then run 04_ai_pipeline.sql.

   Connector config reference:
     Site URL:     https://oceancloudtech.sharepoint.com/sites/openflowdemo
     Tenant ID:    cc43eda7-53cf-4c89-8150-957c3653364d
     Domain:       oceancloudtech.sharepoint.com
     Database:     OF_SHAREPOINT
     Schema:       DOCS
     Auth:         SNOWFLAKE_MANAGED
     Role:         OF_SHAREPOINT_RUNTIME_ROLE
     Warehouse:    OF_SHAREPOINT_INGEST_WH
     Library:      Documents
     Extensions:   pdf,xlsx
     Site Groups:  true
   ============================================================================= */

USE ROLE OF_SHAREPOINT_ADMIN;
USE DATABASE OF_SHAREPOINT;
USE SCHEMA DOCS;
USE WAREHOUSE OF_SHAREPOINT_INGEST_WH;

/* These are all idempotent — safe to re-run */
GRANT USAGE ON DATABASE OF_SHAREPOINT
    TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;

GRANT USAGE ON SCHEMA OF_SHAREPOINT.DOCS
    TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;

GRANT CREATE TABLE, CREATE DYNAMIC TABLE, CREATE STAGE,
      CREATE SEQUENCE, CREATE CORTEX SEARCH SERVICE
    ON SCHEMA OF_SHAREPOINT.DOCS
    TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;

GRANT USAGE, OPERATE ON WAREHOUSE OF_SHAREPOINT_INGEST_WH
    TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;
