-- =============================================================================
-- PHYSICAL RELATIONAL DDL
-- =============================================================================

-- Concrete Table: Employee
CREATE TABLE Employees (
  EmployeeId STRING(36) NOT NULL,
  EmployeeName STRING(MAX),
  JobTitle STRING(MAX),
  ManagerId STRING(36),
  CONSTRAINT FK_Employee_Manager FOREIGN KEY (ManagerId) REFERENCES Employees (EmployeeId)
) PRIMARY KEY (EmployeeId);

-- Concrete Table: Component
CREATE TABLE Components (
  ComponentId STRING(36) NOT NULL,
  ComponentName STRING(MAX),
  SemanticVersion STRING(MAX)
) PRIMARY KEY (ComponentId);

-- Edge Table: Component Dependencies (Many-to-Many self-reference)
CREATE TABLE ComponentDependencies (
  ComponentId STRING(36) NOT NULL,
  DependsOnComponentId STRING(36) NOT NULL,
  CONSTRAINT FK_Dependency_Source FOREIGN KEY (ComponentId) REFERENCES Components (ComponentId),
  CONSTRAINT FK_Dependency_Target FOREIGN KEY (DependsOnComponentId) REFERENCES Components (ComponentId)
) PRIMARY KEY (ComponentId, DependsOnComponentId);

-- =============================================================================
-- PROPERTY GRAPH DDL
-- =============================================================================

CREATE PROPERTY GRAPH RecursiveOntologyGraph
  NODE TABLES (
    Employees
      LABEL Employee PROPERTIES (EmployeeId, EmployeeName, JobTitle),
    Components
      LABEL Component PROPERTIES (ComponentId, ComponentName, SemanticVersion)
  )
  EDGE TABLES (
    -- Direct adjacency list edge via physical table alias
    Employees AS EmployeeReportsTo
      SOURCE KEY (EmployeeId) REFERENCES Employees (EmployeeId)
      DESTINATION KEY (ManagerId) REFERENCES Employees (EmployeeId)
      LABEL REPORTS_TO PROPERTIES (EmployeeId, ManagerId),
    -- Edge table mapping for component dependency trees
    ComponentDependencies
      SOURCE KEY (ComponentId) REFERENCES Components (ComponentId)
      DESTINATION KEY (DependsOnComponentId) REFERENCES Components (ComponentId)
      LABEL DEPENDS_ON PROPERTIES (ComponentId, DependsOnComponentId)
  );