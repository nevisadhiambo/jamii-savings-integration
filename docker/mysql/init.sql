-- Jamii Integration – MySQL initialisation
-- Runs once when the container is first created.

CREATE DATABASE IF NOT EXISTS jamii CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE jamii;

-- ── Accounts table (used by AccountBalanceAPI / AccountDataService) ──────────
CREATE TABLE IF NOT EXISTS accounts (
    account_number VARCHAR(20)    NOT NULL PRIMARY KEY,
    account_holder VARCHAR(120)   NOT NULL,
    balance        DECIMAL(15,2)  NOT NULL DEFAULT 0.00,
    currency       CHAR(3)        NOT NULL DEFAULT 'KES',
    status         ENUM('ACTIVE','FROZEN','CLOSED') NOT NULL DEFAULT 'ACTIVE',
    created_at     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Seed data
INSERT IGNORE INTO accounts (account_number, account_holder, balance, currency, status) VALUES
  ('ACC001', 'Alice Wanjiru',    125000.00, 'KES', 'ACTIVE'),
  ('ACC002', 'Bob Kamau',         88500.50, 'KES', 'ACTIVE'),
  ('ACC003', 'Carol Njoki',           0.00, 'KES', 'FROZEN');

-- ── Customers table (used by CustomerProxyAPI) ────────────────────────────────
CREATE TABLE IF NOT EXISTS customers (
    customer_id  INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
    name         VARCHAR(120) NOT NULL,
    email        VARCHAR(120) NOT NULL,
    phone        VARCHAR(30),
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

INSERT IGNORE INTO customers (customer_id, name, email, phone) VALUES
  (1, 'Alice Wanjiru', 'alice@example.com', '+254700000001'),
  (2, 'Bob Kamau',     'bob@example.com',   '+254700000002');

-- ── Loan applications log (optional audit, used by LoanEligibilityAPI) ────────
CREATE TABLE IF NOT EXISTS loan_applications (
    id             BIGINT        NOT NULL PRIMARY KEY AUTO_INCREMENT,
    applicant_name VARCHAR(120)  NOT NULL,
    amount         DECIMAL(15,2) NOT NULL,
    term_months    INT           NOT NULL,
    eligible       TINYINT(1),
    reason         VARCHAR(255),
    applied_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;
