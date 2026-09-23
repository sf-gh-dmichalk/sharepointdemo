/* =============================================================================
   05_agent.sql — Semantic view + Cortex Agent
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
   STEP 0 — Grants for semantic view + agent creation
   ============================================================================= */
USE ROLE ACCOUNTADMIN;
GRANT CREATE SEMANTIC VIEW ON SCHEMA OF_SHAREPOINT.DOCS TO ROLE OF_SHAREPOINT_ADMIN;
GRANT CREATE AGENT ON SCHEMA OF_SHAREPOINT.DOCS TO ROLE OF_SHAREPOINT_ADMIN;

-- Cortex Agents uses the caller's DEFAULT ROLE and DEFAULT WAREHOUSE — not the
-- session role/warehouse.  The user's default role must have USAGE on the agent,
-- its database/schema, and a warehouse.  The default warehouse must be one that
-- role can actually use, or the Analyst tool fails with "missing execution
-- environment" even if warehouse is set in tool_resources.
GRANT USAGE ON WAREHOUSE OF_SHAREPOINT_WH TO ROLE OPENFLOW_ADMIN;
GRANT USAGE ON DATABASE OF_SHAREPOINT TO ROLE OPENFLOW_ADMIN;
GRANT USAGE ON SCHEMA OF_SHAREPOINT.DOCS TO ROLE OPENFLOW_ADMIN;

-- Point the user's default warehouse at one the default role can reach.
-- Replace DMICHALK with your username (ALTER USER does not accept CURRENT_USER).
ALTER USER DMICHALK SET DEFAULT_WAREHOUSE = 'OF_SHAREPOINT_WH';

USE ROLE OF_SHAREPOINT_ADMIN;

/* =============================================================================
   STEP 1 — Deploy semantic view from YAML

   The source of truth is snowflake/store_ops_analytics.sv.yaml.

   Deploy with cortex agent-studio CLI:
     cortex agent-studio sv-deploy \
       --file-path snowflake/store_ops_analytics.sv.yaml \
       --fqn OF_SHAREPOINT.DOCS.STORE_OPS_ANALYTICS

   Or from Snowsight: paste the YAML into SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML.
   See https://docs.snowflake.com/en/sql-reference/stored-procedures/system_create_semantic_view_from_yaml
   ============================================================================= */

/* =============================================================================
   STEP 2 — Cortex Agent
   ============================================================================= */

CREATE OR REPLACE AGENT STORE_OPS_AGENT
  COMMENT = 'Retail store ops assistant — answers questions about inspections, maintenance, incidents, and planograms'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    capabilities:
      analytical_search: true
    tool_not_accessible: accept

  instructions:
    response: >
      You are a retail store operations assistant. You help operations managers,
      district managers, and safety teams understand what is happening across their
      stores by answering questions about inspections, maintenance work orders,
      incident reports, and planogram compliance audits.
      Always include the store number when referencing specific stores.
      When reporting severity, use the exact values from the data (Critical, Major,
      Minor, HIGH, MODERATE, LOW, NON-COMPLIANT).
      Be concise. Lead with the answer, then provide supporting detail.
    orchestration: >
      Use the Analyst tool for analytical questions that need counts, aggregations,
      comparisons, or structured data (e.g. "which stores have the most critical
      findings", "show me open maintenance orders", "compare compliance across stores").
      Use the Search tool for document-level questions that need raw text from the
      original PDFs (e.g. "what did the inspector say about refrigeration at store 4421",
      "find the incident report about the slip and fall").
      For cross-document questions (e.g. "what's going on at store 4421"), use both
      tools: Analyst for structured data and Search for raw document details.

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "Analyst"
        description: "Answers analytical questions about inspections, maintenance, incidents, and planograms using structured data"
    - tool_spec:
        type: "cortex_search"
        name: "Search"
        description: "Searches raw document text from inspection reports, work orders, incident reports, and planogram audits"

  tool_resources:
    Analyst:
      semantic_view: "OF_SHAREPOINT.DOCS.STORE_OPS_ANALYTICS"
      execution_environment:
        type: "warehouse"
        warehouse: "OF_SHAREPOINT_WH"
    Search:
      search_service: "OF_SHAREPOINT.DOCS.CORTEX_SEARCH_SERVICE"
  $$;

-- Grant the user's default role USAGE on the agent (must come after CREATE AGENT).
USE ROLE ACCOUNTADMIN;
GRANT USAGE ON AGENT OF_SHAREPOINT.DOCS.STORE_OPS_AGENT TO ROLE OPENFLOW_ADMIN;
USE ROLE OF_SHAREPOINT_ADMIN;

/* =============================================================================
   VERIFICATION
   ============================================================================= */

SHOW SEMANTIC VIEWS IN SCHEMA OF_SHAREPOINT.DOCS;
SHOW AGENTS IN SCHEMA OF_SHAREPOINT.DOCS;

--- Test queries (uncomment to run) ---

-- Analyst question (structured data):
SELECT TRY_PARSE_JSON(
    SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'OF_SHAREPOINT.DOCS.STORE_OPS_AGENT',
        '{"messages":[{"role":"user","content":[{"type":"text","text":"Which stores have the most critical inspection findings?"}]}]}',
        TRUE
    )
) AS resp;

-- Search question (raw document):
SELECT TRY_PARSE_JSON(
    SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'OF_SHAREPOINT.DOCS.STORE_OPS_AGENT',
        '{"messages":[{"role":"user","content":[{"type":"text","text":"What did the inspector find about refrigeration at store #4421?"}]}]}',
        TRUE
    )
) AS resp;

-- Cross-document question:
SELECT TRY_PARSE_JSON(
    SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'OF_SHAREPOINT.DOCS.STORE_OPS_AGENT',
        '{"messages":[{"role":"user","content":[{"type":"text","text":"What is going on at store #4421?"}]}]}',
        TRUE
    )
) AS resp;
