# Project Reference Table
## Cardiometabolic Deterioration Monitoring System — P3

This document exports the `project_reference` database table in full. Every locked design decision, scoring parameter, clinical threshold, and governance rule is stored here as a versioned, queryable record. Each row references a D-series decision from `docs/sprint1_log.md`. Core scoring thresholds, windows, tier definitions, and governance parameters are stored in this table and referenced by the scoring pipeline rather than embedded as undocumented SQL constants.

Source: `project_reference` table, `p3_deterioration_full.db`  
Pipeline version: BANDS_V6 / PS_V4 / TEMPORAL_V3 — NO_DRIFT_DETECTED

---

## Observation Window

| Ref | Item | Value | Source | Decision |
|---|---|---|---|---|
| 1 | window_start | 2025-04-06 | NICE NG136 annual review cycle | D-48 |
| 2 | window_end | 2026-04-06 | Snapshot date (inclusive) | D-48 |
| 3 | min_readings | 2 | Clinical governance decision | D-49 |
| 4 | min_months | 3 | Clinical governance decision | D-49 |

---

## Clinical Thresholds

| Ref | Item | Value | Source | Decision | Notes |
|---|---|---|---|---|---|
| 5 | SBP all patients | 140 mmHg | NICE NG136 | D-39 | Diagnostic threshold proxy. Real deployment requires risk-stratified targets. |
| 6 | HbA1c all patients | 53 mmol/mol | NICE NG28 | D-39 | |
| 7 | LDL CVD present | 2.0 mmol/L | NICE NG238 | D-39 | Established or recent CVD |
| 8 | LDL no CVD | 3.0 mmol/L | NICE NG238 | D-39 | Primary prevention |
| 9 | BMI all patients | 25.0 kg/m² | NICE CG189 | D-44 | Severity only — excluded from trajectory and variance |
| 10 | LDL threshold selection rule | IF CVD_RECENT OR ESTABLISHED → LDL=2.0 ELSE 3.0 | NICE NG238 | D-39 | Applied in score_patients.sql |

---

## Marker Eligibility

| Ref | Item | Value | Source | Decision | Notes |
|---|---|---|---|---|---|
| 22 | Trajectory and variance eligible (SBP/HbA1c/LDL) and stage transition eligible (eGFR) | SBP, HbA1c, LDL (trajectory and variance); eGFR (stage transition only) | NICE longitudinal threshold structure | D-44 | eGFR receives stage transition model only — not trajectory or variance |
| 23 | Excluded from trajectory and variance | BMI | No NICE longitudinal threshold | D-44 | Severity only |
| 24 | eGFR scoring method | Stage transition — not exceedance intensity | KDIGO 2012, NICE NG203 | D-45 | |

---

## Clinical Behaviour

| Ref | Item | Value | Source | Decision | Notes |
|---|---|---|---|---|---|
| 11 | Monthly aggregation | mean(I) per calendar month | Chronic disease burden model | D-47 | Frequency bias removal — one time unit per calendar month |
| 12 | Patient severity | mean(Month_scores) | Chronic disease burden model | D-47 | Equal monthly weighting, no recency decay |
| 13 | SBP measurement error threshold | 5/130 = 0.038 I units | BHS validated device standard | D-50 | Stability threshold for trajectory classification |
| 14 | HbA1c measurement error threshold | 2/53 = 0.038 I units | RCPath HbA1c analytical guidance | D-50 | Stability threshold for trajectory classification |
| 15 | LDL biological variation threshold | 9% = 0.090 I units | RCPath clinical biochemistry | D-50 | Stability threshold for trajectory classification |
| 16 | eGFR stage transition | Confirmed by 2 readings ≥90 days apart | KDIGO 2012, NICE NG203 | D-45 | Replaces continuous trajectory for eGFR |
| 17 | Non-compensatory worst-case model | Any worsening marker = patient WORSENING. Any unstable marker = patient UNSTABLE. Improvement does not offset deterioration. | Clinical safety monitoring principle | D-51 | Applies to both trajectory and variance aggregation |
| 32 | Trajectory for PARTIALLY_SUFFICIENT | Direction only: SIGN(last_month_i - first_month_i). WORSENING if >0, IMPROVING if <0, STABLE if =0. | Clinical governance decision | D-61 | Two months insufficient for stability threshold application per BHS/RCPath |

---

## Clinical Modelling

| Ref | Item | Value | Source | Decision | Notes |
|---|---|---|---|---|---|
| 33 | Variance instability threshold | 0.001 | Empirical distribution analysis of Synthea-derived monthly I-score variance | D-62 | Separates synthetic-data noise floor (~0–0.0005) from stable physiological drift (~0.002–0.003) and higher instability (≥0.01). Sensitivity analysis documented; not externally validated. |
| 34 | Breach detection data tier gate | mean_i > 0 across all data tiers | Internal design decision | D-63 | Data tier gates trajectory and variance only. A single reading exceeding NICE threshold = breach regardless of data density. |
| 36 | Marker tier definitions — absolute | SBP: 0=<140, 1=140–159, 2=160–179, 3=≥180; HbA1c: 0=<7.0, 1=7.0–8.5, 2=8.5–10.0, 3=>10.0; BMI: 0=<25.0, 1=25.0–29.9, 2=30.0–34.9, 3=≥35.0 | NICE NG136, NG28, CG189 | D-66 | At-threshold values assigned to higher tier (D-69). Band 2 dominance reflects Synthea treatment simulation. |
| 37 | Marker tier definitions — LDL | 0=mean_i=0 or NULL; 1=mean_i 0–0.25; 2=mean_i 0.25–0.50; 3=mean_i>0.50 | NICE NG238 (threshold anchor); deviation tiers = internal design decision | D-67 | No published severity tiers above NG238 target. Deviation tiers are a design choice. |
| 39 | Tier boundary rule | At-threshold values → higher tier for absolute markers | NICE NG28 clinical interpretation | D-69 | HbA1c 7.0% → Tier 1. SBP 140 → Tier 1. LDL unaffected — uses mean_i which is 0 at threshold. |
| 40 | RECENT CVD band floor | RECENT CVD → final_band = MAX(capped_band, 2) | ESC 2021 Cardiovascular Prevention Guidelines | D-70 | RECENT CVD creates a minimum Band 2 floor. In this cohort, all 4 RECENT CVD patients were assigned Band 4 due to additional severity/temporal criteria. |
| 45 | eGFR tier definition | Tier 0: ≥60; Tier 1: 45–59; Tier 2: 30–44; Tier 3: <30 | KDIGO 2012, NICE NG203 | D-75 | Compressed from KDIGO 5-stage to 0–3 ordinal. KDIGO Stage 1 vs 2 distinction lost in compression — documented limitation. |
| 49 | BMI band dominance | BMI drives band for 110/479 scored patients (23.0%) after BMI floor rule applied (D-79) | Empirical analysis of patient_bands; NICE CG189 | D-77 | Pre-floor rule dominance was 89.9% (427/475). BMI floor rule reduced dominance by removing BMI from direct tier competition. Remaining 23.0% reflects patients where BMI floor exceeds dynamic base band. |
| 51 | BMI band floor rule | Tier 2 → floor 2; Tier 3 → floor 3; Tier 0/1 → floor 1 | NICE CG189 | D-79 | BMI contributes static risk floor, not dynamic tier competition. Prevents BMI from dominating band assignment. |

---

## CVD Recency

| Ref | Item | Value | Source | Decision | Notes |
|---|---|---|---|---|---|
| 19 | Recent CVD window | 12 months | ESC 2021, ACC/AHA 2019 | D-41 | Applies to MI, STEMI, NSTEMI, CVA only. HF is always ESTABLISHED regardless of onset date. |

---

## Output Format

| Ref | Item | Value | Source | Decision | Notes |
|---|---|---|---|---|---|
| 25 | Universal string format | CVD_STATUS\|MARKERS_BREACHING\|WORST_MARKER\|CONDITION_COUNT | Clinical governance decision | D-53 | Fixed four positions |
| 26 | WORST_MARKER format | MARKER:mean(x)/target (+deviation%) e.g. HbA1c:8.2/7.0 (+17.0%) | Clinical governance decision | D-53 | Mean value over observation window |
| 27 | NO_DEVIATION value | All markers within NICE target | Clinical governance decision | D-53 | Distinct from DATA_INSUFFICIENT |
| 28 | DATA_INSUFFICIENT value | Below minimum data threshold | Clinical governance decision | D-49 | Distinct from zero — zero means controlled |

---

## Design Rules

| Ref | Item | Value | Source | Decision | Notes |
|---|---|---|---|---|---|
| 35 | Three-layer signal architecture | NULL = undefined signal; 0 = below threshold only | Internal design decision | D-65 | mean_i=0 means controlled. mean_i=NULL means no threshold or no data. trajectory=NULL means data density insufficient. |
| 38 | Dual-scale tier input | SBP/HbA1c/BMI tier from mean_x; LDL tier from mean_i | Internal design decision | D-68 | Mixed-input model is intentional — forcing mean_i onto all markers would distort clinical meaning. |
| 41 | Marker absence handling | base_band from available markers; status = NO_DATA/SPARSE/PARTIAL/ROBUST | Internal design decision | D-71 | Absent markers contribute -1 to max_tier — never win over present markers. |
| 42 | BMI split rule | BMI included in banding; excluded from data sufficiency colour logic | Internal design decision | D-72 | Two distinct sufficiency concepts: band confidence (includes eGFR) vs temporal signal confidence (excludes eGFR). BMI excluded from both. |
| 43 | Tier normalisation rule | All tier outputs normalised to 0–3 ordinal scale | Internal design decision | D-73 | Band calculation layer receives only normalised tiers — never raw units. |
| 44 | Tier computable vs temporal evaluable | tier_computable: mean_x IS NOT NULL (absolute) or mean_i IS NOT NULL (LDL); temporal_evaluable: mean_i IS NOT NULL AND data_tier != DATA_INSUFFICIENT | Internal design decision | D-74 | Conflating these caused BANDS_V1/V2 bug — 360 patients incorrectly UNSCORED. Corrected in BANDS_V3. |
| 48 | Temporal sufficiency marker exclusions | markers_data_sufficient counts SBP, HbA1c, LDL only | Internal design decision | D-76 | BMI and eGFR excluded from temporal sufficiency counts. General data completeness = marker_count_scored in patient_bands. |
| 50 | Sufficiency colour rule | data_sufficiency_display = data_tier of band_driver_marker | Internal design decision | D-78 | BLUE = DATA_SUFFICIENT; YELLOW = PARTIALLY_SUFFICIENT; GREY = DATA_INSUFFICIENT |
| 54 | Mean deviation calculation method | Overall mean method: mean_i = MAX(0,(mean_x - T)/T) | Internal design decision | D-82 | Monthly method retained in monthly_i_scores for traceability only. Not used in final scoring. |
| 18 | Worst marker tiebreak | Ascending alphabetical marker_name | Internal design decision | D-52 | Arbitrary mechanical rule, documented as such. Supersedes earlier HbA1c > SBP > LDL > eGFR assumption which lacked citation. |

---

## Governance

| Ref | Item | Value | Source | Decision | Notes |
|---|---|---|---|---|---|
| 30 | Cohort vs scoring separation | Cohort = 631 clinically eligible patients. Scoring universe = 479 with observable data. Gap (n=152) = data absence, not exclusion. | Clinical informatics design principle | G-COHORT-01 | Ensures no silent exclusion of clinically eligible patients. Missingness explicitly modelled. |
| 52 | Emergency SBP acute exclusion gap | Sprint 1 excluded INPATIENT only; EMERGENCY SBP added in pipeline refinement | Sprint 4 validation — S04b | D-80 | 37 EMERGENCY SBP readings retained in Sprint 1. 5 readings from 2 patients at or above 140 mmHg threshold. Fixed by rebuilding obs_scoring_window excluding both encounter classes. |
| 53 | monthly_i_scores / marker_scores inconsistency | 4 DATA_INSUFFICIENT rows have mean_i discrepancy | Sprint 4 validation — M03 | D-81 | No downstream impact. marker_scores.mean_i is single source of truth. Inconsistency preserved for reproducibility. M03 severity: INFO. |

---

## Pregnancy Handling

| Ref | Item | Value | Source | Decision | Notes |
|---|---|---|---|---|---|
| 20 | Episode boundary | 270 days | Obstetric gestational maximum | D-56 | Gap >270 days = new episode |
| 21 | Active pregnancy SNOMED codes | 72892002, 47200007, 609496007, 198992004, 79586000 | Clinical classification | D-56 | Excluded from multimorbidity burden |
| 29 | Active pregnancy definition | Active SNOMED code AND onset_date within 270 days of snapshot date 2026-04-06 | Clinical governance rule | D-57 | Prevents Synthea artefact of persistent is_active flags on historical obstetric records |

---

*All values queryable from `project_reference` table in `p3_deterioration_full.db`*  
*Cross-reference: D-series decisions in `docs/sprint1_log.md`*  
*Pipeline locked: BANDS_V6 / PS_V4 / TEMPORAL_V3*
