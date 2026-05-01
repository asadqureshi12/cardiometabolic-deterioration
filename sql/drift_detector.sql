-- ============================================================
-- drift_detector.sql
-- Compare current production outputs against golden set
-- Run after any pipeline rebuild to detect unexpected changes
-- PASS = output identical to golden set
-- FAIL = something changed — investigate before proceeding
-- ============================================================

-- ============================================================
-- LAYER 1: marker_scores drift
-- ============================================================

SELECT
    'marker_scores'          AS layer,
    'mean_i'                 AS metric,
    COUNT(*)                 AS total_rows,
    SUM(CASE WHEN ABS(COALESCE(ms.mean_i,0)
                      - COALESCE(g.mean_i,0)) > 1e-5
             THEN 1 ELSE 0 END) AS drifted_rows,
    CASE WHEN SUM(CASE WHEN ABS(COALESCE(ms.mean_i,0)
                               - COALESCE(g.mean_i,0)) > 1e-5
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM marker_scores ms
JOIN golden_marker_scores g
  ON ms.patient_id  = g.patient_id
 AND ms.loinc_code  = g.loinc_code

UNION ALL

SELECT
    'marker_scores',
    'data_tier',
    COUNT(*),
    SUM(CASE WHEN ms.data_tier != g.data_tier
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN ms.data_tier != g.data_tier
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM marker_scores ms
JOIN golden_marker_scores g
  ON ms.patient_id = g.patient_id
 AND ms.loinc_code = g.loinc_code

UNION ALL

SELECT
    'marker_scores',
    'trajectory',
    COUNT(*),
    SUM(CASE WHEN COALESCE(ms.trajectory,'NULL')
                  != COALESCE(g.trajectory,'NULL')
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN COALESCE(ms.trajectory,'NULL')
                            != COALESCE(g.trajectory,'NULL')
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM marker_scores ms
JOIN golden_marker_scores g
  ON ms.patient_id = g.patient_id
 AND ms.loinc_code = g.loinc_code

UNION ALL

SELECT
    'marker_scores',
    'variance_score',
    COUNT(*),
    SUM(CASE WHEN ABS(COALESCE(ms.variance_score,0)
                      - COALESCE(g.variance_score,0)) > 1e-6
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN ABS(COALESCE(ms.variance_score,0)
                               - COALESCE(g.variance_score,0)) > 1e-6
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM marker_scores ms
JOIN golden_marker_scores g
  ON ms.patient_id = g.patient_id
 AND ms.loinc_code = g.loinc_code

-- ============================================================
-- LAYER 2: priority_scores drift
-- ============================================================

UNION ALL

SELECT
    'priority_scores',
    'breach_count',
    COUNT(*),
    SUM(CASE WHEN ps.breach_count != g.breach_count
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN ps.breach_count != g.breach_count
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM priority_scores ps
JOIN golden_priority_scores g ON ps.patient_id = g.patient_id

UNION ALL

SELECT
    'priority_scores',
    'worst_marker_name',
    COUNT(*),
    SUM(CASE WHEN COALESCE(ps.worst_marker_name,'NULL')
                  != COALESCE(g.worst_marker_name,'NULL')
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN COALESCE(ps.worst_marker_name,'NULL')
                            != COALESCE(g.worst_marker_name,'NULL')
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM priority_scores ps
JOIN golden_priority_scores g ON ps.patient_id = g.patient_id

UNION ALL

SELECT
    'priority_scores',
    'patient_string',
    COUNT(*),
    SUM(CASE WHEN ps.patient_string != g.patient_string
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN ps.patient_string != g.patient_string
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM priority_scores ps
JOIN golden_priority_scores g ON ps.patient_id = g.patient_id

-- ============================================================
-- LAYER 3: patient_bands drift
-- ============================================================

UNION ALL

SELECT
    'patient_bands',
    'final_band',
    COUNT(*),
    SUM(CASE WHEN COALESCE(pb.final_band,-1)
                  != COALESCE(g.final_band,-1)
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN COALESCE(pb.final_band,-1)
                            != COALESCE(g.final_band,-1)
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM patient_bands pb
JOIN golden_patient_bands g ON pb.patient_id = g.patient_id

UNION ALL

SELECT
    'patient_bands',
    'band_driver_marker',
    COUNT(*),
    SUM(CASE WHEN COALESCE(pb.band_driver_marker,'NULL')
                  != COALESCE(g.band_driver_marker,'NULL')
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN COALESCE(pb.band_driver_marker,'NULL')
                            != COALESCE(g.band_driver_marker,'NULL')
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM patient_bands pb
JOIN golden_patient_bands g ON pb.patient_id = g.patient_id

UNION ALL

SELECT
    'patient_bands',
    'data_sufficiency_display',
    COUNT(*),
    SUM(CASE WHEN pb.data_sufficiency_display
                  != g.data_sufficiency_display
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN pb.data_sufficiency_display
                            != g.data_sufficiency_display
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM patient_bands pb
JOIN golden_patient_bands g ON pb.patient_id = g.patient_id

-- ============================================================
-- LAYER 4: temporal_signals drift
-- ============================================================

UNION ALL

SELECT
    'temporal_signals',
    'system_trajectory',
    COUNT(*),
    SUM(CASE WHEN pts.system_trajectory != g.system_trajectory
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN pts.system_trajectory != g.system_trajectory
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM patient_temporal_signals pts
JOIN golden_temporal_signals g ON pts.patient_id = g.patient_id

UNION ALL

SELECT
    'temporal_signals',
    'system_variance',
    COUNT(*),
    SUM(CASE WHEN pts.system_variance != g.system_variance
             THEN 1 ELSE 0 END),
    CASE WHEN SUM(CASE WHEN pts.system_variance != g.system_variance
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END
FROM patient_temporal_signals pts
JOIN golden_temporal_signals g ON pts.patient_id = g.patient_id

ORDER BY layer, metric;