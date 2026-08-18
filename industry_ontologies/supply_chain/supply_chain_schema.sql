-- =============================================================================
-- GOOGLE CLOUD SPANNER RELATIONAL DDL (TABLE-PER-CONCRETE-CLASS)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Locations (Concrete Subclasses of ex:Location / ex:Asset)
-- -----------------------------------------------------------------------------

CREATE TABLE Warehouses (
  WarehouseId STRING(36) NOT NULL,
  LocationCode STRING(MAX) NOT NULL
) PRIMARY KEY (WarehouseId);

CREATE TABLE ManufacturingPlants (
  ManufacturingPlantId STRING(36) NOT NULL,
  LocationCode STRING(MAX)
) PRIMARY KEY (ManufacturingPlantId);

CREATE TABLE SupplierFacilities (
  SupplierFacilityId STRING(36) NOT NULL,
  LocationCode STRING(MAX)
) PRIMARY KEY (SupplierFacilityId);

-- -----------------------------------------------------------------------------
-- 2. Items (Concrete Subclasses of ex:Item / ex:Asset)
-- -----------------------------------------------------------------------------

CREATE TABLE RawMaterials (
  RawMaterialId STRING(36) NOT NULL,
  UnitCost NUMERIC,
  QuantityInStock INT64,
  IsHighValueItem BOOL AS (UnitCost > 5000.00) STORED,
  StoredInWarehouseId STRING(36),
  SuppliedByFacilityId STRING(36),
  CONSTRAINT FK_RawMaterials_Warehouse FOREIGN KEY (StoredInWarehouseId) REFERENCES Warehouses (WarehouseId),
  CONSTRAINT FK_RawMaterials_Supplier FOREIGN KEY (SuppliedByFacilityId) REFERENCES SupplierFacilities (SupplierFacilityId)
) PRIMARY KEY (RawMaterialId);

CREATE TABLE SubAssemblies (
  SubAssemblyId STRING(36) NOT NULL,
  UnitCost NUMERIC,
  QuantityInStock INT64,
  IsHighValueItem BOOL AS (UnitCost > 5000.00) STORED,
  StoredInWarehouseId STRING(36),
  CONSTRAINT FK_SubAssemblies_Warehouse FOREIGN KEY (StoredInWarehouseId) REFERENCES Warehouses (WarehouseId)
) PRIMARY KEY (SubAssemblyId);

CREATE TABLE FinishedProducts (
  FinishedProductId STRING(36) NOT NULL,
  UnitCost NUMERIC,
  QuantityInStock INT64,
  IsHighValueItem BOOL AS (UnitCost > 5000.00) STORED,
  StoredInWarehouseId STRING(36),
  ManufacturedAtPlantId STRING(36) NOT NULL,
  CONSTRAINT FK_FinishedProducts_Warehouse FOREIGN KEY (StoredInWarehouseId) REFERENCES Warehouses (WarehouseId),
  CONSTRAINT FK_FinishedProducts_Plant FOREIGN KEY (ManufacturedAtPlantId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
) PRIMARY KEY (FinishedProductId);

-- -----------------------------------------------------------------------------
-- 3. Logistics & Carriers
-- -----------------------------------------------------------------------------

CREATE TABLE Carriers (
  CarrierId STRING(36) NOT NULL,
  CarrierName STRING(MAX)
) PRIMARY KEY (CarrierId);

CREATE TABLE Shipments (
  ShipmentId STRING(36) NOT NULL,
  ShipmentTrackingNumber STRING(MAX),
  ShipmentDate TIMESTAMP,
  ShippedViaCarrierId STRING(36),
  OriginLocationId STRING(36),
  DestinationLocationId STRING(36),
  CONSTRAINT FK_Shipments_Carrier FOREIGN KEY (ShippedViaCarrierId) REFERENCES Carriers (CarrierId)
) PRIMARY KEY (ShipmentId);

-- -----------------------------------------------------------------------------
-- 4. Associative Relationship Tables (Transitive & Symmetric Properties)
-- -----------------------------------------------------------------------------

-- Transitive Bill-of-Materials Hierarchy (ex:partOf / ex:hasPart)
CREATE TABLE ItemParts (
  ParentItemId STRING(36) NOT NULL,
  ChildItemId STRING(36) NOT NULL
) PRIMARY KEY (ParentItemId, ChildItemId);

-- Symmetric Route Network Connections (ex:connectedTo)
CREATE TABLE LocationConnections (
  LocationId STRING(36) NOT NULL,
  ConnectedLocationId STRING(36) NOT NULL
) PRIMARY KEY (LocationId, ConnectedLocationId);


-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH DDL
-- =============================================================================

CREATE PROPERTY GRAPH SupplyChainGraph
  NODE TABLES (
    -- Location Taxonomy Nodes
    Warehouses
      LABEL Warehouse PROPERTIES (WarehouseId, LocationCode)
      LABEL Location PROPERTIES (WarehouseId AS LocationId, LocationCode)
      LABEL Asset NO PROPERTIES,
    ManufacturingPlants
      LABEL ManufacturingPlant PROPERTIES (ManufacturingPlantId, LocationCode)
      LABEL Location PROPERTIES (ManufacturingPlantId AS LocationId, LocationCode)
      LABEL Asset NO PROPERTIES,
    SupplierFacilities
      LABEL SupplierFacility PROPERTIES (SupplierFacilityId, LocationCode)
      LABEL Location PROPERTIES (SupplierFacilityId AS LocationId, LocationCode)
      LABEL Asset NO PROPERTIES,

    -- Item Taxonomy Nodes
    RawMaterials
      LABEL RawMaterial PROPERTIES (RawMaterialId, UnitCost, QuantityInStock, IsHighValueItem)
      LABEL Item PROPERTIES (RawMaterialId AS ItemId, UnitCost, QuantityInStock, IsHighValueItem)
      LABEL Asset NO PROPERTIES,
    SubAssemblies
      LABEL SubAssembly PROPERTIES (SubAssemblyId, UnitCost, QuantityInStock, IsHighValueItem)
      LABEL Item PROPERTIES (SubAssemblyId AS ItemId, UnitCost, QuantityInStock, IsHighValueItem)
      LABEL Asset NO PROPERTIES,
    FinishedProducts
      LABEL FinishedProduct PROPERTIES (FinishedProductId, UnitCost, QuantityInStock, IsHighValueItem)
      LABEL Item PROPERTIES (FinishedProductId AS ItemId, UnitCost, QuantityInStock, IsHighValueItem)
      LABEL Asset NO PROPERTIES,

    -- Logistics Nodes
    Carriers
      LABEL Carrier PROPERTIES (CarrierId, CarrierName),
    Shipments
      LABEL Shipment PROPERTIES (ShipmentId, ShipmentTrackingNumber, ShipmentDate)
  )
  EDGE TABLES (
    -- ex:storedIn
    RawMaterials AS RawMaterialStoredInWarehouse
      SOURCE KEY (RawMaterialId) REFERENCES RawMaterials (RawMaterialId)
      DESTINATION KEY (StoredInWarehouseId) REFERENCES Warehouses (WarehouseId)
      LABEL STORED_IN NO PROPERTIES,
    SubAssemblies AS SubAssemblyStoredInWarehouse
      SOURCE KEY (SubAssemblyId) REFERENCES SubAssemblies (SubAssemblyId)
      DESTINATION KEY (StoredInWarehouseId) REFERENCES Warehouses (WarehouseId)
      LABEL STORED_IN NO PROPERTIES,
    FinishedProducts AS FinishedProductStoredInWarehouse
      SOURCE KEY (FinishedProductId) REFERENCES FinishedProducts (FinishedProductId)
      DESTINATION KEY (StoredInWarehouseId) REFERENCES Warehouses (WarehouseId)
      LABEL STORED_IN NO PROPERTIES,

    -- ex:suppliedBy
    RawMaterials AS RawMaterialSuppliedByFacility
      SOURCE KEY (RawMaterialId) REFERENCES RawMaterials (RawMaterialId)
      DESTINATION KEY (SuppliedByFacilityId) REFERENCES SupplierFacilities (SupplierFacilityId)
      LABEL SUPPLIED_BY NO PROPERTIES,

    -- ex:manufacturedAt
    FinishedProducts AS FinishedProductManufacturedAtPlant
      SOURCE KEY (FinishedProductId) REFERENCES FinishedProducts (FinishedProductId)
      DESTINATION KEY (ManufacturedAtPlantId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
      LABEL MANUFACTURED_AT NO PROPERTIES,

    -- ex:shippedVia
    Shipments AS ShipmentShippedViaCarrier
      SOURCE KEY (ShipmentId) REFERENCES Shipments (ShipmentId)
      DESTINATION KEY (ShippedViaCarrierId) REFERENCES Carriers (CarrierId)
      LABEL SHIPPED_VIA NO PROPERTIES,

    -- ex:origin (Polymorphic Location Target)
    Shipments AS ShipmentOriginWarehouse
      SOURCE KEY (ShipmentId) REFERENCES Shipments (ShipmentId)
      DESTINATION KEY (OriginLocationId) REFERENCES Warehouses (WarehouseId)
      LABEL ORIGIN NO PROPERTIES,
    Shipments AS ShipmentOriginPlant
      SOURCE KEY (ShipmentId) REFERENCES Shipments (ShipmentId)
      DESTINATION KEY (OriginLocationId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
      LABEL ORIGIN NO PROPERTIES,
    Shipments AS ShipmentOriginFacility
      SOURCE KEY (ShipmentId) REFERENCES Shipments (ShipmentId)
      DESTINATION KEY (OriginLocationId) REFERENCES SupplierFacilities (SupplierFacilityId)
      LABEL ORIGIN NO PROPERTIES,

    -- ex:destination (Polymorphic Location Target)
    Shipments AS ShipmentDestinationWarehouse
      SOURCE KEY (ShipmentId) REFERENCES Shipments (ShipmentId)
      DESTINATION KEY (DestinationLocationId) REFERENCES Warehouses (WarehouseId)
      LABEL DESTINATION NO PROPERTIES,
    Shipments AS ShipmentDestinationPlant
      SOURCE KEY (ShipmentId) REFERENCES Shipments (ShipmentId)
      DESTINATION KEY (DestinationLocationId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
      LABEL DESTINATION NO PROPERTIES,
    Shipments AS ShipmentDestinationFacility
      SOURCE KEY (ShipmentId) REFERENCES Shipments (ShipmentId)
      DESTINATION KEY (DestinationLocationId) REFERENCES SupplierFacilities (SupplierFacilityId)
      LABEL DESTINATION NO PROPERTIES,

    -- ex:partOf (Forward Edge)
    ItemParts AS RawMaterialPartOfSubAssembly
      SOURCE KEY (ChildItemId) REFERENCES RawMaterials (RawMaterialId)
      DESTINATION KEY (ParentItemId) REFERENCES SubAssemblies (SubAssemblyId)
      LABEL PART_OF NO PROPERTIES,
    ItemParts AS SubAssemblyPartOfFinishedProduct
      SOURCE KEY (ChildItemId) REFERENCES SubAssemblies (SubAssemblyId)
      DESTINATION KEY (ParentItemId) REFERENCES FinishedProducts (FinishedProductId)
      LABEL PART_OF NO PROPERTIES,
    ItemParts AS RawMaterialPartOfFinishedProduct
      SOURCE KEY (ChildItemId) REFERENCES RawMaterials (RawMaterialId)
      DESTINATION KEY (ParentItemId) REFERENCES FinishedProducts (FinishedProductId)
      LABEL PART_OF NO PROPERTIES,
    ItemParts AS SubAssemblyPartOfSubAssembly
      SOURCE KEY (ChildItemId) REFERENCES SubAssemblies (SubAssemblyId)
      DESTINATION KEY (ParentItemId) REFERENCES SubAssemblies (SubAssemblyId)
      LABEL PART_OF NO PROPERTIES,

    -- ex:hasPart (Inverse Edge: owl:inverseOf ex:partOf)
    ItemParts AS SubAssemblyHasRawMaterial
      SOURCE KEY (ParentItemId) REFERENCES SubAssemblies (SubAssemblyId)
      DESTINATION KEY (ChildItemId) REFERENCES RawMaterials (RawMaterialId)
      LABEL HAS_PART NO PROPERTIES,
    ItemParts AS FinishedProductHasSubAssembly
      SOURCE KEY (ParentItemId) REFERENCES FinishedProducts (FinishedProductId)
      DESTINATION KEY (ChildItemId) REFERENCES SubAssemblies (SubAssemblyId)
      LABEL HAS_PART NO PROPERTIES,
    ItemParts AS FinishedProductHasRawMaterial
      SOURCE KEY (ParentItemId) REFERENCES FinishedProducts (FinishedProductId)
      DESTINATION KEY (ChildItemId) REFERENCES RawMaterials (RawMaterialId)
      LABEL HAS_PART NO PROPERTIES,
    ItemParts AS SubAssemblyHasSubAssembly
      SOURCE KEY (ParentItemId) REFERENCES SubAssemblies (SubAssemblyId)
      DESTINATION KEY (ChildItemId) REFERENCES SubAssemblies (SubAssemblyId)
      LABEL HAS_PART NO PROPERTIES,

    -- ex:connectedTo (Symmetric Property between Locations)
    LocationConnections AS WarehouseToWarehouse
      SOURCE KEY (LocationId) REFERENCES Warehouses (WarehouseId)
      DESTINATION KEY (ConnectedLocationId) REFERENCES Warehouses (WarehouseId)
      LABEL CONNECTED_TO NO PROPERTIES,
    LocationConnections AS WarehouseToPlant
      SOURCE KEY (LocationId) REFERENCES Warehouses (WarehouseId)
      DESTINATION KEY (ConnectedLocationId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
      LABEL CONNECTED_TO NO PROPERTIES,
    LocationConnections AS WarehouseToSupplier
      SOURCE KEY (LocationId) REFERENCES Warehouses (WarehouseId)
      DESTINATION KEY (ConnectedLocationId) REFERENCES SupplierFacilities (SupplierFacilityId)
      LABEL CONNECTED_TO NO PROPERTIES,
    LocationConnections AS PlantToWarehouse
      SOURCE KEY (LocationId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
      DESTINATION KEY (ConnectedLocationId) REFERENCES Warehouses (WarehouseId)
      LABEL CONNECTED_TO NO PROPERTIES,
    LocationConnections AS PlantToPlant
      SOURCE KEY (LocationId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
      DESTINATION KEY (ConnectedLocationId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
      LABEL CONNECTED_TO NO PROPERTIES,
    LocationConnections AS PlantToSupplier
      SOURCE KEY (LocationId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
      DESTINATION KEY (ConnectedLocationId) REFERENCES SupplierFacilities (SupplierFacilityId)
      LABEL CONNECTED_TO NO PROPERTIES,
    LocationConnections AS SupplierToWarehouse
      SOURCE KEY (LocationId) REFERENCES SupplierFacilities (SupplierFacilityId)
      DESTINATION KEY (ConnectedLocationId) REFERENCES Warehouses (WarehouseId)
      LABEL CONNECTED_TO NO PROPERTIES,
    LocationConnections AS SupplierToPlant
      SOURCE KEY (LocationId) REFERENCES SupplierFacilities (SupplierFacilityId)
      DESTINATION KEY (ConnectedLocationId) REFERENCES ManufacturingPlants (ManufacturingPlantId)
      LABEL CONNECTED_TO NO PROPERTIES,
    LocationConnections AS SupplierToSupplier
      SOURCE KEY (LocationId) REFERENCES SupplierFacilities (SupplierFacilityId)
      DESTINATION KEY (ConnectedLocationId) REFERENCES SupplierFacilities (SupplierFacilityId)
      LABEL CONNECTED_TO NO PROPERTIES
  );