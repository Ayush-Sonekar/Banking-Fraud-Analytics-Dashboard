# Phase 2 SQL Implementation & Validation Results

## Execution Results

**Q1. Total Ground-Truth Fraud Amount**
- **Result:** 945,301.87

**Q2. Monthly Fraud-Rate Components by Channel**
- Executed successfully. Fraud Rate calculated in DAX as: Fraud Transactions / Total Transactions.

**Q3. Fraud Loss by Merchant Industry**
- Executed successfully.

**Q4. Precision Components by Customer Risk Tier**
- Executed successfully.

**Q5. Recall Components by Customer Risk Tier**
- Executed successfully.

**Q6. Rule Alert-Volume Analysis**
- Executed successfully.

**Q7. Average Case Resolution Time**
- **Result:** 47.9675 hours (~48 hours).

**Q8. Investigation Queue Size Over Time**
- **Result:** No open investigations returned (current dataset state).

**Q9. Analyst Resolution Performance**
- **Result:** 292–293 closed cases per analyst; average resolution times: 46.20–48.86 hours.

**Q10. Avg_Trans_Volume_D7 Analysis**
- Executed successfully. **Note:** This metric represents 7-day average transaction volume, not velocity.

**Q11. Alert Patterns by Rule**
- Executed successfully.

---

## Validation Results

**Q12. Fraud Amount Validation**
- **Result:** SQL sum = Direct sum = 945,301.87.

**Q13. Confusion Matrix Components**
- **Counts:** TP=450, FP=2,475, TN=47,025, FN=50.
- **Derived Metrics:**
  - Precision = 15.38%
  - Recall = 90.00%
  - FPR = 5.00%

**Alert Coverage**
- **Total Alerts:** 7,820
- **Alert Rows Linked to Investigations:** 4,539 (corresponding to 2,925 distinct investigations, since multiple rule alerts on a single transaction share one `Investigation_ID`)
- **Uninvestigated Alerts:** 3,281
- **Alert-to-Investigation Rate:** 58.04% (alert-row grain; 37.40% at distinct investigation-to-alert grain)

**Alert-Investigation Link Integrity**
- Distinct investigated alerts = Total alert-investigation pairs (4,539). No duplicate alert rows introduced by the join.

**Fraud Amount Reconciliation**
- **Total Ground-Truth Fraud:** 945,301.87
- **Industry-Attributed Fraud:** 940,710.22
- **Difference:** 4,591.65 (explained by 2 unmapped ground-truth fraud transactions).

---

## Analytical Caveats

1. **Ground-Truth Label Definition:**
   - `Ground_Truth_Label` indicates ground-truth fraud, **not** investigation-confirmed fraud. Metrics using this field (e.g., Q1, Q3) reflect known fraud cases from synthetic data, not operational outcomes.

2. **Rule Effectiveness Limitations:**
   - Rule-level fraud counts show associations between alerts and ground-truth transactions. They **do not** imply causal attribution (e.g., "Rule X detected fraud Y"). Rules may correlate with fraud without independently causing detection.

3. **Investigation Queue State:**
   - Q8 returning no open investigations reflects the **current dataset snapshot**, not a universal business conclusion. This may not represent live operational data.

4. **Dimensional Coverage:**
   - Two ground-truth fraud transactions (totaling 4,591.65) lack merchant mappings. These **must not** be fabricated into an industry or silently altered. Document this as a data limitation.

---

## Delivery Status
- Power BI semantic model and 6-page dashboard completed in `Banking_fraud_intelligence.pbix` and exported to `Banking_fraud_intelligence.pdf`.
- Deferred items (geographic analysis, customer churn, recovery rate, fraud type categorization) remain out of scope unless additional source attributes become available.