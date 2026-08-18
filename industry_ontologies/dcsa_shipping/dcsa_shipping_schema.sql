-- =============================================================================
-- GOOGLE CLOUD SPANNER PHYSICAL RELATIONAL SCHEMA (DDL)
-- Pattern: Table-Per-Concrete-Class with Flattened Superclass Hierarchies
-- =============================================================================

-- Core Entity: BillOfLading
CREATE TABLE BillsOfLading (
  BillOfLadingId STRING(36) NOT NULL,
  BolNumber STRING(MAX)
) PRIMARY KEY (BillOfLadingId);

-- Core Entity: Container
CREATE TABLE Containers (
  ContainerId STRING(36) NOT NULL,
  ContainerNumber STRING(MAX) NOT NULL
) PRIMARY KEY (ContainerId);

-- Core Entity: Vessel
CREATE TABLE Vessels (
  VesselId STRING(36) NOT NULL,
  VesselImo INT64,
  VesselName STRING(MAX)
) PRIMARY KEY (VesselId);

-- Symmetric Relationship: Vessel Alliances / Sharing Agreements
CREATE TABLE VesselAlliances (
  VesselId STRING(36) NOT NULL,
  AllianceVesselId STRING(36) NOT NULL,
  CONSTRAINT FK_VesselAlliance_Vessel FOREIGN KEY (VesselId) REFERENCES Vessels (VesselId),
  CONSTRAINT FK_VesselAlliance_Target FOREIGN KEY (AllianceVesselId) REFERENCES Vessels (VesselId)
) PRIMARY KEY (VesselId, AllianceVesselId);

-- Spatial Context: Concrete Base Location
CREATE TABLE Locations (
  LocationId STRING(36) NOT NULL,
  UnLocode STRING(MAX)
) PRIMARY KEY (LocationId);

-- Spatial Context: Concrete Subclass Facility (inherits UnLocode from Location)
CREATE TABLE Facilities (
  FacilityId STRING(36) NOT NULL,
  UnLocode STRING(MAX)
) PRIMARY KEY (FacilityId);

-- Core Entity: Booking (holds 1:1 / 1:N references to BL and Container)
CREATE TABLE Bookings (
  BookingId STRING(36) NOT NULL,
  BookingReference STRING(MAX),
  BillOfLadingId STRING(36),
  ContainerId STRING(36),
  CONSTRAINT FK_Booking_BL FOREIGN KEY (BillOfLadingId) REFERENCES BillsOfLading (BillOfLadingId),
  CONSTRAINT FK_Booking_Container FOREIGN KEY (ContainerId) REFERENCES Containers (ContainerId)
) PRIMARY KEY (BookingId);

-- Logistics Activity: TransportCall
CREATE TABLE TransportCalls (
  TransportCallId STRING(36) NOT NULL,
  VesselId STRING(36) NOT NULL,
  LocationId STRING(36),
  NextTransportCallId STRING(36),
  CONSTRAINT FK_TransportCall_Vessel FOREIGN KEY (VesselId) REFERENCES Vessels (VesselId),
  CONSTRAINT FK_TransportCall_Location FOREIGN KEY (LocationId) REFERENCES Locations (LocationId),
  CONSTRAINT FK_TransportCall_NextLeg FOREIGN KEY (NextTransportCallId) REFERENCES TransportCalls (TransportCallId)
) PRIMARY KEY (TransportCallId);

-- Event Hierarchy Leaf 1: EquipmentEvent (inherits Event fields + Container link + ActiveContainerEvent equivalent logic)
CREATE TABLE EquipmentEvents (
  EquipmentEventId STRING(36) NOT NULL,
  EventClassifier STRING(MAX),
  EventDateTime TIMESTAMP,
  LocationId STRING(36),
  ContainerId STRING(36),
  -- Equivalent Class: ActiveContainerEvent (EquipmentEvent with eventClassifier = 'ACTUAL')
  IsActiveContainerEvent BOOL AS (EventClassifier = 'ACTUAL') STORED,
  CONSTRAINT FK_EquipmentEvent_Location FOREIGN KEY (LocationId) REFERENCES Locations (LocationId),
  CONSTRAINT FK_EquipmentEvent_Container FOREIGN KEY (ContainerId) REFERENCES Containers (ContainerId)
) PRIMARY KEY (EquipmentEventId);

-- Event Hierarchy Leaf 2: TransportEvent (disjoint from EquipmentEvent & ShipmentEvent)
CREATE TABLE TransportEvents (
  TransportEventId STRING(36) NOT NULL,
  EventClassifier STRING(MAX),
  EventDateTime TIMESTAMP,
  LocationId STRING(36),
  CONSTRAINT FK_TransportEvent_Location FOREIGN KEY (LocationId) REFERENCES Locations (LocationId)
) PRIMARY KEY (TransportEventId);

-- Event Hierarchy Leaf 3: ShipmentEvent (disjoint from TransportEvent)
CREATE TABLE ShipmentEvents (
  ShipmentEventId STRING(36) NOT NULL,
  EventClassifier STRING(MAX),
  EventDateTime TIMESTAMP,
  LocationId STRING(36),
  CONSTRAINT FK_ShipmentEvent_Location FOREIGN KEY (LocationId) REFERENCES Locations (LocationId)
) PRIMARY KEY (ShipmentEventId);

-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH SCHEMA
-- =============================================================================

CREATE PROPERTY GRAPH DcsaGraph
  NODE TABLES (
    BillsOfLading
      LABEL BillOfLading PROPERTIES (BillOfLadingId, BolNumber),

    Containers
      LABEL Container PROPERTIES (ContainerId, ContainerNumber),

    Vessels
      LABEL Vessel PROPERTIES (VesselId, VesselImo, VesselName),

    Bookings
      LABEL Booking PROPERTIES (BookingId, BookingReference),

    Locations
      LABEL Location PROPERTIES (LocationId, UnLocode),

    Facilities
      LABEL Facility PROPERTIES (FacilityId, UnLocode)
      LABEL Location PROPERTIES (FacilityId AS LocationId, UnLocode),

    TransportCalls
      LABEL TransportCall PROPERTIES (TransportCallId),

    EquipmentEvents
      LABEL EquipmentEvent PROPERTIES (EquipmentEventId, EventClassifier, EventDateTime, IsActiveContainerEvent)
      LABEL Event PROPERTIES (EquipmentEventId AS EventId, EventClassifier, EventDateTime),

    TransportEvents
      LABEL TransportEvent PROPERTIES (TransportEventId, EventClassifier, EventDateTime)
      LABEL Event PROPERTIES (TransportEventId AS EventId, EventClassifier, EventDateTime),

    ShipmentEvents
      LABEL ShipmentEvent PROPERTIES (ShipmentEventId, EventClassifier, EventDateTime)
      LABEL Event PROPERTIES (ShipmentEventId AS EventId, EventClassifier, EventDateTime)
  )
  EDGE TABLES (
    -- Booking -> BillOfLading
    Bookings AS BookingAssociatedBL
      SOURCE KEY (BookingId) REFERENCES Bookings (BookingId)
      DESTINATION KEY (BillOfLadingId) REFERENCES BillsOfLading (BillOfLadingId)
      LABEL ASSOCIATED_WITH_BL NO PROPERTIES,

    -- Booking -> Container (bookingHasContainer)
    Bookings AS BookingContainers
      SOURCE KEY (BookingId) REFERENCES Bookings (BookingId)
      DESTINATION KEY (ContainerId) REFERENCES Containers (ContainerId)
      LABEL BOOKING_HAS_CONTAINER NO PROPERTIES,

    -- Container -> Booking (containerLinkedToBooking: owl:inverseOf bookingHasContainer)
    Bookings AS ContainerBookings
      SOURCE KEY (ContainerId) REFERENCES Containers (ContainerId)
      DESTINATION KEY (BookingId) REFERENCES Bookings (BookingId)
      LABEL CONTAINER_LINKED_TO_BOOKING NO PROPERTIES,

    -- EquipmentEvent -> Container
    EquipmentEvents AS EquipmentEventContainers
      SOURCE KEY (EquipmentEventId) REFERENCES EquipmentEvents (EquipmentEventId)
      DESTINATION KEY (ContainerId) REFERENCES Containers (ContainerId)
      LABEL CONTAINER_IN_EVENT NO PROPERTIES,

    -- Event -> Location edges across concrete event subclasses
    EquipmentEvents AS EquipmentEventLocations
      SOURCE KEY (EquipmentEventId) REFERENCES EquipmentEvents (EquipmentEventId)
      DESTINATION KEY (LocationId) REFERENCES Locations (LocationId)
      LABEL EVENT_AT_LOCATION NO PROPERTIES,

    TransportEvents AS TransportEventLocations
      SOURCE KEY (TransportEventId) REFERENCES TransportEvents (TransportEventId)
      DESTINATION KEY (LocationId) REFERENCES Locations (LocationId)
      LABEL EVENT_AT_LOCATION NO PROPERTIES,

    ShipmentEvents AS ShipmentEventLocations
      SOURCE KEY (ShipmentEventId) REFERENCES ShipmentEvents (ShipmentEventId)
      DESTINATION KEY (LocationId) REFERENCES Locations (LocationId)
      LABEL EVENT_AT_LOCATION NO PROPERTIES,

    -- TransportCall relationships
    TransportCalls AS TransportCallVessels
      SOURCE KEY (TransportCallId) REFERENCES TransportCalls (TransportCallId)
      DESTINATION KEY (VesselId) REFERENCES Vessels (VesselId)
      LABEL CALL_VESSEL NO PROPERTIES,

    TransportCalls AS TransportCallLocations
      SOURCE KEY (TransportCallId) REFERENCES TransportCalls (TransportCallId)
      DESTINATION KEY (LocationId) REFERENCES Locations (LocationId)
      LABEL CALL_LOCATION NO PROPERTIES,

    -- Transitive Property: followedByLeg (TransportCall -> TransportCall)
    TransportCalls AS TransportCallLegs
      SOURCE KEY (TransportCallId) REFERENCES TransportCalls (TransportCallId)
      DESTINATION KEY (NextTransportCallId) REFERENCES TransportCalls (TransportCallId)
      LABEL FOLLOWED_BY_LEG NO PROPERTIES,

    -- Symmetric Property: sharesAllianceWith (Vessel -> Vessel)
    VesselAlliances
      SOURCE KEY (VesselId) REFERENCES Vessels (VesselId)
      DESTINATION KEY (AllianceVesselId) REFERENCES Vessels (VesselId)
      LABEL SHARES_ALLIANCE_WITH NO PROPERTIES
  );