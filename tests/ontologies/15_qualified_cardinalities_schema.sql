-- =============================================================================
-- Google Cloud Spanner Physical Relational & Property Graph Schema
-- Translation of Qualified Cardinality Restrictions Ontology & SHACL Shapes
-- Pattern: Table-Per-Concrete-Class with Flattened Top-Down Inheritance
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Concrete Vehicle Leaf Tables (Table-Per-Concrete-Class)
-- Top-down inheritance flattens ex:vehicleId and ex:modelName from ex:Vehicle
-- -----------------------------------------------------------------------------

CREATE TABLE Bicycles (
  VehicleId STRING(MAX) NOT NULL,
  ModelName STRING(MAX)
) PRIMARY KEY (VehicleId);

CREATE TABLE Cars (
  VehicleId STRING(MAX) NOT NULL,
  ModelName STRING(MAX)
) PRIMARY KEY (VehicleId);

-- -----------------------------------------------------------------------------
-- 2. Concrete VehiclePart Leaf Tables (Table-Per-Concrete-Class)
-- Top-down inheritance flattens ex:partId and ex:partSerialNum from ex:VehiclePart
-- -----------------------------------------------------------------------------

CREATE TABLE Wheels (
  PartId STRING(MAX) NOT NULL,
  PartSerialNum STRING(MAX)
) PRIMARY KEY (PartId);

CREATE TABLE Engines (
  PartId STRING(MAX) NOT NULL,
  PartSerialNum STRING(MAX)
) PRIMARY KEY (PartId);

-- -----------------------------------------------------------------------------
-- 3. Relationship Tables (ex:hasPart Concrete Edges)
-- Explicit link tables connecting concrete vehicles to concrete component parts
-- -----------------------------------------------------------------------------

CREATE TABLE BicycleWheels (
  VehicleId STRING(MAX) NOT NULL,
  PartId STRING(MAX) NOT NULL,
  CONSTRAINT FK_BicycleWheels_Bicycle FOREIGN KEY (VehicleId) REFERENCES Bicycles (VehicleId),
  CONSTRAINT FK_BicycleWheels_Wheel FOREIGN KEY (PartId) REFERENCES Wheels (PartId)
) PRIMARY KEY (VehicleId, PartId);

CREATE TABLE CarWheels (
  VehicleId STRING(MAX) NOT NULL,
  PartId STRING(MAX) NOT NULL,
  CONSTRAINT FK_CarWheels_Car FOREIGN KEY (VehicleId) REFERENCES Cars (VehicleId),
  CONSTRAINT FK_CarWheels_Wheel FOREIGN KEY (PartId) REFERENCES Wheels (PartId)
) PRIMARY KEY (VehicleId, PartId);

CREATE TABLE CarEngines (
  VehicleId STRING(MAX) NOT NULL,
  PartId STRING(MAX) NOT NULL,
  CONSTRAINT FK_CarEngines_Car FOREIGN KEY (VehicleId) REFERENCES Cars (VehicleId),
  CONSTRAINT FK_CarEngines_Engine FOREIGN KEY (PartId) REFERENCES Engines (PartId)
) PRIMARY KEY (VehicleId, PartId);

-- -----------------------------------------------------------------------------
-- 4. Google Cloud Spanner Property Graph Definition
-- Implements multi-label taxonomy hierarchy and uniform edge labels
-- -----------------------------------------------------------------------------

CREATE PROPERTY GRAPH VehiclePartsGraph
  NODE TABLES (
    Bicycles
      LABEL Bicycle PROPERTIES (VehicleId, ModelName)
      LABEL Vehicle PROPERTIES (VehicleId, ModelName),
    Cars
      LABEL Car PROPERTIES (VehicleId, ModelName)
      LABEL Vehicle PROPERTIES (VehicleId, ModelName),
    Wheels
      LABEL Wheel PROPERTIES (PartId, PartSerialNum)
      LABEL VehiclePart PROPERTIES (PartId, PartSerialNum),
    Engines
      LABEL Engine PROPERTIES (PartId, PartSerialNum)
      LABEL VehiclePart PROPERTIES (PartId, PartSerialNum)
  )
  EDGE TABLES (
    BicycleWheels
      SOURCE KEY (VehicleId) REFERENCES Bicycles (VehicleId)
      DESTINATION KEY (PartId) REFERENCES Wheels (PartId)
      LABEL HAS_PART,
    CarWheels
      SOURCE KEY (VehicleId) REFERENCES Cars (VehicleId)
      DESTINATION KEY (PartId) REFERENCES Wheels (PartId)
      LABEL HAS_PART,
    CarEngines
      SOURCE KEY (VehicleId) REFERENCES Cars (VehicleId)
      DESTINATION KEY (PartId) REFERENCES Engines (PartId)
      LABEL HAS_PART
  );