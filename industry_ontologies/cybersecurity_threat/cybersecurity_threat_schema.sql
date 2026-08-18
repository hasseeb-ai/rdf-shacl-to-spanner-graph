-- =============================================================================
-- Google Cloud Spanner Physical Relational Schema & Property Graph DDL
-- Ontology: Cybersecurity Network Threat Intelligence and Vulnerability Ontology
-- Pattern: Table-Per-Concrete-Class with Flattened Superclass Hierarchies
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. PHYSICAL RELATIONAL TABLES
-- -----------------------------------------------------------------------------

-- Concrete Class: IPAddress
CREATE TABLE IPAddresses (
  IPAddressId STRING(36) NOT NULL,
  IpString STRING(MAX)
) PRIMARY KEY (IPAddressId);

-- Concrete Class: Vulnerability
CREATE TABLE Vulnerabilities (
  VulnerabilityId STRING(36) NOT NULL,
  CveId STRING(MAX),
  CvssScore NUMERIC
) PRIMARY KEY (VulnerabilityId);

-- Concrete Class: ThreatActor
CREATE TABLE ThreatActors (
  ThreatActorId STRING(36) NOT NULL,
  ActorName STRING(MAX),
  ExploitedVulnerabilityId STRING(36),
  CONSTRAINT FK_ThreatActors_Vulnerabilities FOREIGN KEY (ExploitedVulnerabilityId) 
    REFERENCES Vulnerabilities (VulnerabilityId)
) PRIMARY KEY (ThreatActorId);

-- Concrete Class: SecurityAlert (includes Equivalent Class: CriticalSeverityAlert via Generated Column)
CREATE TABLE SecurityAlerts (
  SecurityAlertId STRING(36) NOT NULL,
  SeverityScore INT64,
  IsCriticalSeverityAlert BOOL AS (SeverityScore >= 9) STORED
) PRIMARY KEY (SecurityAlertId);

-- Concrete Class: Gateway (subClassOf NetworkNode)
CREATE TABLE Gateways (
  GatewayId STRING(36) NOT NULL
) PRIMARY KEY (GatewayId);

-- Concrete Class: Server (subClassOf Endpoint -> NetworkNode)
CREATE TABLE Servers (
  ServerId STRING(36) NOT NULL,
  MacAddress STRING(MAX) NOT NULL,
  IPAddressId STRING(36) NOT NULL,
  VulnerabilityId STRING(36),
  CompromisedByThreatActorId STRING(36),
  TriggeredSecurityAlertId STRING(36),
  CONSTRAINT FK_Servers_IPAddresses FOREIGN KEY (IPAddressId) 
    REFERENCES IPAddresses (IPAddressId),
  CONSTRAINT FK_Servers_Vulnerabilities FOREIGN KEY (VulnerabilityId) 
    REFERENCES Vulnerabilities (VulnerabilityId),
  CONSTRAINT FK_Servers_ThreatActors FOREIGN KEY (CompromisedByThreatActorId) 
    REFERENCES ThreatActors (ThreatActorId),
  CONSTRAINT FK_Servers_SecurityAlerts FOREIGN KEY (TriggeredSecurityAlertId) 
    REFERENCES SecurityAlerts (SecurityAlertId)
) PRIMARY KEY (ServerId);

-- Concrete Class: Workstation (subClassOf Endpoint -> NetworkNode)
CREATE TABLE Workstations (
  WorkstationId STRING(36) NOT NULL,
  MacAddress STRING(MAX) NOT NULL,
  IPAddressId STRING(36),
  VulnerabilityId STRING(36),
  CompromisedByThreatActorId STRING(36),
  TriggeredSecurityAlertId STRING(36),
  CONSTRAINT FK_Workstations_IPAddresses FOREIGN KEY (IPAddressId) 
    REFERENCES IPAddresses (IPAddressId),
  CONSTRAINT FK_Workstations_Vulnerabilities FOREIGN KEY (VulnerabilityId) 
    REFERENCES Vulnerabilities (VulnerabilityId),
  CONSTRAINT FK_Workstations_ThreatActors FOREIGN KEY (CompromisedByThreatActorId) 
    REFERENCES ThreatActors (ThreatActorId),
  CONSTRAINT FK_Workstations_SecurityAlerts FOREIGN KEY (TriggeredSecurityAlertId) 
    REFERENCES SecurityAlerts (SecurityAlertId)
) PRIMARY KEY (WorkstationId);

-- Concrete Class: SystemProcess (with Transitive Self-Referential Parent-Child Hierarchy)
CREATE TABLE SystemProcesses (
  SystemProcessId STRING(36) NOT NULL,
  ProcessId INT64,
  ParentProcessNodeId STRING(36),
  CONSTRAINT FK_SystemProcesses_Parent FOREIGN KEY (ParentProcessNodeId) 
    REFERENCES SystemProcesses (SystemProcessId)
) PRIMARY KEY (SystemProcessId);

-- Concrete Class: UserAccount
CREATE TABLE UserAccounts (
  UserAccountId STRING(36) NOT NULL,
  Username STRING(MAX)
) PRIMARY KEY (UserAccountId);

-- Relational Edge Table: UserLogins (UserAccount -> Server / Workstation)
CREATE TABLE UserServerLogins (
  UserAccountId STRING(36) NOT NULL,
  ServerId STRING(36) NOT NULL,
  CONSTRAINT FK_UserServerLogins_User FOREIGN KEY (UserAccountId) 
    REFERENCES UserAccounts (UserAccountId),
  CONSTRAINT FK_UserServerLogins_Server FOREIGN KEY (ServerId) 
    REFERENCES Servers (ServerId)
) PRIMARY KEY (UserAccountId, ServerId);

CREATE TABLE UserWorkstationLogins (
  UserAccountId STRING(36) NOT NULL,
  WorkstationId STRING(36) NOT NULL,
  CONSTRAINT FK_UserWorkstationLogins_User FOREIGN KEY (UserAccountId) 
    REFERENCES UserAccounts (UserAccountId),
  CONSTRAINT FK_UserWorkstationLogins_Workstation FOREIGN KEY (WorkstationId) 
    REFERENCES Workstations (WorkstationId)
) PRIMARY KEY (UserAccountId, WorkstationId);

-- Relational Edge Table: EndpointCommunications (Symmetric Network Connections)
CREATE TABLE ServerServerCommunications (
  SourceServerId STRING(36) NOT NULL,
  TargetServerId STRING(36) NOT NULL,
  CONSTRAINT FK_SS_Source FOREIGN KEY (SourceServerId) REFERENCES Servers (ServerId),
  CONSTRAINT FK_SS_Target FOREIGN KEY (TargetServerId) REFERENCES Servers (ServerId)
) PRIMARY KEY (SourceServerId, TargetServerId);

CREATE TABLE ServerWorkstationCommunications (
  ServerId STRING(36) NOT NULL,
  WorkstationId STRING(36) NOT NULL,
  CONSTRAINT FK_SW_Server FOREIGN KEY (ServerId) REFERENCES Servers (ServerId),
  CONSTRAINT FK_SW_Workstation FOREIGN KEY (WorkstationId) REFERENCES Workstations (WorkstationId)
) PRIMARY KEY (ServerId, WorkstationId);

CREATE TABLE WorkstationWorkstationCommunications (
  SourceWorkstationId STRING(36) NOT NULL,
  TargetWorkstationId STRING(36) NOT NULL,
  CONSTRAINT FK_WW_Source FOREIGN KEY (SourceWorkstationId) REFERENCES Workstations (WorkstationId),
  CONSTRAINT FK_WW_Target FOREIGN KEY (TargetWorkstationId) REFERENCES Workstations (WorkstationId)
) PRIMARY KEY (SourceWorkstationId, TargetWorkstationId);

-- -----------------------------------------------------------------------------
-- 2. SQL SECURITY INVOKER VIEWS
-- -----------------------------------------------------------------------------

-- View: CriticalSeverityAlerts representing equivalent class
CREATE VIEW CriticalSeverityAlerts SQL SECURITY INVOKER AS
SELECT
  sa.SecurityAlertId,
  sa.SeverityScore,
  sa.IsCriticalSeverityAlert
FROM SecurityAlerts sa
WHERE sa.SeverityScore >= 9;

-- -----------------------------------------------------------------------------
-- 3. PROPERTY GRAPH SCHEMA
-- -----------------------------------------------------------------------------

CREATE PROPERTY GRAPH CybersecurityGraph
  NODE TABLES (
    Gateways
      LABEL Gateway PROPERTIES (GatewayId)
      LABEL NetworkNode NO PROPERTIES,

    Servers
      LABEL Server PROPERTIES (ServerId, MacAddress)
      LABEL Endpoint PROPERTIES (MacAddress)
      LABEL NetworkNode NO PROPERTIES,

    Workstations
      LABEL Workstation PROPERTIES (WorkstationId, MacAddress)
      LABEL Endpoint PROPERTIES (MacAddress)
      LABEL NetworkNode NO PROPERTIES,

    IPAddresses
      LABEL IPAddress PROPERTIES (IPAddressId, IpString),

    Vulnerabilities
      LABEL Vulnerability PROPERTIES (VulnerabilityId, CveId, CvssScore),

    ThreatActors
      LABEL ThreatActor PROPERTIES (ThreatActorId, ActorName),

    SecurityAlerts
      LABEL SecurityAlert PROPERTIES (SecurityAlertId, SeverityScore, IsCriticalSeverityAlert),

    CriticalSeverityAlerts KEY (SecurityAlertId)
      LABEL CriticalSeverityAlert PROPERTIES (SecurityAlertId, SeverityScore),

    SystemProcesses
      LABEL SystemProcess PROPERTIES (SystemProcessId, ProcessId),

    UserAccounts
      LABEL UserAccount PROPERTIES (UserAccountId, Username)
  )
  EDGE TABLES (
    -- Forward Edge: Server -> hasIPAddress -> IPAddress
    Servers AS ServerHasIPAddresses
      SOURCE KEY (ServerId) REFERENCES Servers (ServerId)
      DESTINATION KEY (IPAddressId) REFERENCES IPAddresses (IPAddressId)
      LABEL HAS_IP_ADDRESS NO PROPERTIES,

    -- Inverse Edge: IPAddress -> ipBelongsTo -> Server
    Servers AS ServerIPBelongsTo
      SOURCE KEY (IPAddressId) REFERENCES IPAddresses (IPAddressId)
      DESTINATION KEY (ServerId) REFERENCES Servers (ServerId)
      LABEL IP_BELONGS_TO NO PROPERTIES,

    -- Forward Edge: Workstation -> hasIPAddress -> IPAddress
    Workstations AS WorkstationHasIPAddresses
      SOURCE KEY (WorkstationId) REFERENCES Workstations (WorkstationId)
      DESTINATION KEY (IPAddressId) REFERENCES IPAddresses (IPAddressId)
      LABEL HAS_IP_ADDRESS NO PROPERTIES,

    -- Inverse Edge: IPAddress -> ipBelongsTo -> Workstation
    Workstations AS WorkstationIPBelongsTo
      SOURCE KEY (IPAddressId) REFERENCES IPAddresses (IPAddressId)
      DESTINATION KEY (WorkstationId) REFERENCES Workstations (WorkstationId)
      LABEL IP_BELONGS_TO NO PROPERTIES,

    -- Server Vulnerability Link
    Servers AS ServerHasVulnerabilities
      SOURCE KEY (ServerId) REFERENCES Servers (ServerId)
      DESTINATION KEY (VulnerabilityId) REFERENCES Vulnerabilities (VulnerabilityId)
      LABEL HAS_VULNERABILITY NO PROPERTIES,

    -- Workstation Vulnerability Link
    Workstations AS WorkstationHasVulnerabilities
      SOURCE KEY (WorkstationId) REFERENCES Workstations (WorkstationId)
      DESTINATION KEY (VulnerabilityId) REFERENCES Vulnerabilities (VulnerabilityId)
      LABEL HAS_VULNERABILITY NO PROPERTIES,

    -- Server Compromised By ThreatActor
    Servers AS ServerCompromisedByActors
      SOURCE KEY (ServerId) REFERENCES Servers (ServerId)
      DESTINATION KEY (CompromisedByThreatActorId) REFERENCES ThreatActors (ThreatActorId)
      LABEL COMPROMISED_BY NO PROPERTIES,

    -- Workstation Compromised By ThreatActor
    Workstations AS WorkstationCompromisedByActors
      SOURCE KEY (WorkstationId) REFERENCES Workstations (WorkstationId)
      DESTINATION KEY (CompromisedByThreatActorId) REFERENCES ThreatActors (ThreatActorId)
      LABEL COMPROMISED_BY NO PROPERTIES,

    -- Server Triggered Alert
    Servers AS ServerTriggeredAlerts
      SOURCE KEY (ServerId) REFERENCES Servers (ServerId)
      DESTINATION KEY (TriggeredSecurityAlertId) REFERENCES SecurityAlerts (SecurityAlertId)
      LABEL TRIGGERED_ALERT NO PROPERTIES,

    -- Workstation Triggered Alert
    Workstations AS WorkstationTriggeredAlerts
      SOURCE KEY (WorkstationId) REFERENCES Workstations (WorkstationId)
      DESTINATION KEY (TriggeredSecurityAlertId) REFERENCES SecurityAlerts (SecurityAlertId)
      LABEL TRIGGERED_ALERT NO PROPERTIES,

    -- ThreatActor exploits Vulnerability
    ThreatActors AS ThreatActorExploits
      SOURCE KEY (ThreatActorId) REFERENCES ThreatActors (ThreatActorId)
      DESTINATION KEY (ExploitedVulnerabilityId) REFERENCES Vulnerabilities (VulnerabilityId)
      LABEL EXPLOITS NO PROPERTIES,

    -- UserAccount LoggedInFrom Server
    UserServerLogins
      SOURCE KEY (UserAccountId) REFERENCES UserAccounts (UserAccountId)
      DESTINATION KEY (ServerId) REFERENCES Servers (ServerId)
      LABEL LOGGED_IN_FROM NO PROPERTIES,

    -- UserAccount LoggedInFrom Workstation
    UserWorkstationLogins
      SOURCE KEY (UserAccountId) REFERENCES UserAccounts (UserAccountId)
      DESTINATION KEY (WorkstationId) REFERENCES Workstations (WorkstationId)
      LABEL LOGGED_IN_FROM NO PROPERTIES,

    -- Symmetric Network Communications: Server -> Server
    ServerServerCommunications
      SOURCE KEY (SourceServerId) REFERENCES Servers (ServerId)
      DESTINATION KEY (TargetServerId) REFERENCES Servers (ServerId)
      LABEL COMMUNICATED_WITH NO PROPERTIES,

    -- Symmetric Network Communications: Server -> Workstation
    ServerWorkstationCommunications
      SOURCE KEY (ServerId) REFERENCES Servers (ServerId)
      DESTINATION KEY (WorkstationId) REFERENCES Workstations (WorkstationId)
      LABEL COMMUNICATED_WITH NO PROPERTIES,

    -- Symmetric Network Communications: Workstation -> Workstation
    WorkstationWorkstationCommunications
      SOURCE KEY (SourceWorkstationId) REFERENCES Workstations (WorkstationId)
      DESTINATION KEY (TargetWorkstationId) REFERENCES Workstations (WorkstationId)
      LABEL COMMUNICATED_WITH NO PROPERTIES,

    -- Transitive Process Tree: Parent Process Of (Forward)
    SystemProcesses AS SystemProcessParentEdges
      SOURCE KEY (ParentProcessNodeId) REFERENCES SystemProcesses (SystemProcessId)
      DESTINATION KEY (SystemProcessId) REFERENCES SystemProcesses (SystemProcessId)
      LABEL PARENT_PROCESS_OF NO PROPERTIES,

    -- Inverse Process Tree: Child Process Of (Inverse)
    SystemProcesses AS SystemProcessChildEdges
      SOURCE KEY (SystemProcessId) REFERENCES SystemProcesses (SystemProcessId)
      DESTINATION KEY (ParentProcessNodeId) REFERENCES SystemProcesses (SystemProcessId)
      LABEL CHILD_PROCESS_OF NO PROPERTIES
  );