-- Final PostgreSQL schema for the 11‑table Banking Transaction & Fraud Intelligence dataset
-- No data loading; only table definitions with constraints and justified indexes.

-- Dimension tables
CREATE TABLE dim_customer (
    Customer_ID   VARCHAR(20)   NOT NULL PRIMARY KEY,
    Name          VARCHAR(100)  NOT NULL,
    Segment       VARCHAR(50)   NOT NULL,
    Risk_Tier     VARCHAR(20)   NOT NULL,
    Region        VARCHAR(50)   NOT NULL
);

CREATE TABLE dim_account (
    Account_ID    VARCHAR(20)   NOT NULL PRIMARY KEY,
    Customer_ID   VARCHAR(20)   NOT NULL,
    Account_Type  VARCHAR(50)   NOT NULL,
    Status        VARCHAR(20)   NOT NULL,
    Open_Date     DATE          NOT NULL,
    CONSTRAINT fk_account_customer FOREIGN KEY (Customer_ID) REFERENCES dim_customer(Customer_ID)
);

CREATE TABLE dim_channel (
    Channel_ID    VARCHAR(10)   NOT NULL PRIMARY KEY,
    Channel_Name  VARCHAR(50)   NOT NULL
);

CREATE TABLE dim_date (
    Date_ID       INTEGER       NOT NULL PRIMARY KEY,   -- expected format YYYYMMDD
    Date          DATE          NOT NULL,
    Day_of_Week   VARCHAR(20)   NOT NULL,
    Month         INTEGER       NOT NULL,
    Quarter       VARCHAR(2)    NOT NULL,
    Year          INTEGER       NOT NULL
);

CREATE TABLE dim_device (
    Device_ID     VARCHAR(20)   NOT NULL PRIMARY KEY,
    OS            VARCHAR(50)   NOT NULL,
    Browser       VARCHAR(50)   NOT NULL,
    Fingerprint_Confidence NUMERIC(5,4) NOT NULL,
    CONSTRAINT chk_device_fp_conf CHECK (Fingerprint_Confidence >= 0 AND Fingerprint_Confidence <= 1)
);

CREATE TABLE dim_merchant (
    Merchant_ID   VARCHAR(20)   NOT NULL PRIMARY KEY,
    Name          VARCHAR(100)  NOT NULL,
    Industry      VARCHAR(100)  NOT NULL,
    MCC_Code      VARCHAR(10)   NOT NULL
);

CREATE TABLE dim_analyst (
    Analyst_ID    VARCHAR(20)   NOT NULL PRIMARY KEY,
    Name          VARCHAR(100)  NOT NULL,
    Team          VARCHAR(50)   NOT NULL,
    Shift         VARCHAR(20)   NOT NULL
);

CREATE TABLE dim_rule (
    Rule_ID       VARCHAR(20)   NOT NULL PRIMARY KEY,
    Rule_Name     VARCHAR(100)  NOT NULL,
    Logic_Type    VARCHAR(50)   NOT NULL
);

-- Fact tables
CREATE TABLE fact_transaction (
    Transaction_ID      VARCHAR(20)   NOT NULL PRIMARY KEY,
    Timestamp           TIMESTAMP     NOT NULL,
    Amount              NUMERIC(12,2) NOT NULL,
    Customer_ID         VARCHAR(20)   NOT NULL,
    Account_ID          VARCHAR(20)   NOT NULL,
    Merchant_ID         VARCHAR(20),
    Date_ID             INTEGER       NOT NULL,
    Channel_ID          VARCHAR(10)   NOT NULL,
    Device_ID           VARCHAR(20),
    Ground_Truth_Label  BOOLEAN       NOT NULL,
    Model_Predicted_Score NUMERIC(5,4) NOT NULL,
    Is_Predicted_Fraud  BOOLEAN       NOT NULL,
    CONSTRAINT chk_tx_model_score CHECK (Model_Predicted_Score >= 0 AND Model_Predicted_Score <= 1),

    CONSTRAINT fk_tx_customer FOREIGN KEY (Customer_ID) REFERENCES dim_customer(Customer_ID),
    CONSTRAINT fk_tx_account  FOREIGN KEY (Account_ID)  REFERENCES dim_account(Account_ID),
    CONSTRAINT fk_tx_merchant FOREIGN KEY (Merchant_ID) REFERENCES dim_merchant(Merchant_ID),
    CONSTRAINT fk_tx_date     FOREIGN KEY (Date_ID)     REFERENCES dim_date(Date_ID),
    CONSTRAINT fk_tx_channel  FOREIGN KEY (Channel_ID)  REFERENCES dim_channel(Channel_ID),
    CONSTRAINT fk_tx_device   FOREIGN KEY (Device_ID)   REFERENCES dim_device(Device_ID)
);

CREATE TABLE fact_investigation (
    Investigation_ID    VARCHAR(20)   NOT NULL PRIMARY KEY,
    Transaction_ID      VARCHAR(20)   NOT NULL,
    Analyst_ID          VARCHAR(20)   NOT NULL,
    Case_Opened_At      TIMESTAMP     NOT NULL,
    Case_Closed_At      TIMESTAMP,
    Resolution_Code     VARCHAR(20),

    CONSTRAINT fk_inv_tx      FOREIGN KEY (Transaction_ID) REFERENCES fact_transaction(Transaction_ID),
    CONSTRAINT fk_inv_analyst FOREIGN KEY (Analyst_ID)   REFERENCES dim_analyst(Analyst_ID)
);

CREATE TABLE fact_alerts (
    Alert_ID            VARCHAR(20)   NOT NULL PRIMARY KEY,
    Transaction_ID      VARCHAR(20)   NOT NULL,
    Rule_ID             VARCHAR(20)   NOT NULL,
    Investigation_ID    VARCHAR(20),   -- nullable per updated model
    Alert_Timestamp     TIMESTAMP     NOT NULL,
    Rule_Hit            BOOLEAN       NOT NULL,

    CONSTRAINT fk_alert_tx      FOREIGN KEY (Transaction_ID) REFERENCES fact_transaction(Transaction_ID),
    CONSTRAINT fk_alert_rule    FOREIGN KEY (Rule_ID)      REFERENCES dim_rule(Rule_ID),
    CONSTRAINT fk_alert_invest  FOREIGN KEY (Investigation_ID) REFERENCES fact_investigation(Investigation_ID)
);

-- Justified indexes for the 50k‑row workload
CREATE INDEX ix_tx_timestamp      ON fact_transaction(Timestamp);
CREATE INDEX ix_tx_customer       ON fact_transaction(Customer_ID);
CREATE INDEX ix_tx_merchant       ON fact_transaction(Merchant_ID);
CREATE INDEX ix_alert_timestamp   ON fact_alerts(Alert_Timestamp);
CREATE INDEX ix_alert_rule        ON fact_alerts(Rule_ID);
CREATE INDEX ix_invest_analyst    ON fact_investigation(Analyst_ID);
CREATE INDEX ix_invest_opened     ON fact_investigation(Case_Opened_At);