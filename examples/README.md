# Example Ontologies and Schemas

This directory contains test ontologies (in Turtle `.ttl` syntax) and generated/corrected Google Cloud Spanner SQL schemas used to test and verify the RDF-to-Spanner Graph DDL translation pipeline.

---

## Files Guide

Click on any ontology filename to jump directly to its visualization section.

| File | Type | Description |
| :--- | :--- | :--- |
| **[`fintech/fintech.ttl`](#1-fintech-ontology)** | Input RDF Ontology | A valid, clean sample OWL ontology modeling a financial technology domain. It contains accounts, parties, and relationships designed to exercise all translation rules. |
| **[`pharma/pharma.ttl`](#2-pharma-ontology)** | Input RDF Ontology | A drug discovery ontology modeling chemical compounds, protein targets, and diseases, useful for testing drug indications and binding affinities. |
| **[`entertainment/entertainment.ttl`](#3-entertainment-ontology)** | Input RDF Ontology | An IMDb-like ontology modeling creative works, movies, actors, and directors, designed to test attributes/properties on edge relations (e.g. character name/billing order). |
| **[`knowledgebase/knowledgebase.ttl`](#4-knowledgebase-ontology)** | Input RDF Ontology | A Wikipedia-style ontology modeling articles, category hierarchies, and linkage networks, testing transitive category relations and symmetric linkages. |
| **[`social_fraud/social_fraud.ttl`](#5-social-fraud-ontology)** | Input RDF Ontology | A social network and fraud detection ontology modeling transactions, device sharing, and phone/IP linking, ideal for testing complex GQL patterns. |
| **[`supply_chain/supply_chain.ttl`](#6-supply-chain-ontology)** | Input RDF Ontology | A manufacturing inventory ontology tracking raw materials, sub-assemblies, and finished products, featuring transitive part hierarchies and symmetric transit routes. |
| **[`ecommerce_recommendations/ecommerce_recommendations.ttl`](#7-e-commerce--recommendations-ontology)** | Input RDF Ontology | An e-commerce purchase and behavior ontology modeling customer shopping patterns, symmetric co-purchasing, and transitive category hierarchies. |
| **[`cybersecurity_threat/cybersecurity_threat.ttl`](#8-cybersecurity-threat-ontology)** | Input RDF Ontology | A network threat intelligence ontology tracking servers, vulnerabilities, threat actors, symmetric network communication, and transitive process trees. |
| **[`healthcare_records/healthcare_records.ttl`](#9-healthcare-records-ontology)** | Input RDF Ontology | A clinical EHR ontology modeling patient encounters, practitioners, procedures, prescriptions, symmetric referral networks, and transitive etiology paths. |
| **[`smart_city_iot/smart_city_iot.ttl`](#10-smart-city-iot-ontology)** | Input RDF Ontology | A smart building and IoT sensor network ontology featuring transitive spatial containment, symmetric power grids, and telemetry threshold equivalent classes. |
| **[`dcsa_shipping/dcsa_shipping.ttl`](#11-dcsa-shipping-ontology)** | Input RDF Ontology | A DCSA industry standard-aligned logistics ontology modeling bookings, bills of lading, transport calls, containers, transitive voyage legs, and symmetric alliance vessel sharing. |
| **[`fibo_financial/fibo_financial.ttl`](#12-fibo-financial-ontology)** | Input RDF Ontology | A FIBO industry standard-aligned financial ontology modeling legal entities, corporations, loans, shares, debt instruments, and transitive parent corporate control chains. |

---

## Domain Concepts Covered

The ontologies test the translation logic against key OWL semantics:

1. **Class Inheritance & Hierarchies:**
   - Account/Subclass mappings (Table-Per-Class pattern), with inheritance preserved dynamically via `LABEL` declarations in the logical property graph.
 2. **Symmetric Relationships:**
   - The relationship `isPartnerOf` (Organization) and `linkedWith` (Article) are symmetric. The generated SQL uses constraints to store only one direction, while GQL pattern queries traverse it bidirectionally.
3. **Transitive Relationships:**
   - `subCategoryOf` (Wikipedia Category) and `subAccountOf` (Fintech Account) are transitive.
4. **Properties on Edges:**
   - Properties like `affinityKi` on `bindsTo` (Pharma) and `characterName`/`billingOrder` on `actedIn` (Entertainment) map directly to edge properties.

---

## Ontology Visualizations

These diagrams show the logical entities, properties, and relationships (symmetric and transitive) modeled by representative ontologies in this directory.

### 1. Fintech Ontology

```mermaid
classDiagram
  direction TD
  class Party {
    PartyId: INT64
    PartyType: STRING
  }
  class Person {
    Name: STRING
  }
  class Organization {
    Name: STRING
  }
  class Account {
    AccountId: INT64
    Balance: NUMERIC
    IsHighRisk: BOOL
  }
  class PersonalAccount {
    OwnerPersonId: INT64
  }
  class CorporateAccount {
    OwnerOrganizationId: INT64
  }

  Party <|-- Person
  Party <|-- Organization
  Account <|-- PersonalAccount
  Account <|-- CorporateAccount

  PersonalAccount --> Person : hasOwner
  CorporateAccount --> Organization : hasOwner
  PersonalAccount --> Person : hasSignatory (0..3)
  Organization --> Organization : "isPartnerOf (Symmetric)"
  Account --> Account : "subAccountOf (Transitive)"
```

### 2. Pharma Ontology

```mermaid
classDiagram
  direction TD
  class Compound {
    molecularWeight: DOUBLE
    chemicalFormula: STRING
  }
  class Drug {
    approvalYear: INTEGER
  }
  class Target
  class Disease

  Compound <|-- Drug
  Compound --> Target : "bindsTo (affinityKi DOUBLE)"
  Drug --> Disease : indicatedFor
  Target --> Disease : associatedWith
```

### 3. Entertainment Ontology

```mermaid
classDiagram
  direction TD
  class RolePlayer {
    name: STRING
  }
  class Actor
  class Director
  class CreativeWork {
    title: STRING
    releaseDate: DATE
  }
  class Movie
  class TVSeries

  RolePlayer <|-- Actor
  RolePlayer <|-- Director
  CreativeWork <|-- Movie
  CreativeWork <|-- TVSeries

  Actor --> CreativeWork : "actedIn (characterName STRING & billingOrder INTEGER)"
  Director --> CreativeWork : directed
```

### 4. Knowledgebase Ontology

```mermaid
classDiagram
  direction TD
  class Entity
  class Article {
    title: STRING
    wordCount: INTEGER
  }
  class Category {
    categoryName: STRING
  }
  class Author {
    username: STRING
  }

  Entity <|-- Article
  Entity <|-- Category

  Article --> Author : hasAuthor
  Article --> Category : categorizedUnder
  Article --> Article : references
  Article --> Article : "linkedWith (Symmetric)"
  Category --> Category : "subCategoryOf (Transitive)"
```

### 5. Social Fraud Ontology

```mermaid
classDiagram
  direction TD
  class Entity
  class Account {
    accountId: STRING
    accountStatus: STRING
  }
  class Device {
    deviceId: STRING
    deviceType: STRING
  }
  class IPAddress {
    ipValue: STRING
  }
  class PhoneNumber {
    phoneValue: STRING
  }

  Entity <|-- Account
  Entity <|-- Device
  Entity <|-- IPAddress
  Entity <|-- PhoneNumber

  Account --> Account : "transferredTo (amount DECIMAL & timestamp DATETIME)"
  Account --> Device : "usedDevice (firstUsed DATETIME & lastUsed DATETIME)"
  Account --> IPAddress : usedIP
  Account --> PhoneNumber : usedPhone
  IPAddress --> IPAddress : "linkedToIP (Symmetric)"
```

### 6. Supply Chain Ontology

```mermaid
classDiagram
  direction TD
  class Location
  class Warehouse
  class ManufacturingPlant
  class SupplierFacility
  class Item {
    unitCost: DECIMAL
    quantityInStock: INTEGER
  }
  class RawMaterial
  class SubAssembly
  class FinishedProduct
  class Shipment {
    shipmentTrackingNumber: STRING
    shipmentDate: DATETIME
  }
  class Carrier {
    carrierName: STRING
  }

  Location <|-- Warehouse
  Location <|-- ManufacturingPlant
  Location <|-- SupplierFacility
  Item <|-- RawMaterial
  Item <|-- SubAssembly
  Item <|-- FinishedProduct

  Item --> Item : "partOf (Transitive)"
  RawMaterial --> SupplierFacility : suppliedBy
  FinishedProduct --> ManufacturingPlant : manufacturedAt
  Item --> Warehouse : storedIn
  Shipment --> Carrier : shippedVia
  Shipment --> Location : origin
  Shipment --> Location : destination
  Location --> Location : "connectedTo (Symmetric)"
```

### 7. E-Commerce & Recommendations Ontology

```mermaid
classDiagram
  direction TD
  class Customer {
    userId: STRING
    userName: STRING
  }
  class Order {
    orderId: STRING
    orderDate: DATETIME
  }
  class Product {
    productPrice: DECIMAL
  }
  class Review {
    ratingValue: INTEGER
    reviewText: STRING
  }
  class Category {
    categoryName: STRING
  }

  Customer --> Order : placedOrder
  Order --> Product : orderContains
  Review --> Customer : reviewedBy
  Review --> Product : reviewFor
  Product --> Category : hasCategory
  Category --> Category : "subCategoryOf (Transitive)"
  Product --> Product : "frequentlyBoughtWith (Symmetric)"
```

### 8. Cybersecurity Threat Ontology

```mermaid
classDiagram
  direction TD
  class NetworkNode
  class Endpoint {
    macAddress: STRING
  }
  class Gateway
  class Server
  class Workstation
  class IPAddress {
    ipString: STRING
  }
  class Vulnerability {
    cveId: STRING
    cvssScore: DECIMAL
  }
  class ThreatActor {
    actorName: STRING
  }
  class SecurityAlert {
    severityScore: INTEGER
  }
  class UserAccount {
    username: STRING
  }
  class SystemProcess {
    processId: INTEGER
  }

  NetworkNode <|-- Endpoint
  NetworkNode <|-- Gateway
  Endpoint <|-- Server
  Endpoint <|-- Workstation

  Endpoint --> IPAddress : hasIPAddress
  Endpoint --> Vulnerability : hasVulnerability
  ThreatActor --> Vulnerability : exploits
  Endpoint --> ThreatActor : compromisedBy
  UserAccount --> Endpoint : loggedInFrom
  Endpoint --> SecurityAlert : triggeredAlert
  Endpoint --> Endpoint : "communicatedWith (Symmetric)"
  SystemProcess --> SystemProcess : "parentProcessOf (Transitive)"
```

### 9. Healthcare Records Ontology

```mermaid
classDiagram
  direction TD
  class Person
  class Patient {
    mrn: STRING
    activeConditionsCount: INTEGER
  }
  class Practitioner {
    npi: STRING
    practitionerSpecialty: STRING
  }
  class Encounter {
    encounterTimestamp: DATETIME
  }
  class Diagnosis {
    icd10Code: STRING
  }
  class Medication {
    rxNormId: STRING
  }
  class Prescription {
    dosageInstruction: STRING
  }
  class Procedure {
    cptCode: STRING
  }

  Person <|-- Patient
  Person <|-- Practitioner

  Patient --> Encounter : participatedIn
  Encounter --> Practitioner : attendedBy
  Encounter --> Diagnosis : encounterDiagnosis
  Encounter --> Prescription : orderedPrescription
  Prescription --> Medication : hasMedication
  Encounter --> Procedure : performedProcedure
  Practitioner --> Practitioner : "referredTo (Symmetric)"
  Diagnosis --> Diagnosis : "leadsToCondition (Transitive)"
```

### 10. Smart City IoT Ontology

```mermaid
classDiagram
  direction TD
  class SpatialEntity
  class CityZone
  class SmartBuilding
  class IotDevice {
    macAddress: STRING
  }
  class GatewayNode
  class Sensor
  class TemperatureSensor
  class EnergySensor
  class TelemetryObservation {
    readingValue: DECIMAL
    readingTimestamp: DATETIME
  }
  class MaintenanceJob {
    jobId: STRING
    jobStatus: STRING
  }

  SpatialEntity <|-- CityZone
  SpatialEntity <|-- SmartBuilding
  IotDevice <|-- GatewayNode
  IotDevice <|-- Sensor
  Sensor <|-- TemperatureSensor
  Sensor <|-- EnergySensor

  SpatialEntity --> SpatialEntity : "containedIn (Transitive)"
  Sensor --> GatewayNode : registeredToGateway
  IotDevice --> SmartBuilding : installedInBuilding
  Sensor --> TelemetryObservation : recordedObservation
  IotDevice --> MaintenanceJob : hasMaintenanceJob
  SmartBuilding --> SmartBuilding : "sharesMicrogridWith (Symmetric)"
```

### 11. DCSA Shipping Ontology

```mermaid
classDiagram
  direction TD
  class Booking {
    bookingReference: STRING
  }
  class BillOfLading {
    bolNumber: STRING
  }
  class Container {
    containerNumber: STRING
  }
  class Vessel {
    vesselImo: INTEGER
    vesselName: STRING
  }
  class Location {
    unLocode: STRING
  }
  class TransportCall
  class Event {
    eventClassifier: STRING
    eventDateTime: DATETIME
  }

  Booking --> BillOfLading : associatedWithBL
  Booking --> Container : bookingHasContainer
  Event --> Location : eventAtLocation
  EquipmentEvent --|> Event
  EquipmentEvent --> Container : containerInEvent
  TransportCall --> Location : callLocation
  TransportCall --> Vessel : callVessel
  Vessel --> Vessel : "sharesAllianceWith (Symmetric)"
  TransportCall --> TransportCall : "followedByLeg (Transitive)"
```

### 12. FIBO Financial Ontology

```mermaid
classDiagram
  direction TD
  class AutonomousAgent
  class LegalEntity {
    leiCode: STRING
    legalName: STRING
  }
  class Corporation
  class Partnership
  class ContractualParty
  class FinancialInstrument
  class Security {
    isinCode: STRING
  }
  class Share {
    sharesOutstanding: INTEGER
  }
  class DebtInstrument
  class Loan {
    loanAmount: DECIMAL
    interestRate: DECIMAL
  }

  AutonomousAgent <|-- LegalEntity
  LegalEntity <|-- Corporation
  LegalEntity <|-- Partnership
  AutonomousAgent <|-- ContractualParty
  FinancialInstrument <|-- Security
  Security <|-- Share
  Security <|-- DebtInstrument
  FinancialInstrument <|-- Loan

  Loan --> ContractualParty : hasLender
  Loan --> ContractualParty : hasBorrower
  Security --> LegalEntity : issuedBy
  Share --> LegalEntity : ownedBy
  Loan --> LegalEntity : guaranteedBy
  LegalEntity --> LegalEntity : "sharesGuarantorRiskWith (Symmetric)"
  LegalEntity --> LegalEntity : "controlledBy (Transitive)"
```

---

## Running Tests with Examples

### 1. Run AI Translation Only
```bash
rdf-spanner-translator translate \
  -i examples/pharma/pharma.ttl \
  -o output/pharma_schema.sql
```

### 2. Run Pipeline with Validation & Self-Correction
```bash
export SPANNER_DATABASE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>/databases/<DATABASE_ID>"

rdf-spanner-translator run \
  -i examples/entertainment/entertainment.ttl \
  -o output/entertainment_schema.sql \
  --mcp-tool "create_database"
```
