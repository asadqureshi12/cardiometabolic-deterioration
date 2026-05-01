DROP TABLE IF EXISTS patient_cohort;

CREATE TABLE patient_cohort (
    patient_id           TEXT PRIMARY KEY,
    age                  INTEGER,
    sex                  TEXT,
    deprivation_decile   INTEGER,
    is_pregnant          INTEGER DEFAULT 0,
    qof_condition_count  INTEGER DEFAULT 0,
    multimorbidity_flag  INTEGER DEFAULT 0,
    cvd_status           TEXT DEFAULT 'NONE',
    cvd_onset_date       DATE,
    cohort_entry_date    DATE NOT NULL,
    cohort_version       TEXT NOT NULL,
    notes                TEXT
);

INSERT INTO patient_cohort (
    patient_id, age, sex, deprivation_decile, is_pregnant,
    qof_condition_count, multimorbidity_flag, cvd_status,
    cvd_onset_date, cohort_entry_date, cohort_version, notes
)
WITH
qualifying AS (
    SELECT DISTINCT patient_id FROM conditions
    WHERE complication_category = 'clinical_active'
      AND is_active = 1
      AND snomed_code IN (SELECT snomed_code FROM snomed_icd10_map_p3)
),
ckd_only AS (
    SELECT DISTINCT patient_id FROM conditions
    WHERE complication_category = 'clinical_active'
      AND is_active = 1
      AND snomed_code IN ('431855005','431856006','433144002','431857002','46177005')
      AND patient_id NOT IN (
          SELECT patient_id FROM conditions
          WHERE complication_category = 'clinical_active'
            AND is_active = 1
            AND snomed_code IN (
                '44054006','127013003','157141000119108','90781000119102',
                '368581000119106','1551000119108','1501000119109','97331000119101'
            )
      )
      AND patient_id NOT IN (
          SELECT patient_id FROM conditions
          WHERE complication_category = 'clinical_active'
            AND is_active = 1
            AND snomed_code = '59621000'
      )
),
eligible AS (
    SELECT patient_id FROM qualifying
    EXCEPT SELECT patient_id FROM ckd_only
),
cvd_status_cte AS (
    SELECT
        c.patient_id,
        CASE
            WHEN MAX(CASE
                WHEN c.snomed_code IN ('401303003','401314000')
                 AND c.onset_date >= DATE('2026-04-06', '-365 days')
                THEN 1 ELSE 0 END) = 1 THEN 'RECENT'
            WHEN MAX(CASE
                WHEN c.snomed_code IN (
                    '1231000119100','399211009','399261000',
                    '401303003','401314000','414545008',
                    '48724000','49436004','60234000',
                    '60573004','84114007','88805009'
                )
                THEN 1 ELSE 0 END) = 1 THEN 'ESTABLISHED'
            ELSE 'NONE'
        END AS cvd_status,
        MIN(CASE WHEN c.snomed_code IN (
                    '1231000119100','399211009','399261000',
                    '401303003','401314000','414545008',
                    '48724000','49436004','60234000',
                    '60573004','84114007','88805009'
                )
            THEN c.onset_date END) AS cvd_onset_date
    FROM conditions c
    WHERE c.complication_category = 'clinical_active'
      AND c.is_active = 1
    GROUP BY c.patient_id
),
qof_counts AS (
    SELECT patient_id,
           COUNT(DISTINCT snomed_code) AS qof_condition_count
    FROM conditions
    WHERE complication_category = 'clinical_active'
      AND is_active = 1
      AND snomed_code IN (SELECT snomed_code FROM snomed_icd10_map_p3)
    GROUP BY patient_id
)
SELECT
    p.patient_id, p.age, p.sex, p.deprivation_decile, p.is_pregnant,
    COALESCE(qc.qof_condition_count, 0),
    CASE WHEN COALESCE(qc.qof_condition_count, 0) >= 2 THEN 1 ELSE 0 END,
    COALESCE(cvd.cvd_status, 'NONE'),
    cvd.cvd_onset_date,
    '2026-04-06',
    '20260406_COHORT_V1',
    NULL
FROM patients p
JOIN eligible e ON p.patient_id = e.patient_id
LEFT JOIN cvd_status_cte cvd ON p.patient_id = cvd.patient_id
LEFT JOIN qof_counts qc ON p.patient_id = qc.patient_id;

SELECT 'patient_cohort total' AS check_name, COUNT(*) AS n FROM patient_cohort
UNION ALL SELECT 'ESTABLISHED', COUNT(*) FROM patient_cohort WHERE cvd_status = 'ESTABLISHED'
UNION ALL SELECT 'RECENT',      COUNT(*) FROM patient_cohort WHERE cvd_status = 'RECENT'
UNION ALL SELECT 'NONE',        COUNT(*) FROM patient_cohort WHERE cvd_status = 'NONE';