> **Historical Note:** This document was the initial Phase 0 architectural vision brief written prior to schema profiling (`database_profiling.txt`) and Phase 1 gap analysis (`DESIGN_VALIDATION.md`). Several proposed fields and workflows (e.g., `Currency_Code`, `Client_Canceled`, `Country_Code`, `Is_Premium_Retailer`, `Isolation Forest`, recovery rate, churn) do not exist in the synthetic source CSVs and were intentionally excluded from the final implementation per the project's no-fabrication rule. See [README.md](../README.md) and [PROJECT_STATUS.md](../PROJECT_STATUS.md) for the implemented scope.

---

**Project:** Banking Transaction & Fraud Intelligence Platform

**Role:** Senior BI Architect
**Date:** 2026-09-23

---

### 1. Business Problem
Banks face a "High-Stakes Trade-off": Aggressive fraud detection leads to blocked legitimate customers (frustration, churn), while lenient detection allows fraudsters to drain accounts.
*The objective is to move from reactive reporting (auditing losses after the fact) to predictive intelligence (identifying risk *before* settlement) and balanced operationalization (minimizing false positives).*

### 2. Stakeholders
*   **Chief Risk Officer (CRO):** Needs high-level financial impact, loss prevention, and regulatory compliance indicators.
*   **Fraud Analysts:** Need drill-down capabilities to investigate specific cases, understand customer behavior, and identify patterns.
*   **Retail Banking Operations:** Needs visibility into high-velocity transactions and operational bottlenecks in the investigation queue.
*   **Value Proposition:** Lower fraud loss ratio, higher fraud recovery, and improved customer Net Promoter Score (NPS) by reducing false blocks.

### 3. Business Questions
*   **Financial:** What is the *Net Financial Impact* (Fraud Loss vs. Recovery)?
*   **Operational:** What is the active investigation queue size? What is the Average Clearance Time (ACT)?
*   **Customer:** Which customer segments have the highest churn rate due to suspected fraud blocks?
*   **Platform:** Where are fraud spikes geographically? Which card issuing channels are most targeted?
*   **Predictive:** Do new account openings correlate with an immediate spike in transaction activity known to precede fraud?

### 4. Dataset Architecture
We will implement a **Star Schema**. This is the standard high-performance architecture for BI reporting.

*   **Fact Table:** `Fct_Transaction_Scored` (Contains the actual events + the analytical features, e.g., risk scores).
*   **Dimension Tables:** `Dim_Customer`, `Dim_Merchant`, `Dim_Channel`, `Dim_Date`, `Dim_Devices`.
*   **Lookup/Stage Tables:** `Stg_Fraud_Templates`, `Stg_Risk_Models`.

**Why this architecture?**
*   **Performance:** Reduces cardinality. Summing millions of transactions is faster than joining millions of rows with dimensions repeatedly in DAX query mode.
*   **Simplicity:** Easier declarative governance, specifically for the "Fair Credit Reporting Act" (privacy compliance) aspects.

### 5. Tables & Columns

#### `Fct_Transaction_Scored` (Fact)
*   `Transaction_ID` (PK, Unique)
*   `Transaction_Date` (FK to Dim_Date)
*   `Customer_ID` (FK to Dim_Customer)
*   `Merchant_ID` (FK to Dim_Merchant)
*   `Channel_ID` (FK to Dim_Channel)
*   `Amount`
*   `Currency_Code`
*   `Transaction_Type`
*   `Status` (`Nominal`, `Fraud` - Hard Flag, `High_Risk` - ML Flag, `Client_Canceled`)
*   `ML_Risk_Score` (0-100, Integer)
*   `Fraud_Type_Cat` (Electronic, Card Not Present, Structural)

#### `Dim_Customer` (Dimension)
*   `Customer_ID` (PK)
*   `Segment_Hierarchy` (e.g., "Mass Market" -> "Young Professional")
*   `Age_Bucket`
*   `Total_Acct_History_Years`
*   `Avg_Trans_Volume_D7`
*   `Last_Charge_Off_Date`
*   `Customer_Risk_Category` (Low, Medium, High)

#### `Dim_Merchant` (Dimension)
*   `Merchant_ID` (PK)
*   `Merchant_Name`
*   `Industry_Code`
*   `Country_Code`
*   `Is_Premium_Retailer` (Boolean)

#### `Dim_Channel` (Dimension)
*   `Channel_ID` (PK)
*   `Channel_Name` (Mobile App, Web, ATM, POS)
*   `Device_Type`
*   `Provider_Name`

#### `Dim_Date` (Dimension)
*   `Date_ID` (YYYYMMDD)
*   `Date`
*   `Year_Number`
*   `Month_Number`
*   `Quarter_Number`
*   `Is_Weekend` (Boolean)
*   `Is_Holiday`

### 6. Primary/Foreign Keys Structure
*   **Fact:** `PK: Transaction_ID` | `FK: Customer_ID`, `FK: Merchant_ID`, `FK: Channel_ID`, `FK: Date_ID`
*   **Dim:** `PK: Customer_ID`, `PK: Merchant_ID`, `PK: Channel_ID`, `PK: Date_ID`

### 7. Fact/Dimension Relationships
These are **One-to-Many (1:n)** relationships.
*   `Dim_Date` connects to `Fct_Transaction_Scored` via a Direct Relationship based on Timestamp internals (some DAX patterns require a Many-to-Many support table for rolling windows, but a standard 1:n is best for general rows).
*   **Granularity:** The Fact table is at the *transaction instance* level.

### 8. SQL Workflow (ETL & Aggregation)
*Before Power BI ingestion.*
1.  **Log Ingestion:** Read raw transaction logs (CSV/Parquet) from cloud storage.
2.  **Enrichment (JOINs):** Join Transaction Logs with Master Customer Data to get risk segments and device fingerprints.
3.  **Feature Engineering (Window Functions):**
    *   *Velocity Check:* Calculate "Cards Used per Loc" (using `LAG` over Window Partition by CardID).
    *   *Frequency:* Calculate "Txns per Day" (using `PARTITION BY`).
4.  **Business Logic (CASE/WHEN):** Apply rules like:
    *   `IF amount > 10,000 AND risk_score > 50 THEN 'HighRisk'`
    *   `IF status = 'REVERSED' THEN 'FraudRecovered'`
5.  **Normalization:** Convert JSON device logs into flat `Dim_Device` columns.
6.  **Aggregation:** Aggregate transaction logs into the Star Schema Fact table for import into Power BI.

### 9. Python Workflow (Data Quality & Analysis)
*Pre-SQL or Intermediate step.*
1.  **Data Cleaning:** Handle missing timestamps, standardize currency formats.
2.  **Data Quality Checks:**
    *   `check_nulls(data['Amount'])`
    *   `assert data['Amount'] > 0`, raising a flag if outliers found.
3.  **Anomaly Detection (Isolation Forest):** Run a lightweight unsupervised learning model to automatically flag transactions that deviate from a customer's historical transaction geometry, adding it to the `ML_Risk_Score` column.
4.  **Exploratory Analysis:** Produce a report of "Top 5 Industries with Highest Fraud Volume" to prove the hypothesis that fraud clusters in specific sectors (e.g., Tech Electronics or Hotel bookings) before building the BI dashboard.

### 10. Power Query Workflow
*Data Load and Transformation (M Code).*
1.  **Step 1: Connection:** Connect to the SQL views generated in section 8.
2.  **Step 2: Filtering:** Filter out cancelled transactions that have no financial impact (create cleaned "Valid Transactions" vs "Archived" tables).
3.  **Step 3: Transformation:** Split the "Merchant" column (if stored as "Store Name - City") using "Split Column by Delimiter".
4.  **Step 4: Type Inference:** Manually set data types (Decimal number for `Amount`, Whole number for `ML_Risk_Score`).
5.  **Step 5: Partitioning:** Add a "Record Date" column to filter data by year (important for temporal slicing in DAX).
6.  **Step 6: Compression:** Enable "Quoted Text" in compression settings to minimize file size.

### 11. Power BI Semantic Model
*Relationships & Data Types.*
*   **Model Mode:** "Import" (We are demonstrating a modeled dataset, not real-time DirectQuery streaming for this specific demo).
*   **Data Categories:** Set `Amount` to "Currency", `ML_Risk_Score` to "Number", Dates to "Date".
*   **Relationship Cross Filter Direction:** Set `Dim_Merchant` -> `Fct_Transaction_Scored` to "Single" (so slicing by Merchant only brings 1 record per transaction, preventing cardinality explosion).
*   **Row Level Security (RLS):** *Design Phase.* Create a "Fraud Analyst" role that filters `Dim_Customer[Sector]` containing "Corporate" and "VIP".

### 12. DAX Measures
*Core logic for the dashboard.*
*   **`Total Value`:** `SUM(Fct_Transaction_Scored[Amount])`
*   **`Total Transactions`:** `COUNT(Fct_Transaction_Scored[Transaction_ID])`
*   **`Detected Fraud Count`:** `CALCULATE([Total Transactions], Fct_Transaction_Scored[Status] = "Fraud")`
*   **`Fraud Loss (Gross)`:** `SUMX(FILTER(Fct_Transaction_Scored, Fct_Transaction_Scored[Status] = "Fraud"), Fct_Transaction_Scored[Amount])`
*   **`Average Transaction Value`:** `DIVIDE([Total Value], [Total Transactions])`
*   **`Fraud Rate (Aligned)`:** `CALCULATE([Detected Fraud Count], ALLSELECTED(Dim_Date)) / [Total Transactions]`
*   **`False Positive Rate`:** `COUNTROWS(FILTER(Fct_Transaction_Scored, Fct_Transaction_Scored[Status] = "HighRisk" && Fct_Transaction_Scored[Merged Status] = "Nominal"))`
*   **`Current_Year_Revenue`:** `CALCULATE([Total Value], Dim_Date[Year] = YEAR(TODAY()))`
*   **`ROP` (Revenue on Prevention):** (Project value) — `(Baseline Revenue - Current Revenue)`.

### 13. Dashboard Pages
1.  **Executive Summary:** Top 5 KPIs (Big Number cards), Fraud Loss vs YoY, Churn rate.
2.  **Fraud Intelligence Heatmap:** A Matrix chart (Period vs Channel) visually highlighting the largest transaction amounts.
3.  **Investigation Case Flow:** A Gantt chart or Funnel chart showing the lifecycle: "Scored" -> "Under Review" -> "Resolved/Closed".
4.  **Geospatial Analysis:** A Map visual showing Merchant Locations colored by `ML_Risk_Score`.
5.  **Customer 360:** A Slicer dashboard where selecting a Customer ID auto-runs a drill-through page showing their transaction history and device fingerprints.

### 14. Key Performance Indicators (KPIs)
1.  **MoM/YoY Fraud Loss:** Trends over time.
2.  **Recovery Rate:** Amount recovered divided by total loss.
3.  **False Positive Count:** Directly correlated with Customer Retention risk.
4.  **Investigation Cycle Time:** Time from "Scored" to "Resolved".
5.  **RiskScore Threshold Hit Rate:** Percentage of high-risk transactions that get flagged by models vs. human analysts.

### 15. Advanced Analytical Features
*   **Drill-Through:** From a specific "High Value Transaction" KPI in the Executive view, drill into the main table, replacing visuals with Customer Details and Transaction Itemized Breakdown.
*   **Dynamic Tooltips:** When the user hovers over a Page segment in a Sunburst chart (Channel vs Fraud Type), a dynamic tooltip appears showing top 3 suspected fraud types in that segment.
*   **Calculation Groups:** Create a "Classification" group (Nominal, Fraud, False Positive) to allow a single measure (e.g., `[Total Volume]`) to be broken down by these categories via a simple slicer toggle.
*   **Bookmarks (Explor view):** A "Focus Mode" bookmark that hides all slicers and drill-down tables to present a clean, full-screen view to the CRO during a presentation.

### 16. Final Business Recommendations
*Based on the analysis patterns this dashboard will reveal.*
1.  **Segmentation:** The data will likely reveal that "App Stores" are an industry-specific fraud vector. Recommendation: Immediately implement velocity checks on that specific industry code.
2.  **Channel Optimization:** If the dashboard shows high fraud on "Mobile App" but low churn, while POS has high churn, the bank should alert security teams to loosen POS post-verification rules (e.g., OTP vs biometric).
3.  **Model Retraining:** If the "ML_Risk_Score" is consistently skewing high (indicating model drift), the data science team needs to retrain the anomaly detection algorithm with fresh data.
4.  **Customer Experience:** Recommend a proactive notification API. Instead of just "blocking" funds, send an SMS: *"We detected unusual activity for Card ****1234. Please confirm this is you via the app to authorize the transaction."* This reduces administrative costs associated with manual investigation.
