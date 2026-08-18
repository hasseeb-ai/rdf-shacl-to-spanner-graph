-- =============================================================================
-- Relational Schema Definitions (Table-Per-Concrete-Class)
-- =============================================================================

-- Concrete Subclass Table for Individual Parties
CREATE TABLE IndividualParties (
  IndividualPartyId STRING(36) NOT NULL
) PRIMARY KEY (IndividualPartyId);

-- Concrete Subclass Table for Corporate Parties
CREATE TABLE CorporateParties (
  CorporatePartyId STRING(36) NOT NULL
) PRIMARY KEY (CorporatePartyId);

-- Concrete Table for Payment Accounts
CREATE TABLE PaymentAccounts (
  PaymentAccountId STRING(36) NOT NULL,
  AccountNumber STRING(34) NOT NULL,
  AccountStatus STRING(20) NOT NULL,
  TierLevel STRING(50) NOT NULL DEFAULT ('STANDARD'),
  OwnerPartyId STRING(36) NOT NULL, -- Omitted physical FK due to polymorphic target (Party)
  
  -- Flattened embedded fields from ex:PostalAddressShape (sh:node ex:billingAddress)
  BillingAddress_StreetLine STRING(120),
  BillingAddress_CityName STRING(80),
  BillingAddress_PostalCode STRING(20),
  BillingAddress_CountryIso STRING(2),
  
  -- Enum validation constraint derived from SHACL sh:in
  CONSTRAINT CK_AccountStatus CHECK (AccountStatus IN ('ACTIVE', 'SUSPENDED', 'CLOSED'))
) PRIMARY KEY (PaymentAccountId);

-- =============================================================================
-- Property Graph Schema Definition
-- =============================================================================

CREATE PROPERTY GRAPH PaymentAccountGraph
  NODE TABLES (
    IndividualParties
      LABEL IndividualParty PROPERTIES (IndividualPartyId)
      LABEL Party PROPERTIES (IndividualPartyId AS PartyId),
      
    CorporateParties
      LABEL CorporateParty PROPERTIES (CorporatePartyId)
      LABEL Party PROPERTIES (CorporatePartyId AS PartyId),
      
    PaymentAccounts
      LABEL PaymentAccount PROPERTIES (
        PaymentAccountId,
        AccountNumber,
        AccountStatus,
        TierLevel,
        OwnerPartyId,
        BillingAddress_StreetLine,
        BillingAddress_CityName,
        BillingAddress_PostalCode,
        BillingAddress_CountryIso
      )
  )
  EDGE TABLES (
    -- Polymorphic Edge Target 1: Individual Parties
    PaymentAccounts AS PaymentAccountIndividualOwners
      SOURCE KEY (PaymentAccountId) REFERENCES PaymentAccounts (PaymentAccountId)
      DESTINATION KEY (OwnerPartyId) REFERENCES IndividualParties (IndividualPartyId)
      LABEL HAS_OWNER_PARTY PROPERTIES (PaymentAccountId, OwnerPartyId),
      
    -- Polymorphic Edge Target 2: Corporate Parties
    PaymentAccounts AS PaymentAccountCorporateOwners
      SOURCE KEY (PaymentAccountId) REFERENCES PaymentAccounts (PaymentAccountId)
      DESTINATION KEY (OwnerPartyId) REFERENCES CorporateParties (CorporatePartyId)
      LABEL HAS_OWNER_PARTY PROPERTIES (PaymentAccountId, OwnerPartyId)
  );