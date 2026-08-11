-- =========================================================================
-- 1. PHYSICAL RELATIONAL SCHEMA (TABLE-PER-CLASS)
-- =========================================================================

-- Concrete Class: Person (Subclass of Party)
CREATE TABLE Person (
    PersonId INT64 NOT NULL,
    Name STRING(MAX) NOT NULL,
) PRIMARY KEY (PersonId);

-- Concrete Class: Organization (Subclass of Party)
CREATE TABLE Organization (
    OrganizationId INT64 NOT NULL,
    Name STRING(MAX) NOT NULL,
) PRIMARY KEY (OrganizationId);

-- Concrete Class: PersonalAccount (Subclass of Account)
CREATE TABLE PersonalAccount (
    AccountId INT64 NOT NULL,
    AccountBalance NUMERIC NOT NULL,
    -- Equivalent Class: HighRiskAccount (Balance > 100,000.00)
    IsHighRisk BOOL AS (AccountBalance > 100000.00) STORED,
) PRIMARY KEY (AccountId);

-- Concrete Class: CorporateAccount (Subclass of Account)
-- Enforces: hasOwner cardinality 1 and allValuesFrom Organization
CREATE TABLE CorporateAccount (
    AccountId INT64 NOT NULL,
    AccountBalance NUMERIC NOT NULL,
    -- Equivalent Class: HighRiskAccount (Balance > 100,000.00)
    IsHighRisk BOOL AS (AccountBalance > 100000.00) STORED,
    OwnerOrganizationId INT64 NOT NULL,
    CONSTRAINT FK_CorporateAccount_Owner FOREIGN KEY (OwnerOrganizationId) REFERENCES Organization (OrganizationId),
) PRIMARY KEY (AccountId);

-- ObjectProperty: hasOwner (PersonalAccount -> Person)
CREATE TABLE PersonalAccountOwners (
    AccountId INT64 NOT NULL,
    PersonId INT64 NOT NULL,
    CONSTRAINT FK_PA_Owners_Account FOREIGN KEY (AccountId) REFERENCES PersonalAccount (AccountId),
    CONSTRAINT FK_PA_Owners_Person FOREIGN KEY (PersonId) REFERENCES Person (PersonId),
) PRIMARY KEY (AccountId, PersonId);

-- ObjectProperty: hasSignatory (PersonalAccount -> Person)
-- Note: maxCardinality 3 must be enforced via application logic
CREATE TABLE PersonalAccountSignatories (
    AccountId INT64 NOT NULL,
    PersonId INT64 NOT NULL,
    CONSTRAINT FK_PA_Sig_Account FOREIGN KEY (AccountId) REFERENCES PersonalAccount (AccountId),
    CONSTRAINT FK_PA_Sig_Person FOREIGN KEY (PersonId) REFERENCES Person (PersonId),
) PRIMARY KEY (AccountId, PersonId);

-- ObjectProperty: isPartnerOf (Organization -> Organization)
-- Note: Symmetry must be handled via application writes or bidirectional queries
CREATE TABLE OrganizationPartners (
    OrganizationId INT64 NOT NULL,
    PartnerOrganizationId INT64 NOT NULL,
    CONSTRAINT FK_OrgPart_Org FOREIGN KEY (OrganizationId) REFERENCES Organization (OrganizationId),
    CONSTRAINT FK_OrgPart_Partner FOREIGN KEY (PartnerOrganizationId) REFERENCES Organization (OrganizationId),
) PRIMARY KEY (OrganizationId, PartnerOrganizationId);

-- Transitive ObjectProperty: subAccountOf (PersonalAccount -> PersonalAccount)
-- Implemented as an Interleaved Table to optimize hierarchical parent-child storage
CREATE TABLE PersonalSubAccounts (
    AccountId INT64 NOT NULL,
    ChildAccountId INT64 NOT NULL,
    CONSTRAINT FK_PersSub_Child FOREIGN KEY (ChildAccountId) REFERENCES PersonalAccount (AccountId),
) PRIMARY KEY (AccountId, ChildAccountId),
INTERLEAVE IN PARENT PersonalAccount ON DELETE CASCADE;

-- Transitive ObjectProperty: subAccountOf (CorporateAccount -> CorporateAccount)
-- Implemented as an Interleaved Table to optimize hierarchical parent-child storage
CREATE TABLE CorporateSubAccounts (
    AccountId INT64 NOT NULL,
    ChildAccountId INT64 NOT NULL,
    CONSTRAINT FK_CorpSub_Child FOREIGN KEY (ChildAccountId) REFERENCES CorporateAccount (AccountId),
) PRIMARY KEY (AccountId, ChildAccountId),
INTERLEAVE IN PARENT CorporateAccount ON DELETE CASCADE;


-- =========================================================================
-- 2. PROPERTY GRAPH SCHEMA
-- =========================================================================

CREATE PROPERTY GRAPH FintechConfigGraph
  NODE TABLES (
    Person KEY (PersonId)
      LABEL Person PROPERTIES (PersonId, Name)
      LABEL Party PROPERTIES (PersonId AS PartyId, Name),
      
    Organization KEY (OrganizationId)
      LABEL Organization PROPERTIES (OrganizationId, Name)
      LABEL Party PROPERTIES (OrganizationId AS PartyId, Name),
      
    PersonalAccount KEY (AccountId)
      LABEL PersonalAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
      LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk),
      
    CorporateAccount KEY (AccountId)
      LABEL CorporateAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
      LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk)
  )
  EDGE TABLES (
    -- Edge: HAS_OWNER (Personal)
    PersonalAccountOwners
      KEY (AccountId, PersonId)
      SOURCE KEY (AccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (PersonId) REFERENCES Person (PersonId)
      LABEL HAS_OWNER PROPERTIES (AccountId, PersonId AS OwnerId)
      LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, PersonId AS PartyId),
      
    -- Edge: HAS_OWNER (Corporate)
    CorporateAccount
      KEY (AccountId)
      SOURCE KEY (AccountId) REFERENCES CorporateAccount (AccountId)
      DESTINATION KEY (OwnerOrganizationId) REFERENCES Organization (OrganizationId)
      LABEL HAS_OWNER PROPERTIES (AccountId, OwnerOrganizationId AS OwnerId)
      LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, OwnerOrganizationId AS PartyId),
      
    -- Edge: HAS_SIGNATORY
    PersonalAccountSignatories
      KEY (AccountId, PersonId)
      SOURCE KEY (AccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (PersonId) REFERENCES Person (PersonId)
      LABEL HAS_SIGNATORY PROPERTIES (AccountId, PersonId AS SignatoryId),
      
    -- Edge: IS_PARTNER_OF
    OrganizationPartners
      KEY (OrganizationId, PartnerOrganizationId)
      SOURCE KEY (OrganizationId) REFERENCES Organization (OrganizationId)
      DESTINATION KEY (PartnerOrganizationId) REFERENCES Organization (OrganizationId)
      LABEL IS_PARTNER_OF PROPERTIES (OrganizationId, PartnerOrganizationId),
      
    -- Edge: SUB_ACCOUNT_OF (Personal Hierarchy)
    PersonalSubAccounts
      KEY (AccountId, ChildAccountId)
      SOURCE KEY (ChildAccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (AccountId) REFERENCES PersonalAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ChildAccountId AS SubAccountId, AccountId AS ParentAccountId),
      
    -- Edge: SUB_ACCOUNT_OF (Corporate Hierarchy)
    CorporateSubAccounts
      KEY (AccountId, ChildAccountId)
      SOURCE KEY (ChildAccountId) REFERENCES CorporateAccount (AccountId)
      DESTINATION KEY (AccountId) REFERENCES CorporateAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ChildAccountId AS SubAccountId, AccountId AS ParentAccountId)
  );