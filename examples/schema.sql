-- =============================================================================
-- RELATIONAL SCHEMA (Physical Tables)
-- =============================================================================

-- Node Tables for Party Hierarchy
-- Represents ex:Person, a subclass of ex:Party
CREATE TABLE Persons (
    PersonId STRING(36) NOT NULL,
    FullName STRING(256),
    DateOfBirth DATE,
) PRIMARY KEY (PersonId);

-- Represents ex:Organization, a subclass of ex:Party
CREATE TABLE Organizations (
    OrganizationId STRING(36) NOT NULL,
    LegalName STRING(256),
    TaxId STRING(100),
) PRIMARY KEY (OrganizationId);

-- Node Tables for Account Hierarchy (Table-Per-Class)
-- Represents ex:PersonalAccount, a subclass of ex:Account
CREATE TABLE PersonalAccounts (
    AccountId STRING(36) NOT NULL,
    AccountBalance NUMERIC NOT NULL,
    -- Implements the ex:HighRiskAccount equivalentClass rule
    IsHighRisk BOOL AS (AccountBalance > 100000.0) STORED,
) PRIMARY KEY (AccountId);

-- Represents ex:CorporateAccount, a subclass of ex:Account
CREATE TABLE CorporateAccounts (
    AccountId STRING(36) NOT NULL,
    AccountBalance NUMERIC NOT NULL,
    -- Implements the ex:HighRiskAccount equivalentClass rule
    IsHighRisk BOOL AS (AccountBalance > 100000.0) STORED,
) PRIMARY KEY (AccountId);


-- Edge Tables for Relationships

-- Implements ex:hasOwner for PersonalAccounts (range: ex:Person)
CREATE TABLE PersonalAccountOwners (
    AccountId STRING(36) NOT NULL,
    PersonId STRING(36) NOT NULL,
    CONSTRAINT FK_PersonalAccountOwners_Account FOREIGN KEY (AccountId) REFERENCES PersonalAccounts (AccountId),
    CONSTRAINT FK_PersonalAccountOwners_Person FOREIGN KEY (PersonId) REFERENCES Persons (PersonId),
) PRIMARY KEY (AccountId, PersonId);

-- Implements ex:hasOwner for CorporateAccounts (range: ex:Organization)
CREATE TABLE CorporateAccountOwners (
    AccountId STRING(36) NOT NULL,
    OrganizationId STRING(36) NOT NULL,
    CONSTRAINT FK_CorporateAccountOwners_Account FOREIGN KEY (AccountId) REFERENCES CorporateAccounts (AccountId),
    CONSTRAINT FK_CorporateAccountOwners_Organization FOREIGN KEY (OrganizationId) REFERENCES Organizations (OrganizationId),
) PRIMARY KEY (AccountId, OrganizationId);

-- Implements ex:hasSignatory for PersonalAccounts (range: ex:Person)
CREATE TABLE PersonalAccountSignatories (
    AccountId STRING(36) NOT NULL,
    PersonId STRING(36) NOT NULL,
    CONSTRAINT FK_PersonalAccountSignatories_Account FOREIGN KEY (AccountId) REFERENCES PersonalAccounts (AccountId),
    CONSTRAINT FK_PersonalAccountSignatories_Person FOREIGN KEY (PersonId) REFERENCES Persons (PersonId),
) PRIMARY KEY (AccountId, PersonId);

-- Implements symmetric ex:isPartnerOf between Organizations
CREATE TABLE OrganizationPartners (
    OrganizationId1 STRING(36) NOT NULL,
    OrganizationId2 STRING(36) NOT NULL,
    -- Enforces single-direction storage for the symmetric relationship
    CONSTRAINT Chk_OrgPartners_Order CHECK (OrganizationId1 < OrganizationId2),
    CONSTRAINT FK_OrgPartners_Org1 FOREIGN KEY (OrganizationId1) REFERENCES Organizations (OrganizationId),
    CONSTRAINT FK_OrgPartners_Org2 FOREIGN KEY (OrganizationId2) REFERENCES Organizations (OrganizationId),
) PRIMARY KEY (OrganizationId1, OrganizationId2);

-- Implements transitive ex:subAccountOf relationship using INTERLEAVED tables.
-- This physically co-locates child accounts with their parents.

-- Child (Personal) interleaved in Parent (Personal)
CREATE TABLE PersToPersSubAccounts (
    AccountId STRING(36) NOT NULL, -- Parent's AccountId
    ChildAccountId STRING(36) NOT NULL,
    CONSTRAINT FK_P2P_Child FOREIGN KEY (ChildAccountId) REFERENCES PersonalAccounts (AccountId),
) PRIMARY KEY (AccountId, ChildAccountId),
INTERLEAVE IN PARENT PersonalAccounts ON DELETE CASCADE;

-- Child (Corporate) interleaved in Parent (Personal)
CREATE TABLE PersToCorpSubAccounts (
    AccountId STRING(36) NOT NULL, -- Parent's AccountId
    ChildCorporateAccountId STRING(36) NOT NULL,
    CONSTRAINT FK_P2C_Child FOREIGN KEY (ChildCorporateAccountId) REFERENCES CorporateAccounts (AccountId),
) PRIMARY KEY (AccountId, ChildCorporateAccountId),
INTERLEAVE IN PARENT PersonalAccounts ON DELETE CASCADE;

-- Child (Personal) interleaved in Parent (Corporate)
CREATE TABLE CorpToPersSubAccounts (
    AccountId STRING(36) NOT NULL, -- Parent's AccountId
    ChildPersonalAccountId STRING(36) NOT NULL,
    CONSTRAINT FK_C2P_Child FOREIGN KEY (ChildPersonalAccountId) REFERENCES PersonalAccounts (AccountId),
) PRIMARY KEY (AccountId, ChildPersonalAccountId),
INTERLEAVE IN PARENT CorporateAccounts ON DELETE CASCADE;

-- Child (Corporate) interleaved in Parent (Corporate)
CREATE TABLE CorpToCorpSubAccounts (
    AccountId STRING(36) NOT NULL, -- Parent's AccountId
    ChildAccountId STRING(36) NOT NULL,
    CONSTRAINT FK_C2C_Child FOREIGN KEY (ChildAccountId) REFERENCES CorporateAccounts (AccountId),
) PRIMARY KEY (AccountId, ChildAccountId),
INTERLEAVE IN PARENT CorporateAccounts ON DELETE CASCADE;


-- =============================================================================
-- PROPERTY GRAPH SCHEMA (GQL-Compliant)
-- =============================================================================

CREATE PROPERTY GRAPH FintechGraph
    -- Node table definitions with multi-label hierarchy
    NODE TABLE Persons
        KEY (PersonId)
        LABEL Person PROPERTIES (FullName, DateOfBirth)
        LABEL Party PROPERTIES (PersonId AS PartyId, FullName AS PartyName)

    NODE TABLE Organizations
        KEY (OrganizationId)
        LABEL Organization PROPERTIES (LegalName, TaxId)
        LABEL Party PROPERTIES (OrganizationId AS PartyId, LegalName AS PartyName)

    NODE TABLE PersonalAccounts
        KEY (AccountId)
        LABEL PersonalAccount PROPERTIES (AccountBalance, IsHighRisk)
        LABEL Account PROPERTIES (AccountBalance, IsHighRisk)

    NODE TABLE CorporateAccounts
        KEY (AccountId)
        LABEL CorporateAccount PROPERTIES (AccountBalance, IsHighRisk)
        LABEL Account PROPERTIES (AccountBalance, IsHighRisk)

    -- Edge table definitions
    EDGE TABLE PersonalAccountOwners
        SOURCE KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
        DESTINATION KEY (PersonId) REFERENCES Persons (PersonId)
        LABEL HAS_OWNER PROPERTIES (PersonId AS OwnerPartyId)

    EDGE TABLE CorporateAccountOwners
        SOURCE KEY (AccountId) REFERENCES CorporateAccounts (AccountId)
        DESTINATION KEY (OrganizationId) REFERENCES Organizations (OrganizationId)
        LABEL HAS_OWNER PROPERTIES (OrganizationId AS OwnerPartyId)

    EDGE TABLE PersonalAccountSignatories
        SOURCE KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
        DESTINATION KEY (PersonId) REFERENCES Persons (PersonId)
        LABEL HAS_SIGNATORY PROPERTIES ()

    EDGE TABLE OrganizationPartners
        SOURCE KEY (OrganizationId1) REFERENCES Organizations (OrganizationId)
        DESTINATION KEY (OrganizationId2) REFERENCES Organizations (OrganizationId)
        LABEL IS_PARTNER_OF PROPERTIES ()

    -- FIX: Edges for the transitive 'subAccountOf' relationship.
    -- The explicit 'PROPERTIES ()' clause ensures a uniform signature for the
    -- 'SUB_ACCOUNT_OF' label across all four tables where it is used.
    -- The direction is (Child)-[SUB_ACCOUNT_OF]->(Parent).
    EDGE TABLE PersToPersSubAccounts
        SOURCE KEY (ChildAccountId) REFERENCES PersonalAccounts (AccountId)
        DESTINATION KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
        LABEL SUB_ACCOUNT_OF PROPERTIES ()

    EDGE TABLE PersToCorpSubAccounts
        SOURCE KEY (ChildCorporateAccountId) REFERENCES CorporateAccounts (AccountId)
        DESTINATION KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
        LABEL SUB_ACCOUNT_OF PROPERTIES ()

    EDGE TABLE CorpToPersSubAccounts
        SOURCE KEY (ChildPersonalAccountId) REFERENCES PersonalAccounts (AccountId)
        DESTINATION KEY (AccountId) REFERENCES CorporateAccounts (AccountId)
        LABEL SUB_ACCOUNT_OF PROPERTIES ()

    EDGE TABLE CorpToCorpSubAccounts
        SOURCE KEY (ChildAccountId) REFERENCES CorporateAccounts (AccountId)
        DESTINATION KEY (AccountId) REFERENCES CorporateAccounts (AccountId)
        LABEL SUB_ACCOUNT_OF PROPERTIES ()
;