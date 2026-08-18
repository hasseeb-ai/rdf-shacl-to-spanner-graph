-- =============================================================================
-- PHYSICAL RELATIONAL SCHEMA (Table-Per-Concrete-Class)
-- =============================================================================

-- Concrete Subclasses of Organization
CREATE TABLE Suppliers (
  SupplierId STRING(36) NOT NULL,
  OrgName STRING(MAX)
) PRIMARY KEY (SupplierId);

CREATE TABLE Distributors (
  DistributorId STRING(36) NOT NULL,
  OrgName STRING(MAX)
) PRIMARY KEY (DistributorId);

-- Concrete Subclasses of Facility
CREATE TABLE Warehouses (
  WarehouseId STRING(36) NOT NULL,
  FacilityCode STRING(MAX)
) PRIMARY KEY (WarehouseId);

CREATE TABLE RetailHubs (
  RetailHubId STRING(36) NOT NULL,
  FacilityCode STRING(MAX)
) PRIMARY KEY (RetailHubId);

-- Concrete Subclasses of Cargo
CREATE TABLE PerishableCargos (
  CargoId STRING(36) NOT NULL,
  CargoDescription STRING(MAX)
) PRIMARY KEY (CargoId);

CREATE TABLE DryCargos (
  CargoId STRING(36) NOT NULL,
  CargoDescription STRING(MAX)
) PRIMARY KEY (CargoId);

-- =============================================================================
-- RELATIONAL RELATIONSHIP TABLES & LOCALIZED RESTRICTIONS
-- =============================================================================

-- Localized Range Restriction: Supplier operatesAt ONLY Warehouse
CREATE TABLE SupplierOperatesAtWarehouses (
  SupplierId STRING(36) NOT NULL,
  WarehouseId STRING(36) NOT NULL,
  CONSTRAINT FK_SupplierOperatesAt_Supplier FOREIGN KEY (SupplierId) REFERENCES Suppliers (SupplierId),
  CONSTRAINT FK_SupplierOperatesAt_Warehouse FOREIGN KEY (WarehouseId) REFERENCES Warehouses (WarehouseId)
) PRIMARY KEY (SupplierId, WarehouseId);

-- Localized Range Restriction: Distributor operatesAt ONLY RetailHub
CREATE TABLE DistributorOperatesAtRetailHubs (
  DistributorId STRING(36) NOT NULL,
  RetailHubId STRING(36) NOT NULL,
  CONSTRAINT FK_DistributorOperatesAt_Distributor FOREIGN KEY (DistributorId) REFERENCES Distributors (DistributorId),
  CONSTRAINT FK_DistributorOperatesAt_RetailHub FOREIGN KEY (RetailHubId) REFERENCES RetailHubs (RetailHubId)
) PRIMARY KEY (DistributorId, RetailHubId);

-- Bottom-Up Object Property: Supplier suppliesTo Distributor
CREATE TABLE SupplierSuppliesToDistributors (
  SupplierId STRING(36) NOT NULL,
  DistributorId STRING(36) NOT NULL,
  CONSTRAINT FK_SuppliesTo_Supplier FOREIGN KEY (SupplierId) REFERENCES Suppliers (SupplierId),
  CONSTRAINT FK_SuppliesTo_Distributor FOREIGN KEY (DistributorId) REFERENCES Distributors (DistributorId)
) PRIMARY KEY (SupplierId, DistributorId);

-- Top-Down Object Property: Facility storesCargo Cargo (Decomposed across concrete leaf pairs)
CREATE TABLE WarehouseStoresPerishableCargos (
  WarehouseId STRING(36) NOT NULL,
  CargoId STRING(36) NOT NULL,
  CONSTRAINT FK_WarehouseStoresPerishable_Warehouse FOREIGN KEY (WarehouseId) REFERENCES Warehouses (WarehouseId),
  CONSTRAINT FK_WarehouseStoresPerishable_Cargo FOREIGN KEY (CargoId) REFERENCES PerishableCargos (CargoId)
) PRIMARY KEY (WarehouseId, CargoId);

CREATE TABLE WarehouseStoresDryCargos (
  WarehouseId STRING(36) NOT NULL,
  CargoId STRING(36) NOT NULL,
  CONSTRAINT FK_WarehouseStoresDry_Warehouse FOREIGN KEY (WarehouseId) REFERENCES Warehouses (WarehouseId),
  CONSTRAINT FK_WarehouseStoresDry_Cargo FOREIGN KEY (CargoId) REFERENCES DryCargos (CargoId)
) PRIMARY KEY (WarehouseId, CargoId);

CREATE TABLE RetailHubStoresPerishableCargos (
  RetailHubId STRING(36) NOT NULL,
  CargoId STRING(36) NOT NULL,
  CONSTRAINT FK_RetailHubStoresPerishable_RetailHub FOREIGN KEY (RetailHubId) REFERENCES RetailHubs (RetailHubId),
  CONSTRAINT FK_RetailHubStoresPerishable_Cargo FOREIGN KEY (CargoId) REFERENCES PerishableCargos (CargoId)
) PRIMARY KEY (RetailHubId, CargoId);

CREATE TABLE RetailHubStoresDryCargos (
  RetailHubId STRING(36) NOT NULL,
  CargoId STRING(36) NOT NULL,
  CONSTRAINT FK_RetailHubStoresDry_RetailHub FOREIGN KEY (RetailHubId) REFERENCES RetailHubs (RetailHubId),
  CONSTRAINT FK_RetailHubStoresDry_Cargo FOREIGN KEY (CargoId) REFERENCES DryCargos (CargoId)
) PRIMARY KEY (RetailHubId, CargoId);

-- =============================================================================
-- PROPERTY GRAPH SCHEMA DEFINITION
-- =============================================================================

CREATE PROPERTY GRAPH SupplyChainGraph
  NODE TABLES (
    -- Suppliers Node (Inherits Supplier & Organization labels)
    Suppliers
      LABEL Supplier PROPERTIES (SupplierId, OrgName)
      LABEL Organization PROPERTIES (SupplierId AS OrgId, OrgName),

    -- Distributors Node (Inherits Distributor & Organization labels)
    Distributors
      LABEL Distributor PROPERTIES (DistributorId, OrgName)
      LABEL Organization PROPERTIES (DistributorId AS OrgId, OrgName),

    -- Warehouses Node (Inherits Warehouse & Facility labels)
    Warehouses
      LABEL Warehouse PROPERTIES (WarehouseId, FacilityCode)
      LABEL Facility PROPERTIES (WarehouseId AS FacilityId, FacilityCode),

    -- RetailHubs Node (Inherits RetailHub & Facility labels)
    RetailHubs
      LABEL RetailHub PROPERTIES (RetailHubId, FacilityCode)
      LABEL Facility PROPERTIES (RetailHubId AS FacilityId, FacilityCode),

    -- PerishableCargos Node (Inherits PerishableCargo & Cargo labels)
    PerishableCargos
      LABEL PerishableCargo PROPERTIES (CargoId, CargoDescription)
      LABEL Cargo PROPERTIES (CargoId, CargoDescription),

    -- DryCargos Node (Inherits DryCargo & Cargo labels)
    DryCargos
      LABEL DryCargo PROPERTIES (CargoId, CargoDescription)
      LABEL Cargo PROPERTIES (CargoId, CargoDescription)
  )
  EDGE TABLES (
    -- operatesAt: Localized Range edges
    SupplierOperatesAtWarehouses
      SOURCE KEY (SupplierId) REFERENCES Suppliers (SupplierId)
      DESTINATION KEY (WarehouseId) REFERENCES Warehouses (WarehouseId)
      LABEL OPERATES_AT NO PROPERTIES,

    DistributorOperatesAtRetailHubs
      SOURCE KEY (DistributorId) REFERENCES Distributors (DistributorId)
      DESTINATION KEY (RetailHubId) REFERENCES RetailHubs (RetailHubId)
      LABEL OPERATES_AT NO PROPERTIES,

    -- suppliesTo: Bottom-up edge
    SupplierSuppliesToDistributors
      SOURCE KEY (SupplierId) REFERENCES Suppliers (SupplierId)
      DESTINATION KEY (DistributorId) REFERENCES Distributors (DistributorId)
      LABEL SUPPLIES_TO NO PROPERTIES,

    -- storesCargo: Top-down polymorphic edges
    WarehouseStoresPerishableCargos
      SOURCE KEY (WarehouseId) REFERENCES Warehouses (WarehouseId)
      DESTINATION KEY (CargoId) REFERENCES PerishableCargos (CargoId)
      LABEL STORES_CARGO NO PROPERTIES,

    WarehouseStoresDryCargos
      SOURCE KEY (WarehouseId) REFERENCES Warehouses (WarehouseId)
      DESTINATION KEY (CargoId) REFERENCES DryCargos (CargoId)
      LABEL STORES_CARGO NO PROPERTIES,

    RetailHubStoresPerishableCargos
      SOURCE KEY (RetailHubId) REFERENCES RetailHubs (RetailHubId)
      DESTINATION KEY (CargoId) REFERENCES PerishableCargos (CargoId)
      LABEL STORES_CARGO NO PROPERTIES,

    RetailHubStoresDryCargos
      SOURCE KEY (RetailHubId) REFERENCES RetailHubs (RetailHubId)
      DESTINATION KEY (CargoId) REFERENCES DryCargos (CargoId)
      LABEL STORES_CARGO NO PROPERTIES
  );