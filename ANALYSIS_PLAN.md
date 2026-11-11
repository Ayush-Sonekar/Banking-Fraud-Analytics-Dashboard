# Banking Transaction & Fraud Intelligence Analysis Plan

## Completed Phases

### Phase 1: Schema Alignment (Completed)
- **Data Generation:** Synthetic dataset created (50,000 transactions, 7,820 alerts, 2,925 investigations).
- **PostgreSQL Schema:** Star schema implemented with 11 tables (3 fact, 8 dimension).
- **Data Loading & Validation:**
  - Row counts matched source CSVs.
  - Foreign-key integrity verified (0 orphaned records).
  - Schema adjustments (e.g., `Merchant_ID` nullable).
- **Data Profiling:** Completed through Query 38 (see `database_profiling.txt`).
- **Analytical Views:** Implemented and validated:
  - `vw_Fct_Transaction_Scored`
  - `vw_Dim_Customer_Enriched`
  - `vw_Fact_Alerts`
  - `vw_Fact_Investigation`

### Phase 2: Fraud Analytics & SQL Validation (Completed)
**Design Specification:** [Phase_2_Final_Fraud_Analytics_Design.md](analysis/Phase_2_Final_Fraud_Analytics_Design.md)

**Key Activities:**
1. **KPI Implementation:**
   - Fraud Amount (Ground Truth)
   - Fraud Rate
   - Precision, Recall, FPR
   - Alert-to-Investigation Rate
   - Case Resolution Time (ACT)
   - Analyst Workload
2. **Validation:**
   - SQL metric verification (e.g., Fraud Amount sum = `945,301.87`).
   - Alert-investigation integrity and unmapped-merchant reconciliation documented in [PHASE_2_VALIDATION.md](docs/PHASE_2_VALIDATION.md).
3. **Deferred Items:**
   - Geographic analysis (no geographic data).
   - Customer churn/recovery rate (requires new data).
   - Transaction velocity (distinct from `Avg_Trans_Volume_D7`).

### Phase 3: Power BI Semantic Model & Dashboard (Completed)
- Built 11-table semantic model and DAX measures in `Banking_fraud_intelligence.pbix`, cross-validated against SQL results.
- Published 6-page executive & operational report exported to `Banking_fraud_intelligence.pdf`.

## Project Rules
1. **Preserve Data Integrity:** No modifications to base tables or CSVs.
2. **Use Existing Views:** Build on Phase 1 views; no new schema changes.
3. **Avoid Fabrication:** Do not invent data for missing fields.
4. **Maintain Relationships:** Preserve 1:n (e.g., alerts to investigations).
5. **Document Limitations:** Note data constraints (e.g., class imbalance, synthetic data).

## Deferred Decisions (Out of Scope Without Additional Data)
1. **Fraud Type Categorization:** Requires external investigation taxonomy data.