/* =============================================================================
   02_openflow_deployment.sql — Gen 2 deployment + runtime
   -----------------------------------------------------------------------------
   Run as OF_SHAREPOINT_ADMIN.
   ============================================================================= */

USE ROLE OF_SHAREPOINT_ADMIN;
USE DATABASE OF_SHAREPOINT;

/* --- Network rule + EAI for SharePoint egress --- */
CREATE NETWORK RULE IF NOT EXISTS OF_SHAREPOINT.OPENFLOW.NR_SHAREPOINT
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('oceancloudtech.sharepoint.com', 'login.microsoftonline.com', 'graph.microsoft.com');

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS OF_SHAREPOINT_EAI
    ALLOWED_NETWORK_RULES = (OF_SHAREPOINT.OPENFLOW.NR_SHAREPOINT)
    ENABLED = TRUE
    COMMENT = 'Openflow SharePoint connector — outbound to M365';

GRANT USAGE ON INTEGRATION OF_SHAREPOINT_EAI TO ROLE OF_SHAREPOINT_RUNTIME_ROLE;

/* --- Deployment --- */
GRANT CREATE OPENFLOW RUNTIME ON SCHEMA OF_SHAREPOINT.OPENFLOW TO ROLE OF_SHAREPOINT_ADMIN;

CREATE OPENFLOW DEPLOYMENT IF NOT EXISTS OF_SHAREPOINT_DEPLOYMENT
    COMMENT = 'Store ops SharePoint demo';

/* Wait for deployment to be ACTIVE (5-10 min) before creating runtime */
SELECT SYSTEM$WAIT_FOR_OPENFLOW_DEPLOYMENT_STATUS(
    600, 'ACTIVE', 'OF_SHAREPOINT_DEPLOYMENT');

/* --- Runtime --- */
CREATE OPENFLOW RUNTIME IF NOT EXISTS OF_SHAREPOINT.OPENFLOW.OF_SHAREPOINT_RUNTIME
    IN DEPLOYMENT OF_SHAREPOINT_DEPLOYMENT
    NODE_TYPE = SMALL
    NODE_TYPE_TIER = 'S1'
    MIN_NODES = 1
    MAX_NODES = 1
    EXECUTE_AS_ROLE = OF_SHAREPOINT_RUNTIME_ROLE
    EXTERNAL_ACCESS_INTEGRATIONS = (OF_SHAREPOINT_EAI)
    DISPLAY_NAME = 'Store Ops Demo Runtime'
    COMMENT = 'Runtime for the SharePoint store ops connector';

/* Wait for ACTIVE (3-5 min) */
SELECT SYSTEM$WAIT_FOR_OPENFLOW_RUNTIME_STATUS(
    600, 'ACTIVE', 'OF_SHAREPOINT.OPENFLOW.OF_SHAREPOINT_RUNTIME');

/* --- Verify --- */
SHOW OPENFLOW RUNTIMES IN SCHEMA OF_SHAREPOINT.OPENFLOW;
