/* =============================================================================
   02_openflow_deployment.sql — Shared deployment + demo-specific runtime
   -----------------------------------------------------------------------------
   Deployment uses OPENFLOW_ADMIN (shared, survives demo teardown).
   Runtime + EAI use OF_SHAREPOINT_ADMIN (demo-specific, torn down with demo).

   IF NOT EXISTS everywhere — fully re-runnable, no-op on second run.
   ============================================================================= */

/* --- Shared deployment (OPENFLOW_ADMIN) --- */
USE ROLE OPENFLOW_ADMIN;

CREATE OPENFLOW DEPLOYMENT IF NOT EXISTS OF_DEPLOYMENT
    COMMENT = 'Shared Openflow deployment for demos';

SELECT SYSTEM$WAIT_FOR_OPENFLOW_DEPLOYMENT_STATUS(
    600, 'ACTIVE', 'OF_DEPLOYMENT');

/* --- Demo-specific: network rule + EAI --- */
USE ROLE OF_SHAREPOINT_ADMIN;
USE DATABASE OF_SHAREPOINT;

CREATE NETWORK RULE IF NOT EXISTS OF_SHAREPOINT.OPENFLOW.NR_SHAREPOINT
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('oceancloudtech.sharepoint.com', 'login.microsoftonline.com', 'graph.microsoft.com');

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS OF_SHAREPOINT_EAI
    ALLOWED_NETWORK_RULES = (OF_SHAREPOINT.OPENFLOW.NR_SHAREPOINT)
    ENABLED = TRUE
    COMMENT = 'Openflow SharePoint connector — outbound to M365';

GRANT USAGE ON INTEGRATION OF_SHAREPOINT_EAI TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;

/* --- Demo-specific runtime on the shared deployment --- */
GRANT CREATE OPENFLOW RUNTIME ON SCHEMA OF_SHAREPOINT.OPENFLOW TO ROLE OF_SHAREPOINT_ADMIN;

CREATE OPENFLOW RUNTIME IF NOT EXISTS OF_SHAREPOINT.OPENFLOW.OF_SHAREPOINT_RUNTIME
    IN DEPLOYMENT OF_DEPLOYMENT
    NODE_TYPE = SMALL
    NODE_TYPE_TIER = 'S1'
    MIN_NODES = 1
    MAX_NODES = 1
    EXECUTE_AS_ROLE = OF_SHAREPOINT_RUNTIME_ROLE
    EXTERNAL_ACCESS_INTEGRATIONS = (OF_SHAREPOINT_EAI)
    DISPLAY_NAME = 'OF_SHAREPOINT_RUNTIME'
    COMMENT = 'Runtime for the SharePoint store ops connector';

SELECT SYSTEM$WAIT_FOR_OPENFLOW_RUNTIME_STATUS(
    600, 'ACTIVE', 'OF_SHAREPOINT.OPENFLOW.OF_SHAREPOINT_RUNTIME');

SHOW OPENFLOW RUNTIMES IN SCHEMA OF_SHAREPOINT.OPENFLOW;
