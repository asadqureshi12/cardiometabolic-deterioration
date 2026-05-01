-- =============================================================================
-- P3: Clinical Deterioration Monitoring System
-- File:    clean_data.sql
-- Purpose: Data integrity fixes and FHIR field preparation
-- Run in:  DB Browser — after load_data.py completes
-- =============================================================================
-- SECTIONS (updated):
--   1.  Delete orphaned records (2 missing patients)
--   2.  Delete corrupt medications (stop before start)
--   3.  Correct off-by-one observation dates (Synthea delivery encounter artefact)
--   4.  Empty string to NULL normalisation
--   5.  is_active flag — conditions
--   6.  is_active flag — medications
--   7.  FHIR: encounter fhir_status derived from end date
--   8.  FHIR: encounter fhir_class mapped from Synthea encounter class
--   9.  FHIR: snomed_description_corrected from snomed_icd10_map
--  10.  FHIR: icd10_code and icd10_desc populated from snomed_icd10_map
--  11.  FHIR: observation_status set to final for numeric, unknown for text
--  12.  FHIR: verification_status confirmed (default already set in schema)
--  13.  FHIR: is_synthetic set to 1 for all patients (default already set)
--  14.  Derived: age calculated from birthdate
--  15.  Derived: deprivation_decile from income
--  16.  Derived: observation_window_start from earliest observation date
--  17.  Delete negative LDL (Friedewald artefact — mathematically impossible)
--  18.  Flag LDL 0-20 mg/dL (Friedewald artefact, PCSK9 ruled out)
--  19.  Flag physiologically impossible values (RCPath floor)
--  20.  Step 0: Administrative exclusion flag (semantic tag filter)
--  21.  Step 0: ICD-10 field correction (wrong field routing)
--  22.  Step 0: SNOMED description backfill
--  23.  Step 0 — Explicit clinical_active label
--  24.  Validation counts
-- =============================================================================

-- =============================================================================
-- SECTION 1: Delete orphaned records
-- Patient IDs with no parent row in patients table
-- Affects: 2d225d70 and 7a1262f2 only (confirmed by Sprint 1 validation)
-- =============================================================================

DELETE FROM conditions
WHERE patient_id NOT IN (SELECT patient_id FROM patients);

DELETE FROM encounters
WHERE patient_id NOT IN (SELECT patient_id FROM patients);

DELETE FROM observations
WHERE patient_id NOT IN (SELECT patient_id FROM patients);

DELETE FROM medications
WHERE patient_id NOT IN (SELECT patient_id FROM patients);

-- =============================================================================
-- SECTION 2: Delete corrupt medications
-- stop_date before start_date — 57 records across 14 patients
-- Deletion preferred over repair as stop date is unverifiable
-- =============================================================================

DELETE FROM medications
WHERE stop_date IS NOT NULL
  AND start_date IS NOT NULL
  AND stop_date < start_date;

-- =============================================================================
-- SECTION 3: Correct off-by-one observation dates
-- 475 observations dated exactly 1 day before patient birthdate
-- Cause: Synthea delivery encounter generates observations day before birthdate
-- Fix: set observation_date = birthdate where gap is exactly 1 day
-- =============================================================================

UPDATE observations
SET observation_date = (
    SELECT p.birthdate
    FROM patients p
    WHERE p.patient_id = observations.patient_id
)
WHERE EXISTS (
    SELECT 1 FROM patients p
    WHERE p.patient_id = observations.patient_id
      AND CAST(JULIANDAY(p.birthdate) - JULIANDAY(observations.observation_date) AS INTEGER) = 1
);

-- =============================================================================
-- SECTION 4: Empty string to NULL normalisation
-- Synthea writes empty strings in some fields instead of NULL
-- =============================================================================

UPDATE encounters
SET reason_description = NULL
WHERE TRIM(reason_description) = '';

UPDATE encounters
SET reason_code = NULL
WHERE TRIM(reason_code) = '';

UPDATE encounters
SET encounter_class = NULL
WHERE TRIM(encounter_class) = '';

UPDATE observations
SET units = NULL
WHERE TRIM(units) = '';

UPDATE observations
SET category = NULL
WHERE TRIM(category) = '';

UPDATE medications
SET reason_description = NULL
WHERE TRIM(reason_description) = '';

UPDATE medications
SET reason_code = NULL
WHERE TRIM(reason_code) = '';

-- =============================================================================
-- SECTION 5: is_active flag — conditions
-- active = 1 where resolution_date is NULL
-- resolved = 0 where resolution_date is populated
-- =============================================================================

UPDATE conditions
SET is_active = CASE
    WHEN resolution_date IS NULL THEN 1
    ELSE 0
END;

-- =============================================================================
-- SECTION 6: is_active flag — medications
-- active = 1 where stop_date is NULL
-- stopped = 0 where stop_date is populated
-- =============================================================================

UPDATE medications
SET is_active = CASE
    WHEN stop_date IS NULL THEN 1
    ELSE 0
END;

-- =============================================================================
-- SECTION 7: FHIR encounter fhir_status
-- finished = encounter_end is populated
-- in-progress = encounter_end is NULL
-- Required field for FHIR R4 Encounter resource
-- =============================================================================

UPDATE encounters
SET fhir_status = CASE
    WHEN encounter_end IS NOT NULL THEN 'finished'
    ELSE 'in-progress'
END;

-- =============================================================================
-- SECTION 8: FHIR encounter fhir_class
-- Maps Synthea encounterclass to FHIR ActEncounterCode vocabulary
-- ambulatory → AMB, emergency → EMER, inpatient → IMP,
-- outpatient → AMB, virtual → VR, home → HH, hospice → HH, snf → IMP
-- =============================================================================

UPDATE encounters
SET fhir_class = CASE LOWER(encounter_class)
    WHEN 'ambulatory'  THEN 'AMB'
    WHEN 'emergency'   THEN 'EMER'
    WHEN 'inpatient'   THEN 'IMP'
    WHEN 'outpatient'  THEN 'AMB'
    WHEN 'virtual'     THEN 'VR'
    WHEN 'home'        THEN 'HH'
    WHEN 'hospice'     THEN 'HH'
    WHEN 'snf'         THEN 'IMP'
    WHEN 'urgentcare'  THEN 'EMER'
    WHEN 'wellness'    THEN 'AMB'
    ELSE 'AMB'
END;

-- =============================================================================
-- SECTION 9: FHIR SNOMED description corrections
-- Replaces Synthea abbreviated display names with canonical SNOMED CT
-- preferred terms from P2-validated snomed_icd10_map reference table
-- Fixes the largest category of P2 FHIR validator errors
-- =============================================================================

UPDATE conditions
SET snomed_description_corrected = (
    SELECT m.snomed_desc_corrected
    FROM snomed_icd10_map m
    WHERE m.snomed_code = conditions.snomed_code
)
WHERE EXISTS (
    SELECT 1 FROM snomed_icd10_map m
    WHERE m.snomed_code = conditions.snomed_code
);

-- =============================================================================
-- SECTION 10: ICD-10 code and description population
-- Populates icd10_code and icd10_desc from snomed_icd10_map
-- Dual terminology coding required for FHIR R4 UK Core Condition resource
-- =============================================================================

UPDATE conditions
SET
    icd10_code = (
        SELECT m.icd10_code
        FROM snomed_icd10_map m
        WHERE m.snomed_code = conditions.snomed_code
    ),
    icd10_desc = (
        SELECT m.icd10_desc
        FROM snomed_icd10_map m
        WHERE m.snomed_code = conditions.snomed_code
    )
WHERE EXISTS (
    SELECT 1 FROM snomed_icd10_map m
    WHERE m.snomed_code = conditions.snomed_code
);

-- =============================================================================
-- SECTION 11: FHIR observation_status
-- final for numeric observations with a valid value
-- unknown for text or missing value observations
-- Required field for FHIR R4 Observation resource
-- =============================================================================

UPDATE observations
SET observation_status = CASE
    WHEN value_numeric IS NOT NULL THEN 'final'
    WHEN value_categorical IS NOT NULL AND TRIM(value_categorical) != '' THEN 'final'
    ELSE 'unknown'
END;

-- =============================================================================
-- SECTION 12: verification_status
-- Already defaulted to 'confirmed' in schema for all conditions
-- No update needed — confirmed is correct for Synthea generated records
-- =============================================================================

-- =============================================================================
-- SECTION 13: is_synthetic
-- Already defaulted to 1 in schema for all patients
-- No update needed
-- =============================================================================

-- =============================================================================
-- SECTION 14: Age calculation
-- Derived from birthdate relative to snapshot date 2026-04-06
-- =============================================================================

UPDATE patients
SET age = CAST(
    (JULIANDAY('2026-04-06') - JULIANDAY(birthdate)) / 365.25
AS INTEGER)
WHERE birthdate IS NOT NULL;

-- =============================================================================
-- SECTION 15: Deprivation decile from income
-- Proxy for UK IMD — income ranked into 10 equal bands
-- 1 = most deprived (lowest income), 10 = least deprived (highest income)
-- Documented limitation: real deployment uses NHS Digital IMD scores
-- =============================================================================

UPDATE patients
SET deprivation_decile = CASE
    WHEN income < 15000  THEN 1
    WHEN income < 20000  THEN 2
    WHEN income < 25000  THEN 3
    WHEN income < 30000  THEN 4
    WHEN income < 40000  THEN 5
    WHEN income < 50000  THEN 6
    WHEN income < 60000  THEN 7
    WHEN income < 75000  THEN 8
    WHEN income < 100000 THEN 9
    ELSE 10
END
WHERE income IS NOT NULL;

-- =============================================================================
-- SECTION 16: Observation window start
-- Earliest observation date per patient
-- Used by scoring engine to determine longitudinal data availability
-- =============================================================================

UPDATE patients
SET observation_window_start = (
    SELECT MIN(o.observation_date)
    FROM observations o
    WHERE o.patient_id = patients.patient_id
)
WHERE EXISTS (
    SELECT 1 FROM observations o
    WHERE o.patient_id = patients.patient_id
);

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 17: DELETE NEGATIVE LDL (FRIEDEWALD ARTEFACT)
-- ─────────────────────────────────────────────────────────────────────────────
-- Negative LDL is mathematically impossible. The Friedewald equation
-- (LDL = Total Cholesterol - HDL - Triglycerides/5) produces negative
-- results when triglycerides exceed approximately 400 mg/dL.
-- A negative cholesterol concentration has no biological interpretation.
-- RCPath guidance: values below 0 represent analytical failure not measurement.
-- Decision: delete. No clinical information is lost.
DELETE FROM observations
WHERE loinc_code = '18262-6'
  AND value_numeric < 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 18: FLAG LDL 0-20 MG/DL (FRIEDEWALD ARTEFACT, PCSK9 RULED OUT)
-- ─────────────────────────────────────────────────────────────────────────────
-- LDL between 0 and 20 mg/dL is physiologically implausible without
-- aggressive lipid-lowering therapy (PCSK9 inhibitors: evolocumab,
-- alirocumab, inclisiran). A medication table query confirmed zero patients
-- with LDL < 20 are prescribed any PCSK9 inhibitor or lipid-lowering biologic.
-- These values are therefore Friedewald artefacts caused by elevated
-- triglycerides producing near-zero calculated LDL.
-- FOURIER and ODYSSEY trials documented genuine LDL as low as 15 mg/dL
-- in treated patients — deletion is not justified without PCSK9 confirmation.
-- Decision: retain record, exclude from trajectory scoring.
-- Reference: RCPath laboratory medicine guidelines; Sabatine et al. NEJM 2017.
UPDATE observations
SET value_excluded = 1
WHERE loinc_code = '18262-6'
  AND value_numeric >= 0
  AND value_numeric < 20;

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 19: FLAG PHYSIOLOGICALLY IMPOSSIBLE VALUES (RCPATH FLOOR)
-- ─────────────────────────────────────────────────────────────────────────────
-- HbA1c below 2.0%:
-- RCPath position: values below 2.0% are below the analytical reliability
-- floor and likely represent haemoglobin variant interference or severe
-- haemolytic anaemia with near-zero red cell lifespan. Not usable for
-- glycaemic trajectory scoring.
-- Reference: RCPath Guidelines for the Evaluation of HbA1c Analysers.
UPDATE observations
SET value_excluded = 1
WHERE loinc_code = '4548-4'
  AND value_numeric < 2.0;

-- Systolic BP below 50 mmHg:
-- A systolic BP of 50 mmHg is incompatible with conscious ambulatory
-- monitoring. Synthea generates routine outpatient encounter observations.
-- A single reading of 48 mmHg in this context is a generation artefact.
-- Physiologically possible only in cardiac arrest or terminal shock —
-- neither of which would produce a routine outpatient observation record.
-- Reference: RCPath clinical biochemistry reference ranges;
-- NICE NG136 hypertension guideline lower measurement bounds.
UPDATE observations
SET value_excluded = 1
WHERE loinc_code = '8480-6'
  AND value_numeric < 50;

-- =============================================================================
-- SECTION 20: Step 0 — Administrative exclusion flag
-- Purpose: Flag non-clinical SNOMED concepts using semantic tag
-- Rationale: SNOMED CT hierarchy encodes concept type in the
--            fully specified name suffix. (person), (procedure),
--            and (observable entity) are never clinical conditions.
--            This is a non-destructive flag — no rows deleted.
-- Note: complication_category column created in schema.sql Sprint 1
-- =============================================================================

UPDATE conditions
SET complication_category = 'excluded_admin'
WHERE (
    snomed_description LIKE '%(person)'
    OR snomed_description LIKE '%(procedure)'
    OR snomed_description LIKE '%(observable entity)'
)
AND complication_category IS NULL;


-- =============================================================================
-- SECTION 21: Step 0 — ICD-10 field correction
-- Purpose: Route ICD-10 codes misfiled in snomed_code column
-- Rationale: Synthea CSV loader placed some ICD-10 codes into
--            the SNOMED code field. These are identifiable by
--            pattern: capital letter + 2 digits + optional chars.
--            Value is copied to icd10_code only if icd10_code
--            is currently NULL — preserves existing dual-coded rows.
--            snomed_code column is NOT nulled out — FHIR export
--            layer resolves coding system dynamically at export time.
-- Known wrong-field codes confirmed in data:
--            K-codes (dental), C-codes (oncology), Z-codes (admin),
--            S-codes (injury), R-codes (symptoms), M-codes (MSK),
--            D-codes (neoplasms)
-- =============================================================================

UPDATE conditions
SET
    icd10_code = CASE
        WHEN icd10_code IS NULL
         AND snomed_code GLOB '[A-Z][0-9][0-9].*'
        THEN snomed_code
        ELSE icd10_code
    END,
    complication_category = CASE
        WHEN complication_category IS NULL
        THEN 'excluded_field_error'
        ELSE complication_category
    END
WHERE snomed_code GLOB '[A-Z][0-9][0-9]*'
  AND snomed_code NOT GLOB '[0-9]*';


-- =============================================================================
-- SECTION 22: Step 0 — SNOMED description backfill
-- Purpose: Populate snomed_description_corrected from
--          snomed_description where corrected is NULL
-- Rationale: Sprint 1 FHIR section 9 populated
--            snomed_description_corrected only for codes present
--            in snomed_icd10_map (141 entries). All other codes
--            were left NULL. This section closes that gap.
--            No overwrite of existing corrected descriptions.
-- =============================================================================

UPDATE conditions
SET snomed_description_corrected = snomed_description
WHERE snomed_description_corrected IS NULL
  AND snomed_description IS NOT NULL;

-- =============================================================================
-- SECTION 23: Step 0 — Explicit clinical_active label
-- Purpose: Assign explicit state to all rows not excluded by Steps 0
-- Rationale: complication_category NULL is ambiguous — it represents
--            both "not yet classified" and "not excluded". Making the
--            inclusion state explicit ensures Step 1 chronic classification
--            operates on a defined population with no hidden logic dependency.
--            Every row now has an explicit state label.
-- =============================================================================

UPDATE conditions
SET complication_category = 'clinical_active'
WHERE complication_category IS NULL;

-- =============================================================================
-- SECTION 24: VALIDATION COUNTS
-- =============================================================================

SELECT 'Orphaned conditions'                        AS check_name, COUNT(*) AS result FROM conditions WHERE patient_id NOT IN (SELECT patient_id FROM patients)
UNION ALL
SELECT 'Orphaned observations',                      COUNT(*) FROM observations WHERE patient_id NOT IN (SELECT patient_id FROM patients)
UNION ALL
SELECT 'Orphaned medications',                       COUNT(*) FROM medications WHERE patient_id NOT IN (SELECT patient_id FROM patients)
UNION ALL
SELECT 'Corrupt medications',                        COUNT(*) FROM medications WHERE stop_date IS NOT NULL AND stop_date < start_date
UNION ALL
SELECT 'Conditions NULL is_active',                  COUNT(*) FROM conditions WHERE is_active IS NULL
UNION ALL
SELECT 'Medications NULL is_active',                 COUNT(*) FROM medications WHERE is_active IS NULL
UNION ALL
SELECT 'Encounters NULL fhir_status',                COUNT(*) FROM encounters WHERE fhir_status IS NULL
UNION ALL
SELECT 'Conditions with ICD-10',                     COUNT(*) FROM conditions WHERE icd10_code IS NOT NULL
UNION ALL
SELECT 'Conditions without ICD-10',                  COUNT(*) FROM conditions WHERE icd10_code IS NULL
UNION ALL
SELECT 'Patients with age',                          COUNT(*) FROM patients WHERE age IS NOT NULL
UNION ALL
SELECT 'Patients with obs window',                   COUNT(*) FROM patients WHERE observation_window_start IS NOT NULL
UNION ALL
SELECT 'Obs status final',                           COUNT(*) FROM observations WHERE observation_status = 'final'
UNION ALL
SELECT 'Obs status unknown',                         COUNT(*) FROM observations WHERE observation_status = 'unknown'
UNION ALL
SELECT 'Value excluded — HbA1c < 2.0',               COUNT(*) FROM observations WHERE loinc_code = '4548-4' AND value_excluded = 1
UNION ALL
SELECT 'Value excluded — LDL 0-20',                  COUNT(*) FROM observations WHERE loinc_code = '18262-6' AND value_excluded = 1
UNION ALL
SELECT 'Value excluded — Systolic BP < 50',          COUNT(*) FROM observations WHERE loinc_code = '8480-6' AND value_excluded = 1
UNION ALL
SELECT 'Negative LDL deleted',                       COUNT(*) FROM observations WHERE loinc_code = '18262-6' AND value_numeric < 0
UNION ALL
SELECT 'Total value_excluded flags',                 COUNT(*) FROM observations WHERE value_excluded = 1
UNION ALL
SELECT 'Step0 — excluded_admin flag',                COUNT(*) FROM conditions WHERE complication_category = 'excluded_admin'
UNION ALL
SELECT 'Step0 — excluded_field_error flag',          COUNT(*) FROM conditions WHERE complication_category = 'excluded_field_error'
UNION ALL
SELECT 'Step0 — field_error icd10 routed',           COUNT(*) FROM conditions WHERE complication_category = 'excluded_field_error' AND icd10_code IS NOT NULL
UNION ALL
SELECT 'Step0 — clinical_active population',        COUNT(*) FROM conditions WHERE complication_category = 'clinical_active'
UNION ALL
SELECT 'Step0 — description corrected backfill',     COUNT(*) FROM conditions WHERE snomed_description_corrected IS NOT NULL
UNION ALL
SELECT 'Step0 — description corrected still NULL',   COUNT(*) FROM conditions WHERE snomed_description_corrected IS NULL
UNION ALL
SELECT 'Step0 — field_conflict flag',               COUNT(*) FROM conditions WHERE complication_category = 'field_conflict'
UNION ALL
SELECT 'Step0 — clean clinical population',         COUNT(*) FROM conditions WHERE complication_category IS NULL;


-- =============================================================================
-- END OF clean_data.sql
-- Next: run prepare_cohort.sql (Sprint 2 — chronic classification and scoring)
-- =============================================================================
