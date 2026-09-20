/* =============================================================================
   03_ai_pipeline.sql — Run AFTER the connector has ingested documents
   -----------------------------------------------------------------------------
   Run as OPENFLOW_DEMO_ADMIN.

   Creates:
     1. DOC_EXTRACT_RAW         — Iceberg table for AI_CLASSIFY + AI_EXTRACT output
     2. TASK_CLASSIFY_AND_EXTRACT — scheduled task (every 2 min)
     3. INSPECTION_FINDINGS     — dynamic Iceberg table
     4. MAINTENANCE_ORDERS      — dynamic Iceberg table
     5. INCIDENT_REPORTS        — dynamic Iceberg table
     6. PLANOGRAM_FINDINGS      — dynamic Iceberg table

   Requires DOC_METADATA and the DOCUMENTS stage to exist (connector creates them).
   ============================================================================= */

USE ROLE OPENFLOW_DEMO_ADMIN;
USE DATABASE OPENFLOW_DEMO;
USE SCHEMA SHAREPOINT_DOCS;
USE WAREHOUSE OPENFLOW_DEMO_INGEST_WH;

ALTER STAGE DOCUMENTS SET DIRECTORY = (ENABLE = TRUE);
ALTER STAGE DOCUMENTS REFRESH;

/* =============================================================================
   STEP 1 — Raw extraction landing table
   ============================================================================= */

CREATE OR REPLACE ICEBERG TABLE DOC_EXTRACT_RAW (
    FILE_ID        STRING,
    FILE_NAME      STRING,
    RELATIVE_PATH  STRING,
    DOC_TYPE       STRING,       -- INSPECTION, MAINTENANCE, INCIDENT, PLANOGRAM
    EXTRACTED      VARIANT,      -- AI_EXTRACT response
    SCORES         VARIANT,      -- AI_EXTRACT scoring
    EXTRACT_ERROR  STRING,
    MODEL_VERSION  STRING,
    EXTRACT_TS     TIMESTAMP_NTZ(6)
)
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Raw AI_EXTRACT output for all store ops document types';

/* =============================================================================
   STEP 2 — Classification + extraction task

   Anti-join pattern: only processes docs not yet in DOC_EXTRACT_RAW.
   AI_CLASSIFY determines doc type, then AI_EXTRACT uses the right schema.

   No WHEN clause — STATE = SUCCEEDED with 0 rows is the healthy steady state.
   ============================================================================= */

CREATE OR REPLACE TASK TASK_CLASSIFY_AND_EXTRACT
    WAREHOUSE = OPENFLOW_DEMO_INGEST_WH
    SCHEDULE  = '2 MINUTE'
    COMMENT   = 'Classify new store ops documents and extract structured data'
AS
INSERT INTO DOC_EXTRACT_RAW (
    FILE_ID, FILE_NAME, RELATIVE_PATH, DOC_TYPE,
    EXTRACTED, SCORES, EXTRACT_ERROR, MODEL_VERSION, EXTRACT_TS
)
WITH new_docs AS (
    SELECT m.FILE_ID, m.FILE_NAME, m.STAGED_FILE_PATH
      FROM DOC_METADATA m
     WHERE NOT EXISTS (SELECT 1 FROM DOC_EXTRACT_RAW r WHERE r.FILE_ID = m.FILE_ID)
),
classified AS (
    SELECT
        d.FILE_ID,
        d.FILE_NAME,
        d.STAGED_FILE_PATH,
        AI_CLASSIFY(
            TO_FILE('@DOCUMENTS', d.STAGED_FILE_PATH),
            ['Inspection Report', 'Maintenance Work Order', 'Incident Report', 'Planogram Audit'],
            {'task_description': 'Classify retail store operations documents by type'}
        ):label::STRING AS DOC_LABEL
      FROM new_docs d
),
extracted AS (
    SELECT
        c.FILE_ID,
        c.FILE_NAME,
        c.STAGED_FILE_PATH,
        c.DOC_LABEL,
        AI_EXTRACT(
            file => TO_FILE('@DOCUMENTS', c.STAGED_FILE_PATH),
            responseFormat => CASE c.DOC_LABEL
                WHEN 'Inspection Report' THEN {
                    'schema': { 'type': 'object', 'properties': {
                        'store_number':   { 'description': 'Store number (e.g. #4421)', 'type': 'string' },
                        'store_location': { 'description': 'Store city and state', 'type': 'string' },
                        'inspection_date':{ 'description': 'Date of the inspection', 'type': 'string' },
                        'inspection_type':{ 'description': 'Type of inspection (food safety, health dept, fire)', 'type': 'string' },
                        'inspector_name': { 'description': 'Name of the inspector', 'type': 'string' },
                        'overall_result': { 'description': 'Overall result or score (PASS, CONDITIONAL PASS, FAIL, or numeric score)', 'type': 'string' },
                        'findings': {
                            'description': 'List of inspection findings',
                            'type': 'object',
                            'column_ordering': ['Severity', 'Description', 'Corrective Action'],
                            'properties': {
                                'Severity':         { 'description': 'Finding severity (Critical, Major, Minor, Observation, Violation, Compliant)', 'type': 'array' },
                                'Description':      { 'description': 'Description of the finding', 'type': 'array' },
                                'Corrective Action': { 'description': 'Corrective action taken or required', 'type': 'array' }
                            }
                        }
                    }}
                }
                WHEN 'Maintenance Work Order' THEN {
                    'schema': { 'type': 'object', 'properties': {
                        'wo_number':      { 'description': 'Work order number', 'type': 'string' },
                        'store_number':   { 'description': 'Store number', 'type': 'string' },
                        'store_location': { 'description': 'Store city and state', 'type': 'string' },
                        'date_opened':    { 'description': 'Date work order was opened', 'type': 'string' },
                        'date_closed':    { 'description': 'Date work order was closed, or OPEN', 'type': 'string' },
                        'priority':       { 'description': 'Priority level (EMERGENCY, HIGH, MEDIUM, LOW)', 'type': 'string' },
                        'category':       { 'description': 'Maintenance category (Refrigeration, HVAC, Plumbing, Electrical)', 'type': 'string' },
                        'equipment':      { 'description': 'Equipment description and model/serial if available', 'type': 'string' },
                        'description':    { 'description': 'Problem description', 'type': 'string' },
                        'resolution':     { 'description': 'Resolution or current status', 'type': 'string' },
                        'cost':           { 'description': 'Total cost including breakdown', 'type': 'string' },
                        'status':         { 'description': 'Current status (OPEN, CLOSED)', 'type': 'string' }
                    }}
                }
                WHEN 'Incident Report' THEN {
                    'schema': { 'type': 'object', 'properties': {
                        'store_number':   { 'description': 'Store number', 'type': 'string' },
                        'store_location': { 'description': 'Store city and state', 'type': 'string' },
                        'incident_date':  { 'description': 'Date and time of the incident', 'type': 'string' },
                        'incident_type':  { 'description': 'Type of incident (Slip & Fall, Equipment Failure, Theft, etc.)', 'type': 'string' },
                        'severity':       { 'description': 'Severity level (HIGH, MODERATE, LOW)', 'type': 'string' },
                        'reported_by':    { 'description': 'Name and title of person reporting', 'type': 'string' },
                        'description':    { 'description': 'Incident description', 'type': 'string' },
                        'root_cause':     { 'description': 'Root cause analysis', 'type': 'string' },
                        'corrective_actions': { 'description': 'Corrective actions taken', 'type': 'string' },
                        'estimated_cost': { 'description': 'Estimated cost or product loss', 'type': 'string' }
                    }}
                }
                ELSE {
                    'schema': { 'type': 'object', 'properties': {
                        'store_number':   { 'description': 'Store number', 'type': 'string' },
                        'store_location': { 'description': 'Store city and state', 'type': 'string' },
                        'audit_date':     { 'description': 'Date of the audit', 'type': 'string' },
                        'department':     { 'description': 'Department or aisle audited', 'type': 'string' },
                        'planogram_id':   { 'description': 'Planogram version identifier', 'type': 'string' },
                        'overall_compliance': { 'description': 'Overall compliance percentage', 'type': 'string' },
                        'findings': {
                            'description': 'Planogram compliance findings',
                            'type': 'object',
                            'column_ordering': ['Status', 'Description'],
                            'properties': {
                                'Status':      { 'description': 'COMPLIANT, NON-COMPLIANT, or OBSERVATION', 'type': 'array' },
                                'Description': { 'description': 'Finding description', 'type': 'array' }
                            }
                        }
                    }}
                }
            END,
            scores => TRUE
        ) AS RESULT
      FROM classified c
)
SELECT
    FILE_ID, FILE_NAME, STAGED_FILE_PATH,
    CASE DOC_LABEL
        WHEN 'Inspection Report'       THEN 'INSPECTION'
        WHEN 'Maintenance Work Order'  THEN 'MAINTENANCE'
        WHEN 'Incident Report'         THEN 'INCIDENT'
        WHEN 'Planogram Audit'         THEN 'PLANOGRAM'
        ELSE 'UNKNOWN'
    END,
    RESULT:response,
    RESULT:scoring,
    RESULT:error::STRING,
    'arctic-extract',
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(6)
  FROM extracted;

ALTER TASK TASK_CLASSIFY_AND_EXTRACT RESUME;


/* =============================================================================
   STEP 3 — Structured dynamic tables per document type
   ============================================================================= */

/* --- Inspection findings: one row per finding --- */
CREATE OR REPLACE DYNAMIC ICEBERG TABLE INSPECTION_FINDINGS
    TARGET_LAG      = '5 minutes'
    WAREHOUSE       = OPENFLOW_DEMO_INGEST_WH
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Structured inspection findings -- one row per finding'
AS
SELECT
    r.FILE_ID,
    r.FILE_NAME,
    r.EXTRACTED:store_number::STRING       AS STORE_NUMBER,
    r.EXTRACTED:store_location::STRING     AS STORE_LOCATION,
    r.EXTRACTED:inspection_date::STRING    AS INSPECTION_DATE,
    r.EXTRACTED:inspection_type::STRING    AS INSPECTION_TYPE,
    r.EXTRACTED:inspector_name::STRING     AS INSPECTOR_NAME,
    r.EXTRACTED:overall_result::STRING     AS OVERALL_RESULT,
    s.value::STRING                        AS SEVERITY,
    d.value::STRING                        AS FINDING_DESCRIPTION,
    c.value::STRING                        AS CORRECTIVE_ACTION,
    r.EXTRACT_TS
  FROM DOC_EXTRACT_RAW r,
       LATERAL FLATTEN(input => r.EXTRACTED:findings:"Severity")          s,
       LATERAL FLATTEN(input => r.EXTRACTED:findings:"Description")       d,
       LATERAL FLATTEN(input => r.EXTRACTED:findings:"Corrective Action") c
 WHERE r.DOC_TYPE = 'INSPECTION'
   AND s.index = d.index
   AND s.index = c.index;

/* --- Maintenance work orders: one row per WO --- */
CREATE OR REPLACE DYNAMIC ICEBERG TABLE MAINTENANCE_ORDERS
    TARGET_LAG      = '5 minutes'
    WAREHOUSE       = OPENFLOW_DEMO_INGEST_WH
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Structured maintenance work orders'
AS
SELECT
    r.FILE_ID,
    r.FILE_NAME,
    r.EXTRACTED:wo_number::STRING          AS WO_NUMBER,
    r.EXTRACTED:store_number::STRING       AS STORE_NUMBER,
    r.EXTRACTED:store_location::STRING     AS STORE_LOCATION,
    r.EXTRACTED:date_opened::STRING        AS DATE_OPENED,
    r.EXTRACTED:date_closed::STRING        AS DATE_CLOSED,
    r.EXTRACTED:priority::STRING           AS PRIORITY,
    r.EXTRACTED:category::STRING           AS CATEGORY,
    r.EXTRACTED:equipment::STRING          AS EQUIPMENT,
    r.EXTRACTED:description::STRING        AS PROBLEM_DESCRIPTION,
    r.EXTRACTED:resolution::STRING         AS RESOLUTION,
    r.EXTRACTED:cost::STRING               AS COST,
    r.EXTRACTED:status::STRING             AS STATUS,
    r.EXTRACT_TS
  FROM DOC_EXTRACT_RAW r
 WHERE r.DOC_TYPE = 'MAINTENANCE';

/* --- Incident reports: one row per incident --- */
CREATE OR REPLACE DYNAMIC ICEBERG TABLE INCIDENT_REPORTS
    TARGET_LAG      = '5 minutes'
    WAREHOUSE       = OPENFLOW_DEMO_INGEST_WH
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Structured store incident reports'
AS
SELECT
    r.FILE_ID,
    r.FILE_NAME,
    r.EXTRACTED:store_number::STRING       AS STORE_NUMBER,
    r.EXTRACTED:store_location::STRING     AS STORE_LOCATION,
    r.EXTRACTED:incident_date::STRING      AS INCIDENT_DATE,
    r.EXTRACTED:incident_type::STRING      AS INCIDENT_TYPE,
    r.EXTRACTED:severity::STRING           AS SEVERITY,
    r.EXTRACTED:reported_by::STRING        AS REPORTED_BY,
    r.EXTRACTED:description::STRING        AS DESCRIPTION,
    r.EXTRACTED:root_cause::STRING         AS ROOT_CAUSE,
    r.EXTRACTED:corrective_actions::STRING AS CORRECTIVE_ACTIONS,
    r.EXTRACTED:estimated_cost::STRING     AS ESTIMATED_COST,
    r.EXTRACT_TS
  FROM DOC_EXTRACT_RAW r
 WHERE r.DOC_TYPE = 'INCIDENT';

/* --- Planogram compliance: one row per finding --- */
CREATE OR REPLACE DYNAMIC ICEBERG TABLE PLANOGRAM_FINDINGS
    TARGET_LAG      = '5 minutes'
    WAREHOUSE       = OPENFLOW_DEMO_INGEST_WH
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Structured planogram compliance findings'
AS
SELECT
    r.FILE_ID,
    r.FILE_NAME,
    r.EXTRACTED:store_number::STRING           AS STORE_NUMBER,
    r.EXTRACTED:store_location::STRING         AS STORE_LOCATION,
    r.EXTRACTED:audit_date::STRING             AS AUDIT_DATE,
    r.EXTRACTED:department::STRING             AS DEPARTMENT,
    r.EXTRACTED:planogram_id::STRING           AS PLANOGRAM_ID,
    r.EXTRACTED:overall_compliance::STRING     AS OVERALL_COMPLIANCE,
    s.value::STRING                            AS COMPLIANCE_STATUS,
    d.value::STRING                            AS FINDING_DESCRIPTION,
    r.EXTRACT_TS
  FROM DOC_EXTRACT_RAW r,
       LATERAL FLATTEN(input => r.EXTRACTED:findings:"Status")      s,
       LATERAL FLATTEN(input => r.EXTRACTED:findings:"Description") d
 WHERE r.DOC_TYPE = 'PLANOGRAM'
   AND s.index = d.index;


/* =============================================================================
   VERIFICATION
   ============================================================================= */

-- Task health
SELECT SCHEDULED_TIME, STATE, ERROR_CODE, ERROR_MESSAGE
  FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'TASK_CLASSIFY_AND_EXTRACT'))
 ORDER BY SCHEDULED_TIME DESC LIMIT 10;

-- Classification results
SELECT DOC_TYPE, COUNT(*) AS DOCS
  FROM DOC_EXTRACT_RAW
 GROUP BY DOC_TYPE ORDER BY DOCS DESC;

-- Inspection findings
SELECT STORE_NUMBER, INSPECTION_DATE, SEVERITY, FINDING_DESCRIPTION
  FROM INSPECTION_FINDINGS
 ORDER BY STORE_NUMBER, INSPECTION_DATE;

-- Open maintenance orders
SELECT WO_NUMBER, STORE_NUMBER, CATEGORY, PRIORITY, STATUS
  FROM MAINTENANCE_ORDERS
 ORDER BY PRIORITY DESC;

-- Incidents by severity
SELECT STORE_NUMBER, INCIDENT_TYPE, SEVERITY, INCIDENT_DATE
  FROM INCIDENT_REPORTS
 ORDER BY SEVERITY;

-- Planogram non-compliance
SELECT STORE_NUMBER, DEPARTMENT, OVERALL_COMPLIANCE, COMPLIANCE_STATUS, FINDING_DESCRIPTION
  FROM PLANOGRAM_FINDINGS
 WHERE COMPLIANCE_STATUS = 'NON-COMPLIANT';

-- Cross-document: stores with critical findings AND open maintenance
SELECT DISTINCT i.STORE_NUMBER, i.SEVERITY, i.FINDING_DESCRIPTION, m.WO_NUMBER, m.CATEGORY
  FROM INSPECTION_FINDINGS i
  JOIN MAINTENANCE_ORDERS m ON i.STORE_NUMBER = m.STORE_NUMBER
 WHERE i.SEVERITY IN ('Critical', 'Major', 'Violation 3-501.16', 'Violation 4-601.11')
   AND m.STATUS = 'OPEN';

/* LIVE ADD — upload food_safety_inspection_store_4421_2026-08-12.pdf to
   Inspections/ in SharePoint. Within ~7 minutes:
     DOC_EXTRACT_RAW      +1 row (classified as INSPECTION)
     INSPECTION_FINDINGS  +4 rows (the follow-up findings)
   The follow-up inspection confirms repairs from the 7/15 findings —
   the story closes itself with no manual step. */
