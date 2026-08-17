-- =============================================================================
-- Google Cloud Spanner Relational DDL
-- Pattern: Table-Per-Concrete-Class with Flattened Superclass Hierarchies
-- =============================================================================

CREATE TABLE RegularEmployees (
  RegularEmployeeId STRING(36) NOT NULL,
  FullName STRING(MAX),
  NationalId STRING(MAX),
  EmployeeId STRING(MAX),
  HourlyRate NUMERIC,
  EmployeeCode STRING(MAX)
) PRIMARY KEY (RegularEmployeeId);

CREATE TABLE UndergraduateStudents (
  UndergraduateStudentId STRING(36) NOT NULL,
  FullName STRING(MAX),
  NationalId STRING(MAX),
  StudentNumber STRING(MAX),
  Gpa NUMERIC,
  StudentCode STRING(MAX)
) PRIMARY KEY (UndergraduateStudentId);

CREATE TABLE TeachingAssistants (
  TeachingAssistantId STRING(36) NOT NULL,
  FullName STRING(MAX),
  NationalId STRING(MAX),
  EmployeeId STRING(MAX),
  HourlyRate NUMERIC,
  EmployeeCode STRING(MAX),
  StudentNumber STRING(MAX),
  Gpa NUMERIC,
  StudentCode STRING(MAX),
  StipendAmount NUMERIC,
  AssignedCourseCode STRING(MAX)
) PRIMARY KEY (TeachingAssistantId);

-- =============================================================================
-- Google Cloud Spanner Property Graph Schema
-- Models Diamond Multiple Inheritance & Multi-Label Class Chains
-- =============================================================================

CREATE PROPERTY GRAPH UniversityGraph
  NODE TABLES (
    RegularEmployees
      LABEL RegularEmployee PROPERTIES (RegularEmployeeId, FullName, NationalId, EmployeeId, HourlyRate, EmployeeCode)
      LABEL Employee PROPERTIES (FullName, NationalId, EmployeeId, HourlyRate, EmployeeCode)
      LABEL Person PROPERTIES (FullName, NationalId),
    UndergraduateStudents
      LABEL UndergraduateStudent PROPERTIES (UndergraduateStudentId, FullName, NationalId, StudentNumber, Gpa, StudentCode)
      LABEL Student PROPERTIES (FullName, NationalId, StudentNumber, Gpa, StudentCode)
      LABEL Person PROPERTIES (FullName, NationalId),
    TeachingAssistants
      LABEL TeachingAssistant PROPERTIES (TeachingAssistantId, FullName, NationalId, EmployeeId, HourlyRate, EmployeeCode, StudentNumber, Gpa, StudentCode, StipendAmount, AssignedCourseCode)
      LABEL Employee PROPERTIES (FullName, NationalId, EmployeeId, HourlyRate, EmployeeCode)
      LABEL Student PROPERTIES (FullName, NationalId, StudentNumber, Gpa, StudentCode)
      LABEL Person PROPERTIES (FullName, NationalId)
  );