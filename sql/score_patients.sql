-- ============================================================
-- score_patients.sql
-- P3: Cardiometabolic Deterioration Monitoring System
-- Full scoring pipeline — Sprint 3/4 final build
-- Depends on: obs_scoring_window (clean_data.sql output)
--             patient_cohort, nice_thresholds, scoring_constants
--             project_reference (D-62)
-- Output tables: monthly_i_scores, marker_scores,
--                patient_temporal_signals, priority_scores,
--                patient_bands
-- Scoring bundles: TEMPORAL_V3, PS_V4, BANDS_V6
-- ============================================================

-- ============================================================
-- STEP 1: obs_scoring_window
-- Full observation window with is_acute_sbp flag
-- Emergency/inpatient SBP flagged weight=0 (D-80)
-- All other markers: all encounter classes retained
-- ============================================================

DROP TABLE IF EXISTS obs_scoring_window;

CREATE TABLE obs_scoring_window (
    patient_id       TEXT,
    loinc_code       TEXT,
    value_numeric    REAL,
    observation_date NUM,
    value_excluded   INT,
    is_acute_sbp     INTEGER DEFAULT 0
);

INSERT INTO obs_scoring_window (
    patient_id,
    loinc_code,
    value_numeric,
    observation_date,
    value_excluded,
    is_acute_sbp
)
SELECT
    o.patient_id,
    o.loinc_code,
    o.value_numeric,
    o.observation_date,
    o.value_excluded,
    CASE
        WHEN o.loinc_code = '8480-6'
         AND EXISTS (
             SELECT 1 FROM encounters e
             WHERE e.encounter_id = o.encounter_id
               AND e.encounter_class IN ('inpatient','emergency')
         )
        THEN 1
        ELSE 0
    END AS is_acute_sbp
FROM observations o
JOIN scoring_constants sc ON sc.constants_id = 1
WHERE o.loinc_code IN (
    '8480-6',   -- Systolic BP
    '4548-4',   -- HbA1c
    '18262-6',  -- LDL Cholesterol
    '39156-5',  -- BMI
    '33914-3'   -- eGFR
)
AND o.observation_date BETWEEN sc.window_start AND sc.window_end
AND o.value_numeric IS NOT NULL
AND o.value_excluded = 0
AND o.patient_id IN (
    SELECT patient_id FROM patient_cohort
);

-- ============================================================
-- STEP 2: monthly_i_scores
-- Weighted SBP aggregation: is_acute_sbp=1 → weight=0 (D-80)
-- eGFR excluded (no exceedance model)
-- ============================================================

DROP TABLE IF EXISTS monthly_i_scores;

CREATE TABLE monthly_i_scores (
    patient_id      TEXT,
    loinc_code      TEXT,
    score_month     TEXT,
    t_value         REAL,
    mean_x_month    REAL,
    mean_i_month    REAL,
    reading_count   INTEGER
);

INSERT INTO monthly_i_scores (
    patient_id,
    loinc_code,
    score_month,
    t_value,
    mean_x_month,
    mean_i_month,
    reading_count
)
WITH thresholds AS (
    SELECT
        pc.patient_id,
        nt.loinc_code,
        nt.t_value
    FROM patient_cohort pc
    JOIN nice_thresholds nt
      ON nt.cvd_status = CASE
             WHEN pc.cvd_status IN ('ESTABLISHED','RECENT')
             THEN 'CVD' ELSE 'NONE'
         END
      OR nt.cvd_status = 'ALL'
    WHERE nt.loinc_code != '33914-3'
),
monthly_raw AS (
    SELECT
        osw.patient_id,
        osw.loinc_code,
        STRFTIME('%Y-%m', osw.observation_date) AS score_month,
        -- Weighted mean: is_acute_sbp=1 → weight=0.0 (D-80)
        CASE
            WHEN SUM(CASE WHEN osw.is_acute_sbp = 0
                         THEN 1 ELSE 0 END) > 0
            THEN SUM(CASE WHEN osw.is_acute_sbp = 0
                         THEN osw.value_numeric ELSE 0 END)
                 / SUM(CASE WHEN osw.is_acute_sbp = 0
                            THEN 1 ELSE 0 END)
            ELSE NULL
        END AS mean_x_month,
        COUNT(*) AS reading_count
    FROM obs_scoring_window osw
    WHERE osw.loinc_code != '33914-3'
    GROUP BY osw.patient_id, osw.loinc_code,
             STRFTIME('%Y-%m', osw.observation_date)
),
monthly_filtered AS (
    SELECT * FROM monthly_raw
    WHERE mean_x_month IS NOT NULL
)
SELECT
    mf.patient_id,
    mf.loinc_code,
    mf.score_month,
    t.t_value,
    mf.mean_x_month,
    CASE
        WHEN (mf.mean_x_month - t.t_value) / t.t_value < 0
        THEN 0.0
        ELSE (mf.mean_x_month - t.t_value) / t.t_value
    END AS mean_i_month,
    mf.reading_count
FROM monthly_filtered mf
JOIN thresholds t
  ON mf.patient_id = t.patient_id
 AND mf.loinc_code = t.loinc_code;

-- ============================================================
-- STEP 3: marker_scores (non-eGFR markers)
-- Full trajectory and variance model
-- Trajectory thresholds: SBP/HbA1c 0.038, LDL 0.090
-- ============================================================

DROP TABLE IF EXISTS marker_scores;

CREATE TABLE marker_scores (
    marker_score_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id              TEXT,
    loinc_code              TEXT,
    marker_name             TEXT,
    observation_count       INTEGER,
    months_with_data        INTEGER,
    total_months            INTEGER,
    observation_coverage    REAL,
    data_tier               TEXT,
    mean_x                  REAL,
    threshold_applied       REAL,
    mean_i                  REAL,
    trajectory              TEXT,
    trajectory_raw          REAL,
    variance_score          REAL,
    system_trajectory       TEXT,
    system_variance         TEXT,
    marker_sufficiency      TEXT,
    scored_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    threshold_version       TEXT
);

INSERT INTO marker_scores (
    patient_id,
    loinc_code,
    marker_name,
    observation_count,
    months_with_data,
    total_months,
    observation_coverage,
    data_tier,
    mean_x,
    threshold_applied,
    mean_i,
    trajectory,
    trajectory_raw,
    variance_score,
    system_trajectory,
    system_variance,
    marker_sufficiency,
    scored_at,
    threshold_version
)
WITH

sc AS (
    SELECT min_readings, min_months, window_start, window_end
    FROM scoring_constants WHERE constants_id = 1
),

thresholds AS (
    SELECT
        pc.patient_id,
        nt.loinc_code,
        nt.t_value
    FROM patient_cohort pc
    JOIN nice_thresholds nt
      ON (nt.cvd_status = 'ALL')
      OR (nt.cvd_status = 'CVD'
          AND pc.cvd_status IN ('ESTABLISHED','RECENT'))
      OR (nt.cvd_status = 'NONE'
          AND pc.cvd_status = 'NONE')
    WHERE nt.loinc_code != '33914-3'
),

obs_stats AS (
    SELECT
        osw.patient_id,
        osw.loinc_code,
        COUNT(*)                                            AS observation_count,
        COUNT(DISTINCT STRFTIME('%Y-%m',osw.observation_date))
                                                            AS months_with_data,
        CAST(
            (JULIANDAY(sc.window_end) - JULIANDAY(sc.window_start))
            / 30.44
        AS INTEGER)                                         AS total_months
    FROM obs_scoring_window osw
    CROSS JOIN sc
    WHERE osw.loinc_code != '33914-3'
      AND osw.patient_id IN (SELECT patient_id FROM patient_cohort)
    GROUP BY osw.patient_id, osw.loinc_code
),

tiered AS (
    SELECT
        os.patient_id,
        os.loinc_code,
        os.observation_count,
        os.months_with_data,
        os.total_months,
        ROUND(CAST(os.months_with_data AS REAL)
              / os.total_months, 4)                         AS observation_coverage,
        CASE
            WHEN os.observation_count >= sc.min_readings
             AND os.months_with_data >= 3
            THEN 'DATA_SUFFICIENT'
            WHEN os.observation_count >= sc.min_readings
             AND os.months_with_data >= 2
            THEN 'PARTIALLY_SUFFICIENT'
            ELSE 'DATA_INSUFFICIENT'
        END                                                 AS data_tier
    FROM obs_stats os
    CROSS JOIN sc
),

monthly_agg AS (
    SELECT
        mi.patient_id,
        mi.loinc_code,
        AVG(mi.mean_x_month)    AS mean_x,
        AVG(mi.mean_i_month)    AS mean_i,
        mi.t_value              AS threshold_applied
    FROM monthly_i_scores mi
    GROUP BY mi.patient_id, mi.loinc_code, mi.t_value
),

monthly_ranked AS (
    SELECT
        mi.patient_id,
        mi.loinc_code,
        mi.score_month,
        mi.mean_i_month,
        ROW_NUMBER() OVER (
            PARTITION BY mi.patient_id, mi.loinc_code
            ORDER BY mi.score_month
        ) AS month_rank
    FROM monthly_i_scores mi
),
monthly_deltas AS (
    SELECT
        a.patient_id,
        a.loinc_code,
        a.mean_i_month - b.mean_i_month AS delta_i
    FROM monthly_ranked a
    JOIN monthly_ranked b
      ON a.patient_id = b.patient_id
     AND a.loinc_code = b.loinc_code
     AND a.month_rank = b.month_rank + 1
),
trajectory_raw AS (
    SELECT
        patient_id,
        loinc_code,
        AVG(delta_i) AS trajectory_raw
    FROM monthly_deltas
    GROUP BY patient_id, loinc_code
),

variance_raw AS (
    SELECT
        patient_id,
        loinc_code,
        AVG(mean_i_month * mean_i_month)
        - (AVG(mean_i_month) * AVG(mean_i_month)) AS variance_score
    FROM monthly_i_scores
    GROUP BY patient_id, loinc_code
),

stability_thresholds AS (
    SELECT
        CASE loinc_code
            WHEN '8480-6'  THEN 0.038
            WHEN '4548-4'  THEN 0.038
            WHEN '18262-6' THEN 0.090
            ELSE 0.038
        END AS stability_threshold,
        loinc_code
    FROM (
        SELECT DISTINCT loinc_code FROM monthly_i_scores
        WHERE loinc_code NOT IN ('33914-3','39156-5')
    )
),

trajectory_classified AS (
    SELECT
        t.patient_id,
        t.loinc_code,
        t.trajectory_raw,
        td.data_tier,
        CASE
            WHEN td.data_tier = 'DATA_SUFFICIENT'
             AND td.months_with_data >= 3
             AND t.trajectory_raw IS NOT NULL
            THEN CASE
                WHEN t.trajectory_raw > st.stability_threshold
                THEN 'WORSENING'
                WHEN t.trajectory_raw < -st.stability_threshold
                THEN 'IMPROVING'
                ELSE 'STABLE'
            END
            WHEN td.data_tier = 'PARTIALLY_SUFFICIENT'
            THEN CASE
                WHEN t.trajectory_raw > 0 THEN 'WORSENING'
                WHEN t.trajectory_raw < 0 THEN 'IMPROVING'
                ELSE 'STABLE'
            END
            WHEN td.loinc_code = '39156-5'
            THEN 'NOT_APPLICABLE'
            ELSE NULL
        END AS trajectory
    FROM trajectory_raw t
    JOIN tiered td
      ON t.patient_id = td.patient_id
     AND t.loinc_code = td.loinc_code
    LEFT JOIN stability_thresholds st
      ON t.loinc_code = st.loinc_code
),

marker_names AS (
    SELECT '8480-6'  AS loinc_code, 'Systolic BP'     AS marker_name UNION ALL
    SELECT '4548-4',                'HbA1c'                          UNION ALL
    SELECT '18262-6',               'LDL Cholesterol'                UNION ALL
    SELECT '39156-5',               'BMI'                            UNION ALL
    SELECT '33914-3',               'eGFR'
),

patient_flags AS (
    SELECT
        td.patient_id,
        CASE MAX(CASE tc.trajectory
                WHEN 'WORSENING' THEN 3
                WHEN 'IMPROVING' THEN 2
                WHEN 'STABLE'    THEN 1
                ELSE 0 END)
            WHEN 3 THEN 'WORSENING'
            WHEN 2 THEN 'IMPROVING'
            WHEN 1 THEN 'STABLE'
            ELSE 'DATA_INSUFFICIENT'
        END AS system_trajectory,
        CASE MAX(CASE
                WHEN vr.variance_score > (
                    SELECT CAST(expected_value AS REAL)
                    FROM project_reference
                    WHERE decision_ref = 'D-62'
                ) THEN 2 ELSE 1 END)
            WHEN 2 THEN 'UNSTABLE'
            ELSE 'STABLE'
        END AS system_variance
    FROM tiered td
    LEFT JOIN trajectory_classified tc
      ON td.patient_id = tc.patient_id
     AND td.loinc_code = tc.loinc_code
    LEFT JOIN variance_raw vr
      ON td.patient_id = vr.patient_id
     AND td.loinc_code = vr.loinc_code
    WHERE td.loinc_code NOT IN ('33914-3','39156-5')
      AND td.data_tier IN ('DATA_SUFFICIENT','PARTIALLY_SUFFICIENT')
    GROUP BY td.patient_id
),

all_markers AS (
    SELECT
        td.patient_id,
        td.loinc_code,
        mn.marker_name,
        td.observation_count,
        td.months_with_data,
        td.total_months,
        td.observation_coverage,
        td.data_tier,
        ma.mean_x,
        ma.threshold_applied,
        CASE WHEN td.data_tier = 'DATA_INSUFFICIENT'
             THEN CASE
                WHEN (ma.mean_x - ma.threshold_applied)
                     / ma.threshold_applied < 0 THEN 0.0
                ELSE (ma.mean_x - ma.threshold_applied)
                     / ma.threshold_applied
             END
             ELSE ma.mean_i
        END AS mean_i,
        CASE WHEN td.data_tier = 'DATA_INSUFFICIENT'
             THEN NULL
             ELSE tc.trajectory
        END AS trajectory,
        CASE WHEN td.data_tier = 'DATA_INSUFFICIENT'
             THEN NULL
             ELSE tc.trajectory_raw
        END AS trajectory_raw,
        CASE WHEN td.data_tier = 'DATA_INSUFFICIENT'
             THEN NULL
             ELSE vr.variance_score
        END AS variance_score,
        pf.system_trajectory,
        pf.system_variance,
        CASE
            WHEN td.observation_count >= 2  THEN 'SUFFICIENT'
            WHEN td.observation_count = 1   THEN 'PARTIAL'
            ELSE 'INSUFFICIENT'
        END AS marker_sufficiency
    FROM tiered td
    JOIN marker_names mn ON td.loinc_code = mn.loinc_code
    LEFT JOIN monthly_agg ma
      ON td.patient_id = ma.patient_id
     AND td.loinc_code = ma.loinc_code
    LEFT JOIN trajectory_classified tc
      ON td.patient_id = tc.patient_id
     AND td.loinc_code = tc.loinc_code
    LEFT JOIN variance_raw vr
      ON td.patient_id = vr.patient_id
     AND td.loinc_code = vr.loinc_code
    LEFT JOIN patient_flags pf
      ON td.patient_id = pf.patient_id
)

SELECT
    patient_id, loinc_code, marker_name,
    observation_count, months_with_data, total_months,
    observation_coverage, data_tier, mean_x, threshold_applied,
    mean_i, trajectory, trajectory_raw, variance_score,
    system_trajectory, system_variance, marker_sufficiency,
    CURRENT_TIMESTAMP,
    'NICE_NG136_NG28_NG238_20260406'
FROM all_markers;

-- ============================================================
-- STEP 4: Add eGFR rows to marker_scores
-- Mean_x only — no exceedance model, no trajectory
-- Data_tier gate applied for tier computation (D-74)
-- ============================================================

INSERT INTO marker_scores (
    patient_id, loinc_code, marker_name,
    observation_count, months_with_data, total_months,
    observation_coverage, data_tier, mean_x,
    threshold_applied, mean_i, trajectory,
    trajectory_raw, variance_score,
    system_trajectory, system_variance,
    marker_sufficiency, scored_at, threshold_version
)
WITH sc AS (
    SELECT min_readings, min_months, window_start, window_end
    FROM scoring_constants WHERE constants_id = 1
),
egfr_stats AS (
    SELECT
        patient_id,
        COUNT(*)                                            AS obs_count,
        COUNT(DISTINCT STRFTIME('%Y-%m', observation_date))
                                                            AS distinct_months,
        ROUND(AVG(value_numeric), 4)                        AS mean_x,
        CAST(
            (JULIANDAY(sc.window_end) - JULIANDAY(sc.window_start))
            / 30.44
        AS INTEGER)                                         AS total_months
    FROM obs_scoring_window
    CROSS JOIN sc
    WHERE loinc_code = '33914-3'
      AND patient_id IN (SELECT patient_id FROM patient_cohort)
    GROUP BY patient_id
)
SELECT
    es.patient_id,
    '33914-3', 'eGFR',
    es.obs_count, es.distinct_months, es.total_months,
    ROUND(CAST(es.distinct_months AS REAL) / es.total_months, 4),
    CASE
        WHEN es.obs_count >= sc.min_readings
         AND es.distinct_months >= 3
        THEN 'DATA_SUFFICIENT'
        WHEN es.obs_count >= sc.min_readings
         AND es.distinct_months >= 2
        THEN 'PARTIALLY_SUFFICIENT'
        ELSE 'DATA_INSUFFICIENT'
    END,
    es.mean_x,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    CASE
        WHEN es.obs_count >= sc.min_readings THEN 'SUFFICIENT'
        WHEN es.obs_count = 1               THEN 'PARTIAL'
        ELSE 'INSUFFICIENT'
    END,
    CURRENT_TIMESTAMP,
    'NICE_NG203_KDIGO2012'
FROM egfr_stats es
CROSS JOIN sc;

-- ============================================================
-- STEP 5: Restore mean_i for DATA_INSUFFICIENT rows (D-63, D-65)
-- Single reading patients get mean_i from formula
-- eGFR excluded (no threshold_applied)
-- ============================================================

UPDATE marker_scores
SET mean_i =
    CASE
        WHEN (mean_x - threshold_applied) / threshold_applied < 0
        THEN 0.0
        ELSE (mean_x - threshold_applied) / threshold_applied
    END
WHERE data_tier = 'DATA_INSUFFICIENT'
  AND mean_x IS NOT NULL
  AND threshold_applied IS NOT NULL
  AND threshold_applied != 0
  AND loinc_code != '33914-3';

-- ============================================================
-- STEP 6: priority_scores
-- Breach detection: mean_i > 0 across all data tiers (D-63)
-- Worst marker: argmax(mean_i), alphabetical tiebreak (D-52)
-- ============================================================

DROP TABLE IF EXISTS priority_scores;

CREATE TABLE priority_scores (
    score_id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id                  TEXT NOT NULL,
    cvd_status                  TEXT,
    breach_count                INTEGER,
    breach_markers              TEXT,
    worst_marker_name           TEXT,
    worst_marker_value          REAL,
    worst_marker_threshold      REAL,
    worst_marker_deviation_pct  REAL,
    condition_count             INTEGER,
    patient_string              TEXT,
    scored_at                   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    scoring_bundle              TEXT,
    UNIQUE (patient_id)
);

INSERT INTO priority_scores (
    patient_id, cvd_status, breach_count, breach_markers,
    worst_marker_name, worst_marker_value, worst_marker_threshold,
    worst_marker_deviation_pct, condition_count, patient_string,
    scoring_bundle
)
WITH

breaching AS (
    SELECT ms.patient_id, ms.marker_name,
           ms.mean_x, ms.mean_i, ms.threshold_applied
    FROM marker_scores ms
    WHERE ms.mean_i IS NOT NULL AND ms.mean_i > 0
),

breach_counts AS (
    SELECT patient_id, COUNT(*) AS breach_count
    FROM breaching GROUP BY patient_id
),

breach_marker_list AS (
    SELECT patient_id,
           GROUP_CONCAT(marker_name, ', ') AS breach_markers
    FROM (
        SELECT patient_id, marker_name FROM breaching
        ORDER BY patient_id, mean_i DESC,
                 marker_name COLLATE NOCASE ASC
    )
    GROUP BY patient_id
),

worst_marker_ranked AS (
    SELECT patient_id, marker_name, mean_x, mean_i, threshold_applied,
           ROW_NUMBER() OVER (
               PARTITION BY patient_id
               ORDER BY mean_i DESC, marker_name COLLATE NOCASE ASC
           ) AS rn
    FROM breaching
),

worst_marker AS (
    SELECT patient_id,
           marker_name            AS worst_marker_name,
           mean_x                 AS worst_marker_value,
           threshold_applied      AS worst_marker_threshold,
           ROUND(mean_i * 100, 1) AS worst_marker_deviation_pct
    FROM worst_marker_ranked WHERE rn = 1
),

scored_patients AS (
    SELECT pc.patient_id, pc.cvd_status,
           pc.qof_condition_count AS condition_count
    FROM patient_cohort pc
    WHERE EXISTS (
        SELECT 1 FROM marker_scores ms WHERE ms.patient_id = pc.patient_id
    )
)

SELECT
    sp.patient_id, sp.cvd_status,
    COALESCE(bc.breach_count, 0)         AS breach_count,
    COALESCE(bml.breach_markers, 'none') AS breach_markers,
    wm.worst_marker_name, wm.worst_marker_value,
    wm.worst_marker_threshold, wm.worst_marker_deviation_pct,
    sp.condition_count,
    sp.cvd_status
        || ' | ' || COALESCE(bc.breach_count, 0)
        || ' (' || COALESCE(bml.breach_markers, 'none') || ') | '
        || COALESCE(
               wm.worst_marker_name
               || ':' || ROUND(wm.worst_marker_value, 1)
               || '/' || ROUND(wm.worst_marker_threshold, 1)
               || ' (+' || wm.worst_marker_deviation_pct || '%)',
               'NO_BREACH'
           )
        || ' | ' || sp.condition_count AS patient_string,
    '20260418_PS_V4' AS scoring_bundle
FROM scored_patients sp
LEFT JOIN breach_counts      bc  ON sp.patient_id = bc.patient_id
LEFT JOIN breach_marker_list bml ON sp.patient_id = bml.patient_id
LEFT JOIN worst_marker       wm  ON sp.patient_id = wm.patient_id;

-- ============================================================
-- STEP 7: patient_temporal_signals
-- Trajectory/variance for SBP, HbA1c, LDL only
-- BMI and eGFR excluded from temporal model (D-76)
-- Sufficiency counts: SBP, HbA1c, LDL only (D-76, Option A)
-- ============================================================

DROP TABLE IF EXISTS patient_temporal_signals;

CREATE TABLE patient_temporal_signals (
    temporal_id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id                    TEXT NOT NULL,
    system_trajectory             TEXT NOT NULL
        CHECK (system_trajectory IN ('WORSENING', 'STABLE', 'IMPROVING')),
    system_variance               TEXT NOT NULL
        CHECK (system_variance IN ('STABLE', 'UNSTABLE')),
    trajectory_evidence_markers   TEXT,
    variance_evidence_markers     TEXT,
    markers_data_sufficient       INTEGER NOT NULL,
    markers_partially_sufficient  INTEGER NOT NULL,
    temporal_string               TEXT,
    scored_at                     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    scoring_bundle                TEXT,
    UNIQUE (patient_id)
);

INSERT INTO patient_temporal_signals (
    patient_id, system_trajectory, system_variance,
    trajectory_evidence_markers, variance_evidence_markers,
    markers_data_sufficient, markers_partially_sufficient,
    temporal_string, scoring_bundle
)
WITH

params AS (
    SELECT CAST(
        (SELECT expected_value FROM project_reference
          WHERE decision_ref = 'D-62'
            AND category     = 'CLINICAL_MODELING'
            AND item         = 'variance_instability_threshold'
          LIMIT 1)
    AS REAL) AS variance_threshold
),

eligible_marker_rows AS (
    SELECT ms.patient_id, ms.marker_name, ms.loinc_code,
           ms.data_tier, ms.trajectory, ms.variance_score
    FROM marker_scores ms
    WHERE ms.data_tier IN ('DATA_SUFFICIENT', 'PARTIALLY_SUFFICIENT')
      AND ms.marker_name != 'BMI'
      AND ms.marker_name != 'eGFR'
),

eligible_patients AS (
    SELECT DISTINCT patient_id FROM eligible_marker_rows
),

trajectory_rank AS (
    SELECT patient_id, marker_name, trajectory,
           CASE trajectory
               WHEN 'WORSENING' THEN 3
               WHEN 'IMPROVING' THEN 2
               WHEN 'STABLE'    THEN 1
               ELSE 0
           END AS rank_value
    FROM eligible_marker_rows
    WHERE trajectory IS NOT NULL AND trajectory != 'NOT_APPLICABLE'
),

system_trajectory_per_patient AS (
    SELECT patient_id,
           MAX(rank_value) AS max_traj_rank,
           CASE MAX(rank_value)
               WHEN 3 THEN 'WORSENING'
               WHEN 2 THEN 'IMPROVING'
               WHEN 1 THEN 'STABLE'
           END AS system_trajectory
    FROM trajectory_rank GROUP BY patient_id
),

trajectory_evidence AS (
    SELECT patient_id,
           GROUP_CONCAT(marker_name, ', ') AS trajectory_evidence_markers
    FROM (
        SELECT tr.patient_id, tr.marker_name
        FROM trajectory_rank tr
        JOIN system_trajectory_per_patient stp
          ON tr.patient_id = stp.patient_id
         AND tr.rank_value = stp.max_traj_rank
        ORDER BY tr.patient_id, tr.marker_name COLLATE NOCASE
    )
    GROUP BY patient_id
),

variance_rank AS (
    SELECT emr.patient_id, emr.marker_name,
           CASE WHEN emr.variance_score > p.variance_threshold
                THEN 'UNSTABLE' ELSE 'STABLE' END AS variance_state,
           CASE WHEN emr.variance_score > p.variance_threshold
                THEN 2 ELSE 1 END AS rank_value
    FROM eligible_marker_rows emr
    CROSS JOIN params p
    WHERE emr.variance_score IS NOT NULL
),

system_variance_per_patient AS (
    SELECT patient_id,
           MAX(rank_value) AS max_var_rank,
           CASE MAX(rank_value)
               WHEN 2 THEN 'UNSTABLE' WHEN 1 THEN 'STABLE'
           END AS system_variance
    FROM variance_rank GROUP BY patient_id
),

variance_evidence AS (
    SELECT patient_id,
           GROUP_CONCAT(marker_name, ', ') AS variance_evidence_markers
    FROM (
        SELECT vr.patient_id, vr.marker_name
        FROM variance_rank vr
        JOIN system_variance_per_patient svp
          ON vr.patient_id = svp.patient_id
         AND vr.rank_value = svp.max_var_rank
        ORDER BY vr.patient_id, vr.marker_name COLLATE NOCASE
    )
    GROUP BY patient_id
),

-- Sufficiency counts: SBP, HbA1c, LDL only (D-76, Option A)
sufficiency_counts AS (
    SELECT patient_id,
           SUM(CASE WHEN data_tier = 'DATA_SUFFICIENT'      THEN 1 ELSE 0 END)
               AS markers_data_sufficient,
           SUM(CASE WHEN data_tier = 'PARTIALLY_SUFFICIENT' THEN 1 ELSE 0 END)
               AS markers_partially_sufficient
    FROM marker_scores
    WHERE marker_name NOT IN ('BMI','eGFR')
    GROUP BY patient_id
)

SELECT
    ep.patient_id,
    stp.system_trajectory,
    svp.system_variance,
    te.trajectory_evidence_markers,
    ve.variance_evidence_markers,
    COALESCE(sc.markers_data_sufficient, 0)      AS markers_data_sufficient,
    COALESCE(sc.markers_partially_sufficient, 0) AS markers_partially_sufficient,
    stp.system_trajectory
        || ' (' || COALESCE(te.trajectory_evidence_markers, '') || ')'
        || ' | '
        || svp.system_variance
        || ' (' || COALESCE(ve.variance_evidence_markers, '') || ')'
        AS temporal_string,
    '20260418_TEMPORAL_V3' AS scoring_bundle
FROM eligible_patients ep
JOIN system_trajectory_per_patient stp ON ep.patient_id = stp.patient_id
JOIN system_variance_per_patient   svp ON ep.patient_id = svp.patient_id
LEFT JOIN trajectory_evidence te ON ep.patient_id = te.patient_id
LEFT JOIN variance_evidence   ve ON ep.patient_id = ve.patient_id
LEFT JOIN sufficiency_counts  sc ON ep.patient_id = sc.patient_id;

-- ============================================================
-- STEP 8: patient_bands (V6)
-- Dynamic base_band: SBP, HbA1c, LDL, eGFR only
-- BMI floor rule: Tier 2→floor 2, Tier 3→floor 3 (D-79)
-- Band driver: bmi_floor > dynamic → BMI; else argmax dynamic (D-78)
-- eGFR data_tier gate (D-74, Option A)
-- Sufficiency colour: data_tier of band_driver_marker (D-78)
-- ============================================================

DROP TABLE IF EXISTS patient_bands;

CREATE TABLE patient_bands (
    band_id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id                  TEXT NOT NULL,
    cvd_status                  TEXT,
    tier_sbp                    INTEGER,
    tier_hba1c                  INTEGER,
    tier_bmi                    INTEGER,
    tier_ldl                    INTEGER,
    tier_egfr                   INTEGER,
    dynamic_base_band           INTEGER,
    bmi_floor                   INTEGER,
    base_band                   INTEGER,
    trajectory_adjust           INTEGER,
    variance_adjust             INTEGER,
    interim_band                INTEGER,
    capped_band                 INTEGER,
    final_band                  INTEGER,
    band_driver_marker          TEXT,
    data_sufficiency_display    TEXT,
    marker_count_scored         INTEGER,
    markers_scored_count        INTEGER,
    markers_missing_count       INTEGER,
    status                      TEXT,
    scored_at                   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    scoring_bundle              TEXT,
    UNIQUE (patient_id)
);

INSERT INTO patient_bands (
    patient_id, cvd_status,
    tier_sbp, tier_hba1c, tier_bmi, tier_ldl, tier_egfr,
    dynamic_base_band, bmi_floor, base_band,
    trajectory_adjust, variance_adjust,
    interim_band, capped_band, final_band,
    band_driver_marker, data_sufficiency_display,
    marker_count_scored, markers_scored_count, markers_missing_count,
    status, scoring_bundle
)
WITH

marker_tiers AS (
    SELECT ms.patient_id, ms.marker_name, ms.mean_x, ms.mean_i, ms.data_tier,
        CASE WHEN ms.marker_name='Systolic BP' AND ms.mean_x IS NOT NULL
             THEN CASE WHEN ms.mean_x<140 THEN 0 WHEN ms.mean_x<160 THEN 1
                       WHEN ms.mean_x<180 THEN 2 ELSE 3 END
             ELSE NULL END AS tier_sbp,
        CASE WHEN ms.marker_name='HbA1c' AND ms.mean_x IS NOT NULL
             THEN CASE WHEN ms.mean_x<7.0 THEN 0 WHEN ms.mean_x<8.5 THEN 1
                       WHEN ms.mean_x<10.0 THEN 2 ELSE 3 END
             ELSE NULL END AS tier_hba1c,
        CASE WHEN ms.marker_name='BMI' AND ms.mean_x IS NOT NULL
             THEN CASE WHEN ms.mean_x<25.0 THEN 0 WHEN ms.mean_x<30.0 THEN 1
                       WHEN ms.mean_x<35.0 THEN 2 ELSE 3 END
             ELSE NULL END AS tier_bmi,
        CASE WHEN ms.marker_name='LDL Cholesterol'
             THEN CASE WHEN ms.mean_i IS NULL OR ms.mean_i=0 THEN 0
                       WHEN ms.mean_i<=0.25 THEN 1
                       WHEN ms.mean_i<=0.50 THEN 2 ELSE 3 END
             ELSE NULL END AS tier_ldl,
        -- eGFR: data_tier gate (D-74, Option A)
        CASE WHEN ms.marker_name='eGFR' AND ms.mean_x IS NOT NULL
              AND ms.data_tier IN ('DATA_SUFFICIENT','PARTIALLY_SUFFICIENT')
             THEN CASE WHEN ms.mean_x>=60.0 THEN 0
                       WHEN ms.mean_x>=45.0 THEN 1
                       WHEN ms.mean_x>=30.0 THEN 2 ELSE 3 END
             ELSE NULL END AS tier_egfr
    FROM marker_scores ms
    WHERE ms.patient_id IN (SELECT patient_id FROM priority_scores)
),

patient_tiers AS (
    SELECT patient_id,
        MAX(tier_sbp)   AS tier_sbp,
        MAX(tier_hba1c) AS tier_hba1c,
        MAX(tier_bmi)   AS tier_bmi,
        MAX(tier_ldl)   AS tier_ldl,
        MAX(tier_egfr)  AS tier_egfr,
        SUM(CASE WHEN marker_name IN ('Systolic BP','HbA1c','BMI')
                  AND mean_x IS NOT NULL THEN 1
                 WHEN marker_name='LDL Cholesterol'
                  AND mean_i IS NOT NULL THEN 1
                 WHEN marker_name='eGFR' AND mean_x IS NOT NULL
                  AND data_tier IN ('DATA_SUFFICIENT','PARTIALLY_SUFFICIENT')
                 THEN 1 ELSE 0 END) AS marker_count_scored,
        SUM(CASE WHEN marker_name IN ('Systolic BP','HbA1c','BMI')
                  AND mean_x IS NOT NULL THEN 1
                 WHEN marker_name='LDL Cholesterol'
                  AND mean_i IS NOT NULL THEN 1
                 WHEN marker_name='eGFR' AND mean_x IS NOT NULL
                  AND data_tier IN ('DATA_SUFFICIENT','PARTIALLY_SUFFICIENT')
                 THEN 1 ELSE 0 END) AS markers_scored_count,
        SUM(CASE WHEN marker_name IN ('Systolic BP','HbA1c','BMI')
                  AND mean_x IS NULL THEN 1
                 WHEN marker_name='LDL Cholesterol'
                  AND mean_i IS NULL THEN 1
                 WHEN marker_name='eGFR'
                  AND (mean_x IS NULL OR data_tier NOT IN
                      ('DATA_SUFFICIENT','PARTIALLY_SUFFICIENT'))
                 THEN 1 ELSE 0 END) AS markers_missing_count
    FROM marker_tiers GROUP BY patient_id
),

dynamic_bands AS (
    SELECT pt.patient_id,
        pt.tier_sbp, pt.tier_hba1c, pt.tier_bmi,
        pt.tier_ldl, pt.tier_egfr,
        pt.marker_count_scored, pt.markers_scored_count,
        pt.markers_missing_count,
        -- Dynamic argmax: SBP > HbA1c > LDL > eGFR tiebreak
        CASE
            WHEN COALESCE(pt.tier_sbp,-1)>=COALESCE(pt.tier_hba1c,-1)
             AND COALESCE(pt.tier_sbp,-1)>=COALESCE(pt.tier_ldl,-1)
             AND COALESCE(pt.tier_sbp,-1)>=COALESCE(pt.tier_egfr,-1)
            THEN COALESCE(pt.tier_sbp,-1)
            WHEN COALESCE(pt.tier_hba1c,-1)>=COALESCE(pt.tier_ldl,-1)
             AND COALESCE(pt.tier_hba1c,-1)>=COALESCE(pt.tier_egfr,-1)
            THEN COALESCE(pt.tier_hba1c,-1)
            WHEN COALESCE(pt.tier_ldl,-1)>=COALESCE(pt.tier_egfr,-1)
            THEN COALESCE(pt.tier_ldl,-1)
            ELSE COALESCE(pt.tier_egfr,-1)
        END AS max_dynamic_tier,
        CASE
            WHEN COALESCE(pt.tier_sbp,-1)>=COALESCE(pt.tier_hba1c,-1)
             AND COALESCE(pt.tier_sbp,-1)>=COALESCE(pt.tier_ldl,-1)
             AND COALESCE(pt.tier_sbp,-1)>=COALESCE(pt.tier_egfr,-1)
            THEN 'Systolic BP'
            WHEN COALESCE(pt.tier_hba1c,-1)>=COALESCE(pt.tier_ldl,-1)
             AND COALESCE(pt.tier_hba1c,-1)>=COALESCE(pt.tier_egfr,-1)
            THEN 'HbA1c'
            WHEN COALESCE(pt.tier_ldl,-1)>=COALESCE(pt.tier_egfr,-1)
            THEN 'LDL Cholesterol'
            ELSE 'eGFR'
        END AS dynamic_driver_marker,
        -- BMI floor (D-79)
        CASE COALESCE(pt.tier_bmi,0)
            WHEN 0 THEN 1 WHEN 1 THEN 1
            WHEN 2 THEN 2 WHEN 3 THEN 3 ELSE 1
        END AS bmi_floor
    FROM patient_tiers pt
),

base_bands AS (
    SELECT db.patient_id,
        db.tier_sbp, db.tier_hba1c, db.tier_bmi,
        db.tier_ldl, db.tier_egfr,
        db.marker_count_scored, db.markers_scored_count,
        db.markers_missing_count, db.bmi_floor, db.dynamic_driver_marker,
        CASE db.max_dynamic_tier
            WHEN -1 THEN 1 WHEN 0 THEN 1
            WHEN 1 THEN 2 WHEN 2 THEN 3 ELSE 4
        END AS dynamic_base_band,
        CASE
            WHEN db.bmi_floor > CASE db.max_dynamic_tier
                WHEN -1 THEN 1 WHEN 0 THEN 1
                WHEN 1 THEN 2 WHEN 2 THEN 3 ELSE 4 END
            THEN db.bmi_floor
            ELSE CASE db.max_dynamic_tier
                WHEN -1 THEN 1 WHEN 0 THEN 1
                WHEN 1 THEN 2 WHEN 2 THEN 3 ELSE 4 END
        END AS base_band,
        -- Band driver (D-78)
        CASE
            WHEN db.bmi_floor > CASE db.max_dynamic_tier
                WHEN -1 THEN 1 WHEN 0 THEN 1
                WHEN 1 THEN 2 WHEN 2 THEN 3 ELSE 4 END
            THEN 'BMI'
            ELSE db.dynamic_driver_marker
        END AS band_driver_marker
    FROM dynamic_bands db
),

temporal_modifiers AS (
    SELECT bb.patient_id, bb.tier_sbp, bb.tier_hba1c, bb.tier_bmi,
        bb.tier_ldl, bb.tier_egfr, bb.marker_count_scored,
        bb.markers_scored_count, bb.markers_missing_count,
        bb.dynamic_base_band, bb.bmi_floor, bb.base_band,
        bb.band_driver_marker,
        CASE WHEN pts.system_trajectory='WORSENING' THEN 1 ELSE 0 END
            AS trajectory_adjust,
        CASE WHEN pts.system_variance='UNSTABLE' THEN 1 ELSE 0 END
            AS variance_adjust
    FROM base_bands bb
    LEFT JOIN patient_temporal_signals pts ON bb.patient_id=pts.patient_id
),

band_pipeline AS (
    SELECT tm.patient_id, tm.tier_sbp, tm.tier_hba1c, tm.tier_bmi,
        tm.tier_ldl, tm.tier_egfr, tm.marker_count_scored,
        tm.markers_scored_count, tm.markers_missing_count,
        tm.dynamic_base_band, tm.bmi_floor, tm.base_band,
        tm.band_driver_marker, tm.trajectory_adjust, tm.variance_adjust,
        CASE WHEN tm.base_band IS NULL THEN NULL
             ELSE tm.base_band + tm.trajectory_adjust + tm.variance_adjust
        END AS interim_band,
        CASE WHEN tm.base_band IS NULL THEN NULL
             WHEN tm.base_band + tm.trajectory_adjust
                  + tm.variance_adjust > 4 THEN 4
             ELSE tm.base_band + tm.trajectory_adjust + tm.variance_adjust
        END AS capped_band
    FROM temporal_modifiers tm
),

final_bands AS (
    SELECT bp.patient_id, pc.cvd_status,
        bp.tier_sbp, bp.tier_hba1c, bp.tier_bmi, bp.tier_ldl, bp.tier_egfr,
        bp.marker_count_scored, bp.markers_scored_count,
        bp.markers_missing_count, bp.dynamic_base_band, bp.bmi_floor,
        bp.base_band, bp.band_driver_marker,
        bp.trajectory_adjust, bp.variance_adjust,
        bp.interim_band, bp.capped_band,
        CASE WHEN pc.cvd_status='RECENT'
              AND bp.capped_band IS NOT NULL
              AND bp.capped_band < 2 THEN 2
             ELSE bp.capped_band
        END AS final_band,
        CASE WHEN bp.marker_count_scored=0 THEN 'NO_DATA'
             WHEN bp.marker_count_scored=1 THEN 'SPARSE'
             WHEN bp.marker_count_scored=2 THEN 'PARTIAL'
             ELSE 'ROBUST'
        END AS status
    FROM band_pipeline bp
    JOIN patient_cohort pc ON bp.patient_id=pc.patient_id
),

driver_sufficiency AS (
    SELECT fb.patient_id,
        CASE ms.data_tier
            WHEN 'DATA_SUFFICIENT'      THEN 'DATA_SUFFICIENT'
            WHEN 'PARTIALLY_SUFFICIENT' THEN 'PARTIALLY_SUFFICIENT'
            ELSE 'DATA_INSUFFICIENT'
        END AS data_sufficiency_display
    FROM final_bands fb
    LEFT JOIN (
        SELECT patient_id, marker_name, MAX(data_tier) AS data_tier
        FROM marker_scores
        GROUP BY patient_id, marker_name
    ) ms ON fb.patient_id=ms.patient_id
         AND fb.band_driver_marker=ms.marker_name
)

SELECT
    fb.patient_id, fb.cvd_status,
    fb.tier_sbp, fb.tier_hba1c, fb.tier_bmi, fb.tier_ldl, fb.tier_egfr,
    fb.dynamic_base_band, fb.bmi_floor, fb.base_band,
    fb.trajectory_adjust, fb.variance_adjust,
    fb.interim_band, fb.capped_band,
    CASE WHEN fb.status='NO_DATA' THEN NULL ELSE fb.final_band END AS final_band,
    fb.band_driver_marker,
    CASE WHEN fb.status='NO_DATA' THEN 'DATA_INSUFFICIENT'
         ELSE COALESCE(ds.data_sufficiency_display,'DATA_INSUFFICIENT')
    END AS data_sufficiency_display,
    fb.marker_count_scored, fb.markers_scored_count, fb.markers_missing_count,
    fb.status,
    '20260418_BANDS_V6' AS scoring_bundle
FROM final_bands fb
LEFT JOIN driver_sufficiency ds ON fb.patient_id=ds.patient_id;
