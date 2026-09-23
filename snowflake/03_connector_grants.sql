/* =============================================================================
   03_connector_grants.sql — Run BEFORE starting the connector
   -----------------------------------------------------------------------------
   Run as OF_SHAREPOINT_ADMIN.

   After this: install + start the Microsoft SharePoint (Cortex Connect)
   connector in Openflow UI, wait for rows in DOC_METADATA, then run
   04_ai_pipeline.sql.

   Connector: Microsoft SharePoint (Cortex Connect)
   Config reference (set via right-click canvas background → Configure → Properties):

     SharePoint connection:
       Site URL:       https://oceancloudtech.sharepoint.com/sites/openflowdemo
       Client ID:      bf21144d-ff46-4f2a-a85a-5b712... (Entra app "snowflake-openflow-sharepoint")
       Client Secret:  (sensitive — set in parameter context)
       Tenant ID:      cc43eda7-53cf-4c89-8150-957c3653364d
       Domain:         oceancloudtech.sharepoint.com

     ACL / group resolution (required when Site Groups = true):
       Application Private Key:  contents of keys/key.pem
       Application Certificate:  contents of keys/cert.pem

     Snowflake destination:
       Database:     OF_SHAREPOINT
       Schema:       DOCS
       Auth:         SNOWFLAKE_MANAGED
       Role:         OF_SHAREPOINT_RUNTIME_ROLE
       Cortex Search Service User Role: OF_SHAREPOINT_RUNTIME_ROLE
       Warehouse:    OF_SHAREPOINT_WH
       Library:      Documents
       Extensions:   pdf,xlsx
       Site Groups:  true
   ============================================================================= */

USE ROLE OF_SHAREPOINT_ADMIN;
USE DATABASE OF_SHAREPOINT;
USE SCHEMA DOCS;
USE WAREHOUSE OF_SHAREPOINT_WH;

/* These are all idempotent — safe to re-run */
GRANT USAGE ON DATABASE OF_SHAREPOINT
    TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;

GRANT USAGE ON SCHEMA OF_SHAREPOINT.DOCS
    TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;

GRANT CREATE TABLE, CREATE DYNAMIC TABLE, CREATE STAGE,
      CREATE SEQUENCE, CREATE CORTEX SEARCH SERVICE
    ON SCHEMA OF_SHAREPOINT.DOCS
    TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;

GRANT USAGE, OPERATE ON WAREHOUSE OF_SHAREPOINT_WH
    TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;
