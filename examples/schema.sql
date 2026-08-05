-- #############################################################################
-- ## Google Cloud Spanner Schema for Fintech Compliance Ontology
-- ##
-- ## This schema translates the provided OWL ontology into a physical relational
-- ## model and a property graph model for use with Google Cloud Spanner.
-- #############################################################################


-- =============================================================================
-- == 1. Relational Schema (Physical DDL)
-- =============================================================================
-- This section defines the physical tables based on a "Table-Per-Class"
-- pattern for concrete leaf classes from the ontology.

-- Node Tables for Party Hierarchy
CREATE TABLE Persons (
    PersonId STRING(36) NOT NULL,
    Name STRING(MAX),
    -- Other person-specific attributes
) PRIMARY KEY (PersonId);

CREATE TABLE Organizations (
    OrganizationId STRING(36) NOT NULL,
    LegalName STRING(MAX),
    -- Other organization-specific attributes
) PRIMARY KEY (OrganizationId);

-- Node Tables for Account Hierarchy
CREATE TABLE PersonalAccounts (
    AccountId STRING(36) NOT NULL,
    AccountBalance NUMERIC,
    IsHighRisk BOOL AS (AccountBalance > 100000.0) STORED,
) PRIMARY KEY (AccountId);

CREATE TABLE CorporateAccounts (
    AccountId STRING(36) NOT NULL,
    AccountBalance NUMERIC,
    IsHighRisk BOOL AS (AccountBalance > 100000.0) STORED,
) PRIMARY KEY (AccountId);


-- Edge Tables for Object Properties
CREATE TABLE PersonalAccount_Owners (
    AccountId STRING(36) NOT NULL,
    PersonId STRING(36) NOT NULL,
    CONSTRAINT FK_PersonalAccountOwner_Account FOREIGN KEY (AccountId) REFERENCES PersonalAccounts (AccountId),
    CONSTRAINT FK_PersonalAccountOwner_Person FOREIGN KEY (PersonId) REFERENCES Persons (PersonId),
) PRIMARY KEY (AccountId, PersonId);

CREATE TABLE CorporateAccount_Owners (
    AccountId STRING(36) NOT NULL,
    OrganizationId STRING(36) NOT NULL,
    CONSTRAINT FK_CorporateAccountOwner_Account FOREIGN KEY (AccountId) REFERENCES CorporateAccounts (AccountId),
    CONSTRAINT FK_CorporateAccountOwner_Organization FOREIGN KEY (OrganizationId) REFERENCES Organizations (OrganizationId),
) PRIMARY KEY (AccountId, OrganizationId);

CREATE TABLE PersonalAccount_Signatories (
    AccountId STRING(36) NOT NULL,
    PersonId STRING(36) NOT NULL,
    CONSTRAINT FK_PersonalAccountSignatory_Account FOREIGN KEY (AccountId) REFERENCES PersonalAccounts (AccountId),
    CONSTRAINT FK_PersonalAccountSignatory_Person FOREIGN KEY (PersonId) REFERENCES Persons (PersonId),
) PRIMARY KEY (AccountId, PersonId);

CREATE TABLE Organization_Partnerships (
    OrganizationId1 STRING(36) NOT NULL,
    OrganizationId2 STRING(36) NOT NULL,
    CONSTRAINT FK_OrgPartner_Org1 FOREIGN KEY (OrganizationId1) REFERENCES Organizations (OrganizationId),
    CONSTRAINT FK_OrgPartner_Org2 FOREIGN KEY (OrganizationId2) REFERENCES Organizations (OrganizationId),
    -- CHECK constraint enforces storing one direction (A,B) for a symmetric pair
    -- to prevent storing a duplicate (B,A).
    CHECK (OrganizationId1 < OrganizationId2),
) PRIMARY KEY (OrganizationId1, OrganizationId2);

CREATE TABLE AccountHierarchy (
    ParentAccountId STRING(36) NOT NULL,
    ChildAccountId STRING(36) NOT NULL,
    -- NOTE: Foreign keys cannot be used here because the referenced account
    -- could be in either PersonalAccounts or CorporateAccounts. This referential
    -- integrity is managed at the graph layer definition below.
) PRIMARY KEY (ParentAccountId, ChildAccountId);


-- =============================================================================
-- == 2. Property Graph Schema (GQL DDL)
-- =============================================================================
-- This statement maps the physical tables to a GQL-compliant property graph,
-- enabling graph-based queries over the relational data.

CREATE PROPERTY GRAPH FintechComplianceGraph
    -- NODE TABLES define the vertices of the graph.
    -- Multi-label inheritance (e.g., Person -> Party) is modeled here.
    NODE TABLE Persons
        KEY (PersonId)
        -- Aliasing PersonId to PartyId for the 'Party' label ensures a uniform
        -- property signature across all tables sharing that label.
        LABEL Person PROPERTIES (PersonId, Name)
        LABEL Party PROPERTIES (PersonId AS PartyId, Name)

    NODE TABLE Organizations
        KEY (OrganizationId)
        LABEL Organization PROPERTIES (OrganizationId, LegalName)
        LABEL Party PROPERTIES (OrganizationId AS PartyId, LegalName)

    NODE TABLE PersonalAccounts
        KEY (AccountId)
        LABEL PersonalAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
        LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk)
        -- The 'HighRiskAccount' label is conditionally applied based on the
        -- generated column, implementing the owl:equivalentClass rule.
        LABEL HighRiskAccount WHERE IsHighRisk = TRUE PROPERTIES (AccountId, AccountBalance)

    NODE TABLE CorporateAccounts
        KEY (AccountId)
        LABEL CorporateAccount PROPERTIES (AccountId, AccountBalance, IsHighRisk)
        LABEL Account PROPERTIES (AccountId, AccountBalance, IsHighRisk)
        LABEL HighRiskAccount WHERE IsHighRisk = TRUE PROPERTIES (AccountId, AccountBalance)

    -- EDGE TABLES define the relationships (edges) between nodes.
    EDGE TABLE PersonalAccount_Owners
        SOURCE KEY (AccountId) REFERENCES PersonalAccounts
        DESTINATION KEY (PersonId) REFERENCES Persons
        -- Aliasing PersonId to OwnerId ensures the 'hasOwner' label has a
        -- consistent property signature across all its defining tables.
        LABEL hasOwner PROPERTIES (AccountId, PersonId AS OwnerId)

    EDGE TABLE CorporateAccount_Owners
        SOURCE KEY (AccountId) REFERENCES CorporateAccounts
        DESTINATION KEY (OrganizationId) REFERENCES Organizations
        LABEL hasOwner PROPERTIES (AccountId, OrganizationId AS OwnerId)

    EDGE TABLE PersonalAccount_Signatories
        SOURCE KEY (AccountId) REFERENCES PersonalAccounts
        DESTINATION KEY (PersonId) REFERENCES Persons
        LABEL hasSignatory PROPERTIES (AccountId, PersonId)

    EDGE TABLE Organization_Partnerships
        SOURCE KEY (OrganizationId1) REFERENCES Organizations
        DESTINATION KEY (OrganizationId2) REFERENCES Organizations
        -- isPartnerOf is symmetric; it can be queried in either direction.
        LABEL isPartnerOf PROPERTIES (OrganizationId1, OrganizationId2)

    EDGE TABLE AccountHierarchy
        -- The source of a 'subAccountOf' edge is the child account.
        SOURCE KEY (ChildAccountId) REFERENCES PersonalAccounts, CorporateAccounts
        -- The destination is the parent account.
        DESTINATION KEY (ParentAccountId) REFERENCES PersonalAccounts, CorporateAccounts
        -- subAccountOf is transitive; path queries (e.g., `->*`) can find all ancestors/descendants.
        LABEL subAccountOf PROPERTIES (ParentAccountId, ChildAccountId)
;


-- =============================================================================
-- == 3. Non-Translatable OWL Capabilities (System Gaps)
-- =============================================================================
-- The following OWL constructs from the source ontology cannot be declaratively
-- enforced by the Spanner DDL and must be handled at the application layer,
-- via database triggers (if supported/desired), or in specific queries.

-- * owl:cardinality "1" (on CorporateAccount -> hasOwner):
--   Spanner does not have a native DDL constraint to enforce an exact
--   cardinality of 1 for a relationship defined in a separate edge table.
--   Application logic must ensure each CorporateAccount has exactly one owner.

-- * owl:maxCardinality "3" (on PersonalAccount -> hasSignatory):
--   Spanner cannot enforce a maximum number of related entities in this model.
--   Application logic must validate that a PersonalAccount does not exceed
--   three signatories before inserting into the PersonalAccount_Signatories table.