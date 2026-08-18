-- ============================================================================
-- GOOGLE CLOUD SPANNER RELATIONAL DDL
-- Table-Per-Concrete-Class Pattern with Superclass Attribute Flattening
-- ============================================================================

-- 1. Disease Node Table
CREATE TABLE Diseases (
  DiseaseId STRING(36) NOT NULL,
  DiseaseName STRING(MAX)
) PRIMARY KEY (DiseaseId);

-- 2. Biological Target Node Table
CREATE TABLE Targets (
  TargetId STRING(36) NOT NULL,
  TargetName STRING(MAX),
  AssociatedDiseaseId STRING(36),
  CONSTRAINT FK_Target_AssociatedDisease FOREIGN KEY (AssociatedDiseaseId) REFERENCES Diseases (DiseaseId)
) PRIMARY KEY (TargetId);

-- 3. Base Compound Leaf Table
CREATE TABLE Compounds (
  CompoundId STRING(36) NOT NULL,
  ChemicalFormula STRING(MAX),
  MolecularWeight FLOAT64
) PRIMARY KEY (CompoundId);

-- 4. Drug Leaf Table (Subclass of Compound: Flattens MolecularWeight & ChemicalFormula)
CREATE TABLE Drugs (
  DrugId STRING(36) NOT NULL,
  ChemicalFormula STRING(MAX),
  MolecularWeight FLOAT64,
  ApprovalYear INT64,
  IndicatedDiseaseId STRING(36) NOT NULL,
  CONSTRAINT FK_Drug_IndicatedDisease FOREIGN KEY (IndicatedDiseaseId) REFERENCES Diseases (DiseaseId)
) PRIMARY KEY (DrugId);

-- 5. Compound-Target Binding Edge Table (ex:bindsTo with ex:affinityKi datatype property)
CREATE TABLE CompoundTargetBindings (
  CompoundId STRING(36) NOT NULL,
  TargetId STRING(36) NOT NULL,
  AffinityKi FLOAT64,
  CONSTRAINT FK_CompoundBinding_Compound FOREIGN KEY (CompoundId) REFERENCES Compounds (CompoundId),
  CONSTRAINT FK_CompoundBinding_Target FOREIGN KEY (TargetId) REFERENCES Targets (TargetId)
) PRIMARY KEY (CompoundId, TargetId);

-- 6. Drug-Target Binding Edge Table (Inherited ex:bindsTo for Drug subclass)
CREATE TABLE DrugTargetBindings (
  DrugId STRING(36) NOT NULL,
  TargetId STRING(36) NOT NULL,
  AffinityKi FLOAT64,
  CONSTRAINT FK_DrugBinding_Drug FOREIGN KEY (DrugId) REFERENCES Drugs (DrugId),
  CONSTRAINT FK_DrugBinding_Target FOREIGN KEY (TargetId) REFERENCES Targets (TargetId)
) PRIMARY KEY (DrugId, TargetId);

-- ============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH SCHEMA
-- GQL / SQL:2023 Property Graph Definition with Uniform Label Signatures
-- ============================================================================

CREATE PROPERTY GRAPH PharmaDrugDiscoveryGraph
  NODE TABLES (
    Diseases
      LABEL Disease PROPERTIES (DiseaseId, DiseaseName),
    Targets
      LABEL Target PROPERTIES (TargetId, TargetName),
    Compounds
      LABEL Compound PROPERTIES (CompoundId, ChemicalFormula, MolecularWeight),
    Drugs
      LABEL Drug PROPERTIES (DrugId, ChemicalFormula, MolecularWeight, ApprovalYear)
      LABEL Compound PROPERTIES (DrugId AS CompoundId, ChemicalFormula, MolecularWeight)
  )
  EDGE TABLES (
    -- Compound to Target Bindings
    CompoundTargetBindings
      SOURCE KEY (CompoundId) REFERENCES Compounds (CompoundId)
      DESTINATION KEY (TargetId) REFERENCES Targets (TargetId)
      LABEL BINDS_TO PROPERTIES (AffinityKi),

    -- Drug to Target Bindings (Polymorphic hierarchy edge)
    DrugTargetBindings
      SOURCE KEY (DrugId) REFERENCES Drugs (DrugId)
      DESTINATION KEY (TargetId) REFERENCES Targets (TargetId)
      LABEL BINDS_TO PROPERTIES (AffinityKi),

    -- Drug Indication for Disease
    Drugs AS DrugIndications
      SOURCE KEY (DrugId) REFERENCES Drugs (DrugId)
      DESTINATION KEY (IndicatedDiseaseId) REFERENCES Diseases (DiseaseId)
      LABEL INDICATED_FOR NO PROPERTIES,

    -- Target Association with Disease
    Targets AS TargetDiseaseAssociations
      SOURCE KEY (TargetId) REFERENCES Targets (TargetId)
      DESTINATION KEY (AssociatedDiseaseId) REFERENCES Diseases (DiseaseId)
      LABEL ASSOCIATED_WITH NO PROPERTIES
  );