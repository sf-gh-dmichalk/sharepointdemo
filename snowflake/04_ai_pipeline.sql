/* =============================================================================
   04_ai_pipeline.sql — Run AFTER the connector has ingested documents
   -----------------------------------------------------------------------------
   Run as OF_SHAREPOINT_ADMIN.

   The Cortex Connect connector creates:
     DOCS_CHUNKS          — chunked + OCR'd text per document
     DOCUMENTS stage      — raw PDFs keyed by SharePoint doc ID
     FILE_HASHES          — maps DOC_ID to stage file path
     CORTEX_SEARCH_SERVICE — ACL-aware Cortex Search over raw chunks

   This script adds structured extraction on top:
     STEP 0: Post-connector grants
     STEP 1: Verify connector output
     STEP 2: DOC_CLASSIFY_RAW — classification landing table
     STEP 3: TASK_CLASSIFY_DOCS — AI_CLASSIFY task
     STEP 4: DOC_EXTRACT_RAW — extraction landing table
     STEP 5: 4 extraction tasks — one per doc type
     STEP 6: 4 dynamic Iceberg tables — structured output
     STEP 7: STORE_OPS_SEARCH — Cortex Search over structured findings
   ============================================================================= */

USE ROLE OF_SHAREPOINT_ADMIN;
USE DATABASE OF_SHAREPOINT;
USE SCHEMA DOCS;
USE WAREHOUSE OF_SHAREPOINT_WH;

/* =============================================================================
   STEP 0 — Post-connector grants

   The connector owns tables and the DOCUMENTS stage. Without these grants
   our tasks fail silently (no secondary roles in task context).
   ============================================================================= */
USE ROLE ACCOUNTADMIN;

GRANT SELECT ON ALL TABLES IN SCHEMA OF_SHAREPOINT.DOCS
    TO ROLE OF_SHAREPOINT_ADMIN;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA OF_SHAREPOINT.DOCS
    TO ROLE OF_SHAREPOINT_ADMIN;
GRANT READ ON STAGE OF_SHAREPOINT.DOCS.DOCUMENTS
    TO ROLE OF_SHAREPOINT_ADMIN;

USE ROLE OF_SHAREPOINT_ADMIN;

/* =============================================================================
   STEP 1 — Verify connector output
   ============================================================================= */
SHOW STAGES IN SCHEMA OF_SHAREPOINT.DOCS;
SHOW TABLES IN SCHEMA OF_SHAREPOINT.DOCS;

SELECT COUNT(*) AS STAGE_FILES FROM DIRECTORY('@DOCUMENTS');
SELECT COUNT(DISTINCT METADATA:id::STRING) AS CHUNKED_DOCS FROM DOCS_CHUNKS;
SELECT COUNT(*) AS FILE_HASHES FROM FILE_HASHES;

/* =============================================================================
   STEP 2 — Classification table

   FILE_ID  = SharePoint doc ID (e.g. 01F5IH3H7MTMF6...)
   FILE_NAME = original filename from METADATA:fullName
   STAGED_FILE_PATH = path in DOCUMENTS stage (FILE_HASHES.DOC_ID)
   ============================================================================= */
CREATE OR REPLACE ICEBERG TABLE DOC_CLASSIFY_RAW (
    FILE_ID        STRING,
    FILE_NAME      STRING,
    STAGED_FILE_PATH STRING,
    DOC_TYPE       STRING,       -- INSPECTION, MAINTENANCE, INCIDENT, PLANOGRAM
    CLASSIFY_LABEL STRING,       -- raw AI_CLASSIFY label
    CLASSIFY_TS    TIMESTAMP_NTZ(6)
)
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'AI_CLASSIFY output — one row per document';

/* =============================================================================
   STEP 3 — Classification task (every 2 min)

   Joins DOCS_CHUNKS (distinct docs) to FILE_HASHES (stage path).
   Anti-join: only classifies docs not yet in DOC_CLASSIFY_RAW.
   ============================================================================= */
CREATE OR REPLACE TASK TASK_CLASSIFY_DOCS
    WAREHOUSE = OF_SHAREPOINT_WH
    SCHEDULE  = '2 MINUTE'
    COMMENT   = 'Classify new store ops documents by type'
AS
INSERT INTO DOC_CLASSIFY_RAW (FILE_ID, FILE_NAME, STAGED_FILE_PATH, DOC_TYPE, CLASSIFY_LABEL, CLASSIFY_TS)
SELECT
    FILE_ID,
    FILE_NAME,
    STAGED_FILE_PATH,
    CASE label
        WHEN 'Inspection Report'       THEN 'INSPECTION'
        WHEN 'Maintenance Work Order'  THEN 'MAINTENANCE'
        WHEN 'Incident Report'         THEN 'INCIDENT'
        WHEN 'Planogram Audit'         THEN 'PLANOGRAM'
        ELSE 'UNKNOWN'
    END,
    label,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(6)
FROM (
    SELECT
        FILE_ID,
        FILE_NAME,
        STAGED_FILE_PATH,
        AI_CLASSIFY(
            TO_FILE('@DOCUMENTS', STAGED_FILE_PATH),
            ['Inspection Report', 'Maintenance Work Order', 'Incident Report', 'Planogram Audit'],
            {'task_description': 'Classify retail store operations documents by type'}
        ):labels[0]::STRING AS label
    FROM (
        SELECT DISTINCT
            c.METADATA:id::STRING AS FILE_ID,
            REGEXP_SUBSTR(c.METADATA:fullName::STRING, '[^/]+$') AS FILE_NAME,
            REGEXP_REPLACE(h.DOC_ID, '-', '_', 1, 1) AS STAGED_FILE_PATH
        FROM DOCS_CHUNKS c
        JOIN FILE_HASHES h
          ON h.DOC_ID LIKE c.METADATA:id::STRING || '%'
    )
    WHERE NOT EXISTS (SELECT 1 FROM DOC_CLASSIFY_RAW cr WHERE cr.FILE_ID = FILE_ID)
) sub;

ALTER TASK TASK_CLASSIFY_DOCS RESUME;

/* =============================================================================
   STEP 4 — Extraction landing table
   ============================================================================= */
CREATE OR REPLACE ICEBERG TABLE DOC_EXTRACT_RAW (
    FILE_ID        STRING,
    FILE_NAME      STRING,
    RELATIVE_PATH  STRING,
    DOC_TYPE       STRING,
    EXTRACTED      VARIANT,
    SCORES         VARIANT,
    EXTRACT_ERROR  STRING,
    MODEL_VERSION  STRING,
    EXTRACT_TS     TIMESTAMP_NTZ(6)
)
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Raw AI_EXTRACT output for all store ops document types';

/* =============================================================================
   STEP 5 — One extraction task per document type

   Each task has its own AI_EXTRACT responseFormat. Anti-join against
   DOC_EXTRACT_RAW so each doc is only extracted once.

   All 4 tasks are children of TASK_CLASSIFY_DOCS — they fire after it.
   ============================================================================= */

/* --- Inspections --- */
CREATE OR REPLACE TASK TASK_EXTRACT_INSPECTIONS
    WAREHOUSE = OF_SHAREPOINT_WH
    AFTER TASK_CLASSIFY_DOCS
AS
INSERT INTO DOC_EXTRACT_RAW (FILE_ID, FILE_NAME, RELATIVE_PATH, DOC_TYPE, EXTRACTED, SCORES, EXTRACT_ERROR, MODEL_VERSION, EXTRACT_TS)
SELECT
    c.FILE_ID, c.FILE_NAME, c.STAGED_FILE_PATH, c.DOC_TYPE,
    r.RESULT:response, r.RESULT:scoring, r.RESULT:error::STRING,
    'arctic-extract', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(6)
FROM DOC_CLASSIFY_RAW c,
     LATERAL (
         SELECT AI_EXTRACT(
             file => TO_FILE('@DOCUMENTS', c.STAGED_FILE_PATH),
             responseFormat => {
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
                             'Severity':          { 'description': 'Finding severity (Critical, Major, Minor, Observation, Violation, Compliant)', 'type': 'array' },
                             'Description':       { 'description': 'Description of the finding', 'type': 'array' },
                             'Corrective Action': { 'description': 'Corrective action taken or required', 'type': 'array' }
                         }
                     }
                 }}
             },
             scores => TRUE
         ) AS RESULT
     ) r
WHERE c.DOC_TYPE = 'INSPECTION'
  AND NOT EXISTS (SELECT 1 FROM DOC_EXTRACT_RAW e WHERE e.FILE_ID = c.FILE_ID);

ALTER TASK TASK_EXTRACT_INSPECTIONS RESUME;

/* --- Maintenance Work Orders --- */
CREATE OR REPLACE TASK TASK_EXTRACT_MAINTENANCE
    WAREHOUSE = OF_SHAREPOINT_WH
    AFTER TASK_CLASSIFY_DOCS
AS
INSERT INTO DOC_EXTRACT_RAW (FILE_ID, FILE_NAME, RELATIVE_PATH, DOC_TYPE, EXTRACTED, SCORES, EXTRACT_ERROR, MODEL_VERSION, EXTRACT_TS)
SELECT
    c.FILE_ID, c.FILE_NAME, c.STAGED_FILE_PATH, c.DOC_TYPE,
    r.RESULT:response, r.RESULT:scoring, r.RESULT:error::STRING,
    'arctic-extract', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(6)
FROM DOC_CLASSIFY_RAW c,
     LATERAL (
         SELECT AI_EXTRACT(
             file => TO_FILE('@DOCUMENTS', c.STAGED_FILE_PATH),
             responseFormat => {
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
             },
             scores => TRUE
         ) AS RESULT
     ) r
WHERE c.DOC_TYPE = 'MAINTENANCE'
  AND NOT EXISTS (SELECT 1 FROM DOC_EXTRACT_RAW e WHERE e.FILE_ID = c.FILE_ID);

ALTER TASK TASK_EXTRACT_MAINTENANCE RESUME;

/* --- Incident Reports --- */
CREATE OR REPLACE TASK TASK_EXTRACT_INCIDENTS
    WAREHOUSE = OF_SHAREPOINT_WH
    AFTER TASK_CLASSIFY_DOCS
AS
INSERT INTO DOC_EXTRACT_RAW (FILE_ID, FILE_NAME, RELATIVE_PATH, DOC_TYPE, EXTRACTED, SCORES, EXTRACT_ERROR, MODEL_VERSION, EXTRACT_TS)
SELECT
    c.FILE_ID, c.FILE_NAME, c.STAGED_FILE_PATH, c.DOC_TYPE,
    r.RESULT:response, r.RESULT:scoring, r.RESULT:error::STRING,
    'arctic-extract', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(6)
FROM DOC_CLASSIFY_RAW c,
     LATERAL (
         SELECT AI_EXTRACT(
             file => TO_FILE('@DOCUMENTS', c.STAGED_FILE_PATH),
             responseFormat => {
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
             },
             scores => TRUE
         ) AS RESULT
     ) r
WHERE c.DOC_TYPE = 'INCIDENT'
  AND NOT EXISTS (SELECT 1 FROM DOC_EXTRACT_RAW e WHERE e.FILE_ID = c.FILE_ID);

ALTER TASK TASK_EXTRACT_INCIDENTS RESUME;

/* --- Planogram Audits --- */
CREATE OR REPLACE TASK TASK_EXTRACT_PLANOGRAMS
    WAREHOUSE = OF_SHAREPOINT_WH
    AFTER TASK_CLASSIFY_DOCS
AS
INSERT INTO DOC_EXTRACT_RAW (FILE_ID, FILE_NAME, RELATIVE_PATH, DOC_TYPE, EXTRACTED, SCORES, EXTRACT_ERROR, MODEL_VERSION, EXTRACT_TS)
SELECT
    c.FILE_ID, c.FILE_NAME, c.STAGED_FILE_PATH, c.DOC_TYPE,
    r.RESULT:response, r.RESULT:scoring, r.RESULT:error::STRING,
    'arctic-extract', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(6)
FROM DOC_CLASSIFY_RAW c,
     LATERAL (
         SELECT AI_EXTRACT(
             file => TO_FILE('@DOCUMENTS', c.STAGED_FILE_PATH),
             responseFormat => {
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
             },
             scores => TRUE
         ) AS RESULT
     ) r
WHERE c.DOC_TYPE = 'PLANOGRAM'
  AND NOT EXISTS (SELECT 1 FROM DOC_EXTRACT_RAW e WHERE e.FILE_ID = c.FILE_ID);

ALTER TASK TASK_EXTRACT_PLANOGRAMS RESUME;


/* =============================================================================
   STEP 6 — Structured dynamic tables per document type
   ============================================================================= */

CREATE OR REPLACE DYNAMIC ICEBERG TABLE INSPECTION_FINDINGS
    TARGET_LAG      = '5 minutes'
    WAREHOUSE       = OF_SHAREPOINT_WH
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Structured inspection findings -- one row per finding'
AS
SELECT
    r.FILE_ID, r.FILE_NAME,
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

CREATE OR REPLACE DYNAMIC ICEBERG TABLE MAINTENANCE_ORDERS
    TARGET_LAG      = '5 minutes'
    WAREHOUSE       = OF_SHAREPOINT_WH
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Structured maintenance work orders'
AS
SELECT
    r.FILE_ID, r.FILE_NAME,
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

CREATE OR REPLACE DYNAMIC ICEBERG TABLE INCIDENT_REPORTS
    TARGET_LAG      = '5 minutes'
    WAREHOUSE       = OF_SHAREPOINT_WH
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Structured store incident reports'
AS
SELECT
    r.FILE_ID, r.FILE_NAME,
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

CREATE OR REPLACE DYNAMIC ICEBERG TABLE PLANOGRAM_FINDINGS
    TARGET_LAG      = '5 minutes'
    WAREHOUSE       = OF_SHAREPOINT_WH
    CATALOG         = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'Structured planogram compliance findings'
AS
SELECT
    r.FILE_ID, r.FILE_NAME,
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
   STEP 7 — Cortex Search: structured findings search

   The connector already creates CORTEX_SEARCH_SERVICE for raw document
   search with ACL filtering. This additional service indexes the structured
   extraction output — store numbers, doc types, severity levels, and
   finding descriptions from the dynamic tables.
   ============================================================================= */

CREATE OR REPLACE CORTEX SEARCH SERVICE STORE_OPS_SEARCH
    ON search_text
    ATTRIBUTES store_number, doc_type, severity
    WAREHOUSE = OF_SHAREPOINT_WH
    TARGET_LAG = '1 hour'
    COMMENT = 'Hybrid search over structured store ops findings'
AS (
    /* Inspections */
    SELECT
        STORE_NUMBER,
        'INSPECTION' AS DOC_TYPE,
        SEVERITY,
        FINDING_DESCRIPTION || ' — ' || COALESCE(CORRECTIVE_ACTION, '') AS search_text,
        FILE_NAME,
        INSPECTION_DATE AS EVENT_DATE
    FROM INSPECTION_FINDINGS

    UNION ALL

    /* Maintenance */
    SELECT
        STORE_NUMBER,
        'MAINTENANCE' AS DOC_TYPE,
        PRIORITY AS SEVERITY,
        WO_NUMBER || ': ' || PROBLEM_DESCRIPTION || ' — ' || COALESCE(RESOLUTION, '') AS search_text,
        FILE_NAME,
        DATE_OPENED AS EVENT_DATE
    FROM MAINTENANCE_ORDERS

    UNION ALL

    /* Incidents */
    SELECT
        STORE_NUMBER,
        'INCIDENT' AS DOC_TYPE,
        SEVERITY,
        INCIDENT_TYPE || ': ' || DESCRIPTION || ' — ' || COALESCE(ROOT_CAUSE, '') AS search_text,
        FILE_NAME,
        INCIDENT_DATE AS EVENT_DATE
    FROM INCIDENT_REPORTS

    UNION ALL

    /* Planograms */
    SELECT
        STORE_NUMBER,
        'PLANOGRAM' AS DOC_TYPE,
        COMPLIANCE_STATUS AS SEVERITY,
        DEPARTMENT || ': ' || FINDING_DESCRIPTION AS search_text,
        FILE_NAME,
        AUDIT_DATE AS EVENT_DATE
    FROM PLANOGRAM_FINDINGS
);


/* =============================================================================
   VERIFICATION
   ============================================================================= */

/* --- Connector's built-in Cortex Search (raw docs + ACLs) --- */
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'OF_SHAREPOINT.DOCS.CORTEX_SEARCH_SERVICE',
        '{
            "query": "refrigeration issues",
            "columns": ["full_name", "chunk"],
            "filter": {"@contains": {"user_emails": "dale@oceancloudtech.com"}},
            "limit": 3
        }'
    )
)['results'] AS results;

/* --- Task health --- */
SELECT SCHEDULED_TIME, STATE, ERROR_CODE, ERROR_MESSAGE
  FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'TASK_CLASSIFY_DOCS'))
 ORDER BY SCHEDULED_TIME DESC LIMIT 5;

/* --- Classification + extraction counts --- */
SELECT DOC_TYPE, COUNT(*) AS DOCS
  FROM DOC_CLASSIFY_RAW
 GROUP BY DOC_TYPE ORDER BY DOCS DESC;

SELECT DOC_TYPE, COUNT(*) AS DOCS
  FROM DOC_EXTRACT_RAW
 GROUP BY DOC_TYPE ORDER BY DOCS DESC;

/* --- Structured tables --- */
SELECT STORE_NUMBER, INSPECTION_DATE, SEVERITY, FINDING_DESCRIPTION
  FROM INSPECTION_FINDINGS ORDER BY STORE_NUMBER, INSPECTION_DATE;

SELECT WO_NUMBER, STORE_NUMBER, CATEGORY, PRIORITY, STATUS
  FROM MAINTENANCE_ORDERS ORDER BY PRIORITY DESC;

SELECT STORE_NUMBER, INCIDENT_TYPE, SEVERITY, INCIDENT_DATE
  FROM INCIDENT_REPORTS ORDER BY SEVERITY;

SELECT STORE_NUMBER, DEPARTMENT, OVERALL_COMPLIANCE, COMPLIANCE_STATUS, FINDING_DESCRIPTION
  FROM PLANOGRAM_FINDINGS WHERE COMPLIANCE_STATUS = 'NON-COMPLIANT';

/* --- Cross-document: stores with critical findings AND open maintenance --- */
SELECT DISTINCT i.STORE_NUMBER, i.SEVERITY, i.FINDING_DESCRIPTION, m.WO_NUMBER, m.CATEGORY
  FROM INSPECTION_FINDINGS i
  JOIN MAINTENANCE_ORDERS m ON i.STORE_NUMBER = m.STORE_NUMBER
 WHERE i.SEVERITY IN ('Critical', 'Major', 'Violation 3-501.16', 'Violation 4-601.11')
   AND m.STATUS = 'OPEN';

/* --- Structured findings search (STORE_OPS_SEARCH) --- */
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'OF_SHAREPOINT.DOCS.STORE_OPS_SEARCH',
        '{
            "query": "refrigeration failures",
            "columns": ["store_number", "doc_type", "severity", "search_text", "event_date"],
            "limit": 5
        }'
    )
)['results'] AS results;

SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'OF_SHAREPOINT.DOCS.STORE_OPS_SEARCH',
        '{
            "query": "slip and fall incidents",
            "columns": ["store_number", "doc_type", "severity", "search_text", "event_date"],
            "limit": 5
        }'
    )
)['results'] AS results;

SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'OF_SHAREPOINT.DOCS.STORE_OPS_SEARCH',
        '{
            "query": "planogram non-compliance cereal aisle",
            "columns": ["store_number", "doc_type", "severity", "search_text", "event_date"],
            "filter": {"@eq": {"doc_type": "PLANOGRAM"}},
            "limit": 5
        }'
    )
)['results'] AS results;

/* --- Cortex Search with filter: only store #4421 --- */
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'OF_SHAREPOINT.DOCS.STORE_OPS_SEARCH',
        '{
            "query": "what issues has this store had",
            "columns": ["doc_type", "severity", "search_text", "event_date"],
            "filter": {"@eq": {"store_number": "#4421"}},
            "limit": 10
        }'
    )
)['results'] AS results;
