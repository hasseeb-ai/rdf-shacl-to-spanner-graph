-- =============================================================================
-- RELATIONAL SCHEMA (Physical Tables)
-- =============================================================================

-- Concrete Table: Building (subclass of SpatialEntity)
CREATE TABLE Buildings (
  BuildingId STRING(MAX) NOT NULL,
  BuildingName STRING(MAX) NOT NULL,
) PRIMARY KEY (BuildingId);

-- Concrete Table: Apartment (subclass of SpatialEntity)
CREATE TABLE Apartments (
  ApartmentId STRING(MAX) NOT NULL,
  ApartmentNumber STRING(MAX) NOT NULL,
  LocatedOnFloor INT64 NOT NULL,
) PRIMARY KEY (ApartmentId);

-- Concrete Table: State (subclass of SpatialEntity)
CREATE TABLE States (
  StateId STRING(MAX) NOT NULL,
  StateName STRING(MAX) NOT NULL,
) PRIMARY KEY (StateId);

-- Concrete Table: City (subclass of SpatialEntity)
CREATE TABLE Cities (
  CityId STRING(MAX) NOT NULL,
  CityName STRING(MAX) NOT NULL,
  EstablishedDate DATE,
) PRIMARY KEY (CityId);

-- Relationship Table: buildingContainsApartment (subPropertyOf contains)
CREATE TABLE BuildingApartments (
  BuildingId STRING(MAX) NOT NULL,
  ApartmentId STRING(MAX) NOT NULL,
  CONSTRAINT FK_BuildingApartments_Building FOREIGN KEY (BuildingId) REFERENCES Buildings (BuildingId),
  CONSTRAINT FK_BuildingApartments_Apartment FOREIGN KEY (ApartmentId) REFERENCES Apartments (ApartmentId)
) PRIMARY KEY (BuildingId, ApartmentId);

-- Relationship Table: stateContainsCity (subPropertyOf contains)
CREATE TABLE StateCities (
  StateId STRING(MAX) NOT NULL,
  CityId STRING(MAX) NOT NULL,
  CONSTRAINT FK_StateCities_State FOREIGN KEY (StateId) REFERENCES States (StateId),
  CONSTRAINT FK_StateCities_City FOREIGN KEY (CityId) REFERENCES Cities (CityId)
) PRIMARY KEY (StateId, CityId);


-- =============================================================================
-- PROPERTY GRAPH SCHEMA
-- =============================================================================

CREATE PROPERTY GRAPH ContainmentGraph
  NODE TABLES (
    Buildings
      LABEL Building PROPERTIES (BuildingId, BuildingName)
      LABEL SpatialEntity NO PROPERTIES,

    Apartments
      LABEL Apartment PROPERTIES (ApartmentId, ApartmentNumber, LocatedOnFloor)
      LABEL SpatialEntity NO PROPERTIES,

    States
      LABEL State PROPERTIES (StateId, StateName)
      LABEL SpatialEntity NO PROPERTIES,

    Cities
      LABEL City PROPERTIES (CityId, CityName, EstablishedDate)
      LABEL SpatialEntity NO PROPERTIES
  )
  EDGE TABLES (
    -- Subproperty: ex:buildingContainsApartment rdfs:subPropertyOf ex:contains
    BuildingApartments
      SOURCE KEY (BuildingId) REFERENCES Buildings (BuildingId)
      DESTINATION KEY (ApartmentId) REFERENCES Apartments (ApartmentId)
      LABEL BUILDING_CONTAINS_APARTMENT NO PROPERTIES
      LABEL `CONTAINS` NO PROPERTIES,

    -- Subproperty: ex:stateContainsCity rdfs:subPropertyOf ex:contains
    StateCities
      SOURCE KEY (StateId) REFERENCES States (StateId)
      DESTINATION KEY (CityId) REFERENCES Cities (CityId)
      LABEL STATE_CONTAINS_CITY NO PROPERTIES
      LABEL `CONTAINS` NO PROPERTIES
  );