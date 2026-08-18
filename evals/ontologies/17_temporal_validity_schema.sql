-- =============================================================================
-- Google Cloud Spanner Physical Relational Schema
-- =============================================================================

CREATE TABLE Patients (
  PatientId STRING(64) NOT NULL,
  PatientName STRING(MAX)
) PRIMARY KEY (PatientId);

CREATE TABLE Medications (
  MedicationId STRING(64) NOT NULL,
  MedicationName STRING(MAX)
) PRIMARY KEY (MedicationId);

CREATE TABLE Prescriptions (
  PrescriptionId STRING(64) NOT NULL,
  PatientId STRING(64) NOT NULL,
  MedicationId STRING(64) NOT NULL,
  DosageMg NUMERIC NOT NULL,
  ValidFrom TIMESTAMP NOT NULL,
  ValidTo TIMESTAMP,
  IsActive BOOL,
  CONSTRAINT FK_Prescriptions_Patient FOREIGN KEY (PatientId) REFERENCES Patients (PatientId),
  CONSTRAINT FK_Prescriptions_Medication FOREIGN KEY (MedicationId) REFERENCES Medications (MedicationId),
  CONSTRAINT CK_Prescription_TemporalValidity CHECK (ValidTo IS NULL OR ValidTo >= ValidFrom)
) PRIMARY KEY (PrescriptionId);

-- =============================================================================
-- Google Cloud Spanner Property Graph Schema
-- =============================================================================

CREATE PROPERTY GRAPH TemporalPrescriptionGraph
  NODE TABLES (
    Patients
      LABEL Patient PROPERTIES (PatientId, PatientName),
    Medications
      LABEL Medication PROPERTIES (MedicationId, MedicationName),
    Prescriptions
      LABEL Prescription PROPERTIES (PrescriptionId, DosageMg, ValidFrom, ValidTo, IsActive)
  )
  EDGE TABLES (
    Prescriptions AS PrescribedForEdges
      SOURCE KEY (PrescriptionId) REFERENCES Prescriptions (PrescriptionId)
      DESTINATION KEY (PatientId) REFERENCES Patients (PatientId)
      LABEL PRESCRIBED_FOR,
    Prescriptions AS DispensesMedicationEdges
      SOURCE KEY (PrescriptionId) REFERENCES Prescriptions (PrescriptionId)
      DESTINATION KEY (MedicationId) REFERENCES Medications (MedicationId)
      LABEL DISPENSES_MEDICATION
  );