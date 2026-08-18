-- =============================================================================
-- Google Cloud Spanner Relational DDL
-- Table-Per-Concrete-Class Pattern & N-ary Relationship Representation
-- =============================================================================

CREATE TABLE Persons (
  PersonId STRING(MAX) NOT NULL,
  FullName STRING(MAX) NOT NULL
) PRIMARY KEY (PersonId);

CREATE TABLE Companies (
  CompanyId STRING(MAX) NOT NULL,
  CompanyName STRING(MAX) NOT NULL
) PRIMARY KEY (CompanyId);

CREATE TABLE Employments (
  EmploymentId STRING(MAX) NOT NULL,
  PersonId STRING(MAX) NOT NULL,
  CompanyId STRING(MAX) NOT NULL,
  JobTitle STRING(MAX) NOT NULL,
  SalaryAmount NUMERIC NOT NULL,
  StartDate DATE NOT NULL,
  EndDate DATE,
  IsFullTime BOOL,
  CONSTRAINT FK_Employments_Person FOREIGN KEY (PersonId) REFERENCES Persons (PersonId),
  CONSTRAINT FK_Employments_Company FOREIGN KEY (CompanyId) REFERENCES Companies (CompanyId)
) PRIMARY KEY (EmploymentId);

-- =============================================================================
-- Google Cloud Spanner Property Graph Schema
-- Attributed Edge Table Mapping for N-ary Relationship Pattern
-- =============================================================================

CREATE PROPERTY GRAPH NaryEmploymentGraph
  NODE TABLES (
    Persons
      LABEL Person PROPERTIES (PersonId, FullName),
    Companies
      LABEL Company PROPERTIES (CompanyId, CompanyName)
  )
  EDGE TABLES (
    -- Forward Edge: Person -> WORKS_FOR -> Company
    Employments
      SOURCE KEY (PersonId) REFERENCES Persons (PersonId)
      DESTINATION KEY (CompanyId) REFERENCES Companies (CompanyId)
      LABEL WORKS_FOR PROPERTIES (EmploymentId, JobTitle, SalaryAmount, StartDate, EndDate, IsFullTime),
    -- Inverse Directional Mapping: Company -> EMPLOYS -> Person
    Employments AS CompanyEmployees
      SOURCE KEY (CompanyId) REFERENCES Companies (CompanyId)
      DESTINATION KEY (PersonId) REFERENCES Persons (PersonId)
      LABEL EMPLOYS PROPERTIES (EmploymentId, JobTitle, SalaryAmount, StartDate, EndDate, IsFullTime)
  );