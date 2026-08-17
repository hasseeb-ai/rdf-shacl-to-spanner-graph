-- =============================================================================
-- PHYSICAL RELATIONAL SCHEMA (Table-Per-Concrete-Class)
-- =============================================================================

-- Concrete Class: ex:NaturalPerson (subClassOf ex:Individual -> ex:LegalSubject)
-- Inherits: ex:taxIdentifier (Union of Individual & Organization), ex:contactEmail (Union of NaturalPerson & Corporation)
CREATE TABLE NaturalPersons (
  PersonId STRING(36) NOT NULL,
  TaxIdentifier STRING(MAX),
  ContactEmail STRING(MAX),
  BirthDate DATE
) PRIMARY KEY (PersonId);

-- Concrete Class: ex:Corporation (subClassOf ex:Organization -> ex:LegalSubject)
-- Inherits: ex:taxIdentifier (Union of Individual & Organization), ex:contactEmail (Union of NaturalPerson & Corporation)
CREATE TABLE Corporations (
  CorporationId STRING(36) NOT NULL,
  TaxIdentifier STRING(MAX),
  ContactEmail STRING(MAX),
  IncorporationNumber STRING(MAX)
) PRIMARY KEY (CorporationId);

-- Concrete Class: ex:NonProfit (subClassOf ex:Organization -> ex:LegalSubject)
-- Inherits: ex:taxIdentifier (Union of Individual & Organization)
-- Note: ex:contactEmail is NOT inherited (domain excludes NonProfit)
CREATE TABLE NonProfits (
  NonProfitId STRING(36) NOT NULL,
  TaxIdentifier STRING(MAX),
  CharityRegistrationId STRING(MAX)
) PRIMARY KEY (NonProfitId);

-- =============================================================================
-- PROPERTY GRAPH SCHEMA
-- =============================================================================

CREATE PROPERTY GRAPH UnionDomainsGraph
  NODE TABLES (
    NaturalPersons
      LABEL NATURAL_PERSON PROPERTIES (PersonId, TaxIdentifier, ContactEmail, BirthDate)
      LABEL INDIVIDUAL PROPERTIES (PersonId, TaxIdentifier, ContactEmail)
      LABEL LEGAL_SUBJECT PROPERTIES (PersonId AS SubjectId, TaxIdentifier),
    Corporations
      LABEL CORPORATION PROPERTIES (CorporationId, TaxIdentifier, ContactEmail, IncorporationNumber)
      LABEL ORGANIZATION PROPERTIES (CorporationId AS OrganizationId, TaxIdentifier)
      LABEL LEGAL_SUBJECT PROPERTIES (CorporationId AS SubjectId, TaxIdentifier),
    NonProfits
      LABEL NON_PROFIT PROPERTIES (NonProfitId, TaxIdentifier, CharityRegistrationId)
      LABEL ORGANIZATION PROPERTIES (NonProfitId AS OrganizationId, TaxIdentifier)
      LABEL LEGAL_SUBJECT PROPERTIES (NonProfitId AS SubjectId, TaxIdentifier)
  );