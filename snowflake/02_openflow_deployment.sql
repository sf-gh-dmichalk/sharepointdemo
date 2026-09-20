/* =============================================================================
   02_openflow_deployment.sql — Gen 2 Openflow deployment + runtime
   -----------------------------------------------------------------------------
   Run as OPENFLOW_ADMIN.

   Creates the deployment and runtime entirely via SQL (gen 2).
   The execute-as role and EAI for SharePoint must exist first.
   ============================================================================= */

USE ROLE OPENFLOW_ADMIN;

/* -----------------------------------------------------------------------------
   STEP 1 — Database + schema to hold the gen 2 Openflow objects

   Gen 2 runtimes are schema-level objects. We put them in the demo database
   so 99_teardown.sql cleans them up with the rest.
   -------------------------------------------------------------------------- */
USE ROLE OPENFLOW_DEMO_ADMIN;
USE DATABASE OPENFLOW_DEMO;
CREATE SCHEMA IF NOT EXISTS OPENFLOW
    COMMENT = 'Gen 2 Openflow deployment and runtime objects';

/* The runtime role needs to use this schema */
GRANT USAGE ON SCHEMA OPENFLOW_DEMO.OPENFLOW
    TO ROLE OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME;

/* OPENFLOW_ADMIN needs access to create objects here */
GRANT USAGE ON DATABASE OPENFLOW_DEMO TO ROLE OPENFLOW_ADMIN;
GRANT USAGE, CREATE OPENFLOW RUNTIME ON SCHEMA OPENFLOW_DEMO.OPENFLOW TO ROLE OPENFLOW_ADMIN;

/* -----------------------------------------------------------------------------
   STEP 2 — External Access Integration for SharePoint

   The SharePoint connector needs outbound HTTPS to your tenant.
   -------------------------------------------------------------------------- */
USE ROLE OPENFLOW_DEMO_ADMIN;

CREATE NETWORK RULE IF NOT EXISTS OPENFLOW_DEMO.OPENFLOW.NR_SHAREPOINT
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('oceancloudtech.sharepoint.com', 'login.microsoftonline.com', 'graph.microsoft.com');

USE ROLE ACCOUNTADMIN;

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS EAI_OPENFLOW_SHAREPOINT
    ALLOWED_NETWORK_RULES = (OPENFLOW_DEMO.OPENFLOW.NR_SHAREPOINT)
    ENABLED = TRUE
    COMMENT = 'Openflow SharePoint connector — outbound to M365';

GRANT USAGE ON INTEGRATION EAI_OPENFLOW_SHAREPOINT TO ROLE OPENFLOW_ADMIN;
GRANT USAGE ON INTEGRATION EAI_OPENFLOW_SHAREPOINT TO ROLE OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME;

/* -----------------------------------------------------------------------------
   STEP 3 — Deployment
   -------------------------------------------------------------------------- */
USE ROLE OPENFLOW_ADMIN;

CREATE OPENFLOW DEPLOYMENT IF NOT EXISTS OPENFLOW_DEMO_DEPLOYMENT
    COMMENT = 'Store ops SharePoint demo';

/* -----------------------------------------------------------------------------
   STEP 4 — Runtime

   NODE_TYPE SMALL / tier S1 is enough for a 10-doc SharePoint connector.
   EXECUTE_AS_ROLE is the pre-created runtime role from 00_account_setup.sql.
   -------------------------------------------------------------------------- */
CREATE OPENFLOW RUNTIME IF NOT EXISTS OPENFLOW_DEMO.OPENFLOW.OPENFLOW_DEMO_RUNTIME
    IN DEPLOYMENT OPENFLOW_DEMO_DEPLOYMENT
    NODE_TYPE = SMALL
    NODE_TYPE_TIER = 'S1'
    MIN_NODES = 1
    MAX_NODES = 1
    EXECUTE_AS_ROLE = OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME
    EXTERNAL_ACCESS_INTEGRATIONS = (EAI_OPENFLOW_SHAREPOINT)
    DISPLAY_NAME = 'Store Ops Demo Runtime'
    COMMENT = 'Runtime for the SharePoint store ops connector';

/* Wait for the runtime to come up (typically 3-5 min) */
SELECT SYSTEM$WAIT_FOR_OPENFLOW_RUNTIME_STATUS(
    600, 'ACTIVE', 'OPENFLOW_DEMO.OPENFLOW.OPENFLOW_DEMO_RUNTIME');

/* -----------------------------------------------------------------------------
   STEP 5 — Verify
   -------------------------------------------------------------------------- */
SHOW OPENFLOW RUNTIMES IN SCHEMA OPENFLOW_DEMO.OPENFLOW;
DESCRIBE OPENFLOW RUNTIME OPENFLOW_DEMO.OPENFLOW.OPENFLOW_DEMO_RUNTIME;

/* NOW: install the SharePoint connector on this runtime via the Openflow UI,
   configure it per the reference in 03_connector_grants.sql, and start it.
   Wait for 10 rows in DOC_METADATA, then run 04_ai_pipeline.sql. */
