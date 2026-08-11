-- =========================================================================
-- 1. PHYSICAL RELATIONAL SCHEMA (DDL)
-- =========================================================================

-- Leaf Class: Person (Subclass of Party)
CREATE TABLE Person (
  PersonId STRING(36) NOT NULL,
  FirstName STRING(100),
  LastName STRING(100),
) PRIMARY KEY (PersonId);

-- Leaf Class: Organization (Subclass of Party)
CREATE TABLE Organization (
  OrganizationId STRING(36) NOT NULL,
  OrganizationName STRING(200) NOT NULL,
) PRIMARY KEY (OrganizationId);

-- Leaf Class: PersonalAccount (Subclass of Account)
CREATE TABLE PersonalAccount (
  AccountId STRING(36) NOT NULL,
  AccountBalance NUMERIC NOT NULL,
  OwnerPersonId STRING(36) NOT NULL,
  -- Equivalent Class: HighRiskAccount (Materialized via STORED Generated Column)
  IsHighRisk BOOL AS (AccountBalance > 100000.00) STORED,
  CONSTRAINT FK_PersonalAccount_Owner FOREIGN KEY (OwnerPersonId) REFERENCES Person (PersonId)
) PRIMARY KEY (AccountId);

-- Leaf Class: CorporateAccount (Subclass of Account)
CREATE TABLE CorporateAccount (
  AccountId STRING(36) NOT NULL,
  AccountBalance NUMERIC NOT NULL,
  OwnerOrganizationId STRING(36) NOT NULL,
  -- Equivalent Class: HighRiskAccount (Materialized via STORED Generated Column)
  IsHighRisk BOOL AS (AccountBalance > 100000.00) STORED,
  -- Enforces owl:cardinality "1" for hasOwner on CorporateAccount
  CONSTRAINT FK_CorporateAccount_Owner FOREIGN KEY (OwnerOrganizationId) REFERENCES Organization (OrganizationId)
) PRIMARY KEY (AccountId);

-- ObjectProperty: hasSignatory (Interleaved for Rule 3 PK Alignment)
CREATE TABLE PersonalAccountSignatory (
  AccountId STRING(36) NOT NULL,
  PersonId STRING(36) NOT NULL,
  CONSTRAINT FK_Signatory_Person FOREIGN KEY (PersonId) REFERENCES Person (PersonId)
) PRIMARY KEY (AccountId, PersonId),
INTERLEAVE IN PARENT PersonalAccount ON DELETE CASCADE;

-- ObjectProperty: isPartnerOf (Symmetric relationship between Organizations)
CREATE TABLE OrganizationPartner (
  OrganizationId STRING(36) NOT NULL,
  PartnerOrganizationId STRING(36) NOT NULL,
  CONSTRAINT FK_Partner_Org FOREIGN KEY (OrganizationId) REFERENCES Organization (OrganizationId),
  CONSTRAINT FK_Partner_PartnerOrg FOREIGN KEY (PartnerOrganizationId) REFERENCES Organization (OrganizationId)
) PRIMARY KEY (OrganizationId, PartnerOrganizationId);

-- ObjectProperty: subAccountOf (Transitive relationship between Accounts)
CREATE TABLE AccountHierarchy (
  ParentAccountId STRING(36) NOT NULL,
  ChildAccountId STRING(36) NOT NULL,
) PRIMARY KEY (ParentAccountId, ChildAccountId);


-- =========================================================================
-- 2. PROPERTY GRAPH SCHEMA (GQL DDL)
-- =========================================================================

CREATE OR REPLACE PROPERTY GRAPH FintechComplianceGraph
  NODE TABLES (
    Person
      LABEL Person PROPERTIES (PersonId, FirstName, LastName)
      LABEL Party PROPERTIES (PersonId AS PartyId),
    
    Organization
      LABEL Organization PROPERTIES (OrganizationId, OrganizationName)
      LABEL Party PROPERTIES (OrganizationId AS PartyId),
    
    PersonalAccount
      LABEL PersonalAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
      LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk),
    
    CorporateAccount
      LABEL CorporateAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
      LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk)
  )
  EDGE TABLES (
    -- ObjectProperty: hasOwner / ownsAccount (PersonalAccount -> Person)
    PersonalAccount AS PersonalAccountOwner
      KEY (AccountId)
      SOURCE KEY (AccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (OwnerPersonId) REFERENCES Person (PersonId)
      LABEL HAS_OWNER PROPERTIES (AccountId, OwnerPersonId AS OwnerId)
      LABEL OWNS_ACCOUNT PROPERTIES (AccountId, OwnerPersonId AS OwnerId),

    -- ObjectProperty: hasOwner / ownsAccount (CorporateAccount -> Organization)
    CorporateAccount AS CorporateAccountOwner
      KEY (AccountId)
      SOURCE KEY (AccountId) REFERENCES CorporateAccount (AccountId)
      DESTINATION KEY (OwnerOrganizationId) REFERENCES Organization (OrganizationId)
      LABEL HAS_OWNER PROPERTIES (AccountId, OwnerOrganizationId AS OwnerId)
      LABEL OWNS_ACCOUNT PROPERTIES (AccountId, OwnerOrganizationId AS OwnerId),

    -- ObjectProperty: hasSignatory (PersonalAccount -> Person)
    PersonalAccountSignatory
      KEY (AccountId, PersonId)
      SOURCE KEY (AccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (PersonId) REFERENCES Person (PersonId)
      LABEL HAS_SIGNATORY PROPERTIES (AccountId, PersonId),

    -- ObjectProperty: isPartnerOf (Organization -> Organization)
    OrganizationPartner
      KEY (OrganizationId, PartnerOrganizationId)
      SOURCE KEY (OrganizationId) REFERENCES Organization (OrganizationId)
      DESTINATION KEY (PartnerOrganizationId) REFERENCES Organization (OrganizationId)
      LABEL IS_PARTNER_OF PROPERTIES (OrganizationId, PartnerOrganizationId),

    -- ObjectProperty: subAccountOf (Polymorphic Edge Mappings)
    AccountHierarchy AS PersonalToPersonalSubAccount
      KEY (ParentAccountId, ChildAccountId)
      SOURCE KEY (ChildAccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (ParentAccountId) REFERENCES PersonalAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ParentAccountId, ChildAccountId),

    AccountHierarchy AS PersonalToCorporateSubAccount
      KEY (ParentAccountId, ChildAccountId)
      SOURCE KEY (ChildAccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (ParentAccountId) REFERENCES CorporateAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ParentAccountId, ChildAccountId),

    AccountHierarchy AS CorporateToPersonalSubAccount
      KEY (ParentAccountId, ChildAccountId)
      SOURCE KEY (ChildAccountId) REFERENCES CorporateAccount (AccountId)
      DESTINATION KEY (ParentAccountId) REFERENCES PersonalAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ParentAccountId, ChildAccountId),

    AccountHierarchy AS CorporateToCorporateSubAccount
      KEY (ParentAccountId, ChildAccountId)
      SOURCE KEY (ChildAccountId) REFERENCES CorporateAccount (AccountId)
      DESTINATION KEY (ParentAccountId) REFERENCES CorporateAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ParentAccountId, ChildAccountId)
  );