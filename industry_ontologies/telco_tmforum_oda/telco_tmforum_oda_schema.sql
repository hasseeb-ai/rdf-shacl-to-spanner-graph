-- =============================================================================
-- GOOGLE CLOUD SPANNER RELATIONAL DDL (Table-Per-Concrete-Class)
-- =============================================================================

-- 1. Party Concrete Hierarchy (Top-Down Inherited Properties Flattened)
CREATE TABLE IndividualParties (
  PartyId STRING(36) NOT NULL,
  PartyName STRING(MAX) NOT NULL,
  NationalId STRING(MAX)
) PRIMARY KEY (PartyId);

CREATE TABLE OrganizationParties (
  PartyId STRING(36) NOT NULL,
  PartyName STRING(MAX) NOT NULL,
  TaxRegistrationNumber STRING(MAX)
) PRIMARY KEY (PartyId);

-- 2. Customer Account Entity
CREATE TABLE CustomerAccounts (
  AccountId STRING(36) NOT NULL,
  AccountStatus STRING(50) NOT NULL,
  CreditLimit NUMERIC NOT NULL,
  CONSTRAINT CK_CustomerAccountStatus CHECK (
    AccountStatus IN ('ACTIVE', 'SUSPENDED', 'CLOSED', 'PENDING')
  )
) PRIMARY KEY (AccountId);

-- 3. Product, Service & Resource Catalog Specifications
CREATE TABLE ProductSpecifications (
  ProductSpecId STRING(36) NOT NULL
) PRIMARY KEY (ProductSpecId);

CREATE TABLE ProductOfferings (
  OfferingId STRING(36) NOT NULL,
  OfferingName STRING(MAX) NOT NULL,
  MonthlyPrice NUMERIC NOT NULL,
  IsBundle BOOL NOT NULL
) PRIMARY KEY (OfferingId);

CREATE TABLE ServiceSpecifications (
  ServiceSpecId STRING(36) NOT NULL,
  TargetSlaAvailability FLOAT64 NOT NULL
) PRIMARY KEY (ServiceSpecId);

CREATE TABLE ResourceSpecifications (
  ResourceSpecId STRING(36) NOT NULL,
  ResourceType STRING(50)
) PRIMARY KEY (ResourceSpecId);

-- 4. Customer Product Orders
CREATE TABLE ProductOrders (
  OrderId STRING(36) NOT NULL,
  OrderDate TIMESTAMP NOT NULL
) PRIMARY KEY (OrderId);

-- =============================================================================
-- RELATIONSHIP & INTERMEDIATE EDGE TABLES
-- =============================================================================

-- Party holds CustomerAccount (Subclass relationships resolved per concrete party)
CREATE TABLE IndividualPartyAccounts (
  PartyId STRING(36) NOT NULL,
  AccountId STRING(36) NOT NULL,
  CONSTRAINT FK_IndPartyAcc_Party FOREIGN KEY (PartyId) REFERENCES IndividualParties (PartyId),
  CONSTRAINT FK_IndPartyAcc_Account FOREIGN KEY (AccountId) REFERENCES CustomerAccounts (AccountId)
) PRIMARY KEY (PartyId, AccountId);

CREATE TABLE OrganizationPartyAccounts (
  PartyId STRING(36) NOT NULL,
  AccountId STRING(36) NOT NULL,
  CONSTRAINT FK_OrgPartyAcc_Party FOREIGN KEY (PartyId) REFERENCES OrganizationParties (PartyId),
  CONSTRAINT FK_OrgPartyAcc_Account FOREIGN KEY (AccountId) REFERENCES CustomerAccounts (AccountId)
) PRIMARY KEY (PartyId, AccountId);

-- Product Specification specifies Commercial Product Offering
CREATE TABLE ProductSpecificationOfferings (
  ProductSpecId STRING(36) NOT NULL,
  OfferingId STRING(36) NOT NULL,
  CONSTRAINT FK_SpecOffering_Spec FOREIGN KEY (ProductSpecId) REFERENCES ProductSpecifications (ProductSpecId),
  CONSTRAINT FK_SpecOffering_Offering FOREIGN KEY (OfferingId) REFERENCES ProductOfferings (OfferingId)
) PRIMARY KEY (ProductSpecId, OfferingId);

-- Product Specification realized by Service Specification (CFS/RFS)
CREATE TABLE ProductSpecServiceSpecs (
  ProductSpecId STRING(36) NOT NULL,
  ServiceSpecId STRING(36) NOT NULL,
  CONSTRAINT FK_SpecServ_ProdSpec FOREIGN KEY (ProductSpecId) REFERENCES ProductSpecifications (ProductSpecId),
  CONSTRAINT FK_SpecServ_ServSpec FOREIGN KEY (ServiceSpecId) REFERENCES ServiceSpecifications (ServiceSpecId)
) PRIMARY KEY (ProductSpecId, ServiceSpecId);

-- Service Specification requires Resource Specification
CREATE TABLE ServiceSpecResourceSpecs (
  ServiceSpecId STRING(36) NOT NULL,
  ResourceSpecId STRING(36) NOT NULL,
  CONSTRAINT FK_ServRes_ServSpec FOREIGN KEY (ServiceSpecId) REFERENCES ServiceSpecifications (ServiceSpecId),
  CONSTRAINT FK_ServRes_ResSpec FOREIGN KEY (ResourceSpecId) REFERENCES ResourceSpecifications (ResourceSpecId)
) PRIMARY KEY (ServiceSpecId, ResourceSpecId);

-- Product Offering Bundling Hierarchy (Transitive Package Composition)
CREATE TABLE ProductOfferingBundles (
  ParentOfferingId STRING(36) NOT NULL,
  ChildOfferingId STRING(36) NOT NULL,
  CONSTRAINT FK_Bundle_Parent FOREIGN KEY (ParentOfferingId) REFERENCES ProductOfferings (OfferingId),
  CONSTRAINT FK_Bundle_Child FOREIGN KEY (ChildOfferingId) REFERENCES ProductOfferings (OfferingId)
) PRIMARY KEY (ParentOfferingId, ChildOfferingId);

-- Inter-Carrier Roaming & Peering Partnership (Symmetric Relationship)
CREATE TABLE OrganizationPeeringPartners (
  OrganizationPartyId STRING(36) NOT NULL,
  PeerOrganizationPartyId STRING(36) NOT NULL,
  CONSTRAINT FK_Peering_Org FOREIGN KEY (OrganizationPartyId) REFERENCES OrganizationParties (PartyId),
  CONSTRAINT FK_Peering_PeerOrg FOREIGN KEY (PeerOrganizationPartyId) REFERENCES OrganizationParties (PartyId)
) PRIMARY KEY (OrganizationPartyId, PeerOrganizationPartyId);

-- Product Order to Offering & Account Links
CREATE TABLE ProductOrderOfferings (
  OrderId STRING(36) NOT NULL,
  OfferingId STRING(36) NOT NULL,
  CONSTRAINT FK_OrderOffering_Order FOREIGN KEY (OrderId) REFERENCES ProductOrders (OrderId),
  CONSTRAINT FK_OrderOffering_Offering FOREIGN KEY (OfferingId) REFERENCES ProductOfferings (OfferingId)
) PRIMARY KEY (OrderId, OfferingId);

CREATE TABLE ProductOrderAccounts (
  OrderId STRING(36) NOT NULL,
  AccountId STRING(36) NOT NULL,
  CONSTRAINT FK_OrderAccount_Order FOREIGN KEY (OrderId) REFERENCES ProductOrders (OrderId),
  CONSTRAINT FK_OrderAccount_Account FOREIGN KEY (AccountId) REFERENCES CustomerAccounts (AccountId)
) PRIMARY KEY (OrderId, AccountId);

-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH DEFINITION
-- =============================================================================

CREATE PROPERTY GRAPH OdaSidGraph
  NODE TABLES (
    IndividualParties
      LABEL IndividualParty PROPERTIES (PartyId, PartyName, NationalId)
      LABEL Party PROPERTIES (PartyId, PartyName),
    OrganizationParties
      LABEL OrganizationParty PROPERTIES (PartyId, PartyName, TaxRegistrationNumber)
      LABEL Party PROPERTIES (PartyId, PartyName),
    CustomerAccounts
      LABEL CustomerAccount PROPERTIES (AccountId, AccountStatus, CreditLimit),
    ProductSpecifications
      LABEL ProductSpecification PROPERTIES (ProductSpecId),
    ProductOfferings
      LABEL ProductOffering PROPERTIES (OfferingId, OfferingName, MonthlyPrice, IsBundle),
    ServiceSpecifications
      LABEL ServiceSpecification PROPERTIES (ServiceSpecId, TargetSlaAvailability),
    ResourceSpecifications
      LABEL ResourceSpecification PROPERTIES (ResourceSpecId, ResourceType),
    ProductOrders
      LABEL ProductOrder PROPERTIES (OrderId, OrderDate)
  )
  EDGE TABLES (
    IndividualPartyAccounts
      SOURCE KEY (PartyId) REFERENCES IndividualParties (PartyId)
      DESTINATION KEY (AccountId) REFERENCES CustomerAccounts (AccountId)
      LABEL HOLDS_ACCOUNT NO PROPERTIES,
    OrganizationPartyAccounts
      SOURCE KEY (PartyId) REFERENCES OrganizationParties (PartyId)
      DESTINATION KEY (AccountId) REFERENCES CustomerAccounts (AccountId)
      LABEL HOLDS_ACCOUNT NO PROPERTIES,
    ProductSpecificationOfferings
      SOURCE KEY (ProductSpecId) REFERENCES ProductSpecifications (ProductSpecId)
      DESTINATION KEY (OfferingId) REFERENCES ProductOfferings (OfferingId)
      LABEL SPECIFIES_OFFERING NO PROPERTIES,
    ProductSpecServiceSpecs
      SOURCE KEY (ProductSpecId) REFERENCES ProductSpecifications (ProductSpecId)
      DESTINATION KEY (ServiceSpecId) REFERENCES ServiceSpecifications (ServiceSpecId)
      LABEL REALIZED_BY_SERVICE_SPEC NO PROPERTIES,
    ServiceSpecResourceSpecs
      SOURCE KEY (ServiceSpecId) REFERENCES ServiceSpecifications (ServiceSpecId)
      DESTINATION KEY (ResourceSpecId) REFERENCES ResourceSpecifications (ResourceSpecId)
      LABEL REQUIRES_RESOURCE_SPEC NO PROPERTIES,
    ProductOfferingBundles
      SOURCE KEY (ParentOfferingId) REFERENCES ProductOfferings (OfferingId)
      DESTINATION KEY (ChildOfferingId) REFERENCES ProductOfferings (OfferingId)
      LABEL BUNDLES_OFFERING NO PROPERTIES,
    OrganizationPeeringPartners
      SOURCE KEY (OrganizationPartyId) REFERENCES OrganizationParties (PartyId)
      DESTINATION KEY (PeerOrganizationPartyId) REFERENCES OrganizationParties (PartyId)
      LABEL PEERING_PARTNER_OF NO PROPERTIES,
    ProductOrderOfferings
      SOURCE KEY (OrderId) REFERENCES ProductOrders (OrderId)
      DESTINATION KEY (OfferingId) REFERENCES ProductOfferings (OfferingId)
      LABEL ORDERS_OFFERING NO PROPERTIES,
    ProductOrderAccounts
      SOURCE KEY (OrderId) REFERENCES ProductOrders (OrderId)
      DESTINATION KEY (AccountId) REFERENCES CustomerAccounts (AccountId)
      LABEL PLACED_FOR_ACCOUNT NO PROPERTIES
  );