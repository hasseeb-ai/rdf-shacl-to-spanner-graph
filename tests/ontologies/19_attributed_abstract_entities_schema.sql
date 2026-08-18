-- =============================================================================
-- Google Cloud Spanner Relational Schema DDL
-- Design Pattern: Table-Per-Concrete-Class with Flattened Superclass Attributes
-- =============================================================================

-- Concrete Table 1: Buildings (Inherits from SpatialEntity)
CREATE TABLE Buildings (
  SpatialEntityId STRING(MAX) NOT NULL,
  DisplayName STRING(MAX) NOT NULL,
  BuildingCode STRING(MAX) NOT NULL
) PRIMARY KEY (SpatialEntityId);

-- Concrete Table 2: Apartments (Inherits from SpatialEntity)
CREATE TABLE Apartments (
  SpatialEntityId STRING(MAX) NOT NULL,
  DisplayName STRING(MAX) NOT NULL,
  UnitNumber STRING(MAX) NOT NULL,
  FloorNumber INT64 NOT NULL
) PRIMARY KEY (SpatialEntityId);

-- Concrete Table 3: States (Inherits from SpatialEntity)
CREATE TABLE States (
  SpatialEntityId STRING(MAX) NOT NULL,
  DisplayName STRING(MAX) NOT NULL,
  StateCode STRING(MAX) NOT NULL
) PRIMARY KEY (SpatialEntityId);

-- Concrete Table 4: Cities (Inherits from SpatialEntity)
CREATE TABLE Cities (
  SpatialEntityId STRING(MAX) NOT NULL,
  DisplayName STRING(MAX) NOT NULL,
  PostalCode STRING(MAX) NOT NULL,
  PopulationCount INT64
) PRIMARY KEY (SpatialEntityId);

-- Physical Edge Table: Building -> Apartment (buildingContainsApartment)
CREATE TABLE BuildingApartments (
  BuildingId STRING(MAX) NOT NULL,
  ApartmentId STRING(MAX) NOT NULL,
  CONSTRAINT FK_BuildingApartments_Building FOREIGN KEY (BuildingId) REFERENCES Buildings (SpatialEntityId),
  CONSTRAINT FK_BuildingApartments_Apartment FOREIGN KEY (ApartmentId) REFERENCES Apartments (SpatialEntityId)
) PRIMARY KEY (BuildingId, ApartmentId);

-- Physical Edge Table: State -> City (stateContainsCity)
CREATE TABLE StateCities (
  StateId STRING(MAX) NOT NULL,
  CityId STRING(MAX) NOT NULL,
  CONSTRAINT FK_StateCities_State FOREIGN KEY (StateId) REFERENCES States (SpatialEntityId),
  CONSTRAINT FK_StateCities_City FOREIGN KEY (CityId) REFERENCES Cities (SpatialEntityId)
) PRIMARY KEY (StateId, CityId);

-- =============================================================================
-- Google Cloud Spanner Property Graph Schema DDL
-- Enforces Multi-Label Hierarchies & Subproperty Label Accumulation
-- =============================================================================

CREATE PROPERTY GRAPH SpatialGraph
  NODE TABLES (
    Buildings
      LABEL Building PROPERTIES (SpatialEntityId, DisplayName, BuildingCode)
      LABEL SpatialEntity PROPERTIES (SpatialEntityId, DisplayName),
    Apartments
      LABEL Apartment PROPERTIES (SpatialEntityId, DisplayName, UnitNumber, FloorNumber)
      LABEL SpatialEntity PROPERTIES (SpatialEntityId, DisplayName),
    States
      LABEL State PROPERTIES (SpatialEntityId, DisplayName, StateCode)
      LABEL SpatialEntity PROPERTIES (SpatialEntityId, DisplayName),
    Cities
      LABEL City PROPERTIES (SpatialEntityId, DisplayName, PostalCode, PopulationCount)
      LABEL SpatialEntity PROPERTIES (SpatialEntityId, DisplayName)
  )
  EDGE TABLES (
    BuildingApartments
      SOURCE KEY (BuildingId) REFERENCES Buildings (SpatialEntityId)
      DESTINATION KEY (ApartmentId) REFERENCES Apartments (SpatialEntityId)
      LABEL BUILDING_CONTAINS_APARTMENT NO PROPERTIES
      LABEL `CONTAINS` NO PROPERTIES,
    StateCities
      SOURCE KEY (StateId) REFERENCES States (SpatialEntityId)
      DESTINATION KEY (CityId) REFERENCES Cities (SpatialEntityId)
      LABEL STATE_CONTAINS_CITY NO PROPERTIES
      LABEL `CONTAINS` NO PROPERTIES
  );