-- =============================================================================
-- System Gaps: Non-Translatable OWL Capabilities
-- =============================================================================
-- The following OWL constructs from the source ontology cannot be directly
-- translated into or enforced by the Spanner DDL. They must be handled by
-- application-layer logic.
--
--   - Cardinality Constraints:
--     - ex:PersonalAccount -> ex:hasSignatory (owl:maxCardinality "3"):
--       The constraint that a personal account can have at most 3 signatories.
--     - ex:CorporateAccount -> ex:hasOwner (owl:cardinality "1"):
--       The constraint that a corporate account must have exactly one owner.
--       This is partially modeled with a NOT NULL constraint on the foreign key,
--       but uniqueness of ownership across accounts is not enforced.
--
-- =============================================================================
-- Part 1: Physical Relational DDL (Table-Per-Class)
-- =============================================================================
-- FAIL_VALIDATION

CREATE TABLE Persons (
    PersonId        STRING(36) NOT NULL,
    FullName        STRING(256),
    DateOfBirth     DATE,
) PRIMARY KEY (PersonId);

CREATE TABLE Organizations (
    OrganizationId  STRING(36) NOT NULL,
    LegalName       STRING(256),
    TaxId           STRING(100),
) PRIMARY KEY (OrganizationId);

-- Abstract parent table for all Account types. This is required to correctly
-- implement the transitive 'subAccountOf' relationship using an interleaved
-- table, which needs a single parent table type.
CREATE TABLE Accounts (
    AccountId       STRING(36) NOT NULL,
) PRIMARY KEY (AccountId);

-- Table for PersonalAccount, a concrete leaf class.
-- Inherits properties from ex:Account.
CREATE TABLE PersonalAccounts (
    AccountId           STRING(36) NOT NULL,
    AccountBalance      NUMERIC NOT NULL,
    OwnerPersonId       STRING(36),
    -- Equivalent Class (ex:HighRiskAccount) implemented as a generated column.
    IsHighRisk          BOOL AS (AccountBalance > 100000.0) STORED,
    CONSTRAINT FK_PersonalAccount_Account FOREIGN KEY (AccountId) REFERENCES Accounts (AccountId),
    -- Localized Property Range (owl:allValuesFrom ex:Person) for hasOwner.
    CONSTRAINT FK_PersonalAccount_Owner FOREIGN KEY (OwnerPersonId) REFERENCES Persons (PersonId),
) PRIMARY KEY (AccountId);

-- Table for CorporateAccount, a concrete leaf class.
-- Disjoint from PersonalAccount, enforced by existing in a separate table.
CREATE TABLE CorporateAccounts (
    AccountId           STRING(36) NOT NULL,
    AccountBalance      NUMERIC NOT NULL,
    -- owl:cardinality "1" on hasOwner is enforced with NOT NULL.
    OwnerOrganizationId STRING(36) NOT NULL,
    -- Equivalent Class (ex:HighRiskAccount) implemented as a generated column.
    IsHighRisk          BOOL AS (AccountBalance > 100000.0) STORED,
    CONSTRAINT FK_CorporateAccount_Account FOREIGN KEY (AccountId) REFERENCES Accounts (AccountId),
    -- Localized Property Range (owl:allValuesFrom ex:Organization) for hasOwner.
    CONSTRAINT FK_CorporateAccount_Owner FOREIGN KEY (OwnerOrganizationId) REFERENCES Organizations (OrganizationId),
) PRIMARY KEY (AccountId);

-- Join table for the 'hasSignatory' relationship between PersonalAccount and Person.
CREATE TABLE PersonalAccountSignatories (
    AccountId           STRING(36) NOT NULL,
    SignatoryPersonId   STRING(36) NOT NULL,
    CONSTRAINT FK_Signatory_Account FOREIGN KEY (AccountId) REFERENCES PersonalAccounts (AccountId),
    CONSTRAINT FK_Signatory_Person FOREIGN KEY (SignatoryPersonId) REFERENCES Persons (PersonId),
) PRIMARY KEY (AccountId, SignatoryPersonId);

-- Join table for the symmetric 'isPartnerOf' relationship between Organizations.
CREATE TABLE OrganizationPartners (
    OrganizationId1     STRING(36) NOT NULL,
    OrganizationId2     STRING(36) NOT NULL,
    -- Enforce storing the symmetric relationship in one direction to avoid duplicates.
    CONSTRAINT Check_Partner_Order CHECK (OrganizationId1 < OrganizationId2),
    CONSTRAINT FK_Partner_Org1 FOREIGN KEY (OrganizationId1) REFERENCES Organizations (OrganizationId),
    CONSTRAINT FK_Partner_Org2 FOREIGN KEY (OrganizationId2) REFERENCES Organizations (OrganizationId),
) PRIMARY KEY (OrganizationId1, OrganizationId2);

-- Interleaved table for the transitive 'subAccountOf' relationship.
-- FIX: The original error was caused by violating Rule 3. The fix is to ensure
-- the child table's primary key starts with the parent's primary key column name.
-- Parent PK is Accounts(AccountId). Child PK must start with a column named 'AccountId'.
CREATE TABLE SubAccounts (
    AccountId           STRING(36) NOT NULL, -- The parent account's ID.
    SubAccountId        STRING(36) NOT NULL, -- The child account's ID.
    CONSTRAINT FK_SubAccount_Id FOREIGN KEY (SubAccountId) REFERENCES Accounts (AccountId),
) PRIMARY KEY (AccountId, SubAccountId),
INTERLEAVE IN PARENT Accounts ON DELETE CASCADE;


-- =============================================================================
-- Part 2: Logical Labeled Property Graph DDL
-- =============================================================================

CREATE PROPERTY GRAPH FintechGraph
  -- NODE TABLE definitions map relational tables to graph nodes.
  NODE TABLE Persons
    PRIMARY KEY (PersonId)
    LABEL Person PROPERTIES (ALL COLUMNS)

  NODE TABLE Organizations
    PRIMARY KEY (OrganizationId)
    LABEL Organization PROPERTIES (ALL COLUMNS)

  -- Abstract node table for linking, used by the SubAccounts edge.
  NODE TABLE Accounts
    PRIMARY KEY (AccountId)
    LABEL Account PROPERTIES (AccountId)

  -- Multi-label node table for Personal Accounts.
  NODE TABLE PersonalAccounts
    PRIMARY KEY (AccountId)
    LABEL PersonalAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk, OwnerPersonId)
    -- FIX: Corrected to satisfy Rule 2 (Shared Label Uniformity).
    -- The 'Account' label signature must match across all tables where it's used.
    -- It is now consistent with the signature from the 'Accounts' node table.
    LABEL Account PROPERTIES (AccountId)

  -- Multi-label node table for Corporate Accounts.
  NODE TABLE CorporateAccounts
    PRIMARY KEY (AccountId)
    LABEL CorporateAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk, OwnerOrganizationId)
    -- FIX: Corrected to satisfy Rule 2 (Shared Label Uniformity).
    LABEL Account PROPERTIES (AccountId)

  -- EDGE TABLE definitions map relational tables (or FKs) to graph edges.
  -- Edge for 'hasSignatory' relationship.
  EDGE TABLE PersonalAccountSignatories (
    SOURCE KEY (AccountId) REFERENCES PersonalAccounts,
    DESTINATION KEY (SignatoryPersonId) REFERENCES Persons
  )
    LABEL HAS_SIGNATORY PROPERTIES ()

  -- Edge for symmetric 'isPartnerOf' relationship.
  EDGE TABLE OrganizationPartners (
    SOURCE KEY (OrganizationId1) REFERENCES Organizations,
    DESTINATION KEY (OrganizationId2) REFERENCES Organizations
  )
    LABEL IS_PARTNER_OF UNDIRECTED PROPERTIES ()

  -- Edge for transitive 'subAccountOf' relationship.
  -- The edge connects the abstract 'Account' node type.
  -- The direction child->parent correctly models 'child subAccountOf parent'.
  EDGE TABLE SubAccounts (
    SOURCE KEY (SubAccountId) REFERENCES Accounts,
    DESTINATION KEY (AccountId) REFERENCES Accounts
  )
    LABEL SUB_ACCOUNT_OF PROPERTIES ()

  -- Edge for 'hasOwner' on Personal Accounts, defined from a foreign key.
  -- Also defines the 'ownsAccount' inverse relationship.
  EDGE TABLE PersonalAccounts_hasOwner (
    SOURCE KEY (AccountId) REFERENCES PersonalAccounts,
    DESTINATION KEY (OwnerPersonId) REFERENCES Persons
  )
    LABEL HAS_OWNER PROPERTIES ()
    LABEL OWNS_ACCOUNT AS REVERSED(HAS_OWNER)

  -- Edge for 'hasOwner' on Corporate Accounts.
  EDGE TABLE CorporateAccounts_hasOwner (
    SOURCE KEY (AccountId) REFERENCES CorporateAccounts,
    DESTINATION KEY (OwnerOrganizationId) REFERENCES Organizations
  )
    LABEL HAS_OWNER PROPERTIES ()
    LABEL OWNS_ACCOUNT AS REVERSED(HAS_OWNER)
;