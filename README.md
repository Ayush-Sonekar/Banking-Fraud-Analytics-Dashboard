# Banking Transaction & Fraud Intelligence Platform

An end-to-end fraud analytics and business intelligence portfolio project analyzing **50,000 synthetic banking transactions** (`$12.64M` total volume from Jan–Jul 2026) using **PostgreSQL** and **Power BI (DAX)** to evaluate financial fraud exposure, ML detection trade-offs, rule effectiveness, and investigation operations.

> **Interactive Report:** Open [Banking_fraud_intelligence.pbix](Banking_fraud_intelligence.pbix) in Power BI Desktop, or view the exported 6-page report in [Banking_fraud_intelligence.pdf](Banking_fraud_intelligence.pdf).

---

## Executive Summary & Key Findings

- **Fraud Exposure:** `500` of `50,000` transactions (`1.00%` volume) are labeled fraud (`Ground_Truth_Label = true`), accounting for **`$945,301.87`** (**`7.48%`** of total dollar volume). Fraudulent transactions average `$1,890.60` (median `$402.57`) compared to `$236.26` (median `$42.89`) for legitimate transactions.
- **Extreme Industry Concentration:** **Travel** represents just `5.23%` of transactions (`2,615` txns), yet exhibits an **`8.15%` fraud rate** (`213` fraud cases) and accounts for **`$800,806.47` (`84.71%` of total fraud loss)**. Other industries (`Retail`, `Tech`, `Dining`) all sit below `0.75%`.
- **High-Value & Off-Hours Spikes:** Transactions of `$1,000+` (`1,437` txns) have a **`16.35%` fraud rate** (vs. `0.48%–0.57%` under `$1,000`). Hourly profiling shows a sharp **`6.43%` fraud rate spike at 02:00 AM** (`33` fraud out of `513` txns), while a `43,005.34` Mobile App fraud transaction (`TX0008050`) drove the April 2026 peak.
- **ML Detection Trade-Off:** The scoring threshold flags `2,925` transactions (`5.85%`), achieving **`90.00%` Recall** (`450 / 500` frauds caught) at a **`5.00%` False Positive Rate** (`2,475` false alarms), yielding **`15.38%` Precision**—meaning analysts review **~6.5 flagged cases per confirmed fraud**. Recall drops from `91.03%` (Low-risk tier) to `81.48%` (High-risk tier, `n = 54` fraud cases).
- **Rule Noise vs. High-Signal Rules:** Out of `7,820` total alerts, `Night-Time-Activity` generates **`2,870` alerts (`36.7%` of all alert volume)** with only a **`1.85%` fraud hit rate** (`53` fraud alerts). By contrast, rules such as `Multiple-Risk-Signals` (`64.45%` hit rate, `426` fraud alerts), `High-Risk-Merchant` (`89.24%`), `Geo-Mismatch` (`100%`), `New-Device` (`100%`), `Rapid-Amount-Escalation` (`100%`), and `Velocity-High` (`100%`) deliver dramatically higher precision.
- **Investigation Operations:** All `2,925` investigations are closed (`450` Confirmed Fraud, `2,475` False Positive) with an average turnaround time of **`47.97` hours**, distributed evenly across `10` analysts (`292–293` cases each). `4,539` of `7,820` alert rows (`58.04%`) are linked to those `2,925` investigations.

---

## Business Questions Addressed

1. **Executive Fraud Overview:** What is the overall fraud rate, gross fraud loss, monthly channel trend, and industry concentration?
2. **Detection Performance:** How well do ML predictions (`Is_Predicted_Fraud`) perform against `Ground_Truth_Label` across precision, recall, FPR, and customer risk tiers?
3. **Investigation Operations:** What is the alert-to-investigation rate, confirmation rate, analyst workload balance, and average case turnaround time?
4. **Fraud Pattern Analysis:** Which merchant industries, transaction amount bands, hours of day, and rule types drive fraud concentration vs. false-positive noise?

---

## Architecture & Data Model

The PostgreSQL warehouse implements an **11-table star schema** (3 fact tables, 8 dimension tables) in [SQL/01_schema.sql](SQL/01_schema.sql) with a non-destructive analytical view layer in [SQL/02_views.sql](SQL/02_views.sql):

### Base Tables ([`SQL/01_schema.sql`](SQL/01_schema.sql))
| Type | Table | Row Count | Description |
|------|-------|----------:|-------------|
| **Fact** | `fact_transaction` | 50,000 | Transaction events, amounts, ground-truth labels, ML scores |
| **Fact** | `fact_alerts` | 7,820 | Rule-based alerts linked to transactions and investigations |
| **Fact** | `fact_investigation` | 2,925 | Investigation lifecycle timestamps, analyst assignments, outcomes |
| **Dim** | `dim_customer` | 1,000 | Customer segment (`Retail`/`Corporate`), risk tier (`Low`/`High`), region |
| **Dim** | `dim_account` | 1,500 | Account metadata (`Checking`, `Savings`, etc.) and open dates |
| **Dim** | `dim_merchant` | 500 | Merchant industry (`Travel`, `Retail`, `Tech`, `Dining`) and MCC codes |
| **Dim** | `dim_device` | 200 | Device OS, browser, and fingerprint confidence |
| **Dim** | `dim_date` | 183 | Calendar attributes (`2026-01-01` to `2026-07-02`) |
| **Dim** | `dim_channel` | 3 | `Mobile App`, `Web`, `POS Terminal` |
| **Dim** | `dim_analyst` | 10 | Fraud operations analysts (`Analyst_00`–`Analyst_09`) and shifts |
| **Dim** | `dim_rule` | 10 | Detection rules (`R01`–`R10`) and logic categories |

### Analytical Views ([`SQL/02_views.sql`](SQL/02_views.sql))
- `vw_Fct_Transaction_Scored` — Transaction fact enriched with `Transaction_Date`, scaled `ML_Risk_Score` (`0–100`), and `ML_Status` (`High_Risk - ML Flag` / `Nominal`).
- `vw_Dim_Customer_Enriched` — Customer dimension enriched with `Customer_Risk_Category` and `Avg_Trans_Volume_D7` (7-day trailing average daily spend anchored to each customer's latest transaction date).
- `vw_Fact_Alerts` — Alert grain enriched with `Rule_Name` and transaction dates (preserving 1:n alert-to-transaction links).
- `vw_Fact_Investigation` — Investigation grain enriched with `Analyst_Name` and transaction dates.

---

## Dashboard Pages ([`Banking_fraud_intelligence.pdf`](Banking_fraud_intelligence.pdf))

1. **Executive Fraud Overview** — Headline KPIs (`50,000` txns, `1.00%` fraud rate, `$945,302` fraud amount, `450` confirmed cases, `2,925` investigations), monthly channel trend, and fraud loss by industry.
2. **Key Findings** — Synthesized executive takeaways on industry risk, `$1,000+` amount risk, `Night-Time-Activity` noise, and analyst review overhead (`~6.5` flags per confirmed fraud).
3. **Detection Performance** — Confusion matrix (`TP=450`, `FP=2,475`, `TN=47,025`, `FN=50`), `15.38%` Precision, `5.00%` FPR, `90.00%` Recall, and risk-tier comparison.
4. **Investigation Operations** — Outcome breakdown (`2,475` False Positive vs. `450` Confirmed Fraud), `47.97h` average turnaround, and workload parity across `10` analysts.
5. **Fraud Pattern Analysis** — Fraud rate by merchant industry, hour of day, transaction size band, and rule effectiveness table.
6. **Limitations & Data Notes** — Synthetic dataset caveats, class imbalance, closed-only case state, and unmapped merchant reconciliation.

---

## Repository Structure

```text
├── README.md                                      # Project overview, findings, and setup guide
├── Banking_fraud_intelligence.pbix                # Power BI Desktop semantic model & report
├── Banking_fraud_intelligence.pdf                 # Exported 6-page Power BI dashboard report
├── SQL/
│   ├── 01_schema.sql                              # 11-table PostgreSQL DDL, FKs, and indexes
│   ├── 02_views.sql                               # 4 analytical reporting views
│   └── 03_fraud_analytics.sql                     # 14 KPI & reconciliation queries (SQL + DAX split)
├── output/                                        # Source synthetic CSVs (11 tables, unmodified)
├── analysis/
│   └── Phase_2_Final_Fraud_Analytics_Design.md    # Approved KPI dictionary & BI architecture
├── docs/
│   ├── 00_initial_vision_brief.md                 # Initial Phase 0 brief (pre-profiling scope)
│   └── PHASE_2_VALIDATION.md                      # SQL execution outputs & reconciliation audit
├── ANALYSIS_PLAN.md                               # Phase-by-phase execution plan & governance rules
├── DESIGN_VALIDATION.md                           # Phase 1 schema gap analysis & view design sign-off
├── PROJECT_STATUS.md                              # Final project status & deliverables summary
└── database_profiling.txt                         # 38 PostgreSQL exploratory profiling queries & outputs
```

---

## Reproducing Locally in PostgreSQL

1. Create a database (e.g., `banking_fraud_intelligence`) and run [`SQL/01_schema.sql`](SQL/01_schema.sql).
2. Load the 11 CSVs from `output/` (dimensions first, then `fact_transaction`, `fact_investigation`, `fact_alerts`).
   > **Important:** Date fields in `dim_account.csv`, `dim_date.csv`, `fact_alerts.csv`, and `fact_transaction.csv` use `DD-MM-YYYY` (`DMY`) formatting. Set `SET datestyle = 'ISO, DMY';` in your session (or configure `DMY` date order in pgAdmin 4) before importing.
3. Run [`SQL/02_views.sql`](SQL/02_views.sql) to create the 4 analytical views.
4. Execute [`SQL/03_fraud_analytics.sql`](SQL/03_fraud_analytics.sql) to reproduce all KPIs and validation checks, or connect Power BI Desktop to the PostgreSQL views.

---

## Known Limitations & Analytical Caveats

- **Synthetic Data & Class Imbalance:** Data is synthetic (`1.00%` fraud rate); precision/recall metrics reflect synthetic label distributions rather than production banking operations.
- **Label Alignment:** Investigation `Resolution_Code` values (`450` Confirmed Fraud, `2,475` False Positive) match `Ground_Truth_Label` on ML-flagged cases; confirmation rate is therefore not an independent audit of ground truth.
- **Closed Snapshot:** All `2,925` investigations have `Case_Closed_At` populated (`0` open backlog rows in the current snapshot), and cases are evenly distributed across the `10` analysts (`292–293` cases each).
- **Unmapped Merchants:** `236` transactions (`2` fraud cases totaling `$4,591.65`) have `NULL` `Merchant_ID` (`$945,301.87` total fraud vs. `$940,710.22` industry-mapped fraud). These records are preserved as unmapped rather than fabricated.
- **Deferred Scope:** Geographic IP analysis, customer churn, fraud recovery rate, and fraud-type taxonomy require external attributes not present in the source CSVs and are intentionally excluded.
