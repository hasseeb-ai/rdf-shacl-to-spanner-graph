-- =============================================================================
-- Google Cloud Spanner DDL for Fintech Compliance Ontology
-- =============================================================================
--
-- Non-Translatable OWL Constructs (to be enforced by Application Logic):
-- -----------------------------------------------------------------------------
-- The following OWL constraints from the source ontology are not directly
-- translatable into Spanner DDL and must be managed at the application layer:
--
-- 1. owl:maxCardinality:
--    - On ex:PersonalAccount, the property ex:hasSignatory has a max cardinality of 3.
--      Application logic should prevent adding a fourth signatory to a personal account.
--
-- 2. owl:cardinality:
--    - On ex:CorporateAccount, the property ex:hasOwner has an exact cardinality of 1.
--      The DDL enforces this via a NOT NULL constraint on the OwnerOrganizationId column,
--      but does not prevent multiple ownership relations if modeled differently. The current
--      schema design (FK column) inherently enforces a "to-one" relationship.
--
-- 3. owl:propertyDisjointWith, owl:IrreflexiveProperty, owl:AsymmetricProperty,
--    owl:propertyChainAxiom were not present in the source ontology but are
--    noted as general system gaps.
--
-- =============================================================================
-- I. Physical Relational Schema (Table-Per-Class)
-- =============================================================================

-- Node Tables for Party Hierarchy
-- Disjointness between Person and Organization is enforced by separate tables.

CREATE TABLE Person (
    PersonId    STRING(36) NOT NULL,
    Name        STRING(MAX)
) PRIMARY KEY (PersonId);

CREATE TABLE Organization (
    OrganizationId  STRING(36) NOT NULL,
    Name            STRING(MAX)
) PRIMARY KEY (OrganizationId);

-- Parent table for the Account hierarchy to allow polymorphic relationships
-- like sub-accounts, where an account can be either Personal or Corporate.
CREATE TABLE Account (
    AccountId   STRING(36) NOT NULL
) PRIMARY KEY (AccountId);

-- Concrete class tables for Account types, interleaved in the parent 'Account' table.
-- Superclass properties (e.g., accountBalance) are flattened into these child tables.

CREATE TABLE PersonalAccount (
    AccountId       STRING(36) NOT NULL,
    Balance         NUMERIC,
    OwnerPersonId   STRING(36) NOT NULL,
    -- owl:equivalentClass 'HighRiskAccount' is implemented as a stored generated column.
    IsHighRisk      BOOL AS (IFNULL(Balance, 0) > 100000.0) STORED,
    -- owl:allValuesFrom restriction is enforced by this foreign key.
    CONSTRAINT FK_PersonalAccount_Owner FOREIGN KEY (OwnerPersonId) REFERENCES Person (PersonId)
) PRIMARY KEY (AccountId),
INTERLEAVE IN PARENT Account ON DELETE CASCADE;

CREATE TABLE CorporateAccount (
    AccountId           STRING(36) NOT NULL,
    Balance             NUMERIC,
    OwnerOrganizationId STRING(36) NOT NULL,
    -- owl:equivalentClass 'HighRiskAccount' is implemented as a stored generated column.
    IsHighRisk          BOOL AS (IFNULL(Balance, 0) > 100000.0) STORED,
    -- owl:allValuesFrom restriction is enforced by this foreign key.
    CONSTRAINT FK_CorporateAccount_Owner FOREIGN KEY (OwnerOrganizationId) REFERENCES Organization (OrganizationId)
) PRIMARY KEY (AccountId),
INTERLEAVE IN PARENT Account ON DELETE CASCADE;


-- Edge Tables for Relationships

-- Join table for the 'hasSignatory' relationship (PersonalAccount -> Person).
CREATE TABLE PersonalAccountSignatories (
    AccountId   STRING(36) NOT NULL,
    PersonId    STRING(36) NOT NULL,
    CONSTRAINT FK_Signatories_Account FOREIGN KEY (AccountId) REFERENCES PersonalAccount (AccountId),
    CONSTRAINT FK_Signatories_Person FOREIGN KEY (PersonId) REFERENCES Person (PersonId)
) PRIMARY KEY (AccountId, PersonId);

-- Join table for the symmetric 'isPartnerOf' relationship (Organization <-> Organization).
-- A CHECK constraint ensures data is stored in a canonical form (Org1 < Org2) to represent
-- the single undirected edge, preventing duplicate (OrgA, OrgB) and (OrgB, OrgA) entries.
CREATE TABLE OrganizationPartners (
    Organization1Id STRING(36) NOT NULL,
    Organization2Id STRING(36) NOT NULL,
    CONSTRAINT FK_Partners_Org1 FOREIGN KEY (Organization1Id) REFERENCES Organization (OrganizationId),
    CONSTRAINT FK_Partners_Org2 FOREIGN KEY (Organization2Id) REFERENCES Organization (OrganizationId),
    CHECK (Organization1Id < Organization2Id)
) PRIMARY KEY (Organization1Id, Organization2Id);

-- Interleaved table for the transitive 'subAccountOf' relationship.
-- This models parent-child hierarchies between any two accounts.
-- The primary key (AccountId, SubAccountId) follows Spanner's interleaving rules.
CREATE TABLE AccountHierarchy (
    AccountId       STRING(36) NOT NULL, -- The parent account
    SubAccountId    STRING(36) NOT NULL, -- The child account
    CONSTRAINT FK_Hierarchy_Parent FOREIGN KEY (AccountId) REFERENCES Account (AccountId),
    CONSTRAINT FK_Hierarchy_Child FOREIGN KEY (SubAccountId) REFERENCES Account (AccountId)
) PRIMARY KEY (AccountId, SubAccountId),
INTERLEAVE IN PARENT Account ON DELETE CASCADE;


-- =============================================================================
-- II. Logical Labeled Property Graph Schema
-- =============================================================================

CREATE PROPERTY GRAPH FintechComplianceGraph

-- Node table definitions map physical tables to graph nodes.
-- Multi-label inheritance (e.g., PersonalAccount, Account) is defined here.
NODE TABLE Person
    KEY (PersonId)
    LABEL Person PROPERTIES (Name)

NODE TABLE Organization
    KEY (OrganizationId)
    LABEL Organization PROPERTIES (Name)

-- The parent Account table serves as an anchor for the abstract 'Account' label.
NODE TABLE Account
    KEY (AccountId)
    LABEL Account NO PROPERTIES

-- Concrete account tables add specific labels and properties to the base Account nodes.
-- Rule 1 (Individual Label Binding): Each LABEL has its own PROPERTIES clause.
-- Rule 2 (Shared Label Uniformity): The 'Account' label has a consistent property
-- signature across both PersonalAccount and CorporateAccount tables.
NODE TABLE PersonalAccount
    KEY (AccountId)
    LABEL PersonalAccount PROPERTIES (Balance, IsHighRisk)
    LABEL Account PROPERTIES (Balance, IsHighRisk)

NODE TABLE CorporateAccount
    KEY (AccountId)
    LABEL CorporateAccount PROPERTIES (Balance, IsHighRisk)
    LABEL Account PROPERTIES (Balance, IsHighRisk)

-- Edge table definitions map physical tables (or FKs) to graph edges.
-- The 'hasOwner' relationship is defined within the account tables themselves (foreign key edge).
-- Its inverse, 'ownsAccount', is defined logically without separate physical storage.
EDGE TABLE PersonalAccount
    SOURCE KEY (AccountId) REFERENCES PersonalAccount
    DESTINATION KEY (OwnerPersonId) REFERENCES Person
    LABEL HAS_OWNER NO PROPERTIES,

    SOURCE KEY (OwnerPersonId) REFERENCES Person
    DESTINATION KEY (AccountId) REFERENCES PersonalAccount
    LABEL OWNS_ACCOUNT NO PROPERTIES

EDGE TABLE CorporateAccount
    SOURCE KEY (AccountId) REFERENCES CorporateAccount
    DESTINATION KEY (OwnerOrganizationId) REFERENCES Organization
    LABEL HAS_OWNER NO PROPERTIES,

    SOURCE KEY (OwnerOrganizationId) REFERENCES Organization
    DESTINATION KEY (AccountId) REFERENCES CorporateAccount
    LABEL OWNS_ACCOUNT NO PROPERTIES

-- Edge for the 'hasSignatory' relationship, from a dedicated join table.
EDGE TABLE PersonalAccountSignatories
    SOURCE KEY (AccountId) REFERENCES PersonalAccount
    DESTINATION KEY (PersonId) REFERENCES Person
    LABEL HAS_SIGNATORY NO PROPERTIES

-- Symmetric Property 'isPartnerOf' is defined by creating two logical directed
-- edges from one physical row, enabling bidirectional traversal in GQL.
EDGE TABLE OrganizationPartners
    SOURCE KEY (Organization1Id) REFERENCES Organization
    DESTINATION KEY (Organization2Id) REFERENCES Organization
    LABEL IS_PARTNER_OF NO PROPERTIES,

    SOURCE KEY (Organization2Id) REFERENCES Organization
    DESTINATION KEY (Organization1Id) REFERENCES Organization
    LABEL IS_PARTNER_OF NO PROPERTIES

-- Transitive Property 'subAccountOf' is defined from the hierarchy table.
-- The edge direction (SubAccountId -> AccountId) reflects that the sub-account
-- 'is a sub-account of' the parent account.
EDGE TABLE AccountHierarchy
    SOURCE KEY (SubAccountId) REFERENCES Account
    DESTINATION KEY (AccountId) REFERENCES Account
    LABEL SUB_ACCOUNT_OF NO PROPERTIES
;