-- ============================================================
-- logic_unit_tests.sql
-- P3: Cardiometabolic Deterioration Monitoring System
-- Deterministic unit test suite — clinical scoring engine
-- Pre-validation layer (specification verification only)
-- No external outcomes. No encounters. No real patient data.
-- Expected values computed inside SQL from same formulas
-- as production pipeline.
-- Acceptance criterion: >=95% PASS, zero boundary failures,
-- zero rule hierarchy failures
-- ============================================================

-- ============================================================
-- SECTION 1: SYNTHETIC INPUTS
-- ============================================================

DROP TABLE IF EXISTS test_inputs;

CREATE TEMP TABLE test_inputs (
    test_id       TEXT,
    component     TEXT,
    patient_id    TEXT,
    loinc_code    TEXT,
    cvd_status    TEXT,
    score_month   TEXT,
    value_numeric REAL
);

INSERT INTO test_inputs VALUES
-- --------------------------------------------------------
-- BLOCK A: Boundary and exceedance correctness
-- A1: SBP = 140.0 (at threshold) → mean_i = 0
-- A2: SBP = 154.0 (above threshold) → mean_i = (154-140)/140
-- A3: SBP = 125.0 (below threshold) → mean_i = 0 (clamped)
-- A4: LDL = 2.0, ESTABLISHED → threshold=1.8,
--     mean_i = (2.0-1.8)/1.8
-- --------------------------------------------------------
('A1','boundary',   'TEST_A1','8480-6', 'NONE',        '2025-06',140.0),
('A2','exceedance', 'TEST_A2','8480-6', 'NONE',        '2025-06',154.0),
('A3','clamp',      'TEST_A3','8480-6', 'NONE',        '2025-06',125.0),
('A4','cvd',        'TEST_A4','18262-6','ESTABLISHED', '2025-06', 90.0),

-- --------------------------------------------------------
-- BLOCK B: Trajectory correctness
-- B1: increasing i (0.05→0.10→0.15) → WORSENING
--     x = threshold*(1+i): 147.0, 154.0, 161.0
-- B2: decreasing i (0.15→0.10→0.05) → IMPROVING
--     x = 161.0, 154.0, 147.0
-- B3: flat i (0.10 each month) → STABLE
--     x = 154.0, 154.0, 154.0
-- --------------------------------------------------------
('B1','traj','TEST_B1','8480-6','NONE','2025-05',147.0),
('B1','traj','TEST_B1','8480-6','NONE','2025-06',154.0),
('B1','traj','TEST_B1','8480-6','NONE','2025-07',161.0),

('B2','traj','TEST_B2','8480-6','NONE','2025-05',161.0),
('B2','traj','TEST_B2','8480-6','NONE','2025-06',154.0),
('B2','traj','TEST_B2','8480-6','NONE','2025-07',147.0),

('B3','traj','TEST_B3','8480-6','NONE','2025-05',154.0),
('B3','traj','TEST_B3','8480-6','NONE','2025-06',154.0),
('B3','traj','TEST_B3','8480-6','NONE','2025-07',154.0),

-- --------------------------------------------------------
-- BLOCK C: Variance correctness
-- C1: high variance → UNSTABLE
--     i values: 0.01, 0.30, 0.01
--     x = 140*(1+i): 141.4, 182.0, 141.4
--     variance = E[i²]-E[i]² >> D-62 threshold (0.001)
-- C2: zero variance → STABLE
--     flat i = 0.10 → x = 154.0 each month
--     variance = 0 < D-62 threshold
-- --------------------------------------------------------
('C1','var','TEST_C1','8480-6','NONE','2025-05',141.4),
('C1','var','TEST_C1','8480-6','NONE','2025-06',182.0),
('C1','var','TEST_C1','8480-6','NONE','2025-07',141.4),

('C2','var','TEST_C2','8480-6','NONE','2025-05',154.0),
('C2','var','TEST_C2','8480-6','NONE','2025-06',154.0),
('C2','var','TEST_C2','8480-6','NONE','2025-07',154.0);

-- ============================================================
-- SECTION 2: ORACLE EXPECTATIONS
-- All expected values deterministic — computed from inputs
-- using same formulas as production pipeline
-- ============================================================

DROP TABLE IF EXISTS expected_outputs;

CREATE TEMP TABLE expected_outputs (
    test_id  TEXT,
    metric   TEXT,
    expected TEXT
);

INSERT INTO expected_outputs VALUES
-- Block A
('A1','mean_i',
    CAST(0.0 AS TEXT)),
('A2','mean_i',
    CAST(ROUND((154.0-140.0)/140.0,6) AS TEXT)),
('A3','mean_i',
    CAST(0.0 AS TEXT)),
('A4','mean_i',
    CAST(ROUND((90.0-77.3)/77.3,6) AS TEXT)),
-- Block B
('B1','trajectory','WORSENING'),
('B2','trajectory','IMPROVING'),
('B3','trajectory','STABLE'),
-- Block C
('C1','variance','UNSTABLE'),
('C2','variance','STABLE');

-- ============================================================
-- SECTION 3: PIPELINE EXECUTION
-- Reuses production CTE logic — only data source changes
-- Thresholds read from nice_thresholds (same as main pipeline)
-- Variance threshold read from project_reference D-62
-- ============================================================

DROP TABLE IF EXISTS test_thresholds;

CREATE TEMP TABLE test_thresholds AS
SELECT
    ti.patient_id,
    ti.loinc_code,
    ti.cvd_status,
    CASE
        WHEN ti.cvd_status IN ('ESTABLISHED','RECENT')
        THEN (
            SELECT t_value FROM nice_thresholds
            WHERE loinc_code = ti.loinc_code
              AND cvd_status = 'CVD'
            LIMIT 1
        )
        ELSE (
            SELECT t_value FROM nice_thresholds
            WHERE loinc_code = ti.loinc_code
              AND cvd_status IN ('NONE','ALL')
            ORDER BY CASE cvd_status
                WHEN 'NONE' THEN 1 ELSE 2 END
            LIMIT 1
        )
    END AS t_value
FROM (
    SELECT DISTINCT patient_id, loinc_code, cvd_status
    FROM test_inputs
    WHERE loinc_code != 'VAR'
) ti;

DROP TABLE IF EXISTS test_monthly;

CREATE TEMP TABLE test_monthly AS
SELECT
    ti.test_id,
    ti.patient_id,
    ti.loinc_code,
    ti.score_month,
    AVG(ti.value_numeric) AS mean_x,
    tt.t_value,
    CASE
        WHEN (AVG(ti.value_numeric) - tt.t_value)
             / tt.t_value < 0
        THEN 0.0
        ELSE (AVG(ti.value_numeric) - tt.t_value)
             / tt.t_value
    END AS mean_i
FROM test_inputs ti
JOIN test_thresholds tt
  ON ti.patient_id = tt.patient_id
 AND ti.loinc_code = tt.loinc_code
GROUP BY ti.test_id, ti.patient_id, ti.loinc_code,
         ti.score_month, tt.t_value;

DROP TABLE IF EXISTS test_computed;

CREATE TEMP TABLE test_computed AS
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY patient_id, loinc_code
               ORDER BY score_month
           ) AS rn
    FROM test_monthly
),
deltas AS (
    SELECT a.test_id, a.patient_id, a.loinc_code,
           a.mean_i - b.mean_i AS delta_i
    FROM ranked a
    JOIN ranked b
      ON a.patient_id = b.patient_id
     AND a.loinc_code = b.loinc_code
     AND a.rn = b.rn + 1
),
traj_raw AS (
    SELECT test_id, patient_id, loinc_code,
           AVG(delta_i) AS trajectory_raw
    FROM deltas
    GROUP BY test_id, patient_id, loinc_code
),
var_raw AS (
    SELECT test_id, patient_id, loinc_code,
           AVG(mean_i * mean_i)
           - (AVG(mean_i) * AVG(mean_i)) AS variance_score
    FROM test_monthly
    GROUP BY test_id, patient_id, loinc_code
),
params AS (
    SELECT CAST(expected_value AS REAL) AS var_threshold
    FROM project_reference
    WHERE decision_ref = 'D-62'
      AND item        = 'variance_instability_threshold'
)
SELECT
    tm.test_id,
    tm.patient_id,
    AVG(tm.mean_i)          AS mean_i,
    tr.trajectory_raw,
    vr.variance_score,
    CASE
        WHEN COUNT(DISTINCT tm.score_month) >= 3
         AND tr.trajectory_raw >  0.038 THEN 'WORSENING'
        WHEN COUNT(DISTINCT tm.score_month) >= 3
         AND tr.trajectory_raw < -0.038 THEN 'IMPROVING'
        WHEN COUNT(DISTINCT tm.score_month) >= 3
        THEN 'STABLE'
        ELSE NULL
    END AS trajectory,
    CASE
        WHEN vr.variance_score >
             (SELECT var_threshold FROM params)
        THEN 'UNSTABLE'
        ELSE 'STABLE'
    END AS variance_label
FROM test_monthly tm
LEFT JOIN traj_raw tr
  ON tm.test_id    = tr.test_id
 AND tm.patient_id = tr.patient_id
LEFT JOIN var_raw vr
  ON tm.test_id    = vr.test_id
 AND tm.patient_id = vr.patient_id
GROUP BY tm.test_id, tm.patient_id,
         tr.trajectory_raw, vr.variance_score;

-- ============================================================
-- SECTION 4: D-SERIES — RULE HIERARCHY
-- Validated against production tables
-- ============================================================

DROP TABLE IF EXISTS test_d_series;

CREATE TEMP TABLE test_d_series AS

SELECT * FROM (
    SELECT
        'D1'                AS test_id,
        'bmi_floor_binding' AS metric,
        CAST(bmi_floor AS TEXT) AS expected,
        CAST(base_band AS TEXT) AS actual,
        CASE WHEN bmi_floor > dynamic_base_band
              AND base_band = bmi_floor
              AND band_driver_marker = 'BMI'
             THEN 'PASS' ELSE 'FAIL' END AS pass_flag
    FROM patient_bands
    WHERE bmi_floor > dynamic_base_band
    LIMIT 5
)

UNION ALL

SELECT * FROM (
    SELECT
        'D2',
        'dynamic_overrides_bmi',
        'NOT BMI',
        band_driver_marker,
        CASE WHEN dynamic_base_band >= bmi_floor
              AND band_driver_marker != 'BMI'
             THEN 'PASS' ELSE 'FAIL' END
    FROM patient_bands
    WHERE dynamic_base_band >= bmi_floor
      AND final_band IS NOT NULL
    LIMIT 5
)

UNION ALL

SELECT
    'D3',
    'recent_cvd_floor',
    '>=2',
    CAST(final_band AS TEXT),
    CASE WHEN final_band >= 2 THEN 'PASS' ELSE 'FAIL' END
FROM patient_bands
WHERE cvd_status = 'RECENT'

UNION ALL

SELECT
    'D4',
    'no_breach_token',
    'NO_BREACH in string',
    CASE WHEN patient_string LIKE '%NO_BREACH%'
         THEN 'NO_BREACH present'
         ELSE 'NO_BREACH absent' END,
    CASE WHEN breach_count = 0
          AND patient_string LIKE '%NO_BREACH%'
         THEN 'PASS' ELSE 'FAIL' END
FROM priority_scores
WHERE breach_count = 0;


-- ============================================================
-- SECTION 5: ASSERTION TABLE
-- Single unified PASS/FAIL matrix
-- ============================================================

DROP TABLE IF EXISTS assertions;

CREATE TEMP TABLE assertions AS

-- A/B/C series
SELECT
    c.test_id,
    e.metric,
    e.expected,
    CASE
        WHEN e.metric = 'mean_i'
        THEN CAST(ROUND(c.mean_i, 6) AS TEXT)
        WHEN e.metric = 'trajectory'
        THEN COALESCE(c.trajectory, 'NULL')
        WHEN e.metric = 'variance'
        THEN COALESCE(c.variance_label, 'NULL')
    END AS actual,
    CASE
        WHEN e.metric = 'mean_i'
         AND ABS(c.mean_i - CAST(e.expected AS REAL)) < 1e-5
        THEN 'PASS'
        WHEN e.metric = 'trajectory'
         AND c.trajectory = e.expected
        THEN 'PASS'
        WHEN e.metric = 'variance'
         AND c.variance_label = e.expected
        THEN 'PASS'
        ELSE 'FAIL'
    END AS pass_flag,
    CASE
        WHEN e.metric = 'mean_i'     THEN 'boundary_exceedance'
        WHEN e.metric = 'trajectory' THEN 'temporal_ordering'
        WHEN e.metric = 'variance'   THEN 'variance_computation'
    END AS logic_block
FROM test_computed c
JOIN expected_outputs e ON c.test_id = e.test_id

UNION ALL

-- D series
SELECT
    test_id,
    metric,
    expected,
    actual,
    pass_flag,
    'rule_precedence' AS logic_block
FROM test_d_series;

-- ============================================================
-- SECTION 6: RESULTS
-- ============================================================

SELECT
    test_id,
    logic_block,
    metric,
    expected,
    actual,
    pass_flag,
    CASE WHEN pass_flag = 'FAIL'
         THEN logic_block || '_error'
         ELSE NULL
    END AS failure_type
FROM assertions
ORDER BY test_id;

-- ============================================================
-- FINAL GATE
-- ============================================================

SELECT
    CASE
        WHEN SUM(CASE WHEN pass_flag='FAIL' THEN 1 ELSE 0 END) = 0
        THEN 'ALL_TESTS_PASS'
        ELSE 'FAILURE_DETECTED'
    END AS final_status,
    COUNT(*)                                               AS total_tests,
    SUM(CASE WHEN pass_flag='PASS' THEN 1 ELSE 0 END)     AS passed,
    SUM(CASE WHEN pass_flag='FAIL' THEN 1 ELSE 0 END)     AS failed,
    ROUND(100.0 * SUM(CASE WHEN pass_flag='PASS'
                           THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                   AS pass_rate_pct
FROM assertions;