-- Phase 1 Analytical Views for Banking Transaction & Fraud Intelligence
-- Created: 2026-09-29
-- Purpose: Implement approved Phase 1 schema-alignment decisions as views (no base table changes)

-- =============================================
-- vw_Fct_Transaction_Scored
-- Grain: one row per transaction
-- =============================================
CREATE OR REPLACE VIEW vw_Fct_Transaction_Scored AS
SELECT
    ft.Transaction_ID,
    ft.Timestamp,
    ft.Amount,
    ft.Customer_ID,
    ft.Account_ID,
    ft.Merchant_ID,
    ft.Date_ID,
    ft.Channel_ID,
    ft.Device_ID,
    ft.Ground_Truth_Label,
    ft.Model_Predicted_Score,
    ft.Is_Predicted_Fraud,
    -- Derived columns per approved decisions
    DATE(ft.Timestamp) AS Transaction_Date,
    ROUND(ft.Model_Predicted_Score * 100) AS ML_Risk_Score,
    CASE
        WHEN ft.Is_Predicted_Fraud THEN 'High_Risk - ML Flag'
        ELSE 'Nominal'
    END AS ML_Status
FROM fact_transaction ft;


-- =============================================
-- vw_Dim_Customer_Enriched
-- Grain: one row per customer
-- =============================================
CREATE OR REPLACE VIEW vw_Dim_Customer_Enriched AS
SELECT
    dc.Customer_ID,
    dc.Name,
    dc.Segment,
    dc.Risk_Tier,
    dc.Region,
    -- Approved Customer_Risk_Category: direct mapping from Risk_Tier (no invented Medium)
    CASE
        WHEN dc.Risk_Tier = 'Low' THEN 'Low'
        WHEN dc.Risk_Tier = 'High' THEN 'High'
        ELSE NULL  -- NULL for any other Risk_Tier values (though data only has Low/High)
    END AS Customer_Risk_Category,
    -- Approved Segment_Hierarchy: use existing Segment as base level
    dc.Segment AS Segment_Hierarchy,
    -- Avg_Trans_Volume_D7: average daily monetary transaction volume over trailing 7 calendar days
    -- Anchor date: customer's latest available transaction date
    cv.avg_daily_volume_7d AS Avg_Trans_Volume_D7
FROM dim_customer dc
LEFT JOIN (
    -- Calculate 7-day trailing sum of Amount per customer, anchored to each customer's latest transaction date
    WITH customer_max_date AS (
        SELECT
            Customer_ID,
            MAX(DATE(Timestamp)) AS max_txn_date
        FROM fact_transaction
        GROUP BY Customer_ID
    ),
    customer_sums AS (
        SELECT
            ft.Customer_ID,
            SUM(ft.Amount) AS total_amount_7d
        FROM fact_transaction ft
        JOIN customer_max_date cmd
            ON ft.Customer_ID = cmd.Customer_ID
        WHERE DATE(ft.Timestamp) BETWEEN (cmd.max_txn_date - INTERVAL '6 days') AND cmd.max_txn_date
        GROUP BY ft.Customer_ID
    )
    SELECT
        Customer_ID,
        total_amount_7d / 7.0 AS avg_daily_volume_7d
    FROM customer_sums
) cv ON dc.Customer_ID = cv.Customer_ID;


-- =============================================
-- vw_Fact_Alerts
-- Grain: one row per alert (preserves 1:n alert relationship)
-- =============================================
CREATE OR REPLACE VIEW vw_Fact_Alerts AS
SELECT
    fa.Alert_ID,
    fa.Transaction_ID,
    fa.Rule_ID,
    fa.Investigation_ID,
    fa.Alert_Timestamp,
    fa.Rule_Hit,
    -- Context from related tables
    dr.Rule_Name,
    ft.Timestamp AS Transaction_Timestamp,
    DATE(ft.Timestamp) AS Transaction_Date
FROM fact_alerts fa
JOIN dim_rule dr ON fa.Rule_ID = dr.Rule_ID
LEFT JOIN fact_transaction ft ON fa.Transaction_ID = ft.Transaction_ID;


-- =============================================
-- vw_Fact_Investigation
-- Grain: one row per investigation
-- =============================================
CREATE OR REPLACE VIEW vw_Fact_Investigation AS
SELECT
    fi.Investigation_ID,
    fi.Transaction_ID,
    fi.Analyst_ID,
    fi.Case_Opened_At,
    fi.Case_Closed_At,
    fi.Resolution_Code,
    -- Context from related tables
    da.Name AS Analyst_Name,
    ft.Timestamp AS Transaction_Timestamp,
    DATE(ft.Timestamp) AS Transaction_Date
FROM fact_investigation fi
JOIN dim_analyst da ON fi.Analyst_ID = da.Analyst_ID
LEFT JOIN fact_transaction ft ON fi.Transaction_ID = ft.Transaction_ID;