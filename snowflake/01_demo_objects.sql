/* =============================================================================
   01_demo_objects.sql — warehouses, database, schemas, grants
   -----------------------------------------------------------------------------
   Run as SYSADMIN (which 00_account_setup.sql put above both custom roles).

   Ownership model:
     SYSADMIN              creates the database and warehouses
     OPENFLOW_DEMO_ADMIN   receives ownership, then creates schemas and objects

   The database-level Iceberg settings are load-bearing: the Openflow
   SharePoint connector READS them at runtime to decide where Iceberg files go.
   Getting them wrong means a full connector reset.
   ============================================================================= */

USE ROLE SYSADMIN;

/* -----------------------------------------------------------------------------
   STEP 1 — Warehouses
   -------------------------------------------------------------------------- */
CREATE WAREHOUSE IF NOT EXISTS OPENFLOW_DEMO_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND   = 60
    AUTO_RESUME    = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Interactive querying and verification during the demo';

CREATE WAREHOUSE IF NOT EXISTS OPENFLOW_DEMO_INGEST_WH
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND   = 60
    AUTO_RESUME    = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Openflow connector and AI_EXTRACT task. '
           || 'Deliberately small: AI_EXTRACT gains nothing above MEDIUM.';

/* -----------------------------------------------------------------------------
   STEP 2 — Database, with Iceberg defaults

   EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED' is a RESERVED VALUE, not an object you
   create. No CREATE EXTERNAL VOLUME, no Azure consent, no IAM role assignment.

   STORAGE_SERIALIZATION_POLICY = COMPATIBLE produces Parquet that external
   engines can read.

   Do NOT set CATALOG at the database level. The Openflow connector sets
   CATALOG = 'SNOWFLAKE' on every CREATE ICEBERG TABLE it issues.
   -------------------------------------------------------------------------- */
CREATE DATABASE IF NOT EXISTS OPENFLOW_DEMO
    COMMENT = 'SharePoint Openflow ingestion demo';

/* -----------------------------------------------------------------------------
   STEP 3 — Hand ownership to the demo role
   -------------------------------------------------------------------------- */
GRANT OWNERSHIP ON DATABASE OPENFLOW_DEMO
    TO ROLE OPENFLOW_DEMO_ADMIN COPY CURRENT GRANTS;

GRANT OWNERSHIP ON WAREHOUSE OPENFLOW_DEMO_WH
    TO ROLE OPENFLOW_DEMO_ADMIN COPY CURRENT GRANTS;

GRANT OWNERSHIP ON WAREHOUSE OPENFLOW_DEMO_INGEST_WH
    TO ROLE OPENFLOW_DEMO_ADMIN COPY CURRENT GRANTS;

/* -----------------------------------------------------------------------------
   STEP 4 — Everything below runs as the owning role
   -------------------------------------------------------------------------- */
USE ROLE OPENFLOW_DEMO_ADMIN;

ALTER DATABASE OPENFLOW_DEMO SET
    EXTERNAL_VOLUME              = 'SNOWFLAKE_MANAGED'
    STORAGE_SERIALIZATION_POLICY = COMPATIBLE
    ICEBERG_VERSION_DEFAULT      = 3;

USE DATABASE OPENFLOW_DEMO;

/* -----------------------------------------------------------------------------
   STEP 5 — Schemas
   -------------------------------------------------------------------------- */
CREATE SCHEMA IF NOT EXISTS SHAREPOINT_DOCS
    COMMENT = 'Openflow SharePoint documents, ACLs, AI extraction';

CREATE SCHEMA IF NOT EXISTS OBSERVABILITY
    COMMENT = 'Event table, alerts, and monitoring';

DROP SCHEMA IF EXISTS PUBLIC;

/* -----------------------------------------------------------------------------
   STEP 6 — Verify
   -------------------------------------------------------------------------- */
SHOW PARAMETERS LIKE 'EXTERNAL_VOLUME'              IN DATABASE OPENFLOW_DEMO;
SHOW PARAMETERS LIKE 'STORAGE_SERIALIZATION_POLICY' IN DATABASE OPENFLOW_DEMO;
SHOW PARAMETERS LIKE 'ICEBERG_VERSION_DEFAULT'      IN DATABASE OPENFLOW_DEMO;

SHOW SCHEMAS IN DATABASE OPENFLOW_DEMO;
SHOW WAREHOUSES LIKE 'OPENFLOW_DEMO%';

/* Smoke-test Snowflake-managed Iceberg */
CREATE OR REPLACE ICEBERG TABLE OPENFLOW_DEMO.OBSERVABILITY.ICEBERG_SMOKE_TEST (
    ID   INT,
    NOTE STRING,
    BLOB VARIANT
)
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3;

INSERT INTO OPENFLOW_DEMO.OBSERVABILITY.ICEBERG_SMOKE_TEST
    SELECT 1, 'iceberg v3 ok', PARSE_JSON('{"variant":"works"}');

SELECT * FROM OPENFLOW_DEMO.OBSERVABILITY.ICEBERG_SMOKE_TEST;

SHOW PARAMETERS LIKE 'ICEBERG_VERSION'
    IN TABLE OPENFLOW_DEMO.OBSERVABILITY.ICEBERG_SMOKE_TEST;

DROP TABLE OPENFLOW_DEMO.OBSERVABILITY.ICEBERG_SMOKE_TEST;
