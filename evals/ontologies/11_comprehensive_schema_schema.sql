-- =============================================================================
-- GOOGLE CLOUD SPANNER PHYSICAL RELATIONAL SCHEMA
-- Architecture: Table-Per-Concrete-Class with Flattened Superclass Hierarchies
-- =============================================================================

-- Concrete Subclass: Manager (Diamond Multiple Inheritance: Employee + LeadSpecialist -> Individual -> LegalEntity)
CREATE TABLE Managers (
  EntityIdentifier STRING(36) NOT NULL,
  LegalName STRING(100) NOT NULL,
  BadgeNumber STRING(20) NOT NULL,
  SpecialtyDomain STRING(MAX) NOT NULL,
  ManagementLevel INT64 NOT NULL
) PRIMARY KEY (EntityIdentifier);

-- Concrete Subclass: RegularStaff (Employee -> Individual -> LegalEntity)
CREATE TABLE RegularStaff (
  EntityIdentifier STRING(36) NOT NULL,
  LegalName STRING(MAX),
  BadgeNumber STRING(MAX)
) PRIMARY KEY (EntityIdentifier);

-- Concrete Subclass: Corporation (Organization -> LegalEntity, Disjoint with NonGovernmentalOrg)
CREATE TABLE Corporations (
  EntityIdentifier STRING(36) NOT NULL,
  LegalName STRING(MAX) NOT NULL
) PRIMARY KEY (EntityIdentifier);

-- Concrete Subclass: NonGovernmentalOrg (Organization -> LegalEntity, Disjoint with Corporation)
CREATE TABLE NonGovernmentalOrgs (
  EntityIdentifier STRING(36) NOT NULL,
  LegalName STRING(MAX)
) PRIMARY KEY (EntityIdentifier);

-- Concrete Subclass: DigitalAsset (Asset) with Equivalent Class Stored Generated Column
CREATE TABLE DigitalAssets (
  AssetId STRING(36) NOT NULL,
  AppraisalValue NUMERIC NOT NULL,
  IsHighValue BOOL AS (AppraisalValue > 100000.00) STORED
) PRIMARY KEY (AssetId);

-- Concrete Class: Department (Self-Referencing Transitive Hierarchy)
CREATE TABLE Departments (
  DepartmentId STRING(36) NOT NULL,
  DepartmentName STRING(MAX)
) PRIMARY KEY (DepartmentId);

-- Edge Table: Transitive Hierarchy for Departments
CREATE TABLE DepartmentHierarchies (
  ParentDepartmentId STRING(36) NOT NULL,
  ChildDepartmentId STRING(36) NOT NULL,
  CONSTRAINT FK_Dept_Parent FOREIGN KEY (ParentDepartmentId) REFERENCES Departments (DepartmentId),
  CONSTRAINT FK_Dept_Child FOREIGN KEY (ChildDepartmentId) REFERENCES Departments (DepartmentId)
) PRIMARY KEY (ParentDepartmentId, ChildDepartmentId);

-- Edge Table: Subproperty Hierarchy (supervisesStaff rdfs:subPropertyOf interactsWith)
CREATE TABLE StaffSupervisions (
  ManagerId STRING(36) NOT NULL,
  StaffId STRING(36) NOT NULL,
  CONSTRAINT FK_Supervision_Manager FOREIGN KEY (ManagerId) REFERENCES Managers (EntityIdentifier),
  CONSTRAINT FK_Supervision_Staff FOREIGN KEY (StaffId) REFERENCES RegularStaff (EntityIdentifier)
) PRIMARY KEY (ManagerId, StaffId);

-- Edge Table: Symmetric Subproperty (collaboratesOnProject rdfs:subPropertyOf interactsWith)
CREATE TABLE StaffCollaborations (
  Staff1Id STRING(36) NOT NULL,
  Staff2Id STRING(36) NOT NULL,
  CONSTRAINT FK_Collab_Staff1 FOREIGN KEY (Staff1Id) REFERENCES RegularStaff (EntityIdentifier),
  CONSTRAINT FK_Collab_Staff2 FOREIGN KEY (Staff2Id) REFERENCES RegularStaff (EntityIdentifier)
) PRIMARY KEY (Staff1Id, Staff2Id);

-- Edge Table: Inverse Properties (employsWorker owl:inverseOf worksForOrganization)
CREATE TABLE CorporationStaffEmployments (
  OrganizationId STRING(36) NOT NULL,
  EmployeeId STRING(36) NOT NULL,
  CONSTRAINT FK_Corp_Employment_Org FOREIGN KEY (OrganizationId) REFERENCES Corporations (EntityIdentifier),
  CONSTRAINT FK_Corp_Employment_Staff FOREIGN KEY (EmployeeId) REFERENCES RegularStaff (EntityIdentifier)
) PRIMARY KEY (OrganizationId, EmployeeId);

-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH SCHEMA
-- =============================================================================

CREATE PROPERTY GRAPH ComprehensiveGraph
  NODE TABLES (
    -- Multi-label hierarchy: Manager -> LeadSpecialist/Employee -> Individual -> LegalEntity
    Managers
      LABEL Manager PROPERTIES (EntityIdentifier, LegalName, BadgeNumber, SpecialtyDomain, ManagementLevel)
      LABEL LeadSpecialist PROPERTIES (EntityIdentifier, LegalName, SpecialtyDomain)
      LABEL Employee PROPERTIES (EntityIdentifier, LegalName, BadgeNumber)
      LABEL Individual PROPERTIES (EntityIdentifier, LegalName)
      LABEL LegalEntity PROPERTIES (EntityIdentifier, LegalName),

    -- Multi-label hierarchy: RegularStaff -> Employee -> Individual -> LegalEntity
    RegularStaff
      LABEL RegularStaff PROPERTIES (EntityIdentifier, LegalName, BadgeNumber)
      LABEL Employee PROPERTIES (EntityIdentifier, LegalName, BadgeNumber)
      LABEL Individual PROPERTIES (EntityIdentifier, LegalName)
      LABEL LegalEntity PROPERTIES (EntityIdentifier, LegalName),

    -- Multi-label hierarchy: Corporation -> Organization -> LegalEntity
    Corporations
      LABEL Corporation PROPERTIES (EntityIdentifier, LegalName)
      LABEL Organization PROPERTIES (EntityIdentifier, LegalName)
      LABEL LegalEntity PROPERTIES (EntityIdentifier, LegalName),

    -- Multi-label hierarchy: NonGovernmentalOrg -> Organization -> LegalEntity
    NonGovernmentalOrgs
      LABEL NonGovernmentalOrg PROPERTIES (EntityIdentifier, LegalName)
      LABEL Organization PROPERTIES (EntityIdentifier, LegalName)
      LABEL LegalEntity PROPERTIES (EntityIdentifier, LegalName),

    -- Multi-label hierarchy: DigitalAsset -> Asset
    DigitalAssets
      LABEL DigitalAsset PROPERTIES (AssetId, AppraisalValue, IsHighValue)
      LABEL Asset PROPERTIES (AssetId),

    -- Concrete Class: Department
    Departments
      LABEL Department PROPERTIES (DepartmentId, DepartmentName)
  )
  EDGE TABLES (
    -- Transitive Edge: Department -> Department
    DepartmentHierarchies
      SOURCE KEY (ParentDepartmentId) REFERENCES Departments (DepartmentId)
      DESTINATION KEY (ChildDepartmentId) REFERENCES Departments (DepartmentId)
      LABEL PARENT_DEPARTMENT_OF NO PROPERTIES,

    -- Subproperty Label Accumulation: supervisesStaff -> interactsWith
    StaffSupervisions
      SOURCE KEY (ManagerId) REFERENCES Managers (EntityIdentifier)
      DESTINATION KEY (StaffId) REFERENCES RegularStaff (EntityIdentifier)
      LABEL SUPERVISES_STAFF NO PROPERTIES
      LABEL INTERACTS_WITH NO PROPERTIES,

    -- Symmetric Subproperty Label Accumulation: collaboratesOnProject -> interactsWith
    StaffCollaborations
      SOURCE KEY (Staff1Id) REFERENCES RegularStaff (EntityIdentifier)
      DESTINATION KEY (Staff2Id) REFERENCES RegularStaff (EntityIdentifier)
      LABEL COLLABORATES_ON_PROJECT NO PROPERTIES
      LABEL INTERACTS_WITH NO PROPERTIES,

    -- Inverse Property Pair 1: employsWorker (Organization -> Employee)
    CorporationStaffEmployments
      SOURCE KEY (OrganizationId) REFERENCES Corporations (EntityIdentifier)
      DESTINATION KEY (EmployeeId) REFERENCES RegularStaff (EntityIdentifier)
      LABEL EMPLOYS_WORKER NO PROPERTIES,

    -- Inverse Property Pair 2: worksForOrganization (Employee -> Organization)
    CorporationStaffEmployments AS StaffCorporationEmployments
      SOURCE KEY (EmployeeId) REFERENCES RegularStaff (EntityIdentifier)
      DESTINATION KEY (OrganizationId) REFERENCES Corporations (EntityIdentifier)
      LABEL WORKS_FOR_ORGANIZATION NO PROPERTIES
  );