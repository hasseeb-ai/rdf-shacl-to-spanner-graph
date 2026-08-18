-- =============================================================================
-- PHYSICAL RELATIONAL SCHEMA
-- =============================================================================

-- Concrete Node Table: Airport
CREATE TABLE Airports (
  AirportId STRING(36) NOT NULL,
  AirportCode STRING(MAX),
  AirportName STRING(MAX),
  CityServiced STRING(MAX)
) PRIMARY KEY (AirportId);

-- Edge Table: Root connectsTo relationship
CREATE TABLE AirportConnections (
  SourceAirportId STRING(36) NOT NULL,
  DestinationAirportId STRING(36) NOT NULL,
  CONSTRAINT FK_AirportConnections_Source FOREIGN KEY (SourceAirportId) REFERENCES Airports (AirportId),
  CONSTRAINT FK_AirportConnections_Dest FOREIGN KEY (DestinationAirportId) REFERENCES Airports (AirportId)
) PRIMARY KEY (SourceAirportId, DestinationAirportId);

-- Edge Table: operatesCommercialRoute relationship
CREATE TABLE OperatesCommercialRoutes (
  SourceAirportId STRING(36) NOT NULL,
  DestinationAirportId STRING(36) NOT NULL,
  CONSTRAINT FK_OperatesCommercial_Source FOREIGN KEY (SourceAirportId) REFERENCES Airports (AirportId),
  CONSTRAINT FK_OperatesCommercial_Dest FOREIGN KEY (DestinationAirportId) REFERENCES Airports (AirportId)
) PRIMARY KEY (SourceAirportId, DestinationAirportId);

-- Edge Table: schedulesDirectRoute relationship
CREATE TABLE SchedulesDirectRoutes (
  SourceAirportId STRING(36) NOT NULL,
  DestinationAirportId STRING(36) NOT NULL,
  CONSTRAINT FK_SchedulesDirect_Source FOREIGN KEY (SourceAirportId) REFERENCES Airports (AirportId),
  CONSTRAINT FK_SchedulesDirect_Dest FOREIGN KEY (DestinationAirportId) REFERENCES Airports (AirportId)
) PRIMARY KEY (SourceAirportId, DestinationAirportId);

-- Edge Table: directNonstopCommercialFlight relationship (Multi-Parent Subproperty Leaf)
CREATE TABLE DirectNonstopCommercialFlights (
  SourceAirportId STRING(36) NOT NULL,
  DestinationAirportId STRING(36) NOT NULL,
  CONSTRAINT FK_DirectNonstop_Source FOREIGN KEY (SourceAirportId) REFERENCES Airports (AirportId),
  CONSTRAINT FK_DirectNonstop_Dest FOREIGN KEY (DestinationAirportId) REFERENCES Airports (AirportId)
) PRIMARY KEY (SourceAirportId, DestinationAirportId);

-- =============================================================================
-- PROPERTY GRAPH SCHEMA
-- =============================================================================

CREATE PROPERTY GRAPH SubpropertyDAGGraph
  NODE TABLES (
    Airports
      LABEL Airport PROPERTIES (AirportId, AirportCode, AirportName, CityServiced)
  )
  EDGE TABLES (
    -- Root Property Mapping
    AirportConnections
      SOURCE KEY (SourceAirportId) REFERENCES Airports (AirportId)
      DESTINATION KEY (DestinationAirportId) REFERENCES Airports (AirportId)
      LABEL CONNECTS_TO PROPERTIES (SourceAirportId, DestinationAirportId),

    -- Subproperty Level 1: operatesCommercialRoute -> connectsTo
    OperatesCommercialRoutes
      SOURCE KEY (SourceAirportId) REFERENCES Airports (AirportId)
      DESTINATION KEY (DestinationAirportId) REFERENCES Airports (AirportId)
      LABEL OPERATES_COMMERCIAL_ROUTE PROPERTIES (SourceAirportId, DestinationAirportId)
      LABEL CONNECTS_TO PROPERTIES (SourceAirportId, DestinationAirportId),

    -- Subproperty Level 1: schedulesDirectRoute -> connectsTo
    SchedulesDirectRoutes
      SOURCE KEY (SourceAirportId) REFERENCES Airports (AirportId)
      DESTINATION KEY (DestinationAirportId) REFERENCES Airports (AirportId)
      LABEL SCHEDULES_DIRECT_ROUTE PROPERTIES (SourceAirportId, DestinationAirportId)
      LABEL CONNECTS_TO PROPERTIES (SourceAirportId, DestinationAirportId),

    -- Multi-Parent Subproperty Level 2: directNonstopCommercialFlight -> (operatesCommercialRoute, schedulesDirectRoute) -> connectsTo
    DirectNonstopCommercialFlights
      SOURCE KEY (SourceAirportId) REFERENCES Airports (AirportId)
      DESTINATION KEY (DestinationAirportId) REFERENCES Airports (AirportId)
      LABEL DIRECT_NONSTOP_COMMERCIAL_FLIGHT PROPERTIES (SourceAirportId, DestinationAirportId)
      LABEL OPERATES_COMMERCIAL_ROUTE PROPERTIES (SourceAirportId, DestinationAirportId)
      LABEL SCHEDULES_DIRECT_ROUTE PROPERTIES (SourceAirportId, DestinationAirportId)
      LABEL CONNECTS_TO PROPERTIES (SourceAirportId, DestinationAirportId)
  );