# Banking Fraud Analytics Dashboard

A SQL and Power BI analysis of **50,000 synthetic banking transactions** ($12.64M total volume, Jan to Jul 2026). The project models the data in PostgreSQL, builds reporting views, and answers four questions: how much fraud there is, where it concentrates, how well the supplied risk scores detect it, and how much work investigating alerts creates.

**Stack:** PostgreSQL, SQL, Power BI (DAX)
**Report:** open `Banking_fraud_intelligence.pbix` in Power BI Desktop, or read the exported 6-page `Banking_fraud_intelligence.pdf`.

## About the data

The data is **synthetic**: 11 CSV files in `output/`, loaded unmodified. [Add one line: who or what generated them, e.g. "generated with a script I wrote" or "a public synthetic dataset from <source>".]

Fraud labels, risk scores, alerts, and investigation outcomes come with the source data. This project **evaluates** the supplied scores against the labels; it does not train a model. Because the data is synthetic, precision, recall, and rule hit rates reflect how the data was built, not real banking operations.

## Key findings

| Question | Finding |
|---|---|
| How much fraud? | 500 of 50,000 transactions (1.00%) are fraud, but they account for $945,301.87, or 7.48% of dollar volume |
| How large are fraud transactions? | Average $1,890.60 (median $402.57) vs. $236.26 (median $42.89) for legitimate ones |
| Where does it concentrate? | Travel is 5.23% of transactions but has an 8.15% fraud rate and 84.71% of fraud loss ($800,806.47). Retail, Tech, and Dining are all below 0.75% |
| Does size matter? | Transactions of $1,000 or more (1,437) have a 16.35% fraud rate vs. 0.48% to 0.57% below $1,000 |
| When does it happen? | Fraud rate peaks at 6.43% at 02:00 (33 of 513 transactions). One $43,005.34 Mobile App transaction (TX0008050) drives the April 2026 peak |
| How good are the risk scores? | At the supplied threshold: 2,925 transactions flagged, 450 of 500 frauds caught (90.00% recall), 5.00% false positive rate, 15.38% precision. Analysts review about 6.5 flagged cases per confirmed fraud |
| Which rules are noisy? | Night-Time-Activity produces 2,870 of 7,820 alerts (36.7%) with a 1.85% fraud hit rate. Multiple-Risk-Signals has a 64.45% hit rate (426 fraud alerts) and High-Risk-Merchant 89.24% |
| How is investigation going? | All 2,925 cases are closed (450 confirmed fraud, 2,475 false positives), averaging 47.97 hours, split evenly across 10 analysts |

Several rules (Geo-Mismatch, New-Device, Rapid-Amount-Escalation, Velocity-High) show 100% hit rates on small alert volumes. Treat these as artifacts of the synthetic data, not as evidence the rules are perfect.

## Data model

An 11-table star schema in PostgreSQL (`SQL/01_schema.sql`), plus four reporting views (`SQL/02_views.sql`).

| Type | Table | Rows | Purpose |
|---|---|---|---|
| Fact | `fact_transaction` | 50,000 | Amounts, labels, risk scores |
| Fact | `fact_alerts` | 7,820 | Rule alerts linked to transactions and investigations |
| Fact | `fact_investigation` | 2,925 | Case timestamps, analysts, outcomes |
| Dim | `dim_customer` | 1,000 | Segment, risk tier, region |
| Dim | `dim_account` | 1,500 | Account type, open date |
| Dim | `dim_merchant` | 500 | Industry, MCC code |
| Dim | `dim_device` | 200 | OS, browser, fingerprint confidence |
| Dim | `dim_date` | 183 | Calendar attributes, 2026-01-01 to 2026-07-02 |
| Dim | `dim_channel` | 3 | Mobile App, Web, POS Terminal |
| Dim | `dim_analyst` | 10 | Analysts and shifts |
| Dim | `dim_rule` | 10 | Detection rules R01 to R10 |

**Views:** `vw_Fct_Transaction_Scored` (adds a 0 to 100 risk score and flag status), `vw_Dim_Customer_Enriched` (adds risk category and a 7-day trailing average spend), `vw_Fact_Alerts` (adds rule names and transaction dates), `vw_Fact_Investigation` (adds analyst names and transaction dates).

## Report pages

1. **Executive Fraud Overview:** headline KPIs, monthly trend by channel, fraud loss by industry
2. **Key Findings:** industry risk, high-value transactions, rule noise, analyst workload
3. **Detection Performance:** confusion matrix (TP 450, FP 2,475, TN 47,025, FN 50), precision, recall, FPR, risk-tier comparison
4. **Investigation Operations:** outcomes, turnaround time, workload by analyst
5. **Fraud Pattern Analysis:** fraud rate by industry, hour, amount band, and rule
6. **Limitations and Data Notes**

## Reproduce locally

1. Create a PostgreSQL database and run `SQL/01_schema.sql`.
2. Load the 11 CSVs from `output/`: dimensions first, then `fact_transaction`, `fact_investigation`, `fact_alerts`.
3. Dates in four files use DD-MM-YYYY. Run `SET datestyle = 'ISO, DMY';` before importing.
4. Run `SQL/02_views.sql`, then `SQL/03_fraud_analytics.sql` to reproduce the KPIs and checks.
5. To view the report, open the `.pbix` and point it at the four views.

## Limitations

- **Synthetic data, 1.00% fraud rate.** Metrics describe this dataset, not production banking.
- **Labels and outcomes align.** Investigation outcomes match the ground-truth labels on flagged cases, so the confirmation rate is not an independent check of the labels.
- **Closed cases only.** There is no open backlog in this snapshot.
- **236 transactions have no merchant ID** (2 fraud cases, $4,591.65). They are kept as "unmapped" rather than guessed, which is why industry-mapped fraud is $940,710.22 against $945,301.87 in total.
- **Out of scope:** IP geolocation, churn, fraud recovery, and fraud-type categories need fields the source data doesn't contain.

## Repository structure

```
├── README.md
├── Banking_fraud_intelligence.pbix
├── Banking_fraud_intelligence.pdf
├── SQL/
│   ├── 01_schema.sql
│   ├── 02_views.sql
│   └── 03_fraud_analytics.sql
├── output/                  # 11 source CSVs
├── analysis/                # KPI definitions
├── docs/                    # validation notes
└── database_profiling.txt   # exploratory profiling queries and output
```
