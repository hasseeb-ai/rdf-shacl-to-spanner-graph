-- =============================================================================
-- Google Cloud Spanner Physical Relational Schema
-- Table-Per-Concrete-Class Pattern & Stored Generated Columns
-- =============================================================================

CREATE TABLE IndividualCustomers (
  CustomerId STRING(36) NOT NULL,
  AccountBalance NUMERIC,
  CustomerSince DATE,
  SSN STRING(MAX),
  IsHighValueAccount BOOL AS (AccountBalance > 500000.00) STORED
) PRIMARY KEY (CustomerId);

CREATE TABLE CorporateCustomers (
  CustomerId STRING(36) NOT NULL,
  AccountBalance NUMERIC,
  CustomerSince DATE,
  TaxRegistrationNumber STRING(MAX)
) PRIMARY KEY (CustomerId);

-- =============================================================================
-- Google Cloud Spanner Property Graph Schema
-- Multi-Label Hierarchy & Label Uniformity
-- =============================================================================

CREATE PROPERTY GRAPH CustomerGraph
  NODE TABLES (
    IndividualCustomers
      LABEL IndividualCustomer PROPERTIES (CustomerId, AccountBalance, CustomerSince, SSN, IsHighValueAccount)
      LABEL Customer PROPERTIES (CustomerId, AccountBalance, CustomerSince),
    CorporateCustomers
      LABEL CorporateCustomer PROPERTIES (CustomerId, AccountBalance, CustomerSince, TaxRegistrationNumber)
      LABEL Customer PROPERTIES (CustomerId, AccountBalance, CustomerSince)
  );