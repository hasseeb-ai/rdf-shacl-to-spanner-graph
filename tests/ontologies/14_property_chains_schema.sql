-- =============================================================================
-- Google Cloud Spanner Relational & Property Graph Schema
-- Ontology: Property Chain Axiom Ontology
-- =============================================================================

CREATE TABLE Countries (
  CountryId STRING(36) NOT NULL
) PRIMARY KEY (CountryId);

CREATE TABLE Cities (
  CityId STRING(36) NOT NULL,
  CountryId STRING(36) NOT NULL,
  CONSTRAINT FK_Cities_Country FOREIGN KEY (CountryId) REFERENCES Countries (CountryId)
) PRIMARY KEY (CityId);

CREATE TABLE Organizations (
  OrgId STRING(36) NOT NULL
) PRIMARY KEY (OrgId);

CREATE TABLE Facilities (
  FacilityId STRING(36) NOT NULL,
  OrgId STRING(36) NOT NULL,
  CityId STRING(36) NOT NULL,
  CONSTRAINT FK_Facilities_Organization FOREIGN KEY (OrgId) REFERENCES Organizations (OrgId),
  CONSTRAINT FK_Facilities_City FOREIGN KEY (CityId) REFERENCES Cities (CityId)
) PRIMARY KEY (FacilityId);

CREATE TABLE Persons (
  PersonId STRING(36) NOT NULL,
  FacilityId STRING(36) NOT NULL,
  CONSTRAINT FK_Persons_Facility FOREIGN KEY (FacilityId) REFERENCES Facilities (FacilityId)
) PRIMARY KEY (PersonId);

-- =============================================================================
-- Property Graph Schema Definition
-- =============================================================================

CREATE PROPERTY GRAPH OrganizationKnowledgeGraph
  NODE TABLES (
    Countries
      LABEL Country PROPERTIES (CountryId),
    Cities
      LABEL City PROPERTIES (CityId),
    Organizations
      LABEL Organization PROPERTIES (OrgId),
    Facilities
      LABEL Facility PROPERTIES (FacilityId),
    Persons
      LABEL Person PROPERTIES (PersonId)
  )
  EDGE TABLES (
    Persons AS PersonWorksAtFacility
      SOURCE KEY (PersonId) REFERENCES Persons (PersonId)
      DESTINATION KEY (FacilityId) REFERENCES Facilities (FacilityId)
      LABEL WORKS_AT,
    Facilities AS FacilityOfOrganization
      SOURCE KEY (FacilityId) REFERENCES Facilities (FacilityId)
      DESTINATION KEY (OrgId) REFERENCES Organizations (OrgId)
      LABEL FACILITY_OF,
    Facilities AS FacilityLocatedInCity
      SOURCE KEY (FacilityId) REFERENCES Facilities (FacilityId)
      DESTINATION KEY (CityId) REFERENCES Cities (CityId)
      LABEL LOCATED_IN_CITY,
    Cities AS CityInCountry
      SOURCE KEY (CityId) REFERENCES Cities (CityId)
      DESTINATION KEY (CountryId) REFERENCES Countries (CountryId)
      LABEL IN_COUNTRY
  );