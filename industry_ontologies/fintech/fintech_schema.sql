-- =============================================================================
-- GOOGLE CLOUD SPANNER RELATIONAL SCHEMA (DDL)
-- =============================================================================

-- Concrete Class: ex:Person (Subclass of ex:Party)
CREATE TABLE People (
  PersonId STRING(36) NOT NULL
) PRIMARY KEY (PersonId);

-- Concrete Class: ex:Organization (Subclass of ex:Party)
CREATE TABLE Organizations (
  OrganizationId STRING(36) NOT NULL
) PRIMARY KEY (OrganizationId);

-- Concrete Class: ex:PersonalAccount (Subclass of ex:Account)
-- Top-down inherited datatype property: ex:accountBalance
-- Equivalent class rule for ex:HighRiskAccount modeled via STORED generated column
CREATE TABLE PersonalAccounts (
  AccountId STRING(36) NOT NULL,
  AccountBalance NUMERIC,
  OwnerPersonId STRING(36),
  IsHighRisk BOOL AS (AccountBalance > 100000.00) STORED,
  CONSTRAINT FK_PersonalAccount_Owner FOREIGN KEY (OwnerPersonId) REFERENCES People (PersonId)
) PRIMARY KEY (AccountId);

-- Concrete Class: ex:CorporateAccount (Subclass of ex:Account)
-- Top-down inherited datatype property: ex:accountBalance
-- Mandatory owner (cardinality 1) enforced via NOT NULL and FOREIGN KEY
CREATE TABLE CorporateAccounts (
  AccountId STRING(36) NOT NULL,
  AccountBalance NUMERIC,
  OwnerOrgId STRING(36) NOT NULL,
  IsHighRisk BOOL AS (AccountBalance > 100000.00) STORED,
  CONSTRAINT FK_CorporateAccount_Owner FOREIGN KEY (OwnerOrgId) REFERENCES Organizations (OrganizationId)
) PRIMARY KEY (AccountId);

-- Object Property: ex:hasSignatory (ex:PersonalAccount -> ex:Person, maxCardinality 3)
CREATE TABLE PersonalAccountSignatories (
  AccountId STRING(36) NOT NULL,
  PersonId STRING(36) NOT NULL,
  CONSTRAINT FK_Signatory_Account FOREIGN KEY (AccountId) REFERENCES PersonalAccounts (AccountId),
  CONSTRAINT FK_Signatory_Person FOREIGN KEY (PersonId) REFERENCES People (PersonId)
) PRIMARY KEY (AccountId, PersonId);

-- Object Property: ex:isPartnerOf (ex:Organization <-> ex:Organization, SymmetricProperty)
CREATE TABLE OrganizationPartners (
  OrgId1 STRING(36) NOT NULL,
  OrgId2 STRING(36) NOT NULL,
  CONSTRAINT FK_OrgPartner_Org1 FOREIGN KEY (OrgId1) REFERENCES Organizations (OrganizationId),
  CONSTRAINT FK_OrgPartner_Org2 FOREIGN KEY (OrgId2) REFERENCES Organizations (OrganizationId)
) PRIMARY KEY (OrgId1, OrgId2);

-- Object Property: ex:subAccountOf (Transitive hierarchy across accounts)
CREATE TABLE AccountSubAccounts (
  ParentAccountId STRING(36) NOT NULL,
  SubAccountId STRING(36) NOT NULL
) PRIMARY KEY (ParentAccountId, SubAccountId);

-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH SCHEMA
-- =============================================================================

CREATE PROPERTY GRAPH FintechGraph
  NODE TABLES (
    -- Nodes for People (Hierarchy: Person -> Party)
    People
      LABEL Person PROPERTIES (PersonId)
      LABEL Party PROPERTIES (PersonId AS PartyId),

    -- Nodes for Organizations (Hierarchy: Organization -> Party)
    Organizations
      LABEL Organization PROPERTIES (OrganizationId)
      LABEL Party PROPERTIES (OrganizationId AS PartyId),

    -- Nodes for Personal Accounts (Hierarchy: PersonalAccount -> Account)
    PersonalAccounts
      LABEL PersonalAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
      LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk),

    -- Nodes for Corporate Accounts (Hierarchy: CorporateAccount -> Account)
    CorporateAccounts
      LABEL CorporateAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
      LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk)
  )
  EDGE TABLES (
    -- Relationship: ex:hasOwner (PersonalAccount -> Person)
    PersonalAccounts AS PersonalAccountOwners
      SOURCE KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
      DESTINATION KEY (OwnerPersonId) REFERENCES People (PersonId)
      LABEL HAS_OWNER NO PROPERTIES,

    -- Inverse Relationship: ex:ownsAccount (Person -> PersonalAccount)
    PersonalAccounts AS PersonOwnedPersonalAccounts
      SOURCE KEY (OwnerPersonId) REFERENCES People (PersonId)
      DESTINATION KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
      LABEL OWNS_ACCOUNT NO PROPERTIES,

    -- Relationship: ex:hasOwner (CorporateAccount -> Organization)
    CorporateAccounts AS CorporateAccountOwners
      SOURCE KEY (AccountId) REFERENCES CorporateAccounts (AccountId)
      DESTINATION KEY (OwnerOrgId) REFERENCES Organizations (OrganizationId)
      LABEL HAS_OWNER NO PROPERTIES,

    -- Inverse Relationship: ex:ownsAccount (Organization -> CorporateAccount)
    CorporateAccounts AS OrgOwnedCorporateAccounts
      SOURCE KEY (OwnerOrgId) REFERENCES Organizations (OrganizationId)
      DESTINATION KEY (AccountId) REFERENCES CorporateAccounts (AccountId)
      LABEL OWNS_ACCOUNT NO PROPERTIES,

    -- Relationship: ex:hasSignatory (PersonalAccount -> Person)
    PersonalAccountSignatories
      SOURCE KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
      DESTINATION KEY (PersonId) REFERENCES People (PersonId)
      LABEL HAS_SIGNATORY NO PROPERTIES,

    -- Relationship: ex:isPartnerOf (Forward Direction)
    OrganizationPartners
      SOURCE KEY (OrgId1) REFERENCES Organizations (OrganizationId)
      DESTINATION KEY (OrgId2) REFERENCES Organizations (OrganizationId)
      LABEL IS_PARTNER_OF NO PROPERTIES,

    -- Relationship: ex:isPartnerOf (Symmetric Inverse Direction)
    OrganizationPartners AS OrganizationPartnersInverse
      SOURCE KEY (OrgId2) REFERENCES Organizations (OrganizationId)
      DESTINATION KEY (OrgId1) REFERENCES Organizations (OrganizationId)
      LABEL IS_PARTNER_OF NO PROPERTIES,

    -- Relationship: ex:subAccountOf (Personal -> Personal)
    AccountSubAccounts AS PersonalToPersonalSubAccounts
      SOURCE KEY (ParentAccountId) REFERENCES PersonalAccounts (AccountId)
      DESTINATION KEY (SubAccountId) REFERENCES PersonalAccounts (AccountId)
      LABEL SUB_ACCOUNT_OF NO PROPERTIES,

    -- Relationship: ex:subAccountOf (Corporate -> Corporate)
    AccountSubAccounts AS CorporateToCorporateSubAccounts
      SOURCE KEY (ParentAccountId) REFERENCES CorporateAccounts (AccountId)
      DESTINATION KEY (SubAccountId) REFERENCES CorporateAccounts (AccountId)
      LABEL SUB_ACCOUNT_OF NO PROPERTIES
  );