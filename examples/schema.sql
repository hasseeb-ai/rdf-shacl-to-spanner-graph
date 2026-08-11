-- =========================================================================
-- 1. PHYSICAL RELATIONAL SCHEMA (TABLES & CONSTRAINTS)
-- =========================================================================

-- Concrete implementation of ex:Person (Subclass of ex:Party)
CREATE TABLE Person (
    PersonId STRING(36) NOT NULL,
    FirstName STRING(256),
    LastName STRING(256)
) PRIMARY KEY (PersonId);

-- Concrete implementation of ex:Organization (Subclass of ex:Party)
CREATE TABLE Organization (
    OrgId STRING(36) NOT NULL,
    OrgName STRING(256)
) PRIMARY KEY (OrgId);

-- Concrete implementation of ex:PersonalAccount (Subclass of ex:Account)
-- Flattens ex:accountBalance and implements ex:HighRiskAccount as a STORED column.
CREATE TABLE PersonalAccount (
    AccountId STRING(36) NOT NULL,
    AccountBalance NUMERIC NOT NULL,
    OwnerPersonId STRING(36) NOT NULL,
    IsHighRisk BOOL AS (AccountBalance > 100000.00) STORED,
    CONSTRAINT FK_PersonalAccount_Owner FOREIGN KEY (OwnerPersonId) REFERENCES Person (PersonId)
) PRIMARY KEY (AccountId);

-- Concrete implementation of ex:CorporateAccount (Subclass of ex:Account)
-- Flattens ex:accountBalance and implements ex:HighRiskAccount as a STORED column.
CREATE TABLE CorporateAccount (
    AccountId STRING(36) NOT NULL,
    AccountBalance NUMERIC NOT NULL,
    OwnerOrgId STRING(36) NOT NULL,
    IsHighRisk BOOL AS (AccountBalance > 100000.00) STORED,
    CONSTRAINT FK_CorporateAccount_Owner FOREIGN KEY (OwnerOrgId) REFERENCES Organization (OrgId)
) PRIMARY KEY (AccountId);

-- Interleaved Table for ex:hasSignatory (PersonalAccount -> Person)
-- Enforces Rule 3: Primary Key Alignment
CREATE TABLE PersonalAccountSignatories (
    AccountId STRING(36) NOT NULL,
    SignatoryPersonId STRING(36) NOT NULL,
    CONSTRAINT FK_Signatory_Person FOREIGN KEY (SignatoryPersonId) REFERENCES Person (PersonId)
) PRIMARY KEY (AccountId, SignatoryPersonId),
  INTERLEAVE IN PARENT PersonalAccount ON DELETE CASCADE;

-- Junction Table for ex:isPartnerOf (Symmetric Organization -> Organization)
CREATE TABLE OrganizationPartners (
    OrgId STRING(36) NOT NULL,
    PartnerOrgId STRING(36) NOT NULL,
    CONSTRAINT FK_OrgPartners_Org FOREIGN KEY (OrgId) REFERENCES Organization (OrgId),
    CONSTRAINT FK_OrgPartners_Partner FOREIGN KEY (PartnerOrgId) REFERENCES Organization (OrgId)
) PRIMARY KEY (OrgId, PartnerOrgId);

-- Concrete Edge Tables for ex:subAccountOf (Transitive Account -> Account)
-- Four tables are required to maintain strict physical referential integrity across concrete tables.

CREATE TABLE PersonalSubAccountOfPersonal (
    ParentAccountId STRING(36) NOT NULL,
    ChildAccountId STRING(36) NOT NULL,
    CONSTRAINT FK_PSP_Parent FOREIGN KEY (ParentAccountId) REFERENCES PersonalAccount (AccountId),
    CONSTRAINT FK_PSP_Child FOREIGN KEY (ChildAccountId) REFERENCES PersonalAccount (AccountId)
) PRIMARY KEY (ParentAccountId, ChildAccountId);

CREATE TABLE PersonalSubAccountOfCorporate (
    ParentAccountId STRING(36) NOT NULL,
    ChildAccountId STRING(36) NOT NULL,
    CONSTRAINT FK_PSC_Parent FOREIGN KEY (ParentAccountId) REFERENCES CorporateAccount (AccountId),
    CONSTRAINT FK_PSC_Child FOREIGN KEY (ChildAccountId) REFERENCES PersonalAccount (AccountId)
) PRIMARY KEY (ParentAccountId, ChildAccountId);

CREATE TABLE CorporateSubAccountOfPersonal (
    ParentAccountId STRING(36) NOT NULL,
    ChildAccountId STRING(36) NOT NULL,
    CONSTRAINT FK_CSP_Parent FOREIGN KEY (ParentAccountId) REFERENCES PersonalAccount (AccountId),
    CONSTRAINT FK_CSP_Child FOREIGN KEY (ChildAccountId) REFERENCES CorporateAccount (AccountId)
) PRIMARY KEY (ParentAccountId, ChildAccountId);

CREATE TABLE CorporateSubAccountOfCorporate (
    ParentAccountId STRING(36) NOT NULL,
    ChildAccountId STRING(36) NOT NULL,
    CONSTRAINT FK_CSC_Parent FOREIGN KEY (ParentAccountId) REFERENCES CorporateAccount (AccountId),
    CONSTRAINT FK_CSC_Child FOREIGN KEY (ChildAccountId) REFERENCES CorporateAccount (AccountId)
) PRIMARY KEY (ParentAccountId, ChildAccountId);


-- =========================================================================
-- 2. PROPERTY GRAPH SCHEMA
-- =========================================================================

CREATE PROPERTY GRAPH FintechComplianceGraph
  NODE TABLES (
    Person
      LABEL Person PROPERTIES (PersonId, FirstName, LastName)
      LABEL Party PROPERTIES (PersonId AS PartyId),
    
    Organization
      LABEL Organization PROPERTIES (OrgId, OrgName)
      LABEL Party PROPERTIES (OrgId AS PartyId),
    
    PersonalAccount
      LABEL PersonalAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
      LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk),
    
    CorporateAccount
      LABEL CorporateAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
      LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk)
  )
  EDGE TABLES (
    -- ex:hasOwner (Account -> Party)
    PersonalAccount AS PersonalAccountOwnerEdge
      SOURCE KEY (AccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (OwnerPersonId) REFERENCES Person (PersonId)
      LABEL HAS_OWNER PROPERTIES (AccountId, OwnerPersonId AS OwnerId),
      
    CorporateAccount AS CorporateAccountOwnerEdge
      SOURCE KEY (AccountId) REFERENCES CorporateAccount (AccountId)
      DESTINATION KEY (OwnerOrgId) REFERENCES Organization (OrgId)
      LABEL HAS_OWNER PROPERTIES (AccountId, OwnerOrgId AS OwnerId),

    -- ex:ownsAccount (Party -> Account) - Inverse of ex:hasOwner
    PersonalAccount AS PersonOwnsAccountEdge
      SOURCE KEY (OwnerPersonId) REFERENCES Person (PersonId)
      DESTINATION KEY (AccountId) REFERENCES PersonalAccount (AccountId)
      LABEL OWNS_ACCOUNT PROPERTIES (AccountId, OwnerPersonId AS OwnerId),
      
    CorporateAccount AS OrgOwnsAccountEdge
      SOURCE KEY (OwnerOrgId) REFERENCES Organization (OrgId)
      DESTINATION KEY (AccountId) REFERENCES CorporateAccount (AccountId)
      LABEL OWNS_ACCOUNT PROPERTIES (AccountId, OwnerOrgId AS OwnerId),

    -- ex:hasSignatory (PersonalAccount -> Person)
    PersonalAccountSignatories
      SOURCE KEY (AccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (SignatoryPersonId) REFERENCES Person (PersonId)
      LABEL HAS_SIGNATORY PROPERTIES (AccountId, SignatoryPersonId),

    -- ex:isPartnerOf (Organization -> Organization)
    OrganizationPartners
      SOURCE KEY (OrgId) REFERENCES Organization (OrgId)
      DESTINATION KEY (PartnerOrgId) REFERENCES Organization (OrgId)
      LABEL IS_PARTNER_OF PROPERTIES (OrgId, PartnerOrgId),

    -- ex:subAccountOf (Account -> Account)
    PersonalSubAccountOfPersonal
      SOURCE KEY (ChildAccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (ParentAccountId) REFERENCES PersonalAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ParentAccountId, ChildAccountId),
      
    PersonalSubAccountOfCorporate
      SOURCE KEY (ChildAccountId) REFERENCES PersonalAccount (AccountId)
      DESTINATION KEY (ParentAccountId) REFERENCES CorporateAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ParentAccountId, ChildAccountId),
      
    CorporateSubAccountOfPersonal
      SOURCE KEY (ChildAccountId) REFERENCES CorporateAccount (AccountId)
      DESTINATION KEY (ParentAccountId) REFERENCES PersonalAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ParentAccountId, ChildAccountId),
      
    CorporateSubAccountOfCorporate
      SOURCE KEY (ChildAccountId) REFERENCES CorporateAccount (AccountId)
      DESTINATION KEY (ParentAccountId) REFERENCES CorporateAccount (AccountId)
      LABEL SUB_ACCOUNT_OF PROPERTIES (ParentAccountId, ChildAccountId)
  );