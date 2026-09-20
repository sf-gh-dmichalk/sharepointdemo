/* =============================================================================
   00_account_setup.sql — roles and privileges
   -----------------------------------------------------------------------------
   Run as ACCOUNTADMIN.

   Two roles only:
     OF_SHAREPOINT_ADMIN         owns everything (database, warehouses,
                                 deployment, runtime, tasks, tables)
     OF_SHAREPOINT_RUNTIME_ROLE  execute-as identity for the Openflow runtime
                                 (Openflow requires this to be separate)

   Everything is namespaced to OF_SHAREPOINT_* so teardown never touches
   another demo's objects.
   ============================================================================= */

USE ROLE ACCOUNTADMIN;

/* --- Roles --- */
CREATE ROLE IF NOT EXISTS OF_SHAREPOINT_ADMIN
    COMMENT = 'Owns all objects for the SharePoint Openflow demo';

CREATE ROLE IF NOT EXISTS OF_SHAREPOINT_RUNTIME_ROLE
    COMMENT = 'Execute-as role for the Openflow runtime';

/* --- Hierarchy: both under SYSADMIN, both granted to DMICHALK --- */
USE ROLE SECURITYADMIN;
GRANT ROLE OF_SHAREPOINT_ADMIN        TO ROLE SYSADMIN;
GRANT ROLE OF_SHAREPOINT_RUNTIME_ROLE TO ROLE SYSADMIN;
GRANT ROLE OF_SHAREPOINT_ADMIN        TO USER DMICHALK;
GRANT ROLE OF_SHAREPOINT_RUNTIME_ROLE TO USER DMICHALK;

/* --- Account-level privileges for the admin role --- */
USE ROLE ACCOUNTADMIN;

-- Openflow
GRANT CREATE OPENFLOW DEPLOYMENT ON ACCOUNT TO ROLE OF_SHAREPOINT_ADMIN;
GRANT CREATE COMPUTE POOL        ON ACCOUNT TO ROLE OF_SHAREPOINT_ADMIN;

-- Database + warehouse (SYSADMIN creates, then hands ownership)
-- No account-level CREATE DATABASE grant needed — SYSADMIN does it in 01.

-- Integrations, tasks, alerts
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE OF_SHAREPOINT_ADMIN;
GRANT EXECUTE TASK       ON ACCOUNT TO ROLE OF_SHAREPOINT_ADMIN;
GRANT EXECUTE ALERT      ON ACCOUNT TO ROLE OF_SHAREPOINT_ADMIN;

-- Cortex AI
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE OF_SHAREPOINT_ADMIN;

-- Monitoring
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE OF_SHAREPOINT_ADMIN;
GRANT MONITOR USAGE ON ACCOUNT TO ROLE OF_SHAREPOINT_ADMIN;

/* --- Openflow login traps --- */
-- TRAP 1: Openflow refuses ACCOUNTADMIN as active role.
-- If DMICHALK's default is ACCOUNTADMIN, Openflow UI won't load.
-- Uncomment if needed:
-- USE ROLE USERADMIN;
-- ALTER USER DMICHALK SET DEFAULT_ROLE = OF_SHAREPOINT_ADMIN;

-- TRAP 2: Openflow needs secondary roles.
-- ALTER USER DMICHALK SET DEFAULT_SECONDARY_ROLES = ('ALL');

/* --- Verify --- */
SHOW GRANTS TO ROLE OF_SHAREPOINT_ADMIN;
SHOW GRANTS OF ROLE OF_SHAREPOINT_ADMIN;
