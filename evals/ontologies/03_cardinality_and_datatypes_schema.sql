-- =============================================================================
-- Google Cloud Spanner Relational DDL
-- Generated from OWL Ontology and SHACL Shapes
-- Pattern: Table-Per-Concrete-Class with Flattened Datatypes & Scalar/Array Constraints
-- =============================================================================

CREATE TABLE FinancialTransactions (
  TransactionId STRING(36) NOT NULL,
  Amount NUMERIC NOT NULL,
  ExchangeRate FLOAT64,
  IsSettled BOOL NOT NULL,
  TransactionTimestamp TIMESTAMP NOT NULL,
  SettlementDate DATE,
  RetryCount INT64 NOT NULL,
  RiskScore FLOAT64,
  AuditTags ARRAY<STRING(MAX)>
) PRIMARY KEY (TransactionId);

CREATE TABLE UserProfiles (
  UserProfileId STRING(36) NOT NULL,
  EmailAddress STRING(255) NOT NULL,
  IsActive BOOL NOT NULL,
  VerificationCodes ARRAY<STRING(MAX)>
) PRIMARY KEY (UserProfileId);

-- =============================================================================
-- Google Cloud Spanner Property Graph DDL
-- Schema: GQL-Compliant Property Graph definition
-- =============================================================================

CREATE PROPERTY GRAPH CardinalityAndDatatypesGraph
  NODE TABLES (
    FinancialTransactions
      LABEL FinancialTransaction PROPERTIES (
        TransactionId,
        Amount,
        ExchangeRate,
        IsSettled,
        TransactionTimestamp,
        SettlementDate,
        RetryCount,
        RiskScore,
        AuditTags
      ),
    UserProfiles
      LABEL UserProfile PROPERTIES (
        UserProfileId,
        EmailAddress,
        IsActive,
        VerificationCodes
      )
  );