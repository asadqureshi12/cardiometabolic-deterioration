-- validation_summary_export.sql
-- P3: Synthetic Cardiometabolic Deterioration Monitoring System
-- Export query for validation_summary.csv
-- Uses permanent tables only — no temp table dependency
-- Production pipeline: full 12-month window

WITH outcome_encounters AS (
    SELECT DISTINCT patient_id, 1 AS had_acute_encounter
    FROM encounters
    WHERE encounter_date > '2025-10-06'
      AND encounter_date <= '2026-04-06'
      AND encounter_class IN ('inpatient','emergency')
),
temporal_groups AS (
    SELECT
        pc.patient_id,
        CASE
            WHEN pts.system_trajectory = 'WORSENING'
             AND pts.system_variance   = 'UNSTABLE' THEN 'WORSENING + UNSTABLE'
            ELSE                                         'All other patients'
        END AS group_label,
        COALESCE(oe.had_acute_encounter, 0) AS event
    FROM patient_cohort pc
    LEFT JOIN patient_temporal_signals pts
      ON pc.patient_id = pts.patient_id
    LEFT JOIN outcome_encounters oe
      ON pc.patient_id = oe.patient_id
),
rates AS (
    SELECT
        SUM(CASE WHEN group_label = 'WORSENING + UNSTABLE'
                 THEN event END) * 1.0
        / NULLIF(SUM(CASE WHEN group_label = 'WORSENING + UNSTABLE'
                          THEN 1 END), 0)              AS wu_rate,
        SUM(CASE WHEN group_label = 'All other patients'
                 THEN event END) * 1.0
        / NULLIF(SUM(CASE WHEN group_label = 'All other patients'
                          THEN 1 END), 0)              AS other_rate
    FROM temporal_groups
)
SELECT
    g.group_label,
    COUNT(*)                                           AS n,
    SUM(g.event)                                       AS events,
    ROUND(100.0 * SUM(g.event) / COUNT(*), 1)         AS event_rate_pct,
    CASE g.group_label
        WHEN 'WORSENING + UNSTABLE'
        THEN ROUND(r.wu_rate / NULLIF(r.other_rate, 0), 2)
        ELSE NULL
    END                                                AS lift_ratio,
    CASE g.group_label
        WHEN 'WORSENING + UNSTABLE' THEN 1
        ELSE                             2
    END                                                AS display_order
FROM temporal_groups g
CROSS JOIN rates r
GROUP BY g.group_label, r.wu_rate, r.other_rate
ORDER BY display_order;