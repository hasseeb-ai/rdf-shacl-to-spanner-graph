-- =============================================================================
-- RELATIONAL SCHEMA (Google Cloud Spanner SQL DDL)
-- Pattern: Table-Per-Concrete-Class with Flattened Superclass Properties
-- =============================================================================

CREATE TABLE SoftwareEngineers (
  SoftwareEngineerId STRING(36) NOT NULL,
  ProfessionalName STRING(MAX),
  GitHandle STRING(MAX)
) PRIMARY KEY (SoftwareEngineerId);

CREATE TABLE TechnicalProjects (
  TechnicalProjectId STRING(36) NOT NULL,
  InitiativeTitle STRING(MAX)
) PRIMARY KEY (TechnicalProjectId);

CREATE TABLE WritesCodeFor (
  SoftwareEngineerId STRING(36) NOT NULL,
  TechnicalProjectId STRING(36) NOT NULL,
  CONSTRAINT FK_WritesCodeFor_Engineer FOREIGN KEY (SoftwareEngineerId) REFERENCES SoftwareEngineers (SoftwareEngineerId),
  CONSTRAINT FK_WritesCodeFor_Project FOREIGN KEY (TechnicalProjectId) REFERENCES TechnicalProjects (TechnicalProjectId)
) PRIMARY KEY (SoftwareEngineerId, TechnicalProjectId);

CREATE TABLE ArchitectFor (
  SoftwareEngineerId STRING(36) NOT NULL,
  TechnicalProjectId STRING(36) NOT NULL,
  CONSTRAINT FK_ArchitectFor_Engineer FOREIGN KEY (SoftwareEngineerId) REFERENCES SoftwareEngineers (SoftwareEngineerId),
  CONSTRAINT FK_ArchitectFor_Project FOREIGN KEY (TechnicalProjectId) REFERENCES TechnicalProjects (TechnicalProjectId)
) PRIMARY KEY (SoftwareEngineerId, TechnicalProjectId);

-- =============================================================================
-- PROPERTY GRAPH SCHEMA (Google Cloud Spanner Graph DDL)
-- Multi-label node inheritance and subproperty label accumulation
-- =============================================================================

CREATE PROPERTY GRAPH InitiativeCollaborationGraph
  NODE TABLES (
    SoftwareEngineers
      LABEL SOFTWARE_ENGINEER PROPERTIES (SoftwareEngineerId, ProfessionalName, GitHandle)
      LABEL PROFESSIONAL PROPERTIES (SoftwareEngineerId, ProfessionalName, GitHandle),
    TechnicalProjects
      LABEL TECHNICAL_PROJECT PROPERTIES (TechnicalProjectId, InitiativeTitle)
      LABEL INITIATIVE PROPERTIES (TechnicalProjectId, InitiativeTitle)
  )
  EDGE TABLES (
    WritesCodeFor
      SOURCE KEY (SoftwareEngineerId) REFERENCES SoftwareEngineers (SoftwareEngineerId)
      DESTINATION KEY (TechnicalProjectId) REFERENCES TechnicalProjects (TechnicalProjectId)
      LABEL WRITES_CODE_FOR PROPERTIES (SoftwareEngineerId, TechnicalProjectId)
      LABEL CONTRIBUTES_TO_INITIATIVE PROPERTIES (SoftwareEngineerId, TechnicalProjectId)
      LABEL ASSOCIATED_WITH_INITIATIVE PROPERTIES (SoftwareEngineerId, TechnicalProjectId),
    ArchitectFor
      SOURCE KEY (SoftwareEngineerId) REFERENCES SoftwareEngineers (SoftwareEngineerId)
      DESTINATION KEY (TechnicalProjectId) REFERENCES TechnicalProjects (TechnicalProjectId)
      LABEL ARCHITECT_FOR PROPERTIES (SoftwareEngineerId, TechnicalProjectId)
      LABEL CONTRIBUTES_TO_INITIATIVE PROPERTIES (SoftwareEngineerId, TechnicalProjectId)
      LABEL ASSOCIATED_WITH_INITIATIVE PROPERTIES (SoftwareEngineerId, TechnicalProjectId)
  );