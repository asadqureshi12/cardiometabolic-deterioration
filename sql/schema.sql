-- =============================================================================
-- P3: Clinical Deterioration Monitoring System
-- File:    schema.sql
-- Version: 3.0
-- Engine:  SQLite
-- Changes from v2.0:
--   patients:    + is_synthetic flag
--   conditions:  + verification_status, icd10_code, icd10_desc,
--                  snomed_system, snomed_edition, snomed_description_corrected,
--                  complication_category, complication_driver, is_index_condition
--   encounters:  + fhir_status, fhir_class
--   observations:+ observation_status, loinc_system
--   medications: + medication_system
--   NEW TABLE 9:   snomed_icd10_map (reference table, P2-validated)
-- =============================================================================

PRAGMA foreign_keys = OFF;
PRAGMA journal_mode = WAL;

-- -----------------------------------------------------------------------------
-- TABLE 1: patients
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patients (
    patient_id                  TEXT    PRIMARY KEY,
    nhs_number_hash             TEXT    NOT NULL UNIQUE,
    birthdate                   DATE,
    deathdate                   DATE,
    age                         INTEGER,
    sex                         TEXT,
    race                        TEXT,
    ethnicity                   TEXT,
    deprivation_decile          INTEGER,
    income                      REAL,
    segment                     TEXT,
    cardiometabolic_confirmed   INTEGER DEFAULT 0,
    observation_window_start    DATE,
    is_synthetic                INTEGER DEFAULT 1,
    city                        TEXT,
    state                       TEXT,
    created_at                  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- TABLE 2: conditions
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conditions (
    condition_id                INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id                  TEXT    NOT NULL REFERENCES patients(patient_id),
    snomed_code                 TEXT    NOT NULL,
    snomed_description          TEXT    NOT NULL,
    snomed_description_corrected TEXT,
    snomed_system               TEXT    DEFAULT 'http://snomed.info/sct',
    snomed_edition              TEXT    DEFAULT 'US',
    icd10_code                  TEXT,
    icd10_desc                  TEXT,
    condition_name              TEXT    NOT NULL,
    complication_category       TEXT,
    complication_driver         TEXT,
    is_index_condition          INTEGER DEFAULT 0,
    is_active                   INTEGER,
    verification_status         TEXT    DEFAULT 'confirmed',
    onset_date                  DATE,
    resolution_date             DATE,
    encounter_id                TEXT,
    recorded_date               DATE,
    UNIQUE (patient_id, snomed_code)
);

-- -----------------------------------------------------------------------------
-- TABLE 3: encounters
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS encounters (
    encounter_id            TEXT    PRIMARY KEY,
    patient_id              TEXT    NOT NULL REFERENCES patients(patient_id),
    encounter_date          DATE,
    encounter_end           DATE,
    encounter_class         TEXT,
    fhir_status             TEXT,
    fhir_class              TEXT,
    reason_code             TEXT,
    reason_description      TEXT,
    is_cardiometabolic      INTEGER DEFAULT 0,
    recorded_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- TABLE 4: observations
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS observations (
    observation_id          INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id              TEXT    NOT NULL REFERENCES patients(patient_id),
    encounter_id            TEXT,
    observation_date        DATE,
    category                TEXT,
    loinc_code              TEXT    NOT NULL,
    loinc_system            TEXT    DEFAULT 'http://loinc.org',
    description             TEXT    NOT NULL,
    value                   TEXT,
    value_numeric           REAL,
    value_categorical       TEXT,
    units                   TEXT,
    observation_type        TEXT,
    observation_status      TEXT    DEFAULT 'final',
    value_excluded          INTEGER DEFAULT 0,
    is_high_value           INTEGER DEFAULT 0,
    recorded_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (patient_id, encounter_id, loinc_code, observation_date)
);

-- -----------------------------------------------------------------------------
-- TABLE 5: medications
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS medications (
    medication_id           INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id              TEXT    NOT NULL REFERENCES patients(patient_id),
    encounter_id            TEXT,
    medication_code         TEXT    NOT NULL,
    medication_system       TEXT    DEFAULT 'http://www.nlm.nih.gov/research/umls/rxnorm',
    medication_description  TEXT    NOT NULL,
    start_date              DATE,
    stop_date               DATE,
    is_active               INTEGER,
    reason_code             TEXT,
    reason_description      TEXT,
    dispenses               INTEGER,
    total_cost              REAL,
    recorded_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- TABLE 6: deterioration_scores
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deterioration_scores (
    score_id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id                  TEXT    NOT NULL REFERENCES patients(patient_id),
    score_version               TEXT    NOT NULL DEFAULT 'v1.0',
    scoring_date                DATE    NOT NULL,
    hba1c_trajectory            REAL,
    egfr_trajectory             REAL,
    bp_trajectory               REAL,
    lipid_trajectory            REAL,
    complication_progression    REAL,
    cardiovascular_trajectory   REAL,
    metabolic_trajectory        REAL,
    composite_score             REAL,
    deterioration_band          TEXT,
    observation_window_days     INTEGER,
    low_confidence_flag         INTEGER DEFAULT 0,
    scoring_notes               TEXT,
    scored_at                   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- TABLE 7: clinical_alerts
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clinical_alerts (
    alert_id                INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id              TEXT    NOT NULL REFERENCES patients(patient_id),
    alert_level             TEXT    NOT NULL,
    triggering_observation  TEXT,
    triggering_condition    TEXT,
    recommended_action      TEXT,
    alert_status            TEXT    DEFAULT 'Generated',
    generated_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- TABLE 8: clinical_problem_log
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clinical_problem_log (
    log_id              INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_reference     TEXT    NOT NULL UNIQUE,
    problem_statement   TEXT    NOT NULL,
    clinical_decision   TEXT    NOT NULL,
    rationale           TEXT    NOT NULL,
    limitation          TEXT    NOT NULL,
    linked_table        TEXT,
    linked_field        TEXT,
    decision_type       TEXT,
    sprint              TEXT,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- TABLE 9: snomed_icd10_map
-- Reference table. Sourced from P2 validated mapping (129 codes) +
-- P3 extensions for cardiometabolic codes absent from P2.
-- Populated by load_snomed_map.py before load_data.py runs.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS snomed_icd10_map (
    snomed_code             TEXT    PRIMARY KEY,
    icd10_code              TEXT    NOT NULL,
    icd10_desc              TEXT    NOT NULL,
    snomed_desc_corrected   TEXT    NOT NULL,
    p2_category             TEXT,
    source                  TEXT    DEFAULT 'P2-validated'
);

-- =============================================================================
-- INDEXES
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_patients_segment      ON patients(segment);
CREATE INDEX IF NOT EXISTS idx_patients_confirmed    ON patients(cardiometabolic_confirmed);
CREATE INDEX IF NOT EXISTS idx_conditions_patient    ON conditions(patient_id);
CREATE INDEX IF NOT EXISTS idx_conditions_snomed     ON conditions(snomed_code);
CREATE INDEX IF NOT EXISTS idx_conditions_active     ON conditions(is_active);
CREATE INDEX IF NOT EXISTS idx_conditions_category   ON conditions(complication_category);
CREATE INDEX IF NOT EXISTS idx_conditions_icd10      ON conditions(icd10_code);
CREATE INDEX IF NOT EXISTS idx_encounters_patient    ON encounters(patient_id);
CREATE INDEX IF NOT EXISTS idx_encounters_date       ON encounters(encounter_date);
CREATE INDEX IF NOT EXISTS idx_obs_patient           ON observations(patient_id);
CREATE INDEX IF NOT EXISTS idx_obs_loinc             ON observations(loinc_code);
CREATE INDEX IF NOT EXISTS idx_obs_date              ON observations(observation_date);
CREATE INDEX IF NOT EXISTS idx_obs_high_value        ON observations(is_high_value);
CREATE INDEX IF NOT EXISTS idx_meds_patient          ON medications(patient_id);
CREATE INDEX IF NOT EXISTS idx_meds_active           ON medications(is_active);
CREATE INDEX IF NOT EXISTS idx_scores_patient        ON deterioration_scores(patient_id);
CREATE INDEX IF NOT EXISTS idx_scores_band           ON deterioration_scores(deterioration_band);
CREATE INDEX IF NOT EXISTS idx_alerts_patient        ON clinical_alerts(patient_id);
CREATE INDEX IF NOT EXISTS idx_alerts_level          ON clinical_alerts(alert_level);
CREATE INDEX IF NOT EXISTS idx_snomed_map            ON snomed_icd10_map(snomed_code);

-- =============================================================================
-- END OF SCHEMA v3.0
-- Run order:
--   1. schema.sql       (this file — in DB Browser)
--   2. load_snomed_map.py
--   3. load_data.py
--   4. clean_data.sql
--   5. fhir_pilot.py    (2-patient FHIR export for validation)
-- =============================================================================
