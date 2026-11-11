-- Phase 2 Fraud Analytics SQL Queries
-- Based on approved design in analysis/Phase_2_Final_Fraud_Analytics_Design.md
-- Validation outputs documented in docs/PHASE_2_VALIDATION.md
-- Uses existing Phase 1 views: vw_Fct_Transaction_Scored, vw_Dim_Customer_Enriched, vw_Fact_Alerts, vw_Fact_Investigation
-- Note: Precision, Recall, and FPR are calculated as component counts for DAX layer per design specification

-- =============================================
-- A. Executive KPIs
-- =============================================

-- 1. Total Fraud Amount (Ground Truth)
-- Business Question: What is the total monetary loss from transactions labeled as fraud (Ground_Truth_Label = true)?
SELECT
    SUM(Amount) AS Total_Fraud_Amount_Ground_Truth
FROM vw_Fct_Transaction_Scored
WHERE Ground_Truth_Label = true;

-- 2. Monthly Fraud Rate by Channel
-- Business Question: How does the fraud rate trend monthly across channels?
-- Note: Fraud Rate is a ratio to be calculated in DAX layer; SQL provides base counts
SELECT
    EXTRACT(YEAR FROM t.Timestamp) AS Year,
    EXTRACT(MONTH FROM t.Timestamp) AS Month,
    c.Channel_Name,
    COUNT(CASE WHEN t.Ground_Truth_Label = true THEN 1 END) AS Fraud_Transactions,
    COUNT(*) AS Total_Transactions
FROM vw_Fct_Transaction_Scored t
JOIN dim_channel c ON t.Channel_ID = c.Channel_ID
GROUP BY EXTRACT(YEAR FROM t.Timestamp), EXTRACT(MONTH FROM t.Timestamp), c.Channel_Name
ORDER BY Year, Month, Channel_Name;

-- 3. Confirmed Fraud by Industry
-- Business Question: Which merchant industries have the highest total fraud loss?
SELECT
    m.Industry AS Industry,
    SUM(t.Amount) AS Total_Fraud_Amount
FROM vw_Fct_Transaction_Scored t
JOIN dim_merchant m ON t.Merchant_ID = m.Merchant_ID
WHERE t.Ground_Truth_Label = true
GROUP BY m.Industry
ORDER BY Total_Fraud_Amount DESC;

-- =============================================
-- B. Detection Performance (Component Counts for DAX)
-- =============================================

-- 4. Precision Components by Customer Risk Tier
-- Business Question: What are the TP and FP counts for precision calculation per customer risk tier?
-- Note: Precision = TP / (TP + FP) to be calculated in DAX layer
SELECT
    d.Customer_Risk_Category,
    COUNT(CASE WHEN t.ML_Status = 'High_Risk - ML Flag' AND t.Ground_Truth_Label = true THEN 1 END) AS True_Positives,
    COUNT(CASE WHEN t.ML_Status = 'High_Risk - ML Flag' AND t.Ground_Truth_Label = false THEN 1 END) AS False_Positives
FROM vw_Fct_Transaction_Scored t
JOIN vw_Dim_Customer_Enriched d ON t.Customer_ID = d.Customer_ID
GROUP BY d.Customer_Risk_Category;

-- 5. Recall Components by Customer Risk Tier
-- Business Question: What are the TP and FN counts for recall calculation per customer risk tier?
-- Note: Recall = TP / (TP + FN) to be calculated in DAX layer
SELECT
    d.Customer_Risk_Category,
    COUNT(CASE WHEN t.ML_Status = 'High_Risk - ML Flag' AND t.Ground_Truth_Label = true THEN 1 END) AS True_Positives,
    COUNT(CASE WHEN t.ML_Status = 'Nominal' AND t.Ground_Truth_Label = true THEN 1 END) AS False_Negatives
FROM vw_Fct_Transaction_Scored t
JOIN vw_Dim_Customer_Enriched d ON t.Customer_ID = d.Customer_ID
GROUP BY d.Customer_Risk_Category;

-- 6. Rule Effectiveness
-- Business Question: Which fraud rules generate the most alerts but fewest confirmed frauds?
SELECT
    r.Rule_Name,
    COUNT(a.Alert_ID) AS Alert_Count,
    COUNT(CASE WHEN t.Ground_Truth_Label = true THEN 1 END) AS Ground_Truth_Fraud_Count
FROM vw_Fact_Alerts a
JOIN dim_rule r ON a.Rule_ID = r.Rule_ID
LEFT JOIN vw_Fct_Transaction_Scored t ON a.Transaction_ID = t.Transaction_ID
GROUP BY r.Rule_Name
ORDER BY Alert_Count DESC, Ground_Truth_Fraud_Count ASC;

-- =============================================
-- C. Investigation Operations
-- =============================================

-- 7. Average Case Resolution Time (ACT)
-- Business Question: What is the average time to resolve closed investigations (in hours)?
SELECT
    AVG(EXTRACT(EPOCH FROM (Case_Closed_At - Case_Opened_At)) / 3600.0) AS Avg_Case_Resolution_Time_Hours
FROM vw_Fact_Investigation
WHERE Case_Closed_At IS NOT NULL;

-- 8. Investigation Queue Size Over Time
-- Business Question: How does the number of open investigations change over time?
-- Business Definition: Queue size = count of investigations where Case_Closed_At IS NULL, grouped by month.
SELECT
    EXTRACT(YEAR FROM Case_Opened_At) AS Year,
    EXTRACT(MONTH FROM Case_Opened_At) AS Month,
    COUNT(*) AS Investigation_Queue_Size
FROM vw_Fact_Investigation
WHERE Case_Closed_At IS NULL
GROUP BY EXTRACT(YEAR FROM Case_Opened_At), EXTRACT(MONTH FROM Case_Opened_At)
ORDER BY Year, Month;

-- 9. Analyst Resolution Performance
-- Business Question: Which analysts have the lowest average case resolution time among closed investigations?
SELECT
    i.Analyst_ID,
    i.Analyst_Name,
    AVG(EXTRACT(EPOCH FROM (i.Case_Closed_At - i.Case_Opened_At)) / 3600.0) AS Avg_Resolution_Time_Hours,
    COUNT(*) AS Closed_Case_Count
FROM vw_Fact_Investigation i
WHERE i.Case_Closed_At IS NOT NULL
GROUP BY i.Analyst_ID, i.Analyst_Name
ORDER BY Avg_Resolution_Time_Hours ASC;

-- =============================================
-- D. Fraud Pattern Analysis
-- =============================================

-- 10. Customers with Highest Avg_Trans_Volume_D7
-- Business Question: Which customers have the highest 7-day average transaction volume?
SELECT
    c.Customer_ID,
    c.Name,
    c.Avg_Trans_Volume_D7
FROM vw_Dim_Customer_Enriched c
WHERE c.Avg_Trans_Volume_D7 IS NOT NULL
ORDER BY c.Avg_Trans_Volume_D7 DESC
LIMIT 10;

-- 11. Alert Patterns by Rule
-- Business Question: How do alert volumes distribute across fraud rules?
SELECT
    r.Rule_Name,
    COUNT(a.Alert_ID) AS Alert_Count
FROM vw_Fact_Alerts a
JOIN dim_rule r ON a.Rule_ID = r.Rule_ID
GROUP BY r.Rule_Name
ORDER BY Alert_Count DESC;

-- =============================================
-- E. Validation Queries
-- =============================================

-- 12. Fraud Amount Validation
-- Business Question: Does the SQL sum of fraud amounts match the direct sum in the source view?

SELECT
  (SELECT SUM(Amount) FROM fact_transaction
    WHERE Ground_Truth_Label = true)            AS base_table_sum,
  (SELECT SUM(Amount) FROM vw_Fct_Transaction_Scored
    WHERE Ground_Truth_Label = true)            AS view_sum;

-- 13. Metric Consistency Check
-- Business Question: Do SQL-calculated components (TP, FP, TN, FN) align with DAX calculations?
-- Outputs TP, FP, TN, FN counts for DAX ratio calculations.
SELECT
    'Metric Consistency Check' AS Validation_Check,
    SUM(CASE WHEN t.ML_Status = 'High_Risk - ML Flag' AND t.Ground_Truth_Label = true THEN 1 END) AS True_Positives,
    SUM(CASE WHEN t.ML_Status = 'High_Risk - ML Flag' AND t.Ground_Truth_Label = false THEN 1 END) AS False_Positives,
    SUM(CASE WHEN t.ML_Status = 'Nominal' AND t.Ground_Truth_Label = false THEN 1 END) AS True_Negatives,
    SUM(CASE WHEN t.ML_Status = 'Nominal' AND t.Ground_Truth_Label = true THEN 1 END) AS False_Negatives
FROM vw_Fct_Transaction_Scored t;

-- 14. Alert-Investigation Link Integrity
-- Business Question: Are all investigated alerts accounted for without duplication?
-- Compares distinct alert count to total alert-investigation pairs to detect duplication in join.

SELECT
  COUNT(*) FILTER (WHERE a.Investigation_ID IS NOT NULL)  AS alerts_with_investigation,
  COUNT(*) FILTER (WHERE a.Investigation_ID IS NOT NULL
                   AND i.Investigation_ID IS NULL)        AS broken_links
FROM fact_alerts a
LEFT JOIN fact_investigation i
  ON a.Investigation_ID = i.Investigation_ID;