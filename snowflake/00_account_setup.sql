/* =============================================================================
   00_account_setup.sql - account-level roles and privileges
   -----------------------------------------------------------------------------
   Run as ACCOUNTADMIN on SFSENORTHAMERICA-DMICHALK_AZURE (Azure East US 2).

   Creates two roles, both granted to DMICHALK:
     OPENFLOW_ADMIN            administers Openflow deployments + runtimes
     OPENFLOW_DEMO_ADMIN       owns the demo database and objects

   A third role, OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME, is ALSO created
   here. Openflow does NOT create it for you — the Create Runtime dialog
   requires a pre-existing role, and the flows inside the runtime execute as it.

   NO SERVICE USER AND NO KEY PAIR. Both connectors use SNOWFLAKE_MANAGED
   authentication, which requires Snowflake Username, Private Key, and Account
   Identifier to be BLANK - Openflow mints its own token bound to the runtime
   role. KEY_PAIR auth is BYOC-only, and BYOC is AWS-commercial only, so it is
   not reachable on this Azure account at all.

   Openflow login traps are handled in STEP 6.
   ============================================================================= */

USE ROLE ACCOUNTADMIN;

/* -----------------------------------------------------------------------------
   STEP 1 — Roles
   -------------------------------------------------------------------------- */
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS OPENFLOW_ADMIN
    COMMENT = 'Administers Openflow: deployments, runtimes, compute pools';

CREATE ROLE IF NOT EXISTS OPENFLOW_DEMO_ADMIN
    COMMENT = 'Owns OPENFLOW_DEMO database, schemas, and ingest objects';

CREATE ROLE IF NOT EXISTS OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME
    COMMENT = 'Identity for flows executing inside the OPENFLOW_DEMO_RUNTIME runtime';

/* -----------------------------------------------------------------------------
   STEP 2 — Openflow platform privileges
   -------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;

GRANT CREATE OPENFLOW DATA PLANE INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE OPENFLOW RUNTIME INTEGRATION    ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE OPENFLOW DEPLOYMENT             ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE COMPUTE POOL                    ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE ROLE                            ON ACCOUNT TO ROLE OPENFLOW_ADMIN;

-- GRANT APPLICATION ROLE SNOWFLAKE.OPENFLOW_ADMIN TO ROLE OPENFLOW_ADMIN;
-- ^ Only exists on accounts where Openflow is provisioned as a managed app.
--   Skip if it errors — the account-level OPENFLOW_ADMIN role is sufficient.

/* -----------------------------------------------------------------------------
   STEP 3 — Integration privileges for the demo admin
   -------------------------------------------------------------------------- */
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_DEMO_ADMIN;
GRANT EXECUTE TASK       ON ACCOUNT TO ROLE OPENFLOW_DEMO_ADMIN;
GRANT EXECUTE ALERT      ON ACCOUNT TO ROLE OPENFLOW_DEMO_ADMIN;

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE OPENFLOW_DEMO_ADMIN;

GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE OPENFLOW_DEMO_ADMIN;
GRANT MONITOR USAGE ON ACCOUNT TO ROLE OPENFLOW_DEMO_ADMIN;

/* -----------------------------------------------------------------------------
   STEP 4 — Role hierarchy: put both custom roles under SYSADMIN
   -------------------------------------------------------------------------- */
USE ROLE SECURITYADMIN;

GRANT ROLE OPENFLOW_ADMIN    TO ROLE SYSADMIN;
GRANT ROLE OPENFLOW_DEMO_ADMIN TO ROLE SYSADMIN;
GRANT ROLE OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME TO ROLE SYSADMIN;

GRANT ROLE OPENFLOW_RUNTIME_ROLE_OPENFLOW_DEMO_RUNTIME TO USER DMICHALK;

/* -----------------------------------------------------------------------------
   STEP 5 — Grant both roles to the operator
   -------------------------------------------------------------------------- */
GRANT ROLE OPENFLOW_ADMIN    TO USER DMICHALK;
GRANT ROLE OPENFLOW_DEMO_ADMIN TO USER DMICHALK;

/* -----------------------------------------------------------------------------
   STEP 6 — The three Openflow login traps
   -------------------------------------------------------------------------- */

/* TRAP 1: Openflow refuses a session whose active role is ACCOUNTADMIN. */
USE ROLE USERADMIN;
ALTER USER DMICHALK SET DEFAULT_ROLE = OPENFLOW_ADMIN;

/* TRAP 2: Openflow needs secondary roles enabled. */
ALTER USER DMICHALK SET DEFAULT_SECONDARY_ROLES = ('ALL');

/* TRAP 3: ORGADMIN must accept the Openflow terms of service ONCE per org.
     Snowsight → Data → Openflow → accept the terms as ORGADMIN */

/* -----------------------------------------------------------------------------
   STEP 7 — Verify
   -------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;

SHOW GRANTS TO ROLE OPENFLOW_ADMIN;
SHOW GRANTS TO ROLE OPENFLOW_DEMO_ADMIN;
SHOW GRANTS TO USER DMICHALK;

SHOW GRANTS OF ROLE OPENFLOW_DEMO_ADMIN;
SHOW GRANTS OF ROLE OPENFLOW_ADMIN;

SELECT CURRENT_REGION(), CURRENT_ACCOUNT(), CURRENT_ORGANIZATION_NAME();
