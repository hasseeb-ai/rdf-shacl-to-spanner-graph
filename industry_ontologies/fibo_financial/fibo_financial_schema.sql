-- =============================================================================
-- GOOGLE CLOUD SPANNER DDL SCHEMA GENERATION
-- Source Ontology: FIBO-Aligned Financial Instrument & Business Entity Ontology
-- Translation Strategy: Table-Per-Concrete-Class with Flattened Superclasses
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. PHYSICAL RELATIONAL TABLES
-- -----------------------------------------------------------------------------

-- Concrete Class: fibo:Corporation (Subclass of LegalEntity -> AutonomousAgent)
CREATE TABLE Corporations (
  CorporationId STRING(36) NOT NULL,
  LeiCode STRING(MAX) NOT NULL,
  LegalName STRING(MAX)
) PRIMARY KEY (CorporationId);

-- Concrete Class: fibo:Partnership (Subclass of LegalEntity -> AutonomousAgent)
CREATE TABLE Partnerships (
  PartnershipId STRING(36) NOT NULL,
  LeiCode STRING(MAX) NOT NULL,
  LegalName STRING(MAX)
) PRIMARY KEY (PartnershipId);

-- Concrete Class: fibo:ContractualParty (Subclass of AutonomousAgent)
CREATE TABLE ContractualParties (
  ContractualPartyId STRING(36) NOT NULL
) PRIMARY KEY (ContractualPartyId);

-- Concrete Class: fibo:Share (Subclass of Security -> FinancialInstrument)
CREATE TABLE Shares (
  ShareId STRING(36) NOT NULL,
  IsinCode STRING(MAX),
  SharesOutstanding INT64
) PRIMARY KEY (ShareId);

-- Concrete Class: fibo:DebtInstrument (Subclass of Security -> FinancialInstrument)
CREATE TABLE DebtInstruments (
  DebtInstrumentId STRING(36) NOT NULL,
  IsinCode STRING(MAX)
) PRIMARY KEY (DebtInstrumentId);

-- Concrete Class: fibo:Loan (Subclass of FinancialInstrument)
-- Includes generated column for Equivalent Class fibo:SignificantCorporateLoan
CREATE TABLE Loans (
  LoanId STRING(36) NOT NULL,
  LoanAmount NUMERIC,
  InterestRate NUMERIC,
  LenderId STRING(36) NOT NULL,
  BorrowerId STRING(36),
  IsSignificant BOOL AS (LoanAmount > 10000000.00) STORED,
  CONSTRAINT FK_Loans_Lender FOREIGN KEY (LenderId) REFERENCES ContractualParties (ContractualPartyId),
  CONSTRAINT FK_Loans_Borrower FOREIGN KEY (BorrowerId) REFERENCES ContractualParties (ContractualPartyId)
) PRIMARY KEY (LoanId);

-- -----------------------------------------------------------------------------
-- 2. RELATIONSHIP STORAGE TABLES (FOR OBJECT PROPERTIES & EDGES)
-- -----------------------------------------------------------------------------

-- Relationship: fibo:issuedBy / fibo:isIssuerOf
CREATE TABLE ShareIssuers (
  ShareId STRING(36) NOT NULL,
  CorporationId STRING(36) NOT NULL,
  CONSTRAINT FK_ShareIssuers_Share FOREIGN KEY (ShareId) REFERENCES Shares (ShareId),
  CONSTRAINT FK_ShareIssuers_Corp FOREIGN KEY (CorporationId) REFERENCES Corporations (CorporationId)
) PRIMARY KEY (ShareId, CorporationId);

-- Relationship: fibo:ownedBy
CREATE TABLE ShareCorporationOwners (
  ShareId STRING(36) NOT NULL,
  OwnerCorporationId STRING(36) NOT NULL,
  CONSTRAINT FK_ShareCorpOwners_Share FOREIGN KEY (ShareId) REFERENCES Shares (ShareId),
  CONSTRAINT FK_ShareCorpOwners_Corp FOREIGN KEY (OwnerCorporationId) REFERENCES Corporations (CorporationId)
) PRIMARY KEY (ShareId, OwnerCorporationId);

-- Relationship: fibo:guaranteedBy
CREATE TABLE LoanCorporationGuarantors (
  LoanId STRING(36) NOT NULL,
  GuarantorCorporationId STRING(36) NOT NULL,
  CONSTRAINT FK_LoanCorpGuar_Loan FOREIGN KEY (LoanId) REFERENCES Loans (LoanId),
  CONSTRAINT FK_LoanCorpGuar_Corp FOREIGN KEY (GuarantorCorporationId) REFERENCES Corporations (CorporationId)
) PRIMARY KEY (LoanId, GuarantorCorporationId);

-- Relationship: fibo:sharesGuarantorRiskWith (Symmetric Property)
CREATE TABLE CorporationRiskAlliances (
  CorporationId1 STRING(36) NOT NULL,
  CorporationId2 STRING(36) NOT NULL,
  CONSTRAINT FK_RiskAlliance_Corp1 FOREIGN KEY (CorporationId1) REFERENCES Corporations (CorporationId),
  CONSTRAINT FK_RiskAlliance_Corp2 FOREIGN KEY (CorporationId2) REFERENCES Corporations (CorporationId)
) PRIMARY KEY (CorporationId1, CorporationId2);

-- Relationship: fibo:controlledBy / fibo:controlsLegalEntity (Transitive Property)
CREATE TABLE CorporationControl (
  ControlledCorporationId STRING(36) NOT NULL,
  ControllingCorporationId STRING(36) NOT NULL,
  CONSTRAINT FK_CorpCtrl_Controlled FOREIGN KEY (ControlledCorporationId) REFERENCES Corporations (CorporationId),
  CONSTRAINT FK_CorpCtrl_Controlling FOREIGN KEY (ControllingCorporationId) REFERENCES Corporations (CorporationId)
) PRIMARY KEY (ControlledCorporationId, ControllingCorporationId);

-- -----------------------------------------------------------------------------
-- 3. SQL VIEWS FOR EQUIVALENT CLASSES
-- -----------------------------------------------------------------------------

-- Equivalent Class View: fibo:SignificantCorporateLoan
CREATE VIEW SignificantCorporateLoans SQL SECURITY INVOKER AS
SELECT 
  l.LoanId,
  l.LoanAmount,
  l.InterestRate,
  l.IsSignificant
FROM Loans l
WHERE l.LoanAmount > 10000000.00;

-- -----------------------------------------------------------------------------
-- 4. PROPERTY GRAPH SCHEMA DEFINITION
-- -----------------------------------------------------------------------------

CREATE PROPERTY GRAPH FinancialGraph
  NODE TABLES (
    Corporations
      LABEL Corporation PROPERTIES (CorporationId, LeiCode, LegalName)
      LABEL LegalEntity PROPERTIES (LeiCode, LegalName)
      LABEL AutonomousAgent NO PROPERTIES,
    Partnerships
      LABEL Partnership PROPERTIES (PartnershipId, LeiCode, LegalName)
      LABEL LegalEntity PROPERTIES (LeiCode, LegalName)
      LABEL AutonomousAgent NO PROPERTIES,
    ContractualParties
      LABEL ContractualParty PROPERTIES (ContractualPartyId)
      LABEL AutonomousAgent NO PROPERTIES,
    Shares
      LABEL Share PROPERTIES (ShareId, IsinCode, SharesOutstanding)
      LABEL Security PROPERTIES (IsinCode)
      LABEL FinancialInstrument NO PROPERTIES,
    DebtInstruments
      LABEL DebtInstrument PROPERTIES (DebtInstrumentId, IsinCode)
      LABEL Security PROPERTIES (IsinCode)
      LABEL FinancialInstrument NO PROPERTIES,
    Loans
      LABEL Loan PROPERTIES (LoanId, LoanAmount, InterestRate, IsSignificant)
      LABEL FinancialInstrument NO PROPERTIES,
    SignificantCorporateLoans KEY (LoanId)
      LABEL SignificantCorporateLoan PROPERTIES (LoanId, LoanAmount, InterestRate, IsSignificant)
  )
  EDGE TABLES (
    -- Relationship: fibo:hasLender
    Loans AS LoanLenders
      SOURCE KEY (LoanId) REFERENCES Loans (LoanId)
      DESTINATION KEY (LenderId) REFERENCES ContractualParties (ContractualPartyId)
      LABEL HAS_LENDER NO PROPERTIES,

    -- Relationship: fibo:hasBorrower
    Loans AS LoanBorrowers
      SOURCE KEY (LoanId) REFERENCES Loans (LoanId)
      DESTINATION KEY (BorrowerId) REFERENCES ContractualParties (ContractualPartyId)
      LABEL HAS_BORROWER NO PROPERTIES,

    -- Relationship: fibo:issuedBy (Forward)
    ShareIssuers
      SOURCE KEY (ShareId) REFERENCES Shares (ShareId)
      DESTINATION KEY (CorporationId) REFERENCES Corporations (CorporationId)
      LABEL ISSUED_BY NO PROPERTIES,

    -- Relationship: fibo:isIssuerOf (Inverse)
    ShareIssuers AS CorporationShareIssuers
      SOURCE KEY (CorporationId) REFERENCES Corporations (CorporationId)
      DESTINATION KEY (ShareId) REFERENCES Shares (ShareId)
      LABEL IS_ISSUER_OF NO PROPERTIES,

    -- Relationship: fibo:ownedBy
    ShareCorporationOwners
      SOURCE KEY (ShareId) REFERENCES Shares (ShareId)
      DESTINATION KEY (OwnerCorporationId) REFERENCES Corporations (CorporationId)
      LABEL OWNED_BY NO PROPERTIES,

    -- Relationship: fibo:guaranteedBy
    LoanCorporationGuarantors
      SOURCE KEY (LoanId) REFERENCES Loans (LoanId)
      DESTINATION KEY (GuarantorCorporationId) REFERENCES Corporations (CorporationId)
      LABEL GUARANTEED_BY NO PROPERTIES,

    -- Relationship: fibo:sharesGuarantorRiskWith (Symmetric)
    CorporationRiskAlliances
      SOURCE KEY (CorporationId1) REFERENCES Corporations (CorporationId)
      DESTINATION KEY (CorporationId2) REFERENCES Corporations (CorporationId)
      LABEL SHARES_GUARANTOR_RISK_WITH NO PROPERTIES,

    -- Relationship: fibo:controlledBy (Transitive - Forward Edge)
    CorporationControl
      SOURCE KEY (ControlledCorporationId) REFERENCES Corporations (CorporationId)
      DESTINATION KEY (ControllingCorporationId) REFERENCES Corporations (CorporationId)
      LABEL CONTROLLED_BY NO PROPERTIES,

    -- Relationship: fibo:controlsLegalEntity (Transitive - Inverse Edge)
    CorporationControl AS CorporationControls
      SOURCE KEY (ControllingCorporationId) REFERENCES Corporations (CorporationId)
      DESTINATION KEY (ControlledCorporationId) REFERENCES Corporations (CorporationId)
      LABEL CONTROLS_LEGAL_ENTITY NO PROPERTIES
  );