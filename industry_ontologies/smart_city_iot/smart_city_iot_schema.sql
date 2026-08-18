-- =============================================================================
-- GOOGLE CLOUD SPANNER PHYSICAL RELATIONAL SCHEMA (DDL)
-- =============================================================================
-- Translation Pattern: Table-Per-Concrete-Class
-- Superclasses (SpatialEntity, IotDevice, Sensor) are abstract and flattened 
-- into concrete child tables following Top-Down Property Propagation rules.
-- SHACL minCount 1 constraints are mapped to NOT NULL columns.
-- =============================================================================

-- Concrete Class: ex:CityZone (subClassOf ex:SpatialEntity)
CREATE TABLE CityZones (
  CityZoneId STRING(36) NOT NULL,
  -- Flattened from ex:SpatialEntity (ex:spatialName)
  SpatialName STRING(MAX)
) PRIMARY KEY (CityZoneId);

-- Concrete Class: ex:SmartBuilding (subClassOf ex:SpatialEntity)
CREATE TABLE SmartBuildings (
  BuildingId STRING(36) NOT NULL,
  -- Flattened from ex:SpatialEntity (ex:spatialName)
  SpatialName STRING(MAX)
) PRIMARY KEY (BuildingId);

-- Concrete Class: ex:MaintenanceJob
CREATE TABLE MaintenanceJobs (
  JobId STRING(36) NOT NULL,
  JobStatus STRING(MAX)
) PRIMARY KEY (JobId);

-- Concrete Class: ex:GatewayNode (subClassOf ex:IotDevice)
CREATE TABLE GatewayNodes (
  GatewayNodeId STRING(36) NOT NULL,
  -- Flattened from ex:IotDevice (ex:macAddress) - SHACL minCount 1 -> NOT NULL
  MacAddress STRING(MAX) NOT NULL,
  InstalledInBuildingId STRING(36),
  MaintenanceJobId STRING(36),
  CONSTRAINT FK_Gateway_Building FOREIGN KEY (InstalledInBuildingId) REFERENCES SmartBuildings (BuildingId),
  CONSTRAINT FK_Gateway_Job FOREIGN KEY (MaintenanceJobId) REFERENCES MaintenanceJobs (JobId)
) PRIMARY KEY (GatewayNodeId);

-- Concrete Class: ex:TemperatureSensor (subClassOf ex:Sensor -> ex:IotDevice)
CREATE TABLE TemperatureSensors (
  SensorId STRING(36) NOT NULL,
  -- Flattened from ex:IotDevice (ex:macAddress) - SHACL minCount 1 -> NOT NULL
  MacAddress STRING(MAX) NOT NULL,
  -- Relationship ex:registeredToGateway - SHACL minCount 1 -> NOT NULL
  RegisteredToGatewayId STRING(36) NOT NULL,
  InstalledInBuildingId STRING(36),
  MaintenanceJobId STRING(36),
  CONSTRAINT FK_TempSensor_Gateway FOREIGN KEY (RegisteredToGatewayId) REFERENCES GatewayNodes (GatewayNodeId),
  CONSTRAINT FK_TempSensor_Building FOREIGN KEY (InstalledInBuildingId) REFERENCES SmartBuildings (BuildingId),
  CONSTRAINT FK_TempSensor_Job FOREIGN KEY (MaintenanceJobId) REFERENCES MaintenanceJobs (JobId)
) PRIMARY KEY (SensorId);

-- Concrete Class: ex:EnergySensor (subClassOf ex:Sensor -> ex:IotDevice)
CREATE TABLE EnergySensors (
  SensorId STRING(36) NOT NULL,
  -- Flattened from ex:IotDevice (ex:macAddress) - SHACL minCount 1 -> NOT NULL
  MacAddress STRING(MAX) NOT NULL,
  -- Relationship ex:registeredToGateway - SHACL minCount 1 -> NOT NULL
  RegisteredToGatewayId STRING(36) NOT NULL,
  InstalledInBuildingId STRING(36),
  MaintenanceJobId STRING(36),
  CONSTRAINT FK_EnergySensor_Gateway FOREIGN KEY (RegisteredToGatewayId) REFERENCES GatewayNodes (GatewayNodeId),
  CONSTRAINT FK_EnergySensor_Building FOREIGN KEY (InstalledInBuildingId) REFERENCES SmartBuildings (BuildingId),
  CONSTRAINT FK_EnergySensor_Job FOREIGN KEY (MaintenanceJobId) REFERENCES MaintenanceJobs (JobId)
) PRIMARY KEY (SensorId);

-- Concrete Class: ex:TelemetryObservation
CREATE TABLE TelemetryObservations (
  ObservationId STRING(36) NOT NULL,
  SensorId STRING(36) NOT NULL,
  ReadingValue NUMERIC,
  ReadingTimestamp TIMESTAMP,
  -- Generated Column representing owl:equivalentClass ex:AnomalousReading
  IsAnomalous BOOL AS (ReadingValue > 100.00) STORED
) PRIMARY KEY (ObservationId);

-- Physical Join Table for Polymorphic/Transitive Property ex:containedIn
CREATE TABLE SpatialEntityContainment (
  ParentSpatialEntityId STRING(36) NOT NULL,
  ChildSpatialEntityId STRING(36) NOT NULL
) PRIMARY KEY (ParentSpatialEntityId, ChildSpatialEntityId);

-- Physical Join Table for Symmetric Property ex:sharesMicrogridWith
CREATE TABLE BuildingMicrogridInterconnects (
  BuildingId STRING(36) NOT NULL,
  ConnectedBuildingId STRING(36) NOT NULL,
  CONSTRAINT FK_Microgrid_Building1 FOREIGN KEY (BuildingId) REFERENCES SmartBuildings (BuildingId),
  CONSTRAINT FK_Microgrid_Building2 FOREIGN KEY (ConnectedBuildingId) REFERENCES SmartBuildings (BuildingId)
) PRIMARY KEY (BuildingId, ConnectedBuildingId);

-- =============================================================================
-- SQL VIEWS FOR EQUIVALENT CLASSES & FILTERED QUERIES
-- =============================================================================

-- View modeling owl:equivalentClass ex:AnomalousReading
CREATE VIEW v_AnomalousReadings SQL SECURITY INVOKER AS
SELECT
  t.ObservationId,
  t.SensorId,
  t.ReadingValue,
  t.ReadingTimestamp
FROM TelemetryObservations t
WHERE t.ReadingValue > 100.00;

-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH DDL
-- =============================================================================
-- Compliance Rules Enforced:
-- 1. Multi-label individual binding (PROPERTIES block explicitly attached per LABEL).
-- 2. Uniform label signature alignment across different concrete tables.
-- 3. Backtick escaping for GoogleSQL reserved keywords (`CONTAINS`).
-- 4. Unique edge table mapping aliases (AS) for multiple edge declarations.
-- =============================================================================

CREATE PROPERTY GRAPH SmartCityGraph
  NODE TABLES (
    CityZones
      LABEL CityZone PROPERTIES (CityZoneId AS SpatialEntityId, SpatialName)
      LABEL SpatialEntity PROPERTIES (CityZoneId AS SpatialEntityId, SpatialName),

    SmartBuildings
      LABEL SmartBuilding PROPERTIES (BuildingId AS SpatialEntityId, SpatialName)
      LABEL SpatialEntity PROPERTIES (BuildingId AS SpatialEntityId, SpatialName),

    GatewayNodes
      LABEL GatewayNode PROPERTIES (GatewayNodeId AS DeviceId, MacAddress)
      LABEL IotDevice PROPERTIES (GatewayNodeId AS DeviceId, MacAddress),

    TemperatureSensors
      LABEL TemperatureSensor PROPERTIES (SensorId AS DeviceId, MacAddress)
      LABEL Sensor PROPERTIES (SensorId AS DeviceId, MacAddress)
      LABEL IotDevice PROPERTIES (SensorId AS DeviceId, MacAddress),

    EnergySensors
      LABEL EnergySensor PROPERTIES (SensorId AS DeviceId, MacAddress)
      LABEL Sensor PROPERTIES (SensorId AS DeviceId, MacAddress)
      LABEL IotDevice PROPERTIES (SensorId AS DeviceId, MacAddress),

    TelemetryObservations
      LABEL TelemetryObservation PROPERTIES (ObservationId, ReadingValue, ReadingTimestamp, IsAnomalous),

    MaintenanceJobs
      LABEL MaintenanceJob PROPERTIES (JobId, JobStatus)
  )
  EDGE TABLES (
    -- ex:containedIn (Transitive property on SpatialEntity -> SpatialEntity)
    SpatialEntityContainment AS ZoneContainsBuilding
      SOURCE KEY (ChildSpatialEntityId) REFERENCES SmartBuildings (BuildingId)
      DESTINATION KEY (ParentSpatialEntityId) REFERENCES CityZones (CityZoneId)
      LABEL CONTAINED_IN NO PROPERTIES,

    -- Inverse Property mapping for owl:inverseOf ex:containsSpace
    SpatialEntityContainment AS BuildingInZone
      SOURCE KEY (ParentSpatialEntityId) REFERENCES CityZones (CityZoneId)
      DESTINATION KEY (ChildSpatialEntityId) REFERENCES SmartBuildings (BuildingId)
      LABEL `CONTAINS` NO PROPERTIES
      LABEL CONTAINS_SPACE NO PROPERTIES,

    -- ex:registeredToGateway (Sensor -> GatewayNode)
    TemperatureSensors AS TempSensorGateways
      SOURCE KEY (SensorId) REFERENCES TemperatureSensors (SensorId)
      DESTINATION KEY (RegisteredToGatewayId) REFERENCES GatewayNodes (GatewayNodeId)
      LABEL REGISTERED_TO_GATEWAY NO PROPERTIES,

    EnergySensors AS EnergySensorGateways
      SOURCE KEY (SensorId) REFERENCES EnergySensors (SensorId)
      DESTINATION KEY (RegisteredToGatewayId) REFERENCES GatewayNodes (GatewayNodeId)
      LABEL REGISTERED_TO_GATEWAY NO PROPERTIES,

    -- ex:installedInBuilding (IotDevice -> SmartBuilding)
    GatewayNodes AS GatewayBuildingInstallations
      SOURCE KEY (GatewayNodeId) REFERENCES GatewayNodes (GatewayNodeId)
      DESTINATION KEY (InstalledInBuildingId) REFERENCES SmartBuildings (BuildingId)
      LABEL INSTALLED_IN_BUILDING NO PROPERTIES,

    TemperatureSensors AS TempSensorBuildingInstallations
      SOURCE KEY (SensorId) REFERENCES TemperatureSensors (SensorId)
      DESTINATION KEY (InstalledInBuildingId) REFERENCES SmartBuildings (BuildingId)
      LABEL INSTALLED_IN_BUILDING NO PROPERTIES,

    EnergySensors AS EnergySensorBuildingInstallations
      SOURCE KEY (SensorId) REFERENCES EnergySensors (SensorId)
      DESTINATION KEY (InstalledInBuildingId) REFERENCES SmartBuildings (BuildingId)
      LABEL INSTALLED_IN_BUILDING NO PROPERTIES,

    -- ex:recordedObservation (Sensor -> TelemetryObservation)
    TelemetryObservations AS TempSensorObservations
      SOURCE KEY (SensorId) REFERENCES TemperatureSensors (SensorId)
      DESTINATION KEY (ObservationId) REFERENCES TelemetryObservations (ObservationId)
      LABEL RECORDED_OBSERVATION NO PROPERTIES,

    TelemetryObservations AS EnergySensorObservations
      SOURCE KEY (SensorId) REFERENCES EnergySensors (SensorId)
      DESTINATION KEY (ObservationId) REFERENCES TelemetryObservations (ObservationId)
      LABEL RECORDED_OBSERVATION NO PROPERTIES,

    -- ex:hasMaintenanceJob (IotDevice -> MaintenanceJob)
    GatewayNodes AS GatewayMaintenance
      SOURCE KEY (GatewayNodeId) REFERENCES GatewayNodes (GatewayNodeId)
      DESTINATION KEY (MaintenanceJobId) REFERENCES MaintenanceJobs (JobId)
      LABEL HAS_MAINTENANCE_JOB NO PROPERTIES,

    TemperatureSensors AS TempSensorMaintenance
      SOURCE KEY (SensorId) REFERENCES TemperatureSensors (SensorId)
      DESTINATION KEY (MaintenanceJobId) REFERENCES MaintenanceJobs (JobId)
      LABEL HAS_MAINTENANCE_JOB NO PROPERTIES,

    EnergySensors AS EnergySensorMaintenance
      SOURCE KEY (SensorId) REFERENCES EnergySensors (SensorId)
      DESTINATION KEY (MaintenanceJobId) REFERENCES MaintenanceJobs (JobId)
      LABEL HAS_MAINTENANCE_JOB NO PROPERTIES,

    -- ex:sharesMicrogridWith (Symmetric Property)
    BuildingMicrogridInterconnects
      SOURCE KEY (BuildingId) REFERENCES SmartBuildings (BuildingId)
      DESTINATION KEY (ConnectedBuildingId) REFERENCES SmartBuildings (BuildingId)
      LABEL SHARES_MICROGRID_WITH NO PROPERTIES
  );