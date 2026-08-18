-- =============================================================================
-- GOOGLE CLOUD SPANNER PHYSICAL RELATIONAL DDL
-- 3GPP 5G Network Resource Model (NRM) & Network Slicing
-- =============================================================================

-- Administrative SubNetwork Scope
CREATE TABLE SubNetworks (
  SubNetworkId STRING(36) NOT NULL,
  ParentSubNetworkId STRING(36),
  dn STRING(MAX) NOT NULL,
  administrativeState STRING(50) NOT NULL,
  operationalState STRING(50) NOT NULL,
  CONSTRAINT CK_SubNetwork_AdminState CHECK (administrativeState IN ('LOCKED', 'UNLOCKED', 'SHUTTING_DOWN')),
  CONSTRAINT CK_SubNetwork_OperState CHECK (operationalState IN ('ENABLED', 'DISABLED')),
  CONSTRAINT FK_SubNetwork_Parent FOREIGN KEY (ParentSubNetworkId) REFERENCES SubNetworks (SubNetworkId)
) PRIMARY KEY (SubNetworkId);

-- Managed Element Host Chassis
CREATE TABLE ManagedElements (
  ManagedElementId STRING(36) NOT NULL,
  SubNetworkId STRING(36) NOT NULL,
  elementName STRING(MAX),
  dn STRING(MAX) NOT NULL,
  administrativeState STRING(50) NOT NULL,
  operationalState STRING(50) NOT NULL,
  CONSTRAINT CK_ME_AdminState CHECK (administrativeState IN ('LOCKED', 'UNLOCKED', 'SHUTTING_DOWN')),
  CONSTRAINT CK_ME_OperState CHECK (operationalState IN ('ENABLED', 'DISABLED')),
  CONSTRAINT FK_ME_SubNetwork FOREIGN KEY (SubNetworkId) REFERENCES SubNetworks (SubNetworkId)
) PRIMARY KEY (ManagedElementId);

-- 5G RAN: gNodeB Central Unit - Control Plane (gNB-CU-CP)
CREATE TABLE GNBCUCPFunctions (
  FunctionId STRING(36) NOT NULL,
  ManagedElementId STRING(36) NOT NULL,
  gNBId INT64 NOT NULL,
  mcc STRING(MAX) NOT NULL,
  mnc STRING(MAX) NOT NULL,
  dn STRING(MAX) NOT NULL,
  administrativeState STRING(50) NOT NULL,
  operationalState STRING(50) NOT NULL,
  CONSTRAINT CK_CUCP_AdminState CHECK (administrativeState IN ('LOCKED', 'UNLOCKED', 'SHUTTING_DOWN')),
  CONSTRAINT CK_CUCP_OperState CHECK (operationalState IN ('ENABLED', 'DISABLED')),
  CONSTRAINT FK_CUCP_ME FOREIGN KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
) PRIMARY KEY (FunctionId);

-- 5G RAN: gNodeB Central Unit - User Plane (gNB-CU-UP)
CREATE TABLE GNBCUUPFunctions (
  FunctionId STRING(36) NOT NULL,
  ManagedElementId STRING(36) NOT NULL,
  maxThroughputGbps FLOAT64,
  dn STRING(MAX) NOT NULL,
  administrativeState STRING(50) NOT NULL,
  operationalState STRING(50) NOT NULL,
  CONSTRAINT CK_CUUP_AdminState CHECK (administrativeState IN ('LOCKED', 'UNLOCKED', 'SHUTTING_DOWN')),
  CONSTRAINT CK_CUUP_OperState CHECK (operationalState IN ('ENABLED', 'DISABLED')),
  CONSTRAINT FK_CUUP_ME FOREIGN KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
) PRIMARY KEY (FunctionId);

-- 5G RAN: gNodeB Distributed Unit (gNB-DU)
CREATE TABLE GNBDUFunctions (
  FunctionId STRING(36) NOT NULL,
  ManagedElementId STRING(36) NOT NULL,
  cellCount INT64,
  dn STRING(MAX) NOT NULL,
  administrativeState STRING(50) NOT NULL,
  operationalState STRING(50) NOT NULL,
  CONSTRAINT CK_DU_AdminState CHECK (administrativeState IN ('LOCKED', 'UNLOCKED', 'SHUTTING_DOWN')),
  CONSTRAINT CK_DU_OperState CHECK (operationalState IN ('ENABLED', 'DISABLED')),
  CONSTRAINT FK_DU_ME FOREIGN KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
) PRIMARY KEY (FunctionId);

-- 5GC: Access and Mobility Management Function (AMF)
CREATE TABLE AMFFunctions (
  FunctionId STRING(36) NOT NULL,
  ManagedElementId STRING(36) NOT NULL,
  dn STRING(MAX) NOT NULL,
  administrativeState STRING(50) NOT NULL,
  operationalState STRING(50) NOT NULL,
  CONSTRAINT CK_AMF_AdminState CHECK (administrativeState IN ('LOCKED', 'UNLOCKED', 'SHUTTING_DOWN')),
  CONSTRAINT CK_AMF_OperState CHECK (operationalState IN ('ENABLED', 'DISABLED')),
  CONSTRAINT FK_AMF_ME FOREIGN KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
) PRIMARY KEY (FunctionId);

-- 5GC: Session Management Function (SMF)
CREATE TABLE SMFFunctions (
  FunctionId STRING(36) NOT NULL,
  ManagedElementId STRING(36) NOT NULL,
  dn STRING(MAX) NOT NULL,
  administrativeState STRING(50) NOT NULL,
  operationalState STRING(50) NOT NULL,
  CONSTRAINT CK_SMF_AdminState CHECK (administrativeState IN ('LOCKED', 'UNLOCKED', 'SHUTTING_DOWN')),
  CONSTRAINT CK_SMF_OperState CHECK (operationalState IN ('ENABLED', 'DISABLED')),
  CONSTRAINT FK_SMF_ME FOREIGN KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
) PRIMARY KEY (FunctionId);

-- 5GC: User Plane Function (UPF)
CREATE TABLE UPFFunctions (
  FunctionId STRING(36) NOT NULL,
  ManagedElementId STRING(36) NOT NULL,
  dn STRING(MAX) NOT NULL,
  administrativeState STRING(50) NOT NULL,
  operationalState STRING(50) NOT NULL,
  CONSTRAINT CK_UPF_AdminState CHECK (administrativeState IN ('LOCKED', 'UNLOCKED', 'SHUTTING_DOWN')),
  CONSTRAINT CK_UPF_OperState CHECK (operationalState IN ('ENABLED', 'DISABLED')),
  CONSTRAINT FK_UPF_ME FOREIGN KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
) PRIMARY KEY (FunctionId);

-- End-to-End 5G Network Slice
CREATE TABLE NetworkSlices (
  SliceId STRING(36) NOT NULL,
  sst INT64 NOT NULL,
  sd STRING(MAX),
  guaranteedLatencyMs FLOAT64 NOT NULL
) PRIMARY KEY (SliceId);

-- Network Slice Subnet Instance (NSSI)
CREATE TABLE NetworkSliceSubnets (
  SliceSubnetId STRING(36) NOT NULL
) PRIMARY KEY (SliceSubnetId);

-- Relational Edge: F1-C Control Interface (CU-CP -> DU)
CREATE TABLE CUCPControlsDU (
  CuCpFunctionId STRING(36) NOT NULL,
  DuFunctionId STRING(36) NOT NULL,
  CONSTRAINT FK_F1C_CUCP FOREIGN KEY (CuCpFunctionId) REFERENCES GNBCUCPFunctions (FunctionId),
  CONSTRAINT FK_F1C_DU FOREIGN KEY (DuFunctionId) REFERENCES GNBDUFunctions (FunctionId)
) PRIMARY KEY (CuCpFunctionId, DuFunctionId);

-- Relational Edge: E1 Interface (CU-CP -> CU-UP)
CREATE TABLE CUCPControlsCUUP (
  CuCpFunctionId STRING(36) NOT NULL,
  CuUpFunctionId STRING(36) NOT NULL,
  CONSTRAINT FK_E1_CUCP FOREIGN KEY (CuCpFunctionId) REFERENCES GNBCUCPFunctions (FunctionId),
  CONSTRAINT FK_E1_CUUP FOREIGN KEY (CuUpFunctionId) REFERENCES GNBCUUPFunctions (FunctionId)
) PRIMARY KEY (CuCpFunctionId, CuUpFunctionId);

-- Relational Edge: Xn Interface Handover (CU-CP <-> CU-CP)
CREATE TABLE XnNeighbors (
  SourceCuCpId STRING(36) NOT NULL,
  TargetCuCpId STRING(36) NOT NULL,
  CONSTRAINT FK_Xn_Src FOREIGN KEY (SourceCuCpId) REFERENCES GNBCUCPFunctions (FunctionId),
  CONSTRAINT FK_Xn_Tgt FOREIGN KEY (TargetCuCpId) REFERENCES GNBCUCPFunctions (FunctionId)
) PRIMARY KEY (SourceCuCpId, TargetCuCpId);

-- Relational Edge: N2 Interface (CU-CP -> AMF)
CREATE TABLE CUCPConnectsToAMF (
  CuCpFunctionId STRING(36) NOT NULL,
  AmfFunctionId STRING(36) NOT NULL,
  CONSTRAINT FK_N2_CUCP FOREIGN KEY (CuCpFunctionId) REFERENCES GNBCUCPFunctions (FunctionId),
  CONSTRAINT FK_N2_AMF FOREIGN KEY (AmfFunctionId) REFERENCES AMFFunctions (FunctionId)
) PRIMARY KEY (CuCpFunctionId, AmfFunctionId);

-- Relational Edge: N3 Interface (CU-UP -> UPF)
CREATE TABLE CUUPConnectsToUPF (
  CuUpFunctionId STRING(36) NOT NULL,
  UpfFunctionId STRING(36) NOT NULL,
  CONSTRAINT FK_N3_CUUP FOREIGN KEY (CuUpFunctionId) REFERENCES GNBCUUPFunctions (FunctionId),
  CONSTRAINT FK_N3_UPF FOREIGN KEY (UpfFunctionId) REFERENCES UPFFunctions (FunctionId)
) PRIMARY KEY (CuUpFunctionId, UpfFunctionId);

-- Relational Edge: Slice -> Subnet Allocation
CREATE TABLE SliceAllocatesSubnet (
  SliceId STRING(36) NOT NULL,
  SliceSubnetId STRING(36) NOT NULL,
  CONSTRAINT FK_Alloc_Slice FOREIGN KEY (SliceId) REFERENCES NetworkSlices (SliceId),
  CONSTRAINT FK_Alloc_Subnet FOREIGN KEY (SliceSubnetId) REFERENCES NetworkSliceSubnets (SliceSubnetId)
) PRIMARY KEY (SliceId, SliceSubnetId);

-- Relational Edge: Function Serves Slice (Polymorphic per concrete NF)
CREATE TABLE CUCPFunctionServesSlice (
  FunctionId STRING(36) NOT NULL,
  SliceId STRING(36) NOT NULL,
  CONSTRAINT FK_CUCPServe_Func FOREIGN KEY (FunctionId) REFERENCES GNBCUCPFunctions (FunctionId),
  CONSTRAINT FK_CUCPServe_Slice FOREIGN KEY (SliceId) REFERENCES NetworkSlices (SliceId)
) PRIMARY KEY (FunctionId, SliceId);

CREATE TABLE CUUPFunctionServesSlice (
  FunctionId STRING(36) NOT NULL,
  SliceId STRING(36) NOT NULL,
  CONSTRAINT FK_CUUPServe_Func FOREIGN KEY (FunctionId) REFERENCES GNBCUUPFunctions (FunctionId),
  CONSTRAINT FK_CUUPServe_Slice FOREIGN KEY (SliceId) REFERENCES NetworkSlices (SliceId)
) PRIMARY KEY (FunctionId, SliceId);

CREATE TABLE DUServesSlice (
  FunctionId STRING(36) NOT NULL,
  SliceId STRING(36) NOT NULL,
  CONSTRAINT FK_DUServe_Func FOREIGN KEY (FunctionId) REFERENCES GNBDUFunctions (FunctionId),
  CONSTRAINT FK_DUServe_Slice FOREIGN KEY (SliceId) REFERENCES NetworkSlices (SliceId)
) PRIMARY KEY (FunctionId, SliceId);

CREATE TABLE UPFServesSlice (
  FunctionId STRING(36) NOT NULL,
  SliceId STRING(36) NOT NULL,
  CONSTRAINT FK_UPFServe_Func FOREIGN KEY (FunctionId) REFERENCES UPFFunctions (FunctionId),
  CONSTRAINT FK_UPFServe_Slice FOREIGN KEY (SliceId) REFERENCES NetworkSlices (SliceId)
) PRIMARY KEY (FunctionId, SliceId);


-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH DDL
-- =============================================================================

CREATE PROPERTY GRAPH NetworkResourceModelGraph
  NODE TABLES (
    SubNetworks
      LABEL SubNetwork PROPERTIES (SubNetworkId)
      LABEL ManagedEntity PROPERTIES (dn, administrativeState, operationalState),
    ManagedElements
      LABEL ManagedElement PROPERTIES (ManagedElementId, elementName)
      LABEL ManagedEntity PROPERTIES (dn, administrativeState, operationalState),
    GNBCUCPFunctions
      LABEL GNBCUCPFunction PROPERTIES (FunctionId, gNBId, mcc, mnc)
      LABEL ManagedFunction NO PROPERTIES
      LABEL ManagedEntity PROPERTIES (dn, administrativeState, operationalState),
    GNBCUUPFunctions
      LABEL GNBCUUPFunction PROPERTIES (FunctionId, maxThroughputGbps)
      LABEL ManagedFunction NO PROPERTIES
      LABEL ManagedEntity PROPERTIES (dn, administrativeState, operationalState),
    GNBDUFunctions
      LABEL GNBDUFunction PROPERTIES (FunctionId, cellCount)
      LABEL ManagedFunction NO PROPERTIES
      LABEL ManagedEntity PROPERTIES (dn, administrativeState, operationalState),
    AMFFunctions
      LABEL AMFFunction PROPERTIES (FunctionId)
      LABEL ManagedFunction NO PROPERTIES
      LABEL ManagedEntity PROPERTIES (dn, administrativeState, operationalState),
    SMFFunctions
      LABEL SMFFunction PROPERTIES (FunctionId)
      LABEL ManagedFunction NO PROPERTIES
      LABEL ManagedEntity PROPERTIES (dn, administrativeState, operationalState),
    UPFFunctions
      LABEL UPFFunction PROPERTIES (FunctionId)
      LABEL ManagedFunction NO PROPERTIES
      LABEL ManagedEntity PROPERTIES (dn, administrativeState, operationalState),
    NetworkSlices
      LABEL NetworkSlice PROPERTIES (SliceId, sst, sd, guaranteedLatencyMs),
    NetworkSliceSubnets
      LABEL NetworkSliceSubnet PROPERTIES (SliceSubnetId)
  )
  EDGE TABLES (
    -- SubNetwork Transitive Parent Hierarchy
    SubNetworks AS SubNetworkHierarchy
      SOURCE KEY (SubNetworkId) REFERENCES SubNetworks (SubNetworkId)
      DESTINATION KEY (ParentSubNetworkId) REFERENCES SubNetworks (SubNetworkId)
      LABEL PARENT_SUBNETWORK NO PROPERTIES,

    -- SubNetwork Containment of Chassis
    ManagedElements AS SubNetworkContainsElement
      SOURCE KEY (SubNetworkId) REFERENCES SubNetworks (SubNetworkId)
      DESTINATION KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
      LABEL CONTAINS_MANAGED_ELEMENT NO PROPERTIES,

    -- ManagedElement Containment of NFs
    GNBCUCPFunctions AS ElementContainsCUCP
      SOURCE KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
      DESTINATION KEY (FunctionId) REFERENCES GNBCUCPFunctions (FunctionId)
      LABEL CONTAINS_MANAGED_FUNCTION NO PROPERTIES,
    GNBCUUPFunctions AS ElementContainsCUUP
      SOURCE KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
      DESTINATION KEY (FunctionId) REFERENCES GNBCUUPFunctions (FunctionId)
      LABEL CONTAINS_MANAGED_FUNCTION NO PROPERTIES,
    GNBDUFunctions AS ElementContainsDU
      SOURCE KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
      DESTINATION KEY (FunctionId) REFERENCES GNBDUFunctions (FunctionId)
      LABEL CONTAINS_MANAGED_FUNCTION NO PROPERTIES,
    AMFFunctions AS ElementContainsAMF
      SOURCE KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
      DESTINATION KEY (FunctionId) REFERENCES AMFFunctions (FunctionId)
      LABEL CONTAINS_MANAGED_FUNCTION NO PROPERTIES,
    SMFFunctions AS ElementContainsSMF
      SOURCE KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
      DESTINATION KEY (FunctionId) REFERENCES SMFFunctions (FunctionId)
      LABEL CONTAINS_MANAGED_FUNCTION NO PROPERTIES,
    UPFFunctions AS ElementContainsUPF
      SOURCE KEY (ManagedElementId) REFERENCES ManagedElements (ManagedElementId)
      DESTINATION KEY (FunctionId) REFERENCES UPFFunctions (FunctionId)
      LABEL CONTAINS_MANAGED_FUNCTION NO PROPERTIES,

    -- F1-C & E1 Interfaces
    CUCPControlsDU
      SOURCE KEY (CuCpFunctionId) REFERENCES GNBCUCPFunctions (FunctionId)
      DESTINATION KEY (DuFunctionId) REFERENCES GNBDUFunctions (FunctionId)
      LABEL CONTROLS_DU NO PROPERTIES,
    CUCPControlsCUUP
      SOURCE KEY (CuCpFunctionId) REFERENCES GNBCUCPFunctions (FunctionId)
      DESTINATION KEY (CuUpFunctionId) REFERENCES GNBCUUPFunctions (FunctionId)
      LABEL CONTROLS_CUUP NO PROPERTIES,

    -- Xn Interface (Symmetric neighbor relationship traversed in both directions)
    XnNeighbors
      SOURCE KEY (SourceCuCpId) REFERENCES GNBCUCPFunctions (FunctionId)
      DESTINATION KEY (TargetCuCpId) REFERENCES GNBCUCPFunctions (FunctionId)
      LABEL XN_INTERFACE_WITH NO PROPERTIES,
    XnNeighbors AS XnNeighborsInverse
      SOURCE KEY (TargetCuCpId) REFERENCES GNBCUCPFunctions (FunctionId)
      DESTINATION KEY (SourceCuCpId) REFERENCES GNBCUCPFunctions (FunctionId)
      LABEL XN_INTERFACE_WITH NO PROPERTIES,

    -- 5GC Service Interfaces (N2 & N3)
    CUCPConnectsToAMF
      SOURCE KEY (CuCpFunctionId) REFERENCES GNBCUCPFunctions (FunctionId)
      DESTINATION KEY (AmfFunctionId) REFERENCES AMFFunctions (FunctionId)
      LABEL CONNECTS_TO_AMF NO PROPERTIES,
    CUUPConnectsToUPF
      SOURCE KEY (CuUpFunctionId) REFERENCES GNBCUUPFunctions (FunctionId)
      DESTINATION KEY (UpfFunctionId) REFERENCES UPFFunctions (FunctionId)
      LABEL CONNECTS_TO_UPF NO PROPERTIES,

    -- Slice Allocation and Serving Relationships
    SliceAllocatesSubnet
      SOURCE KEY (SliceId) REFERENCES NetworkSlices (SliceId)
      DESTINATION KEY (SliceSubnetId) REFERENCES NetworkSliceSubnets (SliceSubnetId)
      LABEL ALLOCATES_SLICE_SUBNET NO PROPERTIES,
    CUCPFunctionServesSlice
      SOURCE KEY (FunctionId) REFERENCES GNBCUCPFunctions (FunctionId)
      DESTINATION KEY (SliceId) REFERENCES NetworkSlices (SliceId)
      LABEL SERVES_SLICE NO PROPERTIES,
    CUUPFunctionServesSlice
      SOURCE KEY (FunctionId) REFERENCES GNBCUUPFunctions (FunctionId)
      DESTINATION KEY (SliceId) REFERENCES NetworkSlices (SliceId)
      LABEL SERVES_SLICE NO PROPERTIES,
    DUServesSlice
      SOURCE KEY (FunctionId) REFERENCES GNBDUFunctions (FunctionId)
      DESTINATION KEY (SliceId) REFERENCES NetworkSlices (SliceId)
      LABEL SERVES_SLICE NO PROPERTIES,
    UPFServesSlice
      SOURCE KEY (FunctionId) REFERENCES UPFFunctions (FunctionId)
      DESTINATION KEY (SliceId) REFERENCES NetworkSlices (SliceId)
      LABEL SERVES_SLICE NO PROPERTIES
  );