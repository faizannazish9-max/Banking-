-- ============================================================
-- PROJECT  : Banking & Finance SQL Analysis
-- DATABASE : PostgreSQL
-- LEVEL    : Intermediate (JOINs, Subqueries, CTEs, Window Fns)
-- AUTHOR   : Faizan
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- SCHEMA OVERVIEW
-- ─────────────────────────────────────────────────────────────
--
--  customers   (customer_id, full_name, city, segment, join_date)
--  branches    (branch_id, branch_name, region)
--  accounts    (account_id, customer_id, branch_id, account_type, balance, opened_date)
--               account_type: 'Savings' | 'Current' | 'Loan'
--  transactions(txn_id, account_id, txn_date, txn_type, amount, description)
--               txn_type: 'Credit' | 'Debit'
--
-- ─────────────────────────────────────────────────────────────


-- ============================================================
-- Q1. Total deposits per customer
--     Concept: Multi-table JOIN + GROUP BY
-- ============================================================
SELECT
    c.customer_id,
    c.full_name,
    c.segment,
    SUM(t.amount)    AS total_deposits,
    COUNT(t.txn_id)  AS total_txns
FROM customers    c
JOIN accounts     a ON c.customer_id = a.customer_id
JOIN transactions t ON a.account_id  = t.account_id
WHERE t.txn_type = 'Credit'
GROUP BY c.customer_id, c.full_name, c.segment
ORDER BY total_deposits DESC;


-- ============================================================
-- Q2. Customers with average transaction value above 10,000
--     Concept: HAVING clause
-- ============================================================
SELECT
    c.customer_id,
    c.full_name,
    ROUND(AVG(t.amount), 2) AS avg_txn_value
FROM customers    c
JOIN accounts     a ON c.customer_id = a.customer_id
JOIN transactions t ON a.account_id  = t.account_id
GROUP BY c.customer_id, c.full_name
HAVING AVG(t.amount) > 10000
ORDER BY avg_txn_value DESC;


-- ============================================================
-- Q3. Transactions above branch average amount
--     Concept: Correlated subquery
-- ============================================================
SELECT
    t.txn_id,
    c.full_name,
    br.branch_name,
    t.amount,
    t.txn_date,
    t.txn_type
FROM transactions  t
JOIN accounts      a  ON t.account_id  = a.account_id
JOIN customers     c  ON a.customer_id = c.customer_id
JOIN branches      br ON a.branch_id   = br.branch_id
WHERE t.amount > (
    SELECT AVG(t2.amount)
    FROM   transactions t2
    JOIN   accounts     a2 ON t2.account_id = a2.account_id
    WHERE  a2.branch_id = a.branch_id
)
ORDER BY t.amount DESC;


-- ============================================================
-- Q4. Monthly transaction trend
--     Concept: CTE + date formatting + GROUP BY
-- ============================================================
WITH monthly AS (
    SELECT
        TO_CHAR(txn_date, 'YYYY-MM') AS txn_month,
        txn_type,
        amount
    FROM transactions
)
SELECT
    txn_month,
    txn_type,
    COUNT(*)              AS num_transactions,
    SUM(amount)           AS total_amount,
    ROUND(AVG(amount), 2) AS avg_amount
FROM monthly
GROUP BY txn_month, txn_type
ORDER BY txn_month, txn_type;


-- ============================================================
-- Q5. Customer Loan-to-Deposit (LTD) ratio
--     Concept: Multiple CTEs + NULLIF for safe division
-- ============================================================
WITH deposits AS (
    SELECT customer_id, SUM(balance) AS total_deposit
    FROM   accounts
    WHERE  account_type IN ('Savings', 'Current')
    GROUP BY customer_id
),
loans AS (
    SELECT customer_id, SUM(balance) AS total_loan
    FROM   accounts
    WHERE  account_type = 'Loan'
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.full_name,
    COALESCE(d.total_deposit, 0) AS total_deposit,
    COALESCE(l.total_loan, 0)    AS total_loan,
    ROUND(
        COALESCE(l.total_loan, 0) / NULLIF(COALESCE(d.total_deposit, 0), 0) * 100
    , 2)                         AS ltd_ratio_pct
FROM      customers c
LEFT JOIN deposits  d ON c.customer_id = d.customer_id
LEFT JOIN loans     l ON c.customer_id = l.customer_id
ORDER BY ltd_ratio_pct DESC NULLS LAST;


-- ============================================================
-- Q6. Branch performance scorecard
--     Concept: JOIN + conditional aggregation with CASE
-- ============================================================
SELECT
    br.branch_name,
    br.region,
    COUNT(DISTINCT a.customer_id)                                AS total_customers,
    COUNT(DISTINCT a.account_id)                                 AS total_accounts,
    SUM(CASE WHEN a.account_type != 'Loan' THEN a.balance END)  AS total_deposits,
    SUM(CASE WHEN a.account_type  = 'Loan' THEN a.balance END)  AS total_loans,
    ROUND(AVG(a.balance), 2)                                     AS avg_balance
FROM   branches br
JOIN   accounts a ON br.branch_id = a.branch_id
GROUP BY br.branch_name, br.region
ORDER BY total_deposits DESC;


-- ============================================================
-- Q7. Dormant accounts (no activity in last 6 months)
--     Concept: NOT IN subquery
-- ============================================================
SELECT
    a.account_id,
    c.full_name,
    c.segment,
    a.account_type,
    a.balance,
    a.opened_date
FROM accounts  a
JOIN customers c ON a.customer_id = c.customer_id
WHERE a.account_id NOT IN (
    SELECT DISTINCT account_id
    FROM   transactions
    WHERE  txn_date >= CURRENT_DATE - INTERVAL '6 months'
)
AND a.account_type != 'Loan'
ORDER BY a.balance DESC;


-- ============================================================
-- Q8. Top 3 customers by deposit per branch
--     Concept: CTE + RANK() window function
-- ============================================================
WITH ranked AS (
    SELECT
        br.branch_name,
        c.full_name,
        c.segment,
        SUM(a.balance)  AS total_balance,
        RANK() OVER (
            PARTITION BY br.branch_id
            ORDER BY SUM(a.balance) DESC
        )               AS branch_rank
    FROM   customers c
    JOIN   accounts  a  ON c.customer_id = a.customer_id
    JOIN   branches  br ON a.branch_id   = br.branch_id
    WHERE  a.account_type != 'Loan'
    GROUP BY br.branch_id, br.branch_name, c.customer_id, c.full_name, c.segment
)
SELECT *
FROM   ranked
WHERE  branch_rank <= 3
ORDER BY branch_name, branch_rank;


-- ============================================================
-- Q9. Risk tier classification using LTD ratio
--     Concept: CASE expression inside CTE
-- ============================================================
WITH ltd AS (
    SELECT
        c.customer_id,
        c.full_name,
        c.segment,
        COALESCE(SUM(CASE WHEN a.account_type  = 'Loan' THEN a.balance END), 0) AS loan_bal,
        COALESCE(SUM(CASE WHEN a.account_type != 'Loan' THEN a.balance END), 0) AS deposit_bal
    FROM customers c
    JOIN accounts  a ON c.customer_id = a.customer_id
    GROUP BY c.customer_id, c.full_name, c.segment
)
SELECT
    customer_id,
    full_name,
    segment,
    loan_bal,
    deposit_bal,
    ROUND(loan_bal / NULLIF(deposit_bal, 0) * 100, 2) AS ltd_pct,
    CASE
        WHEN loan_bal / NULLIF(deposit_bal, 0) > 1.2        THEN 'HIGH RISK'
        WHEN loan_bal / NULLIF(deposit_bal, 0) BETWEEN 0.8
                                               AND     1.2  THEN 'MEDIUM RISK'
        WHEN loan_bal / NULLIF(deposit_bal, 0) < 0.8        THEN 'LOW RISK'
        ELSE 'NO LOAN'
    END AS risk_tier
FROM ltd
ORDER BY ltd_pct DESC NULLS LAST;


-- ============================================================
-- Q10. Running total of credits per customer (chronological)
--      Concept: SUM() as window function (running total)
-- ============================================================
SELECT
    c.full_name,
    t.txn_date,
    t.amount,
    SUM(t.amount) OVER (
        PARTITION BY c.customer_id
        ORDER BY t.txn_date
    ) AS running_total
FROM transactions  t
JOIN accounts      a ON t.account_id  = a.account_id
JOIN customers     c ON a.customer_id = c.customer_id
WHERE t.txn_type = 'Credit'
ORDER BY c.full_name, t.txn_date;


-- ============================================================
-- Q11. Month-over-month growth in total transaction volume
--      Concept: LAG() window function
-- ============================================================
WITH monthly_vol AS (
    SELECT
        TO_CHAR(txn_date, 'YYYY-MM') AS txn_month,
        SUM(amount)                  AS total_volume
    FROM transactions
    GROUP BY TO_CHAR(txn_date, 'YYYY-MM')
)
SELECT
    txn_month,
    total_volume,
    LAG(total_volume) OVER (ORDER BY txn_month)  AS prev_month_volume,
    ROUND(
        (total_volume - LAG(total_volume) OVER (ORDER BY txn_month))
        / NULLIF(LAG(total_volume) OVER (ORDER BY txn_month), 0) * 100
    , 2)                                         AS mom_growth_pct
FROM monthly_vol
ORDER BY txn_month;


-- ============================================================
-- Q12. Customers who have both Savings and Loan accounts
--      Concept: EXISTS + subquery
-- ============================================================
SELECT
    c.customer_id,
    c.full_name,
    c.segment
FROM customers c
WHERE EXISTS (
    SELECT 1 FROM accounts a
    WHERE a.customer_id = c.customer_id
    AND   a.account_type = 'Savings'
)
AND EXISTS (
    SELECT 1 FROM accounts a
    WHERE a.customer_id = c.customer_id
    AND   a.account_type = 'Loan'
)
ORDER BY c.full_name;


-- ============================================================
-- Q13. Duplicate transaction check (same account, date, amount)
--      Concept: GROUP BY + HAVING (data quality check)
-- ============================================================
SELECT
    account_id,
    txn_date,
    amount,
    txn_type,
    COUNT(*) AS duplicate_count
FROM transactions
GROUP BY account_id, txn_date, amount, txn_type
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;


-- ============================================================
-- Q14. Customer segmentation by total balance bucket
--      Concept: CASE + GROUP BY for bucketing / binning
-- ============================================================
SELECT
    CASE
        WHEN total_balance >= 500000            THEN 'Platinum  (500K+)'
        WHEN total_balance BETWEEN 200000
                           AND     499999       THEN 'Gold      (200K-500K)'
        WHEN total_balance BETWEEN 50000
                           AND     199999       THEN 'Silver    (50K-200K)'
        ELSE                                         'Standard  (<50K)'
    END                    AS balance_bucket,
    COUNT(*)               AS num_customers,
    ROUND(AVG(total_balance), 0) AS avg_balance
FROM (
    SELECT
        c.customer_id,
        SUM(CASE WHEN a.account_type != 'Loan' THEN a.balance ELSE 0 END) AS total_balance
    FROM customers c
    JOIN accounts  a ON c.customer_id = a.customer_id
    GROUP BY c.customer_id
) bal
GROUP BY balance_bucket
ORDER BY avg_balance DESC;


-- ============================================================
-- Q15. Full customer 360 view (summary per customer)
--      Concept: Multi-CTE pipeline — ties everything together
-- ============================================================
WITH deposit_summary AS (
    SELECT customer_id,
           SUM(balance)  AS total_deposits,
           COUNT(*)      AS num_deposit_accounts
    FROM   accounts
    WHERE  account_type != 'Loan'
    GROUP BY customer_id
),
loan_summary AS (
    SELECT customer_id,
           SUM(balance) AS total_loans,
           COUNT(*)     AS num_loan_accounts
    FROM   accounts
    WHERE  account_type = 'Loan'
    GROUP BY customer_id
),
txn_summary AS (
    SELECT
        a.customer_id,
        COUNT(t.txn_id)                                           AS total_txns,
        SUM(CASE WHEN t.txn_type = 'Credit' THEN t.amount END)   AS total_credits,
        SUM(CASE WHEN t.txn_type = 'Debit'  THEN t.amount END)   AS total_debits,
        MAX(t.txn_date)                                           AS last_txn_date
    FROM transactions t
    JOIN accounts     a ON t.account_id = a.account_id
    GROUP BY a.customer_id
)
SELECT
    c.customer_id,
    c.full_name,
    c.segment,
    c.city,
    COALESCE(d.total_deposits,       0)  AS total_deposits,
    COALESCE(l.total_loans,          0)  AS total_loans,
    COALESCE(t.total_txns,           0)  AS total_txns,
    COALESCE(t.total_credits,        0)  AS total_credits,
    COALESCE(t.total_debits,         0)  AS total_debits,
    t.last_txn_date,
    ROUND(
        COALESCE(l.total_loans, 0) / NULLIF(COALESCE(d.total_deposits, 0), 0) * 100
    , 2)                                 AS ltd_ratio_pct
FROM      customers      c
LEFT JOIN deposit_summary d ON c.customer_id = d.customer_id
LEFT JOIN loan_summary    l ON c.customer_id = l.customer_id
LEFT JOIN txn_summary     t ON c.customer_id = t.customer_id
ORDER BY total_deposits DESC;

-- ============================================================
-- END OF PROJECT
-- ============================================================
