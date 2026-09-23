/* =============================================================================
   06_agent.sql — Semantic view + Cortex Agent
   -----------------------------------------------------------------------------
   Run as OF_SHAREPOINT_ADMIN AFTER 04_ai_pipeline.sql has populated the
   structured dynamic tables (INSPECTION_FINDINGS, MAINTENANCE_ORDERS,
   INCIDENT_REPORTS, PLANOGRAM_FINDINGS).

   Creates:
     STORE_OPS_ANALYTICS  — Semantic view over the 4 structured tables
     STORE_OPS_AGENT      — Cortex Agent with two tools:
       1. Analyst (semantic view) — for analytical/SQL questions
       2. Cortex Search (CORTEX_SEARCH_SERVICE) — for raw doc retrieval + ACLs

   The agent can answer both:
     "which stores have the most critical findings"   → Analyst → SQL
     "what does the inspection say about store 4421"  → Search → chunks
   ============================================================================= */

USE ROLE OF_SHAREPOINT_ADMIN;
USE DATABASE OF_SHAREPOINT;
USE SCHEMA DOCS;
USE WAREHOUSE OF_SHAREPOINT_WH;

/* =============================================================================
   STEP 0 — Grants for semantic view creation
   ============================================================================= */
USE ROLE ACCOUNTADMIN;
GRANT CREATE SEMANTIC VIEW ON SCHEMA OF_SHAREPOINT.DOCS TO ROLE OF_SHAREPOINT_ADMIN;
GRANT CREATE AGENT ON SCHEMA OF_SHAREPOINT.DOCS TO ROLE OF_SHAREPOINT_ADMIN;
USE ROLE OF_SHAREPOINT_ADMIN;

/* =============================================================================
   STEP 1 — Deploy semantic view from YAML

   The YAML is in snowflake/store_ops_analytics.sv.yaml. To deploy, run either:

     Option A (cortex agent-studio CLI):
       cortex agent-studio sv-deploy \
         --file-path /tmp/store_ops.sv.yaml \
         --fqn OF_SHAREPOINT.DOCS.STORE_OPS_ANALYTICS

     Option B (SQL — paste YAML inline or load from stage):
       See SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML call below.
   ============================================================================= */

-- Deploy via stored procedure. The YAML is read from the file and pasted here
-- as a string literal. To regenerate, copy contents of store_ops_analytics.sv.yaml.
-- Pass TRUE as third arg to validate-only without creating.

CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
    'OF_SHAREPOINT.DOCS',
    $$
name: STORE_OPS_ANALYTICS
description: >
  Retail store operations analytics across inspections, maintenance work orders,
  incident reports, and planogram compliance audits. Documents are ingested from
  SharePoint via Openflow Cortex Connect, classified by AI_CLASSIFY, and extracted
  into structured tables by AI_EXTRACT. Use this to answer questions about store
  safety, compliance, maintenance status, and operational risk.

tables:

  - name: INSPECTION_FINDINGS
    description: >
      Structured inspection findings — one row per finding per inspection report.
      Covers food safety inspections, health department visits, and fire inspections.
    base_table:
      database: OF_SHAREPOINT
      schema: DOCS
      table: INSPECTION_FINDINGS
    dimensions:
      - name: FILE_ID
        description: SharePoint document ID
        expr: FILE_ID
        data_type: TEXT
      - name: FILE_NAME
        description: Original PDF filename
        expr: FILE_NAME
        data_type: TEXT
      - name: STORE_NUMBER
        synonyms: ["store", "store #", "location number"]
        description: Store identifier (e.g. "#4421")
        expr: STORE_NUMBER
        data_type: TEXT
      - name: STORE_LOCATION
        synonyms: ["city", "location"]
        description: Store city and state
        expr: STORE_LOCATION
        data_type: TEXT
      - name: INSPECTION_DATE
        synonyms: ["date", "inspected on"]
        description: Date of the inspection
        expr: INSPECTION_DATE
        data_type: TEXT
      - name: INSPECTION_TYPE
        synonyms: ["type", "kind of inspection"]
        description: "Type: food safety, health dept, fire"
        expr: INSPECTION_TYPE
        data_type: TEXT
      - name: INSPECTOR_NAME
        synonyms: ["inspector", "auditor"]
        description: Name of the inspector
        expr: INSPECTOR_NAME
        data_type: TEXT
      - name: OVERALL_RESULT
        synonyms: ["result", "score", "pass/fail"]
        description: "Overall result (PASS, CONDITIONAL PASS, FAIL, or numeric score)"
        expr: OVERALL_RESULT
        data_type: TEXT
      - name: SEVERITY
        synonyms: ["finding severity", "level"]
        description: "Finding severity: Critical, Major, Minor, Observation, Violation, Compliant"
        expr: SEVERITY
        data_type: TEXT
      - name: FINDING_DESCRIPTION
        synonyms: ["finding", "issue", "problem"]
        description: Description of the inspection finding
        expr: FINDING_DESCRIPTION
        data_type: TEXT
      - name: CORRECTIVE_ACTION
        synonyms: ["action", "fix", "remedy"]
        description: Corrective action taken or required
        expr: CORRECTIVE_ACTION
        data_type: TEXT
    measures:
      - name: FINDING_COUNT
        synonyms: ["number of findings", "total findings"]
        description: Count of inspection findings
        expr: "1"
        data_type: NUMBER
        default_aggregation: sum
      - name: INSPECTION_COUNT
        synonyms: ["number of inspections"]
        description: Count of distinct inspections
        expr: FILE_ID
        data_type: TEXT
        default_aggregation: count_distinct

  - name: MAINTENANCE_ORDERS
    description: >
      Structured maintenance work orders — one row per work order.
      Covers refrigeration, HVAC, plumbing, and electrical maintenance.
    base_table:
      database: OF_SHAREPOINT
      schema: DOCS
      table: MAINTENANCE_ORDERS
    dimensions:
      - name: FILE_ID
        description: SharePoint document ID
        expr: FILE_ID
        data_type: TEXT
      - name: FILE_NAME
        description: Original PDF filename
        expr: FILE_NAME
        data_type: TEXT
      - name: WO_NUMBER
        synonyms: ["work order", "work order number", "WO"]
        description: Work order number
        expr: WO_NUMBER
        data_type: TEXT
      - name: STORE_NUMBER
        synonyms: ["store", "store #", "location number"]
        description: Store identifier
        expr: STORE_NUMBER
        data_type: TEXT
      - name: STORE_LOCATION
        synonyms: ["city", "location"]
        description: Store city and state
        expr: STORE_LOCATION
        data_type: TEXT
      - name: DATE_OPENED
        synonyms: ["opened", "created date"]
        description: Date work order was opened
        expr: DATE_OPENED
        data_type: TEXT
      - name: DATE_CLOSED
        synonyms: ["closed", "completed date"]
        description: Date work order was closed, or OPEN
        expr: DATE_CLOSED
        data_type: TEXT
      - name: PRIORITY
        synonyms: ["urgency", "priority level"]
        description: "Priority: EMERGENCY, HIGH, MEDIUM, LOW"
        expr: PRIORITY
        data_type: TEXT
      - name: CATEGORY
        synonyms: ["maintenance type", "trade"]
        description: "Category: Refrigeration, HVAC, Plumbing, Electrical"
        expr: CATEGORY
        data_type: TEXT
      - name: EQUIPMENT
        synonyms: ["unit", "asset"]
        description: Equipment description and model/serial if available
        expr: EQUIPMENT
        data_type: TEXT
      - name: PROBLEM_DESCRIPTION
        synonyms: ["problem", "issue"]
        description: Problem description
        expr: PROBLEM_DESCRIPTION
        data_type: TEXT
      - name: RESOLUTION
        synonyms: ["fix", "repair"]
        description: Resolution or current status
        expr: RESOLUTION
        data_type: TEXT
      - name: COST
        synonyms: ["repair cost", "total cost"]
        description: Total cost including breakdown
        expr: COST
        data_type: TEXT
      - name: STATUS
        synonyms: ["open/closed", "state"]
        description: "Current status: OPEN or CLOSED"
        expr: STATUS
        data_type: TEXT
    measures:
      - name: ORDER_COUNT
        synonyms: ["number of work orders", "total orders"]
        description: Count of maintenance work orders
        expr: "1"
        data_type: NUMBER
        default_aggregation: sum
      - name: OPEN_ORDER_COUNT
        synonyms: ["open orders", "backlog"]
        description: Count of open maintenance work orders
        expr: "CASE WHEN STATUS = 'OPEN' THEN 1 ELSE 0 END"
        data_type: NUMBER
        default_aggregation: sum

  - name: INCIDENT_REPORTS
    description: >
      Structured incident reports — one row per incident.
      Covers slip/fall, equipment failure, theft, and employee injury.
    base_table:
      database: OF_SHAREPOINT
      schema: DOCS
      table: INCIDENT_REPORTS
    dimensions:
      - name: FILE_ID
        description: SharePoint document ID
        expr: FILE_ID
        data_type: TEXT
      - name: FILE_NAME
        description: Original PDF filename
        expr: FILE_NAME
        data_type: TEXT
      - name: STORE_NUMBER
        synonyms: ["store", "store #", "location number"]
        description: Store identifier
        expr: STORE_NUMBER
        data_type: TEXT
      - name: STORE_LOCATION
        synonyms: ["city", "location"]
        description: Store city and state
        expr: STORE_LOCATION
        data_type: TEXT
      - name: INCIDENT_DATE
        synonyms: ["date", "when"]
        description: Date and time of the incident
        expr: INCIDENT_DATE
        data_type: TEXT
      - name: INCIDENT_TYPE
        synonyms: ["type", "kind of incident"]
        description: "Type: Slip & Fall, Equipment Failure, Theft, Employee Injury"
        expr: INCIDENT_TYPE
        data_type: TEXT
      - name: SEVERITY
        synonyms: ["level", "seriousness"]
        description: "Severity: HIGH, MODERATE, LOW"
        expr: SEVERITY
        data_type: TEXT
      - name: REPORTED_BY
        synonyms: ["reporter", "who reported"]
        description: Name and title of person reporting
        expr: REPORTED_BY
        data_type: TEXT
      - name: DESCRIPTION
        synonyms: ["what happened", "details"]
        description: Incident description
        expr: DESCRIPTION
        data_type: TEXT
      - name: ROOT_CAUSE
        synonyms: ["cause", "why"]
        description: Root cause analysis
        expr: ROOT_CAUSE
        data_type: TEXT
      - name: CORRECTIVE_ACTIONS
        synonyms: ["actions", "remedy"]
        description: Corrective actions taken
        expr: CORRECTIVE_ACTIONS
        data_type: TEXT
      - name: ESTIMATED_COST
        synonyms: ["cost", "loss"]
        description: Estimated cost or product loss
        expr: ESTIMATED_COST
        data_type: TEXT
    measures:
      - name: INCIDENT_COUNT
        synonyms: ["number of incidents", "total incidents"]
        description: Count of incidents
        expr: "1"
        data_type: NUMBER
        default_aggregation: sum

  - name: PLANOGRAM_FINDINGS
    description: >
      Structured planogram compliance findings — one row per finding per audit.
      Covers shelf compliance audits across departments.
    base_table:
      database: OF_SHAREPOINT
      schema: DOCS
      table: PLANOGRAM_FINDINGS
    dimensions:
      - name: FILE_ID
        description: SharePoint document ID
        expr: FILE_ID
        data_type: TEXT
      - name: FILE_NAME
        description: Original PDF filename
        expr: FILE_NAME
        data_type: TEXT
      - name: STORE_NUMBER
        synonyms: ["store", "store #", "location number"]
        description: Store identifier
        expr: STORE_NUMBER
        data_type: TEXT
      - name: STORE_LOCATION
        synonyms: ["city", "location"]
        description: Store city and state
        expr: STORE_LOCATION
        data_type: TEXT
      - name: AUDIT_DATE
        synonyms: ["date", "audited on"]
        description: Date of the planogram audit
        expr: AUDIT_DATE
        data_type: TEXT
      - name: DEPARTMENT
        synonyms: ["aisle", "section"]
        description: Department or aisle audited
        expr: DEPARTMENT
        data_type: TEXT
      - name: PLANOGRAM_ID
        synonyms: ["planogram", "POG"]
        description: Planogram version identifier
        expr: PLANOGRAM_ID
        data_type: TEXT
      - name: OVERALL_COMPLIANCE
        synonyms: ["compliance rate", "compliance %"]
        description: Overall compliance percentage
        expr: OVERALL_COMPLIANCE
        data_type: TEXT
      - name: COMPLIANCE_STATUS
        synonyms: ["status", "compliant/non-compliant"]
        description: "COMPLIANT, NON-COMPLIANT, or OBSERVATION"
        expr: COMPLIANCE_STATUS
        data_type: TEXT
      - name: FINDING_DESCRIPTION
        synonyms: ["finding", "issue"]
        description: Planogram finding description
        expr: FINDING_DESCRIPTION
        data_type: TEXT
    measures:
      - name: FINDING_COUNT
        synonyms: ["number of findings"]
        description: Count of planogram findings
        expr: "1"
        data_type: NUMBER
        default_aggregation: sum
      - name: NON_COMPLIANT_COUNT
        synonyms: ["violations", "non-compliant findings"]
        description: Count of non-compliant findings
        expr: "CASE WHEN COMPLIANCE_STATUS = 'NON-COMPLIANT' THEN 1 ELSE 0 END"
        data_type: NUMBER
        default_aggregation: sum

relationships:
  - name: inspection_to_maintenance
    left_table: INSPECTION_FINDINGS
    right_table: MAINTENANCE_ORDERS
    relationship_columns:
      - left_column: STORE_NUMBER
        right_column: STORE_NUMBER
    join_type: many_to_many
  - name: inspection_to_incidents
    left_table: INSPECTION_FINDINGS
    right_table: INCIDENT_REPORTS
    relationship_columns:
      - left_column: STORE_NUMBER
        right_column: STORE_NUMBER
    join_type: many_to_many
  - name: maintenance_to_incidents
    left_table: MAINTENANCE_ORDERS
    right_table: INCIDENT_REPORTS
    relationship_columns:
      - left_column: STORE_NUMBER
        right_column: STORE_NUMBER
    join_type: many_to_many
  - name: inspection_to_planograms
    left_table: INSPECTION_FINDINGS
    right_table: PLANOGRAM_FINDINGS
    relationship_columns:
      - left_column: STORE_NUMBER
        right_column: STORE_NUMBER
    join_type: many_to_many

verified_queries:
  - name: critical_findings_by_store
    question: Which stores have the most critical inspection findings?
    sql: >
      SELECT STORE_NUMBER, COUNT(*) AS critical_findings
      FROM OF_SHAREPOINT.DOCS.INSPECTION_FINDINGS
      WHERE SEVERITY IN ('Critical', 'Major')
      GROUP BY STORE_NUMBER
      ORDER BY critical_findings DESC
    use_as_onboarding_question: true
  - name: maintenance_by_store_category
    question: Show me maintenance work orders by store and category
    sql: >
      SELECT STORE_NUMBER, CATEGORY, PRIORITY, STATUS, COUNT(*) AS orders
      FROM OF_SHAREPOINT.DOCS.MAINTENANCE_ORDERS
      GROUP BY ALL
      ORDER BY STORE_NUMBER
  - name: incident_types
    question: What types of incidents are happening across stores?
    sql: >
      SELECT STORE_NUMBER, INCIDENT_TYPE, SEVERITY, COUNT(*) AS incidents
      FROM OF_SHAREPOINT.DOCS.INCIDENT_REPORTS
      GROUP BY ALL
      ORDER BY incidents DESC
    use_as_onboarding_question: true
  - name: planogram_compliance
    question: Which stores have the worst planogram compliance?
    sql: >
      SELECT STORE_NUMBER, DEPARTMENT, OVERALL_COMPLIANCE,
             COUNT(*) FILTER (WHERE COMPLIANCE_STATUS = 'NON-COMPLIANT') AS non_compliant
      FROM OF_SHAREPOINT.DOCS.PLANOGRAM_FINDINGS
      GROUP BY ALL
      ORDER BY non_compliant DESC
  - name: critical_with_open_orders
    question: Which stores have critical inspection findings with open maintenance orders?
    sql: >
      SELECT DISTINCT i.STORE_NUMBER, i.SEVERITY, i.FINDING_DESCRIPTION,
             m.WO_NUMBER, m.CATEGORY, m.STATUS
      FROM OF_SHAREPOINT.DOCS.INSPECTION_FINDINGS i
      JOIN OF_SHAREPOINT.DOCS.MAINTENANCE_ORDERS m ON i.STORE_NUMBER = m.STORE_NUMBER
      WHERE i.SEVERITY IN ('Critical', 'Major')
        AND m.STATUS = 'OPEN'
    use_as_onboarding_question: true
  - name: store_risk_summary
    question: Give me a risk summary by store
    sql: >
      SELECT STORE_NUMBER,
             COUNT(DISTINCT FILE_ID) AS total_docs,
             COUNT(DISTINCT CASE WHEN SEVERITY IN ('Critical', 'Major', 'HIGH') THEN FILE_ID END) AS high_severity_docs
      FROM (
        SELECT FILE_ID, STORE_NUMBER, SEVERITY FROM OF_SHAREPOINT.DOCS.INSPECTION_FINDINGS
        UNION ALL
        SELECT FILE_ID, STORE_NUMBER, SEVERITY FROM OF_SHAREPOINT.DOCS.INCIDENT_REPORTS
      )
      GROUP BY STORE_NUMBER
      ORDER BY high_severity_docs DESC
    $$
);

/* =============================================================================
   STEP 2 — Cortex Agent
   ============================================================================= */

CREATE OR REPLACE CORTEX AGENT STORE_OPS_AGENT
  COMMENT = 'Retail store ops assistant — answers questions about inspections, maintenance, incidents, and planograms'
  TOOLS = (
    CORTEX_ANALYST(
      SEMANTIC_VIEW => 'OF_SHAREPOINT.DOCS.STORE_OPS_ANALYTICS'
    ),
    CORTEX_SEARCH(
      CORTEX_SEARCH_SERVICE => 'OF_SHAREPOINT.DOCS.CORTEX_SEARCH_SERVICE'
    )
  )
  AGENT_INSTRUCTIONS = $$
You are a retail store operations assistant. You help operations managers,
district managers, and safety teams understand what is happening across their
stores by answering questions about inspections, maintenance work orders,
incident reports, and planogram compliance audits.

TOOLS:
- Use the Analyst tool for analytical questions that need counts, aggregations,
  comparisons, or structured data (e.g. "which stores have the most critical
  findings", "show me open maintenance orders", "compare compliance across stores").
- Use the Search tool for document-level questions that need raw text from the
  original PDFs (e.g. "what did the inspector say about refrigeration at store 4421",
  "find the incident report about the slip and fall").

GUIDELINES:
- Always include the store number when referencing specific stores.
- When reporting severity, use the exact values from the data (Critical, Major,
  Minor, HIGH, MODERATE, LOW, NON-COMPLIANT).
- For cross-document questions (e.g. "what's going on at store 4421"), use both
  tools: Analyst for structured data and Search for raw document details.
- Be concise. Lead with the answer, then provide supporting detail.
$$;

/* =============================================================================
   VERIFICATION
   ============================================================================= */

SHOW SEMANTIC VIEWS IN SCHEMA OF_SHAREPOINT.DOCS;
SHOW CORTEX AGENTS IN SCHEMA OF_SHAREPOINT.DOCS;

/* --- Test queries (uncomment to run) ---

-- Analyst question (structured data):
SELECT SNOWFLAKE.CORTEX.AGENT(
    'OF_SHAREPOINT.DOCS.STORE_OPS_AGENT',
    'Which stores have the most critical inspection findings?'
);

-- Search question (raw document):
SELECT SNOWFLAKE.CORTEX.AGENT(
    'OF_SHAREPOINT.DOCS.STORE_OPS_AGENT',
    'What did the inspector find about refrigeration at store #4421?'
);

-- Cross-document question:
SELECT SNOWFLAKE.CORTEX.AGENT(
    'OF_SHAREPOINT.DOCS.STORE_OPS_AGENT',
    'What is going on at store #4421?'
);

*/
