-- =============================================================================
-- GOOGLE CLOUD SPANNER RELATIONAL DDL
-- Translating: Transitive & Symmetric Properties Test Ontology
-- Patterns Applied:
--  - Table-Per-Concrete-Class with Flattened Superclass Properties
--  - Interleaved Tables with Primary Key Alignment (owl:TransitiveProperty)
--  - Single-row storage with dual-edge mapping (owl:SymmetricProperty)
-- =============================================================================

-- Base / Parent Class: ex:Department
CREATE TABLE Departments (
  DepartmentId STRING(36) NOT NULL,
  DepartmentName STRING(MAX),
  BudgetCode STRING(MAX)
) PRIMARY KEY (DepartmentId);

-- Subclass & Interleaved Child: ex:Division (rdfs:subClassOf ex:Department)
-- Inherits Department properties (DepartmentName, BudgetCode)
-- Interleaved in Departments table with PK beginning with parent PK (DepartmentId)
CREATE TABLE Divisions (
  DepartmentId STRING(36) NOT NULL,
  DivisionId STRING(36) NOT NULL,
  DepartmentName STRING(MAX),
  BudgetCode STRING(MAX)
) PRIMARY KEY (DepartmentId, DivisionId),
  INTERLEAVE IN PARENT Departments ON DELETE CASCADE;

-- Transitive Hierarchy Link: ex:subDepartmentOf (owl:TransitiveProperty)
-- Models transitive parent-child sub-department relationships
CREATE TABLE SubDepartments (
  DepartmentId STRING(36) NOT NULL,
  SubDepartmentId STRING(36) NOT NULL,
  CONSTRAINT FK_SubDept_Child FOREIGN KEY (SubDepartmentId) REFERENCES Departments (DepartmentId)
) PRIMARY KEY (DepartmentId, SubDepartmentId),
  INTERLEAVE IN PARENT Departments ON DELETE CASCADE;

-- Concrete Class: ex:Researcher
CREATE TABLE Researchers (
  ResearcherId STRING(36) NOT NULL,
  ResearcherName STRING(MAX),
  OrcidId STRING(MAX)
) PRIMARY KEY (ResearcherId);

-- Symmetric Relationship: ex:collaboratesWith (owl:SymmetricProperty)
-- Physically stored in a single direction to eliminate relational duplication.
CREATE TABLE ResearcherCollaborations (
  ResearcherId STRING(36) NOT NULL,
  CollaboratorResearcherId STRING(36) NOT NULL,
  CONSTRAINT CK_No_Self_Collab CHECK (ResearcherId != CollaboratorResearcherId),
  CONSTRAINT FK_Collab_Researcher FOREIGN KEY (ResearcherId) REFERENCES Researchers (ResearcherId),
  CONSTRAINT FK_Collab_Target FOREIGN KEY (CollaboratorResearcherId) REFERENCES Researchers (ResearcherId)
) PRIMARY KEY (ResearcherId, CollaboratorResearcherId);

-- Object Property: ex:memberOfDepartment (Researcher -> Department)
CREATE TABLE ResearcherDepartmentMemberships (
  ResearcherId STRING(36) NOT NULL,
  DepartmentId STRING(36) NOT NULL,
  CONSTRAINT FK_Member_Researcher FOREIGN KEY (ResearcherId) REFERENCES Researchers (ResearcherId),
  CONSTRAINT FK_Member_Department FOREIGN KEY (DepartmentId) REFERENCES Departments (DepartmentId)
) PRIMARY KEY (ResearcherId, DepartmentId);

-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH DDL
-- =============================================================================

CREATE PROPERTY GRAPH ResearchGraph
  NODE TABLES (
    -- Node: Departments
    Departments
      LABEL Department PROPERTIES (DepartmentId, DepartmentName, BudgetCode),

    -- Node: Divisions (Multi-label with uniform Department property signature)
    Divisions
      LABEL Division PROPERTIES (DepartmentId, DivisionId, DepartmentName, BudgetCode)
      LABEL Department PROPERTIES (DepartmentId, DepartmentName, BudgetCode),

    -- Node: Researchers
    Researchers
      LABEL Researcher PROPERTIES (ResearcherId, ResearcherName, OrcidId)
  )
  EDGE TABLES (
    -- Edge: Transitive Sub-Department Relationship (evaluate depth via GQL + / * paths)
    SubDepartments
      SOURCE KEY (DepartmentId) REFERENCES Departments (DepartmentId)
      DESTINATION KEY (SubDepartmentId) REFERENCES Departments (DepartmentId)
      LABEL SUB_DEPARTMENT_OF,

    -- Edge: Symmetric Collaboration (Forward Mapping)
    ResearcherCollaborations
      SOURCE KEY (ResearcherId) REFERENCES Researchers (ResearcherId)
      DESTINATION KEY (CollaboratorResearcherId) REFERENCES Researchers (ResearcherId)
      LABEL COLLABORATES_WITH,

    -- Edge: Symmetric Collaboration (Inverse Alias Mapping for Bidirectional Traversal)
    ResearcherCollaborations AS ResearcherCollaborationsInverse
      SOURCE KEY (CollaboratorResearcherId) REFERENCES Researchers (ResearcherId)
      DESTINATION KEY (ResearcherId) REFERENCES Researchers (ResearcherId)
      LABEL COLLABORATES_WITH,

    -- Edge: Researcher Department Membership
    ResearcherDepartmentMemberships
      SOURCE KEY (ResearcherId) REFERENCES Researchers (ResearcherId)
      DESTINATION KEY (DepartmentId) REFERENCES Departments (DepartmentId)
      LABEL MEMBER_OF_DEPARTMENT
  );