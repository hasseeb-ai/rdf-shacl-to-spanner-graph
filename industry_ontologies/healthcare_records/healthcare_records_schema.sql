-- =============================================================================
-- GOOGLE CLOUD SPANNER SCHEMA TRANSLATION
-- Source Ontology: Healthcare EHR and Clinical Operations Ontology
-- Table Pattern: Table-Per-Concrete-Class with Flattened Inheritance
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. PHYSICAL RELATIONAL SCHEMA (GoogleSQL DDL)
-- -----------------------------------------------------------------------------

CREATE TABLE Medications (
  MedicationId STRING(36) NOT NULL,
  RxNormId STRING(MAX)
) PRIMARY KEY (MedicationId);

CREATE TABLE Prescriptions (
  PrescriptionId STRING(36) NOT NULL,
  DosageInstruction STRING(MAX),
  MedicationId STRING(36),
  CONSTRAINT FK_Prescriptions_Medication FOREIGN KEY (MedicationId) REFERENCES Medications (MedicationId)
) PRIMARY KEY (PrescriptionId);

CREATE TABLE Diagnoses (
  DiagnosisId STRING(36) NOT NULL,
  Icd10Code STRING(MAX),
  LeadsToDiagnosisId STRING(36),
  CONSTRAINT FK_Diagnoses_LeadsTo FOREIGN KEY (LeadsToDiagnosisId) REFERENCES Diagnoses (DiagnosisId)
) PRIMARY KEY (DiagnosisId);

CREATE TABLE Procedures (
  ProcedureId STRING(36) NOT NULL,
  CptCode STRING(MAX)
) PRIMARY KEY (ProcedureId);

CREATE TABLE Practitioners (
  PractitionerId STRING(36) NOT NULL,
  Npi STRING(MAX),
  PractitionerSpecialty STRING(MAX),
  ReferredToPractitionerId STRING(36),
  CONSTRAINT FK_Practitioners_ReferredTo FOREIGN KEY (ReferredToPractitionerId) REFERENCES Practitioners (PractitionerId)
) PRIMARY KEY (PractitionerId);

CREATE TABLE Encounters (
  EncounterId STRING(36) NOT NULL,
  EncounterTimestamp TIMESTAMP,
  PractitionerId STRING(36) NOT NULL, -- Enforced by SHACL minCount 1 (ex:attendedBy)
  DiagnosisId STRING(36),
  ProcedureId STRING(36),
  PrescriptionId STRING(36),
  CONSTRAINT FK_Encounters_Practitioner FOREIGN KEY (PractitionerId) REFERENCES Practitioners (PractitionerId),
  CONSTRAINT FK_Encounters_Diagnosis FOREIGN KEY (DiagnosisId) REFERENCES Diagnoses (DiagnosisId),
  CONSTRAINT FK_Encounters_Procedure FOREIGN KEY (ProcedureId) REFERENCES Procedures (ProcedureId),
  CONSTRAINT FK_Encounters_Prescription FOREIGN KEY (PrescriptionId) REFERENCES Prescriptions (PrescriptionId)
) PRIMARY KEY (EncounterId);

CREATE TABLE Patients (
  PatientId STRING(36) NOT NULL,
  Mrn STRING(MAX) NOT NULL, -- Enforced by SHACL minCount 1 / OWL cardinality 1
  ActiveConditionsCount INT64,
  EncounterId STRING(36),
  IsComplexCase BOOL AS (ActiveConditionsCount >= 5) STORED, -- Computed from owl:equivalentClass restriction
  CONSTRAINT FK_Patients_Encounter FOREIGN KEY (EncounterId) REFERENCES Encounters (EncounterId)
) PRIMARY KEY (PatientId);

-- View representing the equivalent class ex:ComplexCasePatient
CREATE VIEW ComplexCasePatients SQL SECURITY INVOKER AS
SELECT 
  p.PatientId,
  p.Mrn,
  p.ActiveConditionsCount
FROM Patients p
WHERE p.ActiveConditionsCount >= 5;


-- -----------------------------------------------------------------------------
-- 2. PROPERTY GRAPH SCHEMA (GoogleSQL DDL)
-- -----------------------------------------------------------------------------

CREATE PROPERTY GRAPH HealthcareGraph
  NODE TABLES (
    Patients
      LABEL Patient PROPERTIES (PatientId, Mrn, ActiveConditionsCount)
      LABEL Person NO PROPERTIES,
    Practitioners
      LABEL Practitioner PROPERTIES (PractitionerId, Npi, PractitionerSpecialty)
      LABEL Person NO PROPERTIES,
    Encounters
      LABEL Encounter PROPERTIES (EncounterId, EncounterTimestamp),
    Diagnoses
      LABEL Diagnosis PROPERTIES (DiagnosisId, Icd10Code),
    Medications
      LABEL Medication PROPERTIES (MedicationId, RxNormId),
    Prescriptions
      LABEL Prescription PROPERTIES (PrescriptionId, DosageInstruction),
    Procedures
      LABEL Procedure PROPERTIES (ProcedureId, CptCode),
    ComplexCasePatients KEY (PatientId)
      LABEL ComplexCasePatient PROPERTIES (PatientId, Mrn, ActiveConditionsCount)
      LABEL Patient PROPERTIES (PatientId, Mrn, ActiveConditionsCount)
      LABEL Person NO PROPERTIES
  )
  EDGE TABLES (
    Patients AS PatientParticipatedIn
      SOURCE KEY (PatientId) REFERENCES Patients (PatientId)
      DESTINATION KEY (EncounterId) REFERENCES Encounters (EncounterId)
      LABEL PARTICIPATED_IN NO PROPERTIES,
    Encounters AS EncounterAttendedBy
      SOURCE KEY (EncounterId) REFERENCES Encounters (EncounterId)
      DESTINATION KEY (PractitionerId) REFERENCES Practitioners (PractitionerId)
      LABEL ATTENDED_BY NO PROPERTIES,
    Encounters AS EncounterDiagnoses
      SOURCE KEY (EncounterId) REFERENCES Encounters (EncounterId)
      DESTINATION KEY (DiagnosisId) REFERENCES Diagnoses (DiagnosisId)
      LABEL ENCOUNTER_DIAGNOSIS NO PROPERTIES,
    Encounters AS EncounterPrescriptions
      SOURCE KEY (EncounterId) REFERENCES Encounters (EncounterId)
      DESTINATION KEY (PrescriptionId) REFERENCES Prescriptions (PrescriptionId)
      LABEL ORDERED_PRESCRIPTION NO PROPERTIES,
    Encounters AS EncounterProcedures
      SOURCE KEY (EncounterId) REFERENCES Encounters (EncounterId)
      DESTINATION KEY (ProcedureId) REFERENCES Procedures (ProcedureId)
      LABEL PERFORMED_PROCEDURE NO PROPERTIES,
    Prescriptions AS PrescriptionMedication
      SOURCE KEY (PrescriptionId) REFERENCES Prescriptions (PrescriptionId)
      DESTINATION KEY (MedicationId) REFERENCES Medications (MedicationId)
      LABEL HAS_MEDICATION NO PROPERTIES,
    -- Inverse Edge: ex:prescribedIn owl:inverseOf ex:hasMedication (uses physical Prescriptions table)
    Prescriptions AS MedicationPrescriptions
      SOURCE KEY (MedicationId) REFERENCES Medications (MedicationId)
      DESTINATION KEY (PrescriptionId) REFERENCES Prescriptions (PrescriptionId)
      LABEL PRESCRIBED_IN NO PROPERTIES,
    -- Symmetric Property: ex:referredTo
    Practitioners AS PractitionerReferrals
      SOURCE KEY (PractitionerId) REFERENCES Practitioners (PractitionerId)
      DESTINATION KEY (ReferredToPractitionerId) REFERENCES Practitioners (PractitionerId)
      LABEL REFERRED_TO NO PROPERTIES,
    -- Transitive Property: ex:leadsToCondition
    Diagnoses AS ConditionProgression
      SOURCE KEY (DiagnosisId) REFERENCES Diagnoses (DiagnosisId)
      DESTINATION KEY (LeadsToDiagnosisId) REFERENCES Diagnoses (DiagnosisId)
      LABEL LEADS_TO_CONDITION NO PROPERTIES
  );