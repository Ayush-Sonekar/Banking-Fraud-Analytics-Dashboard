# Phase 2 Final Design Document: Fraud Analytics & BI

## 1. Business Questions
1. **Financial Impact**
   - What is the gross fraud loss (total amount of confirmed fraud transactions)?
   - Which merchant industries have the highest fraud loss?
   - How does fraud loss trend monthly by channel?

2. **Operational Efficiency**
   - What is the average time to resolve investigations (ACT)?
   - Which fraud rules generate the most alerts but fewest confirmed frauds?
   - How does the investigation queue size change over time?

3. **Detection Performance**
   - What is the precision and recall of the ML model by **customer risk tier**?
   - How does the fraud rate compare across channels?

4. **Investigative Effectiveness**
   - What is the investigation confirmation rate (fraud vs. false positive)?
   - Which analysts have the lowest average case resolution time among closed investigations?

---

## 2. KPI Dictionary

| KPI                          | Numerator                                                                 | Denominator                                                                 | Grain               | Source Views                                                                 | Calculation Layer | Caveats                                                                 |
|------------------------------|---------------------------------------------------------------------------|-----------------------------------------------------------------------------|---------------|-----------------------------------------------------------------------------|--------------------|---------------------------------------------------------------------------------------|
| **Total Transactions**        | `COUNT(Transaction_ID)`                                                  | N/A                                                                         | Transaction        | `vw_Fct_Transaction_Scored`                                                 | PostgreSQL          | None                                                                                   |
| **Transaction Amount**        | `SUM(Amount)`                                                            | N/A                                                                         | Transaction        | `vw_Fct_Transaction_Scored`                                                 | PostgreSQL          | None                                                                                   |
| **Fraud Transactions (Ground Truth)** | `COUNT(CASE WHEN Ground_Truth_Label = true END)`                  | N/A                                                                         | Transaction        | `vw_Fct_Transaction_Scored`                                                 | PostgreSQL          | Class imbalance; synthetic data may skew results                                        |
| **Fraud Rate (Ground Truth)** | `Fraud Transactions (Ground Truth)`                                      | `Total Transactions`                                                      | Transaction/Channel | `vw_Fct_Transaction_Scored`                                                 | DAX                 | Includes all transactions (alerted and unalerted)                                       |
| **Fraud Amount (Ground Truth)** | `SUM(CASE WHEN Ground_Truth_Label = true THEN Amount ELSE 0 END)`        | N/A                                                                         | Transaction        | `vw_Fct_Transaction_Scored`                                                 | PostgreSQL          | Synthetic data may inflate amounts                                                     |
| **Alert Volume**              | `COUNT(Alert_ID)`                                                        | N/A                                                                         | Alert              | `vw_Fact_Alerts`                                                           | PostgreSQL          | Multiple alerts/transaction inflate counts                                              |
| **Investigated Alerts**       | `COUNT(DISTINCT fa.Alert_ID)`                                            | N/A                                                                         | Alert              | `vw_Fact_Alerts fa JOIN vw_Fact_Investigation fi ON fa.Investigation_ID = fi.Investigation_ID` | PostgreSQL          | Only alerted transactions are investigated                                              |
| **Alert-to-Investigation Rate** | `Investigated Alerts`                                                    | `Alert Volume`                                                            | Alert              | (see above)                                                                 | DAX                 | Selection bias: high-risk alerts more likely investigated                               |
| **Confirmed Fraud Investigations** | `COUNT(CASE WHEN Resolution_Code = 'Confirmed Fraud' END)`               | N/A                                                                         | Investigation      | `vw_Fact_Investigation`                                                    | PostgreSQL          | None                                                                                   |
| **False Positive Investigations** | `COUNT(CASE WHEN Resolution_Code = 'False Positive' END)`                | N/A                                                                         | Investigation      | `vw_Fact_Investigation`                                                    | PostgreSQL          | None                                                                                   |
| **Investigation Confirmation Rate** | `Confirmed Fraud Investigations`                                        | `Confirmed Fraud Investigations + False Positive Investigations`          | Investigation      | `vw_Fact_Investigation`                                                    | DAX                 | Excludes unresolved cases                                                               |
| **Case Resolution Time (ACT)** | `AVG(EXTRACT(EPOCH FROM (Case_Closed_At - Case_Opened_At)) / 3600.0)` | N/A                                                                         | Investigation      | `vw_Fact_Investigation` (filtered for `Case_Closed_At IS NOT NULL`)        | PostgreSQL          | Unresolved cases excluded; timezone handling                                           |
| **True Positives (TP)**       | `COUNT(CASE WHEN ML_Status = 'High_Risk - ML Flag' AND Ground_Truth_Label = true END)` | N/A                                                                         | Model/Risk Tier   | `vw_Fct_Transaction_Scored`                                                | PostgreSQL          | Class imbalance; synthetic data                                                        |
| **False Positives (FP)**      | `COUNT(CASE WHEN ML_Status = 'High_Risk - ML Flag' AND Ground_Truth_Label = false END)` | N/A                                                                         | Model/Risk Tier   | `vw_Fct_Transaction_Scored`                                                | PostgreSQL          | None                                                                                   |
| **True Negatives (TN)**       | `COUNT(CASE WHEN ML_Status = 'Nominal' AND Ground_Truth_Label = false END)` | N/A                                                                         | Model/Risk Tier   | `vw_Fct_Transaction_Scored`                                                | PostgreSQL          | None                                                                                   |
| **False Negatives (FN)**      | `COUNT(CASE WHEN ML_Status = 'Nominal' AND Ground_Truth_Label = true END)` | N/A                                                                         | Model/Risk Tier   | `vw_Fct_Transaction_Scored`                                                | PostgreSQL          | None                                                                                   |
| **Precision**                 | `TP`                                                                    | `TP + FP`                                                                | Model/Risk Tier   | (see TP/FP)                                                              | DAX                 | Requires TP/FP from SQL; class imbalance                                               |
| **Recall**                    | `TP`                                                                    | `TP + FN`                                                                | Model/Risk Tier   | (see TP/FN)                                                              | DAX                 | Requires TP/FN from SQL; class imbalance                                               |
| **False Positive Rate (FPR)** | `FP`                                                                    | `FP + TN`                                                                | Model             | (see FP/TN)                                                              | DAX                 | Requires FP/TN from SQL                                                                |
| **Avg_Trans_Volume_D7**       | `SUM(Amount) / 7.0` (over 7 calendar days)                              | N/A                                                                         | Customer          | `vw_Dim_Customer_Enriched` (via CTE)                                      | SQL                 | Anchor date = customer's latest transaction; not rolling velocity                      |
| **Analyst Workload**          | `COUNT(Investigation_ID)`                                               | N/A                                                                         | Analyst           | `vw_Fact_Investigation`                                                    | PostgreSQL          | Includes unresolved cases (opened but not closed)                                      |

---

## 3. Analytical Dimensions
- **Time:** Day, week, month (from existing `Dim_Date` table via `vw_Dim_Date` if available; else derive from `Timestamp`).
- **Channel:** `Channel_Name` (`vw_Fct_Transaction_Scored`).
- **Merchant Industry:** `Industry_Code` (joined from `vw_Dim_Merchant_Enriched` if available; else use `Industry` from `vw_Fct_Transaction_Scored`).
- **Customer Risk Tier:** `Customer_Risk_Category` (`vw_Dim_Customer_Enriched`).
- **Transaction Amount:** Binned ranges (e.g., <$100, $100-500).
- **Fraud Rules:** `Rule_Name` (`vw_Fact_Alerts`).
- **Investigation Outcomes:** `Resolution_Code` (`vw_Fact_Investigation`).

---

## 4. KPI Implementation Layers
- **PostgreSQL (SQL):** Aggregations (e.g., counts, sums, `Avg_Trans_Volume_D7`).
- **Power BI DAX:** Ratios, rates, and multi-dimensional calculations (e.g., Precision, Recall, FPR).

---

## 5. Core Metrics & Caveats
- **Fraud Rate (Ground Truth):** Includes all transactions (alerted and unalerted).
- **Precision/Recall/FPR:** Model evaluation uses `ML_Status` and `Ground_Truth_Label`; class imbalance impacts metrics.
- **Alert-to-Investigation Rate:** Uses distinct alerts to avoid duplication.
- **Avg_Trans_Volume_D7:** Calendar-day window, anchored to customer's latest transaction (not velocity).
- **Case Resolution Time:** Reported in hours; excludes unresolved cases.
- **Analyst Workload:** Counts all assigned investigations (open and closed).

---

## 6. Dashboard Pages
1. **Executive Fraud Overview**
   - KPIs: Fraud Amount (Ground Truth), Fraud Rate, Confirmed Fraud, False Positives.
   - Visuals: Time trends (line chart), industry treemap, risk tier bar chart.
2. **Detection Performance**
   - KPIs: Precision, Recall, FPR by customer risk tier.
   - Visuals: PR curve, confusion matrix, rule effectiveness table.
3. **Investigation Operations**
   - KPIs: ACT, Confirmation Rate, Analyst Workload.
   - Visuals: Gantt chart (case duration), workload heatmap (analyst vs. cases).
4. **Fraud Pattern Analysis**
   - KPIs: High-velocity customers, alert patterns by rule.
   - Visuals: Scatter plot (amount vs. velocity), alert volume bar chart.

---

## 7. Validation Plan
1. **SQL Metrics:**
   - Verify `Fraud Amount (Ground Truth)` matches the direct sum of `Amount` where `Ground_Truth_Label = true`.
   - Validate `Avg_Trans_Volume_D7` for 5 customers against direct calculation.
2. **DAX Metrics:**
   - Cross-check `Precision` and `Recall` with TP/FP/TN/FN counts from SQL.
   - Ensure `FPR` uses `FP + TN` denominator.
3. **Class Imbalance Awareness:**
   - Document impact on model metrics (no weighting applied in Phase 2).
4. **Alert-Investigation Link:**
   - Confirm distinct alert counts in `Alert-to-Investigation Rate`.

---

## 8. Do Not Implement Yet
- **Geographic Analysis:** No suitable geographic field available.
- **Customer Churn:** Requires new data (churn flags).
- **Account-Opening Correlation:** Requires account creation dates.
- **Recovery Rate:** No recovery amount data.
- **Transaction Velocity:** Distinct from `Avg_Trans_Volume_D7`; requires separate definition.

---

## 9. Unresolved Decisions
1. **Fraud Type Categorization:** Awaiting investigation data schema.

---

## Implemented Phase 2 Architecture
- **PostgreSQL:** Built on existing Phase 1 views (`SQL/02_views.sql`); no materialized views needed for 50k-row scale.
- **Power BI:** Import mode used for `Banking_fraud_intelligence.pbix`.

---

## Status
Approved, implemented in `SQL/03_fraud_analytics.sql`, and validated in [PHASE_2_VALIDATION.md](../docs/PHASE_2_VALIDATION.md).