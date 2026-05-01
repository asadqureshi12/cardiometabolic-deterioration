-- ============================================================
-- create_golden_set.sql
-- Snapshot current production outputs as reference baseline
-- Run ONCE after validated pipeline build
-- Do NOT rerun unless deliberately updating the baseline
-- ============================================================

DROP TABLE IF EXISTS golden_marker_scores;

CREATE TABLE golden_marker_scores AS
SELECT
    patient_id,
    loinc_code,
    marker_name,
    data_tier,
    ROUND(mean_x, 4)         AS mean_x,
    ROUND(mean_i, 6)         AS mean_i,
    threshold_applied,
    trajectory,
    ROUND(variance_score, 8) AS variance_score
FROM marker_scores;

DROP TABLE IF EXISTS golden_priority_scores;

CREATE TABLE golden_priority_scores AS
SELECT
    patient_id,
    cvd_status,
    breach_count,
    breach_markers,
    worst_marker_name,
    ROUND(worst_marker_value, 4) AS worst_marker_value,
    worst_marker_deviation_pct,
    condition_count,
    patient_string,
    scoring_bundle
FROM priority_scores;

DROP TABLE IF EXISTS golden_patient_bands;

CREATE TABLE golden_patient_bands AS
SELECT
    patient_id,
    cvd_status,
    tier_sbp,
    tier_hba1c,
    tier_bmi,
    tier_ldl,
    tier_egfr,
    dynamic_base_band,
    bmi_floor,
    base_band,
    trajectory_adjust,
    variance_adjust,
    final_band,
    band_driver_marker,
    data_sufficiency_display,
    status,
    scoring_bundle
FROM patient_bands;

DROP TABLE IF EXISTS golden_temporal_signals;

CREATE TABLE golden_temporal_signals AS
SELECT
    patient_id,
    system_trajectory,
    system_variance,
    markers_data_sufficient,
    markers_partially_sufficient,
    scoring_bundle
FROM patient_temporal_signals;

SELECT 'golden_marker_scores'    AS tbl, COUNT(*) AS n
FROM golden_marker_scores
UNION ALL
SELECT 'golden_priority_scores',  COUNT(*) FROM golden_priority_scores
UNION ALL
SELECT 'golden_patient_bands',    COUNT(*) FROM golden_patient_bands
UNION ALL
SELECT 'golden_temporal_signals', COUNT(*) FROM golden_temporal_signals;