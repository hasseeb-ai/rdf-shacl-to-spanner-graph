-- =============================================================================
-- Google Cloud Spanner Physical Relational Schema
-- =============================================================================

-- Concrete Table: Enterprises
CREATE TABLE Enterprises (
  EnterpriseId STRING(36) NOT NULL,
  EnterpriseName STRING(MAX)
) PRIMARY KEY (EnterpriseId);

-- Concrete Table: Contractors
CREATE TABLE Contractors (
  ContractorId STRING(36) NOT NULL,
  ContractorName STRING(MAX),
  HourlyRate NUMERIC
) PRIMARY KEY (ContractorId);

-- Concrete Table: Projects
CREATE TABLE Projects (
  ProjectId STRING(36) NOT NULL,
  ProjectName STRING(MAX)
) PRIMARY KEY (ProjectId);

-- Associative Edge Table: Enterprise <-> Contractor (Storage deduplication for ex:contractsWith & ex:contractedBy)
CREATE TABLE EnterpriseContractors (
  EnterpriseId STRING(36) NOT NULL,
  ContractorId STRING(36) NOT NULL,
  CONSTRAINT FK_EnterpriseContractors_Enterprise FOREIGN KEY (EnterpriseId) REFERENCES Enterprises (EnterpriseId),
  CONSTRAINT FK_EnterpriseContractors_Contractor FOREIGN KEY (ContractorId) REFERENCES Contractors (ContractorId)
) PRIMARY KEY (EnterpriseId, ContractorId);

-- Associative Edge Table: Contractor <-> Project (Storage deduplication for ex:assignedToProject & ex:hasAssignedContractor)
CREATE TABLE ContractorProjects (
  ContractorId STRING(36) NOT NULL,
  ProjectId STRING(36) NOT NULL,
  CONSTRAINT FK_ContractorProjects_Contractor FOREIGN KEY (ContractorId) REFERENCES Contractors (ContractorId),
  CONSTRAINT FK_ContractorProjects_Project FOREIGN KEY (ProjectId) REFERENCES Projects (ProjectId)
) PRIMARY KEY (ContractorId, ProjectId);

-- =============================================================================
-- Google Cloud Spanner Property Graph Schema
-- =============================================================================

CREATE PROPERTY GRAPH EnterpriseGraph
  NODE TABLES (
    Enterprises
      LABEL Enterprise PROPERTIES (EnterpriseId, EnterpriseName),
    Contractors
      LABEL Contractor PROPERTIES (ContractorId, ContractorName, HourlyRate),
    Projects
      LABEL Project PROPERTIES (ProjectId, ProjectName)
  )
  EDGE TABLES (
    -- Forward Edge: Enterprise -> contractsWith -> Contractor
    EnterpriseContractors
      SOURCE KEY (EnterpriseId) REFERENCES Enterprises (EnterpriseId)
      DESTINATION KEY (ContractorId) REFERENCES Contractors (ContractorId)
      LABEL CONTRACTS_WITH,
    -- Inverse Edge: Contractor -> contractedBy -> Enterprise
    EnterpriseContractors AS EnterpriseContractorsInverse
      SOURCE KEY (ContractorId) REFERENCES Contractors (ContractorId)
      DESTINATION KEY (EnterpriseId) REFERENCES Enterprises (EnterpriseId)
      LABEL CONTRACTED_BY,
    -- Forward Edge: Contractor -> assignedToProject -> Project
    ContractorProjects
      SOURCE KEY (ContractorId) REFERENCES Contractors (ContractorId)
      DESTINATION KEY (ProjectId) REFERENCES Projects (ProjectId)
      LABEL ASSIGNED_TO_PROJECT,
    -- Inverse Edge: Project -> hasAssignedContractor -> Contractor
    ContractorProjects AS ContractorProjectsInverse
      SOURCE KEY (ProjectId) REFERENCES Projects (ProjectId)
      DESTINATION KEY (ContractorId) REFERENCES Contractors (ContractorId)
      LABEL HAS_ASSIGNED_CONTRACTOR
  );