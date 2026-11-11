# Phase 1 — Schema Alignment: Design & Validation Document

## GOAL: Produce implementation-ready design for review before SQL execution

---

### 🔍 **CORRECTION 1: Avg_Trans_Volume_D7 Definition**

**Issue**: Proposed `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` is row-based, not time-based.

**Analysis from Vision & Profiling**:
- Vision lists `Avg_Trans_Volume_D7` under `Dim_Customer` 
- Profiling Query 22: "Customer Transaction Activity" shows transaction counts per customer
- Profiling Query 23: "Customer Transaction Amount behaviour" shows avg/max amounts per customer
- Profiling Query 28: "Customer transaction velocity" shows transactions_per_day per customer
- Profiling Query 30: "Fraud by transaction velocity bucket" uses transaction count bands

**Business Question**: 
"What is the customer's average daily transaction amount over the last 7 days?" 
This is a temporal rolling window, not transaction-count-based.

**Correct Definition**:
```sql
AVG(Amount) OVER (
    PARTITION BY Customer_ID 
    ORDER BY Timestamp 
    RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW
)
```

**Why RANGE?** 
- `ROWS` = fixed number of preceding rows (transaction-count-based)
- `RANGE` = time-based window (looks back exactly 6 days of time)
- Matches "D7" suffix meaning "last 7 days" including current day

**Validation Plan in pgAdmin**:
1. Sample 5 customers with varying transaction frequencies
2. For each customer, manually calculate 7-day average for their latest transaction
3. Compare against view output
4. Check edge cases: customers with <1 transaction/week, bursty patterns

**Leakage/Risks**:
- None - purely historical calculation using only past data
- Requires indexed Timestamp column for performance (already indexed)

---

### 🔍 **CORRECTION 2: Status Logic Definition**

**Issue**: Cannot safely collapse Ground_Truth_Label, Model_Predicted_Score, Resolution_Code.

**Analysis from Vision**:
Vision defines `Status` ENUM: ('Nominal', 'Fraud - Hard Flag', 'High_Risk - ML Flag', 'Client_Canceled')

**Analysis from Profiling**:
- Query 6-8: Investigation resolutions are 'False Positive' or 'Confirmed Fraud'
- Query 10-11: Model predictions vs ground truth (Model_Predicted_Score 0-1, Is_Predicted_Fraud boolean)
- Query 18: Rule effectiveness shows investigations triggered by alerts

**Ambiguity Identified**:
1. **Ground_Truth_Label**: Actual fraud (from labeling process)
2. **Model_Predicted_Score**: ML model output (0-1 probability)
3. **Is_Predicted_Fraud**: Binary threshold of Model_Predicted_Score (likely >0.5)
4. **Resolution_Code**: Human investigation outcome ('False Positive', 'Confirmed Fraud')
5. **Alerts/Investigations**: Triggered by rules, not direct fraud labels

**Business Definition for Status**:
Status should reflect **operational state** for fraud workflow, not just ground truth:

| Status Value | Business Meaning | Derivation Logic |
|--------------|------------------|------------------|
| 'Nominal' | Normal transaction | Ground_Truth_Label = false AND (Model_Predicted_Score <= 0.5 OR Is_Predicted_Fraud = false) AND Resolution_Code IS NULL |
| 'Fraud - Hard Flag' | Confirmed fraud | Ground_Truth_Label = true AND Resolution_Code = 'Confirmed Fraud' |
| 'High_Risk - ML Flag' | ML flagged, not confirmed | Model_Predicted_Score > 0.5 AND Ground_Truth_Label = false AND (Resolution_Code IS NULL OR Resolution_Code = 'False Positive') |
| 'Client_Canceled' | Customer-initiated cancel | [Requires new data - CANCELED flag not in current dataset] |

**Critical Finding**: 
`Client_Canceled` status **cannot be derived** from current dataset - requires transaction cancellation flag.

**Revised Approach**:
Create status as best-approximation with available data, flagging missing data:
```sql
CASE 
    WHEN Ground_Truth_Label = true THEN 'Fraud - Hard Flag'
    WHEN Model_Predicted_Score > 0.5 AND Resolution_Code = 'False Positive' THEN 'High_Risk - ML Flag'
    WHEN Model_Predicted_Score > 0.5 AND Resolution_Code IS NULL THEN 'High_Risk - ML Flag'  -- Pending investigation
    ELSE 'Nominal'
END AS Status
```

**Note**: Will add comment that 'Client_Canceled' requires new data source.

**Validation Plan in pgAdmin**:
1. Count transactions by derived Status vs actual Ground_Truth_Label
2. Verify 'Fraud - Hard Flag' matches Ground_Truth_Label = true count (should be ~500)
3. Check 'High_Risk - ML Flag' count roughly matches Is_Predicted_Fraud = true minus confirmed fraud
4. Sample 10 transactions from each status category and verify logic manually

**Leakage/Risks**:
- Temporal leakage: Using Resolution_Code (future investigation outcome) for current status
- **Solution**: Only use Resolution_Code for historical analysis, not real-time scoring
- For production: Status would be ML-based only, investigations update status later

---

### 🔍 **CORRECTION 3: Stg_Fraud_Templates & Stg_Risk_Models Requirements**

**Analysis of Vision Document**:
- Section 8 (SQL Workflow): Mentions these as lookup/stage tables
- Section 9 (Python Workflow): No direct reference
- Section 10 (Power Query): No direct reference
- Sections 11-16 (BI/Model): No direct reference in dashboard/KPIs

**Analysis of Current Project State**:
- No ETL/ELT workflows implemented yet (all in future phases)
- No Python/Power Query components built
- Current state: Raw data loaded into star schema

**Determination**:
These tables are **architectural placeholders** for future workflows, not currently required:
- Not referenced in any existing SQL, Python, or M-code
- Not needed for current star schema querying
- Vision describes them as "lookup/stage" for workflows not yet built

**Recommendation**:
**Do NOT create these tables in Phase 1.**
- Create them only when implementing Phase 2 ETL/Python workflows
- Current gap analysis shows they are vision-only, not implementation-required
- Creating them now would be premature optimization

**Alternative**: If metadata tracking is needed immediately, add to existing `dim_rule` table:
- Add `Rule_Version`, `Rule_Active_From`, `Rule_Active_To` columns
- Much lighter weight than new tables

---

### 📐 **CORRECTION 4: Analytical View Approach First**

**Strategy**: Start with views, not schema changes. Zero risk, fully reversible.

#### **Proposed View: `vw_Fct_Transaction_Scored`**

| View Column | Source Column | Transformation | Data Type | Business Meaning |
|-------------|---------------|----------------|-----------|------------------|
| Transaction_ID | Transaction_ID | Direct | VARCHAR(20) | Unique transaction |
| Transaction_Date | Timestamp | `DATE(Timestamp)` | DATE | Date-only for time intelligence |
| Customer_ID | Customer_ID | Direct | VARCHAR(20) | Customer foreign key |
| Merchant_ID | Merchant_ID | Direct | VARCHAR(20) | Merchant foreign key (nullable) |
| Channel_ID | Channel_ID | Direct | VARCHAR(10) | Channel foreign key |
| Device_ID | Device_ID | Direct | VARCHAR(20) | Device foreign key (nullable) |
| Amount | Amount | Direct | NUMERIC(12,2) | Transaction amount |
| Currency_Code | *(literal)* | `'USD'` (placeholder) | VARCHAR(3) | **Requires new data** - hardcoded USD for now |
| Transaction_Type | *(literal)* | `'STANDARD'` (placeholder) | VARCHAR(20) | **Requires new data** - hardcoded for now |
| Status | Model_Predicted_Score + Ground_Truth_Label + Resolution_Code | See Correction 2 logic | VARCHAR(25) | Operational fraud status |
| ML_Risk_Score | Model_Predicted_Score | `ROUND(Model_Predicted_Score * 100)` | INTEGER | ML score scaled 0-100 |
| Fraud_Type_Cat | *(literal)* | `'UNKNOWN'` | VARCHAR(20) | **Requires new data** - hardcoded for now |
| Is_Predicted_Fraud | Is_Predicted_Fraud | Direct | BOOLEAN | Raw model prediction flag |
| Ground_Truth_Label | Ground_Truth_Label | Direct | BOOLEAN | Actual fraud label |
| Timestamp | Timestamp | Direct | TIMESTAMP | Full transaction timestamp |
| Date_ID | Date_ID | Direct | INTEGER | Date foreign key |
| Account_ID | Account_ID | Direct | VARCHAR(20) | Account foreign key |
| Rule_ID | *(via fact_alerts)* | `COALESCE((SELECT Rule_ID FROM fact_alerts WHERE fact_alerts.Transaction_ID = fact_transaction.Transaction_ID LIMIT 1), 'R00')` | VARCHAR(20) | Most recent alert rule (optional) |

**Note**: Currency_Code, Transaction_Type, Fraud_Type_Cat are hardcoded placeholders with clear documentation that they require new data sources.

---

### 📋 **CORRECTION 5: Transformation Validation Blueprint**

For every proposed transformation, here is the validation plan:

#### **Transformation 1: Transaction_Date**
- **Business Question**: "What date did this transaction occur on?" (for daily/monthly reporting)
- **Source**: `fact_transaction.Timestamp`
- **SQL**: `DATE(Timestamp)`
- **Validation**: 
  - Sample 100 transactions
  - Verify DATE() matches date portion of Timestamp
  - Check timezone handling (should be UTC/local consistent)
- **Risk**: None - deterministic date extraction

#### **Transformation 2: ML_Risk_Score (0-100)**
- **Business Question**: "What is the model's risk score on an intuitive 0-100 scale?"
- **Source**: `fact_transaction.Model_Predicted_Score` (0-1 float)
- **SQL**: `ROUND(Model_Predicted_Score * 100)`
- **Validation**:
  - Verify 0.0 → 0, 0.5 → 50, 1.0 → 100
  - Check rounding behavior at edges
  - Confirm no data loss (original score recoverable via /100.0)
- **Risk**: None - simple linear transformation

#### **Transformation 3: Status (Best-Effort)**
- **Business Question**: "What is the current operational fraud status for workflow routing?"
- **Sources**: Multiple columns (see Correction 2)
- **SQL**: CASE expression (see above)
- **Validation**:
  - Build confusion matrix vs Ground_Truth_Label
  - Verify 'Fraud - Hard Flag' = all confirmed fraud cases
  - Monitor % of transactions in each status bucket
  - Flag when Resolution_Code used (indicates future leakage)
- **Risk**: **Future leakage** if Resolution_Code used in real-time
  - **Mitigation**: Document as "historical analysis only"; for production use ML-score only

#### **Transformation 4: Avg_Trans_Volume_D7 (Corrected)**
- **Business Question**: "What is this customer's average daily transaction amount over the last 7 days?"
- **Sources**: `fact_transaction.Customer_ID`, `Timestamp`, `Amount`
- **SQL**: Windowed average with RANGE clause
- **Validation**:
  - Pick 5 customers with known transaction patterns
  - For their latest transaction, manually compute 7-day trailing average
  - Compare to view output
  - Test edge cases: new customers, inactive customers
- **Risk**: None - purely historical calculation
- **Performance**: Requires `(Customer_ID, Timestamp)` index (consider adding)

#### **Transformation 5: Currency_Code/Transaction_Type/Fraud_Type_Cat (Placeholders)**
- **Business Question**: "What are the currency, type, and fraud category?" (preparing for future data)
- **Sources**: None available
- **SQL**: Hardcoded literals with clear documentation
- **Validation**:
  - Verify all rows show placeholder values
  - Document in view comments: "PLACEHOLDER - requires external data source"
  - Prepare for future ALTER when data available
- **Risk**: None if clearly marked as placeholders

---

### 📊 **SUMMARY: IMPLEMENTATION-READY DESIGN**

**Approach**: VIEW-BASED (zero schema changes, fully reversible)

**Files to Create/Modify** (after approval):
1. **NEW**: `SQL/02_views.sql` - Contains `vw_Fct_Transaction_Scored` and dimension views
2. **UPDATE**: `SQL/01_schema.sql` - Add comments about placeholder fields
3. **UPDATE**: `ANALYSIS_PLAN.md` - Document view-based approach
4. **UPDATE**: `PROJECT_STATUS.md` - Note views created, tables pending

**What Will NOT Be Created**:
- ❌ No ALTER TABLE on existing tables
- ❌ No new staging tables (deferred to Phase 2)
- ❌ No modifications to CSV files
- ❌ No database schema changes yet

**Status:** Approved and implemented in `SQL/02_views.sql` (Phase 1 complete).

> **Implementation Note:** Following final review, unpopulated placeholder literal columns (`Currency_Code`, `Transaction_Type`, `Fraud_Type_Cat`) and `Rule_ID` lookup on the transaction view were intentionally omitted from `vw_Fct_Transaction_Scored` in `SQL/02_views.sql` to adhere strictly to the project's no-fabrication rule, and `Avg_Trans_Volume_D7` was implemented on `vw_Dim_Customer_Enriched` anchored to each customer's latest transaction date.