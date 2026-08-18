-- =============================================================================
-- PHYSICAL RELATIONAL SCHEMA
-- =============================================================================

-- Concrete Table: Devices
CREATE TABLE Devices (
  DeviceId STRING(MAX) NOT NULL,
  DeviceType STRING(MAX)
) PRIMARY KEY (DeviceId);

-- Concrete Table: IPAddresses
CREATE TABLE IPAddresses (
  IPAddressId STRING(MAX) NOT NULL,
  IPValue STRING(MAX)
) PRIMARY KEY (IPAddressId);

-- Concrete Table: PhoneNumbers
CREATE TABLE PhoneNumbers (
  PhoneNumberId STRING(MAX) NOT NULL,
  PhoneValue STRING(MAX)
) PRIMARY KEY (PhoneNumberId);

-- Concrete Table: Accounts
-- Flattened superclass attributes, foreign keys, and edge interaction properties
CREATE TABLE Accounts (
  AccountId STRING(MAX) NOT NULL,
  AccountStatus STRING(MAX),
  DeviceId STRING(MAX) NOT NULL,
  DeviceFirstUsed TIMESTAMP,
  DeviceLastUsed TIMESTAMP,
  IPAddressId STRING(MAX) NOT NULL,
  PhoneNumberId STRING(MAX) NOT NULL,
  CONSTRAINT FK_Accounts_Device FOREIGN KEY (DeviceId) REFERENCES Devices (DeviceId),
  CONSTRAINT FK_Accounts_IPAddress FOREIGN KEY (IPAddressId) REFERENCES IPAddresses (IPAddressId),
  CONSTRAINT FK_Accounts_PhoneNumber FOREIGN KEY (PhoneNumberId) REFERENCES PhoneNumbers (PhoneNumberId)
) PRIMARY KEY (AccountId);

-- Physical Relationship Table: AccountTransfers (ex:transferredTo)
CREATE TABLE AccountTransfers (
  TransferId STRING(36) NOT NULL,
  FromAccountId STRING(MAX) NOT NULL,
  ToAccountId STRING(MAX) NOT NULL,
  Amount NUMERIC,
  TransferTimestamp TIMESTAMP,
  CONSTRAINT FK_Transfers_FromAccount FOREIGN KEY (FromAccountId) REFERENCES Accounts (AccountId),
  CONSTRAINT FK_Transfers_ToAccount FOREIGN KEY (ToAccountId) REFERENCES Accounts (AccountId)
) PRIMARY KEY (TransferId);

-- Physical Relationship Table: IPAddressLinks (ex:linkedToIP - Symmetric Property)
CREATE TABLE IPAddressLinks (
  IPAddressId STRING(MAX) NOT NULL,
  LinkedIPAddressId STRING(MAX) NOT NULL,
  CONSTRAINT FK_IPLinks_Src FOREIGN KEY (IPAddressId) REFERENCES IPAddresses (IPAddressId),
  CONSTRAINT FK_IPLinks_Dst FOREIGN KEY (LinkedIPAddressId) REFERENCES IPAddresses (IPAddressId)
) PRIMARY KEY (IPAddressId, LinkedIPAddressId);

-- =============================================================================
-- PROPERTY GRAPH SCHEMA
-- =============================================================================

CREATE PROPERTY GRAPH SocialFraudGraph
  NODE TABLES (
    Accounts
      LABEL Account PROPERTIES (AccountId, AccountStatus)
      LABEL Entity NO PROPERTIES,
    Devices
      LABEL Device PROPERTIES (DeviceId, DeviceType)
      LABEL Entity NO PROPERTIES,
    IPAddresses
      LABEL IPAddress PROPERTIES (IPAddressId, IPValue)
      LABEL Entity NO PROPERTIES,
    PhoneNumbers
      LABEL PhoneNumber PROPERTIES (PhoneNumberId, PhoneValue)
      LABEL Entity NO PROPERTIES
  )
  EDGE TABLES (
    -- Transaction Edge between Accounts
    AccountTransfers
      SOURCE KEY (FromAccountId) REFERENCES Accounts (AccountId)
      DESTINATION KEY (ToAccountId) REFERENCES Accounts (AccountId)
      LABEL TRANSFERRED_TO PROPERTIES (Amount, TransferTimestamp),
      
    -- N:1 Edge: Account -> Device (Aliased as AccountDevices to prevent collision with Accounts Node Table)
    Accounts AS AccountDevices
      SOURCE KEY (AccountId) REFERENCES Accounts (AccountId)
      DESTINATION KEY (DeviceId) REFERENCES Devices (DeviceId)
      LABEL USED_DEVICE PROPERTIES (DeviceFirstUsed AS FirstUsed, DeviceLastUsed AS LastUsed),
      
    -- N:1 Edge: Account -> IPAddress
    Accounts AS AccountIPs
      SOURCE KEY (AccountId) REFERENCES Accounts (AccountId)
      DESTINATION KEY (IPAddressId) REFERENCES IPAddresses (IPAddressId)
      LABEL USED_IP NO PROPERTIES,
      
    -- N:1 Edge: Account -> PhoneNumber
    Accounts AS AccountPhones
      SOURCE KEY (AccountId) REFERENCES Accounts (AccountId)
      DESTINATION KEY (PhoneNumberId) REFERENCES PhoneNumbers (PhoneNumberId)
      LABEL USED_PHONE NO PROPERTIES,
      
    -- Symmetric Edge: IPAddress -> IPAddress
    IPAddressLinks
      SOURCE KEY (IPAddressId) REFERENCES IPAddresses (IPAddressId)
      DESTINATION KEY (LinkedIPAddressId) REFERENCES IPAddresses (IPAddressId)
      LABEL LINKED_TO_IP NO PROPERTIES
  );