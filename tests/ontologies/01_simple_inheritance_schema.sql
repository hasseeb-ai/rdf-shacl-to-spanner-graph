-- =============================================================================
-- Google Cloud Spanner Relational DDL
-- Table-Per-Concrete-Class Inheritance Mapping
-- =============================================================================

CREATE TABLE Cars (
  CarId STRING(36) NOT NULL,
  Vin STRING(MAX),
  Manufacturer STRING(MAX),
  EngineDisplacementCc INT64,
  FuelType STRING(MAX),
  SeatingCapacity INT64,
  HasSunroof BOOL
) PRIMARY KEY (CarId);

CREATE TABLE Trucks (
  TruckId STRING(36) NOT NULL,
  Vin STRING(MAX),
  Manufacturer STRING(MAX),
  EngineDisplacementCc INT64,
  FuelType STRING(MAX),
  PayloadCapacityKg NUMERIC,
  AxleCount INT64
) PRIMARY KEY (TruckId);

-- =============================================================================
-- Google Cloud Spanner Property Graph DDL
-- Multi-Label Node Mapping for Class Hierarchy
-- =============================================================================

CREATE PROPERTY GRAPH SimpleInheritanceGraph
  NODE TABLES (
    Cars
      LABEL Car PROPERTIES (CarId, Vin, Manufacturer, EngineDisplacementCc, FuelType, SeatingCapacity, HasSunroof)
      LABEL MotorVehicle PROPERTIES (Vin, Manufacturer, EngineDisplacementCc, FuelType)
      LABEL Vehicle PROPERTIES (Vin, Manufacturer),
    Trucks
      LABEL Truck PROPERTIES (TruckId, Vin, Manufacturer, EngineDisplacementCc, FuelType, PayloadCapacityKg, AxleCount)
      LABEL MotorVehicle PROPERTIES (Vin, Manufacturer, EngineDisplacementCc, FuelType)
      LABEL Vehicle PROPERTIES (Vin, Manufacturer)
  );