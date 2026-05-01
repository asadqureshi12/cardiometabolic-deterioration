-- =============================================================================
-- P3: Cardiometabolic Deterioration Monitoring System
-- File:    load_reference.sql
-- Purpose: Create and populate clinical reference tables
-- Run in:  DB Browser — after schema.sql, before prepare_cohort.sql
-- Output tables: nice_thresholds, scoring_constants,
--                snomed_icd10_map_p3, project_reference
-- =============================================================================

-- =============================================================================
-- SECTION 1: nice_thresholds
-- NICE guideline-grounded exceedance thresholds
-- Sources: NICE NG136 (SBP), NICE NG28 (HbA1c, BMI), NICE NG238 (LDL)
-- =============================================================================

DROP TABLE IF EXISTS nice_thresholds;

CREATE TABLE nice_thresholds (
    threshold_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    loinc_code       TEXT NOT NULL,
    marker_name      TEXT NOT NULL,
    cvd_status       TEXT NOT NULL,
    t_value          REAL NOT NULL,
    unit             TEXT,
    nice_rule        TEXT,
    guideline_source TEXT,
    effective_date   DATE
);

INSERT INTO nice_thresholds
    (loinc_code, marker_name, cvd_status, t_value, unit, nice_rule, guideline_source, effective_date)
VALUES
    ('8480-6',  'Systolic BP',     'ALL',  140.0,  'mmHg',   'Treat if clinic BP >= 140/90 mmHg',                                                                                              'NICE_NG136', '2026-04-06'),
    ('4548-4',  'HbA1c',           'ALL',  7.0,    '%',      'Target HbA1c <= 53 mmol/mol (7.0%) for most adults with T2DM. Synthea stores HbA1c as NGSP %.',                                 'NICE_NG28',  '2026-04-06'),
    ('18262-6', 'LDL Cholesterol', 'CVD',  77.3,   'mg/dL',  'Target LDL < 2.0 mmol/L (77.3 mg/dL) if established or recent CVD present. Synthea stores LDL in mg/dL.',                      'NICE_NG238', '2026-04-06'),
    ('18262-6', 'LDL Cholesterol', 'NONE', 116.0,  'mg/dL',  'Target LDL < 3.0 mmol/L (116.0 mg/dL) if no established CVD. Synthea stores LDL in mg/dL.',                                    'NICE_NG238', '2026-04-06'),
    ('39156-5', 'BMI',             'ALL',  25.0,   'kg/m2',  'Healthy weight threshold for adults',                                                                                            'NICE_NG28',  '2026-04-06');

-- =============================================================================
-- SECTION 2: scoring_constants
-- Observation window and minimum data requirements
-- Sources: NICE NG136, ACC/AHA 2019
-- =============================================================================

DROP TABLE IF EXISTS scoring_constants;

CREATE TABLE scoring_constants (
    constants_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    window_start  DATE    NOT NULL,
    window_end    DATE    NOT NULL,
    min_readings  INTEGER NOT NULL,
    min_months    INTEGER NOT NULL,
    rationale     TEXT,
    source        TEXT
);

INSERT INTO scoring_constants
    (window_start, window_end, min_readings, min_months, rationale, source)
VALUES (
    '2025-04-06',
    '2026-04-06',
    2,
    3,
    'Tiered data sufficiency model:
- DATA_SUFFICIENT: >=2 readings AND >=3 distinct months → full scoring
- PARTIALLY_SUFFICIENT: >=2 readings AND >=2 distinct months → severity only
- DATA_INSUFFICIENT: <2 readings OR <2 distinct months → excluded
Trajectory requires >=3 distinct months. Severity valid from >=2 readings.
Synthea generates sparse longitudinal sampling; tiering preserves signal without inflating trends.',
    'NICE_NG136, ACC/AHA_2019'
);

-- =============================================================================
-- SECTION 3: snomed_icd10_map_p3
-- 46-row SNOMED CT to ICD-10 mapping
-- Source: NHS Digital TRUD ExtendedMap GB_20260311
-- FSN descriptions: NHS Digital TRUD SNOMED CT MonolithRF2 GB_20260311
-- =============================================================================

DROP TABLE IF EXISTS snomed_icd10_map_p3;

CREATE TABLE snomed_icd10_map_p3 (
    snomed_code        TEXT PRIMARY KEY,
    icd10_code         TEXT,
    mapping_source     TEXT,
    notes              TEXT,
    snomed_description TEXT,
    icd10_description  TEXT,
    description_source TEXT
);

INSERT INTO snomed_icd10_map_p3 VALUES ('109838007','C18.8','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Overlapping lesion of colon','Overlapping malignant neoplasm of colon (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');
INSERT INTO snomed_icd10_map_p3 VALUES ('109989006','C90.0','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Multiple myeloma','Multiple myeloma (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('110359009','F79','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Intellectual disability unspecified — F70-F73 available if severity known, SNOMED concept non-specific','Intellectual disability (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('126906006','D40.0','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Neoplasm of uncertain behaviour — SNOMED ambiguous, cautious choice','Neoplasm of prostate (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('127013003','E11.21','NHS_Digital_TRUD_ExtendedMap_GB_20260311','T2DM with diabetic nephropathy','Disorder of kidney due to diabetes mellitus (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');
INSERT INTO snomed_icd10_map_p3 VALUES ('128613002','G40.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Semantic duplicate — same ICD-10 as 84757009, Synthea duplication not mapping error','Seizure disorder (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('1501000119109','E11.311','NHS_Digital_TRUD_ExtendedMap_GB_20260311','T2DM with macular oedema','Proliferative retinopathy due to type 2 diabetes mellitus (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');
INSERT INTO snomed_icd10_map_p3 VALUES ('1551000119108','E11.39','NHS_Digital_TRUD_ExtendedMap_GB_20260311','T2DM other diabetic ophthalmic complication','Nonproliferative retinopathy due to type 2 diabetes mellitus (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');
INSERT INTO snomed_icd10_map_p3 VALUES ('157141000119108','E11.22','NHS_Digital_TRUD_ExtendedMap_GB_20260311','T2DM with diabetic CKD','Proteinuria due to type 2 diabetes mellitus (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('162864005','E66.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Obesity unspecified','Body mass index 30+ - obesity (finding)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('185086009','J44.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','COPD unspecified — J44.1 rejected, exacerbation not explicitly encoded in SNOMED concept','Chronic obstructive bronchitis (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('195967001','J45.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Asthma unspecified — paediatric codes excluded from cohort, all asthma scoring consolidated here','Asthma (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('230265002','F00.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Dementia in Alzheimers unspecified — F00 for dementia manifestation, G30 for pathology','Familial Alzheimer''s disease of early onset (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');
INSERT INTO snomed_icd10_map_p3 VALUES ('254632001','C34.90','NHS_Digital_TRUD_ExtendedMap_GB_20260311','SCLC — histology not location, C34.10 rejected, unspecified correct','Small cell carcinoma of lung (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('254637007','C34.90','NHS_Digital_TRUD_ExtendedMap_GB_20260311','NSCLC — lobe not specified in SNOMED, unspecified correct, C34.10 rejected','Non-small cell lung cancer (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('254837009','C50.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Breast cancer unspecified','Malignant neoplasm of breast (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('26929004','G30.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Alzheimers disease unspecified — G30 for pathology, F00 for dementia manifestation','Alzheimer''s disease (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('302870006','E78.1','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Pure hypertriglyceridaemia — direct mapping','Hypertriglyceridemia (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('363406005','C18.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Colon cancer unspecified','Malignant neoplasm of colon (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('368581000119106','E11.40','NHS_Digital_TRUD_ExtendedMap_GB_20260311','T2DM with diabetic neuropathy unspecified','Neuropathy due to type 2 diabetes mellitus (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('370143000','F32.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Depressive episode unspecified','Major depressive disorder (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('408512008','E66.01','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Morbid obesity due to excess calories','Body mass index 40+ - severely obese (finding)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('414545008','I25.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Chronic IHD unspecified — Synthea does not specify subtype','Ischemic heart disease (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');
INSERT INTO snomed_icd10_map_p3 VALUES ('424132000','C34.90','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Lung cancer unspecified','Non-small cell carcinoma of lung, TNM stage 1 (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');
INSERT INTO snomed_icd10_map_p3 VALUES ('431855005','N18.1','NHS_Digital_TRUD_ExtendedMap_GB_20260311','CKD stage 1 — direct stage mapping, ICD-10 structurally aligned with SNOMED staging','Chronic kidney disease stage 1 (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('431856006','N18.2','NHS_Digital_TRUD_ExtendedMap_GB_20260311','CKD stage 2 — direct stage mapping','Chronic kidney disease stage 2 (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('431857002','N18.4','NHS_Digital_TRUD_ExtendedMap_GB_20260311','CKD stage 4 — direct stage mapping','Chronic kidney disease stage 4 (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('433144002','N18.3','NHS_Digital_TRUD_ExtendedMap_GB_20260311','CKD stage 3 — direct stage mapping','Chronic kidney disease stage 3 (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('44054006','E11.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','T2DM without complications unspecified','Diabetes mellitus type 2 (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');
INSERT INTO snomed_icd10_map_p3 VALUES ('46177005','N18.5','NHS_Digital_TRUD_ExtendedMap_GB_20260311','CKD stage 5 — direct stage mapping','End-stage renal disease (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('49436004','I48.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','AF unspecified','Atrial fibrillation (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('55822004','E78.5','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Hyperlipidaemia unspecified','Hyperlipidemia (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('59621000','I10','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Adult non-obstetric HTN — O10 excluded, cohort scope','Essential hypertension (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('64859006','M81.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Osteoporosis unspecified','Osteoporosis (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('67811000119102','C34.90','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Primary lung cancer unspecified','Primary small cell malignant neoplasm of lung, TNM stage 1 (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');
INSERT INTO snomed_icd10_map_p3 VALUES ('69896004','M06.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Rheumatoid arthritis unspecified','Rheumatoid arthritis (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('83664006','E03.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Hypothyroidism unspecified','Idiopathic atrophic hypothyroidism (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('84114007','I50.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','HF unspecified — O29 excluded, cohort scope','Heart failure (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('84757009','G40.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Epilepsy unspecified','Epilepsy (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('87433001','J43.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Emphysema unspecified','Pulmonary emphysema (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('88805009','I50.0','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Congestive HF non-obstetric adult','Chronic congestive heart failure (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('90781000119102','E11.29','NHS_Digital_TRUD_ExtendedMap_GB_20260311','T2DM other diabetic kidney complication — proteinuria not explicitly mapped in ICD-10','Microalbuminuria due to type 2 diabetes mellitus (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('92691004','D07.5','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Carcinoma in situ of prostate','Carcinoma in situ of prostate (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('93143009','C95.9','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Leukaemia unspecified','Leukemia  disease (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('94503003','C79.82','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Secondary malignant neoplasm of prostate','Metastatic malignant neoplasm to prostate (disorder)',NULL,'Synthea_conditions_csv_DESCRIPTION_column');
INSERT INTO snomed_icd10_map_p3 VALUES ('97331000119101','E11.311','NHS_Digital_TRUD_ExtendedMap_GB_20260311','Semantic duplicate — same ICD-10 as 1501000119109, Synthea duplication not mapping error','Macular edema and retinopathy due to type 2 diabetes mellitus (disorder)',NULL,'NHS_Digital_TRUD_SNOMED_CT_MonolithRF2_GB_20260311_FSN');

-- =============================================================================
-- SECTION 4: project_reference
-- Design decision audit trail — CREATE only
-- Rows inserted incrementally throughout project sessions
-- 51 entries (D-52 through D-82) confirmed in database
-- =============================================================================

CREATE TABLE IF NOT EXISTS project_reference (
    ref_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    category       TEXT,
    item           TEXT,
    expected_value TEXT,
    source         TEXT,
    decision_ref   TEXT,
    notes          TEXT
);

-- =============================================================================
-- VALIDATION
-- =============================================================================

SELECT 'nice_thresholds'    AS tbl, COUNT(*) AS n FROM nice_thresholds
UNION ALL
SELECT 'scoring_constants',          COUNT(*) FROM scoring_constants
UNION ALL
SELECT 'snomed_icd10_map_p3',        COUNT(*) FROM snomed_icd10_map_p3;

-- Expected: 5, 1, 46
-- =============================================================================
-- END OF load_reference.sql
-- Next: run prepare_cohort.sql
-- =============================================================================