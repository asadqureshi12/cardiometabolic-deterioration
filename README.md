# Cardiometabolic Deterioration Monitoring System

## TL;DR

- Rule-based cardiometabolic deterioration monitoring system built in SQL with Python and FHIR export
- 631-patient synthetic cohort derived from Synthea 1,113-patient EHR
- Two parallel output layers: objective clinician-facing priority string and holistic band assignment
- 4-layer scoring architecture: threshold exceedance → BMI floor → temporal signals → clinical caps
- Flags patients with concurrent deterioration trajectory and instability across biomarker domains
- FHIR R4 export — 39,070+ resources, zero structural errors, HL7 Validator v6.9.4
- Four complementary validation and consistency analyses
- No machine learning, probabilistic modelling, or predictive calibration was performed
- Designed as a population prioritisation system, not a diagnostic tool
- All clinical reasoning occurs in SQL; Python is used for ingestion and FHIR export only

![FHIR Validation](https://img.shields.io/badge/FHIR_R4-Validated-green?style=flat&logo=hl7&logoColor=white)
![Validator](https://img.shields.io/badge/HL7_Validator-v6.9.4-blue?style=flat)
![Structural Errors](https://img.shields.io/badge/Structural_Errors-0-brightgreen?style=flat)
![Resources](https://img.shields.io/badge/Resources-39%2C070-informational?style=flat)
![SQL](https://img.shields.io/badge/Primary_Language-SQL-orange?style=flat&logo=sqlite&logoColor=white)
![Tableau](https://img.shields.io/badge/Visualisation-Tableau_Public-blue?style=flat&logo=tableau&logoColor=white)
![Data](https://img.shields.io/badge/Data-Synthea_Synthetic-lightgrey?style=flat)
[![FHIR Validation](https://github.com/asadqureshi12/cardiometabolic-deterioration/actions/workflows/fhir-validation.yml/badge.svg)](https://github.com/asadqureshi12/cardiometabolic-deterioration/actions/workflows/fhir-validation.yml)

---

## Key Findings
| Metric | Value |
|---|---|
| Cohort patients | 631 |
| Temporal patients | 118 |
| Highest-risk patients | 7 |
| FHIR resources | 39,070 |
| Structural FHIR errors | 0 |
| Unit tests | 29/29 PASS |

---


## Live Demo

<p align="center">
  <img src="screenshots/explorer-demo.gif" alt="Patient Explorer — search by ID, view band, priority string, and monthly exceedance chart" style="max-width:100%; border-radius:6px;">
</p>

<p align="center">
  <a href="https://asadqureshi12.github.io/cardiometabolic-deterioration/explorer/">Launch Patient Explorer →</a>
</p>

---
## 1. Clinical Context

Cardiometabolic disease — encompassing Type 2 diabetes, cardiovascular disease, hypertension, and chronic kidney disease — represents the highest burden of morbidity and hospitalisation in NHS secondary care. Deterioration in this population is characterised by gradual, simultaneous biomarker trajectory changes across multiple physiological domains. Standard clinical monitoring is episodic and reactive. This system demonstrates a proactive, longitudinal monitoring architecture that aggregates biomarker signals into a structured deterioration prioritisation output using a one-year observation window.

All clinical thresholds and escalation criteria are derived from NICE, KDIGO, RCPath, and QOF guidance. No thresholds were invented or calibrated to the dataset.

---

## 2. Cohort Pipeline

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw.png" style="max-width:100%;">
</p>

| Stage | n |
|---|---|
| Source patients (Synthea) | 1,113 |
| Cardiometabolic cohort (CKD-only exclusion applied) | 631 |
| Scored (sufficient marker data) | 479 |
| Temporal signal computed (observation density threshold met) | 118 |
| WORSENING + UNSTABLE | 7 |

The attrition from 479 scored to 118 temporal reflects a deliberate design constraint: trajectory and variance signals require minimum longitudinal observation density across SBP, HbA1c, and LDL. Synthea under-populates outpatient observations relative to NHS EHR systems such as EMIS or SystmOne. In a real deployment, temporal coverage would be substantially higher.

---

## 3. Cohort Selection

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511 (4).png" style="max-width:100%;">
</p>

---

## 4. CVD Status Assignment

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (3).png" style="max-width:100%;">
</p>

---

## 5. Data Sufficiency Tiers

Temporal deterioration analysis requires repeated observations across time. Patients without sufficient longitudinal density cannot safely generate trajectory or variance signals without introducing synthetic assumptions or imputation bias.

Three sufficiency states were implemented:

| State | Logic | Behaviour |
|---|---|---|
| `DATA_SUFFICIENT` | ≥2 observations across ≥3 months | Full temporal scoring enabled |
| `PARTIALLY_SUFFICIENT` | ≥2 observations across ≥2 months | Severity scoring only |
| `DATA_INSUFFICIENT` | Does not meet minimum temporal criteria | Mean exceedance only |

No imputation, interpolation, or synthetic trajectory reconstruction was performed. Patients with sparse data remain explicitly flagged as `DATA_INSUFFICIENT` in accordance with CPL-008. This design prioritises transparency and auditability over artificial signal completion.

---

## 6. Scoring Architecture — Two Output Layers

The system produces two parallel and independent output layers. This was an explicit architectural decision.

### Layer 1 — Objective Clinician-Facing Priority String

A six-field structured string encoding the patient's physiological position:
CVD_STATUS | MARKERS_BREACHING | WORST_SEVERITY | SYSTEM_TRAJECTORY | SYSTEM_VARIANCE | CONDITION_COUNT
This layer is designed for objective clinical interpretation. A clinician can read the string and understand the patient's cardiometabolic state without needing to interpret a composite score. Each field maps directly to a computable, guideline-anchored value. This layer contains no subjectivity — it reports what the data shows.

### Layer 2 — Holistic Band Assignment (Bands 1–4)

A composite prioritisation category that integrates clinical severity, temporal trajectory, structural clinical concern, and data sufficiency into a single triage band. This layer is designed to support clinical decision-making rather than replace it. Band assignment is a prioritisation signal — it indicates which patients warrant closer review, not what clinical action should follow.

The separation of these two layers reflects the DCB0129 principle that clinical decision support tools must be transparent, auditable, and interpretable by the clinician using them.

### Why Rule-Based Instead of ML?

Interpretability, auditability, guideline traceability, and DCB0129 alignment were prioritised over predictive optimisation. A rule-based system produces outputs that can be fully explained to a clinician, fully traced to a published source, and fully audited in a clinical safety case. A probabilistic model optimised to a synthetic dataset would produce none of these properties and would require real-world validation before any NHS governance body would consider deployment. The design choice was deliberate.

---

## 7. Band Distribution

Band assignment covers all 479 scored patients. Temporal signal computation is a separate downstream step applied to the 118 patients who met observation density criteria — it does not gate band assignment.

| Band | n (all scored) | Interpretation |
|---|---|---|
| 1 | 166 | Stable — no active exceedance |
| 2 | 179 | Emerging concern — monitoring indicated |
| 3 | 56 | Significant deterioration — clinical review |
| 4 | 78 | Highest-priority surveillance state |
| **Total** | **479** | |

Of the 78 Band 4 patients, 118 received temporal scoring. Of those 118, 7 carry a WORSENING+UNSTABLE temporal signal — concurrent deterioration trajectory and instability confirmed across biomarker domains. These 7 patients represent the intersection of the highest band assignment and the highest-priority temporal designation, arrived at through two independent scoring pathways that share no underlying logic.

---

## 8. Temporal Signal Logic

Temporal modelling applied to **SBP, HbA1c, and LDL only**. BMI and eGFR excluded (D-76) — BMI does not produce a meaningful short-term trajectory signal and contributes via the band floor mechanism instead; eGFR is modelled via the KDIGO stage transition framework rather than continuous exceedance. **118 patients** met temporal sufficiency criteria.

### 8.1 Trajectory and Variance

| Component | State | Logic | Threshold |
|---|---|---|---|
| **Trajectory** | WORSENING | Delta exceeds deterioration threshold | SBP 0.038 / HbA1c 0.038 / LDL 0.090 |
| | IMPROVING | Delta exceeds improvement threshold | Same as above |
| | STABLE | Within bounds | — |
| **Variance** | UNSTABLE | Variance > threshold | 0.001 (D-62, RCPath analytical variation) |
| | STABLE | Variance ≤ threshold | 0.001 |

Trajectory captures directional change. Variance captures physiological volatility — a stable mean with high variance indicates an unpredictable trajectory, which carries distinct clinical concern from a patient whose markers are consistently elevated but stable.

### 8.2 System-Level Aggregation (D-51)

Non-compensatory worst-case aggregation is applied at the system level:

- Any marker WORSENING → system WORSENING
- Any marker UNSTABLE → system UNSTABLE
- Improvements in one marker do not offset deterioration elsewhere

This is a clinical safety governance decision. In chronic disease monitoring, severe compromise in one physiological domain must not be masked by stability in another. A patient with controlled HbA1c but worsening SBP and LDL carries genuine cardiovascular clinical concern. Compensatory averaging would suppress that signal.

### 8.3 Highest-Priority Temporal State

| Group | Definition | n |
|---|---|---|
| **WORSENING + UNSTABLE** | Concurrent deterioration and instability across markers | 7 |

---

## 9. Priority String

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (2).png" style="max-width:100%;">
</p>

### Example Priority String — Annotated
CVD_POSITIVE | 3 | HIGH | WORSENING | UNSTABLE | 4
| Field | Value | Meaning |
|---|---|---|
| CVD_STATUS | `CVD_POSITIVE` | Established cardiovascular disease — lower LDL threshold applies (NICE NG238) |
| MARKERS_BREACHING | `3` | 3 of 5 scored markers exceed their guideline threshold |
| WORST_SEVERITY | `HIGH` | Highest single-marker exceedance intensity falls in the HIGH tier (>50% above threshold) |
| SYSTEM_TRAJECTORY | `WORSENING` | At least one temporal marker shows a deteriorating directional trend |
| SYSTEM_VARIANCE | `UNSTABLE` | At least one temporal marker shows variance above the RCPath analytical variation threshold |
| CONDITION_COUNT | `4` | 4 active coded conditions in the cardiometabolic domain |

A clinician reading this string can immediately identify that this patient has established CVD, three markers above threshold with at least one severely elevated, a worsening and unstable trajectory, and a high comorbidity burden — without needing to interpret a composite score.

---

## 10. Scoring Pipeline

| Marker | Guideline | Tier 0 | Tier 1 | Tier 2 | Tier 3 |
|--------|-----------|--------|--------|--------|--------|
| Systolic BP | NICE NG136 | <140 mmHg | 140–159 | 160–179 | ≥180 |
| HbA1c | NICE NG28 | <7.0% | 7.0–8.4% | 8.5–9.9% | ≥10.0% |
| LDL (CVD) | NICE NG238 | No breach | Low excess (0–25%) | Moderate (25–50%) | High excess (>50%) |
| LDL (no CVD) | NICE NG238 | No breach | Low excess (0–25%) | Moderate (25–50%) | High excess (>50%) |
| eGFR | KDIGO 2012 | ≥60 | 45–59 | 30–44 | <30 |
| BMI | NICE CG189 | <25 | 25–29.9 | 30–34.9 → Band 2 floor | ≥35 → Band 3 floor |
| **Band** | **Derived composite** | **1** | **2** | **3** | **4** |
| **Interpretation** | | **Stable** | **Emerging concern** | **Significant deterioration** | **Highest-priority** |

### Exceedance Intensity Formula

For all continuous markers: I = MAX(0, (x - T) / T)
Where `x` is the patient's observed mean value and `T` is the published guideline threshold. This produces a normalised exceedance intensity anchored to the threshold. Two patients can cross the same threshold but receive different scores if their absolute exceedance differs. Intensity feeds into the WORST_SEVERITY field of the priority string and into band escalation logic via non-compensatory aggregation.

LDL does not have published severity tiers above the NICE NG238 target threshold. The deviation tiers (0–25%, 25–50%, >50% exceedance) are a design choice anchored to the NICE NG238 threshold as the reference point. BMI functions as a minimum band floor mechanism based on obesity class severity per NICE CG189 rather than contributing proportionally to score escalation.

---

## 10a. Four Scoring Layers

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (1).png" style="max-width:100%;">
</p>

---

## 11. System Architecture

Synthea CSVs
│
▼
load_data.py ──────────────────── SQLite Database
│                                   │
load_snomed_map.py                       │
│                            SQL Scoring Pipeline
└──────────────────────────► clean_data.sql
load_reference.sql
prepare_cohort.sql
score_patients.sql
validate_outputs.sql
│
┌──────────────┼──────────────┐
▼              ▼              ▼
fhir_export       Tableau         explorer/
_final_v2.py      Public          index.html
│              │              │
FHIR R4         Dashboard 1    GitHub Pages
Bundles         Dashboard 2    Patient drill-down
│
HL7 Validator
v6.9.4
0 structural errors
---

## 12. FHIR R4 Export

All 631 cohort patients were exported as FHIR R4 bundles using `fhir_export_final_v2.py`. No scoring logic sits in Python — the export script reads final scoring outputs from SQLite and maps them to FHIR resource types. All clinical reasoning is in SQL.

The export produces 39,070 resources across three batch files. Each patient bundle contains: `Patient`, `Condition` (SNOMED CT + ICD-10), `Observation` (BP panel and biomarkers, LOINC-coded), `MedicationRequest` (RxNorm), `Encounter`, and `RiskAssessment` (deterioration band and temporal trajectory).

Validated against HL7 FHIR Validator v6.9.4 against the R4.0.1 specification. Zero structural errors. Residual warnings are terminology-related and reflect the synthetic data source — documented limitations consistent with P2.

| Batch | Patients | Resources |
|---|---|---|
| Part 1 | 210 | 12,958 |
| Part 2 | 210 | 12,468 |
| Part 3 | 211 | 13,644 |
| **Total** | **631** | **39,070** |

---

## 13. Validation

Four complementary validation and consistency analyses were applied. Given the WORSENING+UNSTABLE group contains 7 patients (CPL-010), no method achieves the n≥20 threshold required for directional statistical inference. This is retrospective observational enrichment analysis, not prospective prediction modelling. The validation pipeline demonstrates that the system is designed to be testable and that its outputs are internally consistent — it does not constitute a performance benchmark.

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (12).png" style="max-width:100%;">
</p>

---

### V1 — Retrospective Acute Encounter Analysis

WORSENING+UNSTABLE patients were compared against all other temporal patients for acute or inpatient encounter rate in the 6 months following the observation window close date.

| Group | n | Acute encounters | Event rate |
|---|---|---|---|
| WORSENING + UNSTABLE | 7 | 0 | 0.0% |
| All other patients | 111 | 17 | 15.3% |

The inverse result — flagged patients showing lower acute encounter rates than the unflagged group — is the synthetic data limitation made quantitatively explicit. Synthea does not generate the clinical trajectories that precede real-world acute admissions in cardiometabolic populations. The scoring rules remain internally consistent and guideline-anchored. The synthetic population does not exhibit the physiological patterns those rules are designed to detect.

### V2 — Tier Convergence (Internal Consistency)

WORSENING+UNSTABLE patients were cross-tabulated against band assignment to test whether two independent scoring layers converge on the same patients. Note: this table covers the 118 temporal patients only, as temporal signal comparison requires temporal data on both sides.

| Group | Band 1 | Band 2 | Band 3 | Band 4 |
|---|---|---|---|---|
| WORSENING + UNSTABLE | 0 | 0 | 0 | 7 |
| All other patients | 31 | 27 | 23 | 23 |

All 7 WORSENING+UNSTABLE patients sit in Band 4. Zero are in Bands 1–3. The band system and the temporal signal system were computed through entirely independent scoring pathways with no shared logic. Their convergence on the same seven patients is the strongest consistency finding in the set.

### V3 — Delta Mean Exceedance Intensity

Average exceedance intensity (mean_i) was compared between groups to test whether flagged patients show higher absolute deviation from guideline thresholds.

| Group | n | Average mean_i | Min | Max |
|---|---|---|---|---|
| WORSENING + UNSTABLE | 7 | 0.1875 | 0.000 | 0.902 |
| All other patients | 111 | 0.1124 | 0.000 | 2.146 |

WORSENING+UNSTABLE patients show 67% higher average exceedance intensity. The higher maximum in the all-other-patients group reflects individual patients with extreme single-marker exceedance without concurrent trajectory deterioration — consistent with the system's design, which requires multi-domain signal convergence for the highest-priority escalation state, not single-marker extremity.

### V4 — Monthly Slope Analysis

Monthly mean_i was tracked across the observation window for both groups to test whether flagged patients show a directional upward trend.

| Month | WORSENING+UNSTABLE | All other patients |
|---|---|---|
| 2025-04 | 0.021 | 0.140 |
| 2025-05 | 0.276 | 0.117 |
| 2025-06 | 0.062 | 0.118 |
| 2025-07 | 0.149 | 0.125 |
| 2025-08 | 0.220 | 0.128 |
| 2025-09 | 0.155 | 0.141 |
| 2025-10 | 0.225 | 0.140 |
| 2025-11 | 0.191 | 0.107 |
| 2025-12 | 0.212 | 0.135 |
| 2026-01 | 0.309 | 0.149 |
| 2026-02 | 0.318 | 0.128 |
| 2026-03 | 0.365 | 0.126 |

The WORSENING+UNSTABLE group shows a clear upward trajectory from 0.021 in April 2025 to 0.365 in March 2026. The all-other-patients group oscillates flatly between 0.107 and 0.150 with no directional trend across the same period.

---

## 14. Operational Considerations

This section documents deployment constraints that would need to be addressed before a system of this architecture could be operationalised in an NHS setting.

**Observation density.** The system requires minimum longitudinal observation density across SBP, HbA1c, and LDL to generate temporal signals. In this synthetic cohort, 74.5% of scored patients did not meet the temporal threshold. Real-world EHR systems with structured chronic disease review pathways — EMIS, SystmOne — would produce substantially higher coverage. Observation density is the primary operational constraint on system utility, not the scoring architecture.

**EHR integration.** Deployment would require a defined data extraction pathway from the source EHR into the scoring pipeline. The SQL scoring architecture is EHR-agnostic; the integration layer would need to map local encounter classification, SNOMED coding, and LOINC observation codes to the formats expected by the pipeline.

**Clinician review capacity.** The system produces a prioritised patient list, not a care plan. The operational value depends on whether the clinical team has the capacity to act on escalation signals — a medication review appointment, a community cardiology referral, a structured GP review. Without a defined clinical workflow for Band 3 and Band 4 patients, the output is informational rather than operational.

**Coding quality.** The system's cohort eligibility gate depends on accurate SNOMED condition coding in the source EHR. Incomplete or inconsistent coding of hypertension, diabetes, and CVD diagnoses would affect cohort completeness. A coding audit would be a prerequisite for deployment.

---

## 15. Technical Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| Primary language | SQL — SQLite / DB Browser | Cleaning, cohort, scoring, validation |
| Data ingestion | Python — load_data.py | Synthea CSVs into SQLite |
| Terminology loading | Python — load_snomed_map.py | MonolithRF2 SNOMED→ICD-10 |
| FHIR export | Python — fhir_export_final_v2.py | FHIR R4 Bundle JSON |
| Visualisation | Tableau Public | Clinical dashboards |
| Patient explorer | HTML/JS — GitHub Pages | Individual patient drill-down |
| Conditions | SNOMED CT MonolithRF2 GB_20260311 | Primary condition coding |
| Conditions | ICD-10 5th Edition | Secondary condition coding |
| Observations | LOINC | Biomarker coding |
| Medications | RxNorm | Medication coding |
| Thresholds | NICE NG136, NG28, NG238, NG203, CG189 | Exceedance thresholds |
| Thresholds | KDIGO 2012 | eGFR staging |
| Thresholds | RCPath | Variance threshold (D-62) |
| Interoperability | HL7 FHIR R4.0.1 | Export standard |

---

## 16. Repository Structure/sql
clean_data.sql
load_reference.sql
prepare_cohort.sql
score_patients.sql
validate_outputs.sql
logic_unit_tests.sql
create_golden_set.sql
drift_detector.sql
/python
load_data.py
load_snomed_map.py
fhir_export_final_v2.py
/fhir
output_part1.json
output_part2.json
output_part3.json
/screenshots
dashboard1.png
dashboard2.png
[excalidraw diagrams]
/explorer
index.html
/docs
sprint1_log.md
sprint2_log.md
---

## 17. Reproducibility

The pipeline is fully deterministic. Running the SQL files in execution order against the source Synthea CSVs will reproduce all outputs exactly.

**Execution order:**

load_data.py               — ingest Synthea CSVs into SQLite
load_snomed_map.py         — load SNOMED→ICD-10 reference table
clean_data.sql             — Sprint 1 data quality framework (67 rules)
load_reference.sql         — reference tables: nice_thresholds, scoring_constants, condition_classification
prepare_cohort.sql         — cohort eligibility, CVD status assignment, patient_cohort
score_patients.sql         — marker scoring, band assignment, temporal signals
validate_outputs.sql       — unit tests, golden set comparison, drift detection
fhir_export_final_v2.py    — FHIR R4 Bundle export (3 parts)

**Locked pipeline versions:**

| Component | Version |
|---|---|
| Band assignment | BANDS_V6 |
| Priority scores | PS_V4 |
| Temporal signals | TEMPORAL_V3 |
| Drift status | NO_DRIFT_DETECTED |
| Unit tests | 29/29 PASS |
| FHIR validator | HL7 v6.9.4, R4.0.1 |
| SNOMED release | NHS Digital TRUD MonolithRF2 GB_20260311 |

All scoring constants are stored in the `scoring_constants` reference table and are queryable. No scoring parameters are hardcoded in SQL comments.

---

## 18. Clinical Problem Log — Summary

| Reference | Type | Summary |
|-----------|------|---------|
| CPL-001 | Architecture | Synthea used — UCLH unavailable, MIMIC-IV requires credentialing |
| CPL-002 | Architecture | RTT design pivoted — Synthea has no waiting list fields |
| CPL-003 | Clinical Rule | BMI floor rule — excluded from dynamic argmax — D-79, NICE CG189 |
| CPL-004 | Clinical Rule | Acute SBP excluded — NICE NG136 resting BP only — D-80 |
| CPL-005 | Clinical Rule | Variance threshold 0.001 — RCPath analytical variation — D-62 |
| CPL-006 | Clinical Rule | Non-compensatory aggregation — any signal fires system flag — D-51 |
| CPL-007 | Clinical Rule | Acute event scope limited to metabolic deterioration — plaque rupture explicitly out of scope |
| CPL-008 | Architecture | 361 DATA_INSUFFICIENT — flagged honestly, not imputed |
| CPL-009 | Clinical Rule | CKD-only patients excluded — no cardiometabolic scoring target without HTN or DM |
| CPL-010 | Validation | Retrospective analysis underpowered (n=7) — four methods documented as methodology demonstration |

---

## 19. Information Governance

### Caldicott Principles

This project was designed in compliance with the Caldicott Principles. Only the five scoring biomarkers are used — no social, behavioural, or unnecessary demographic data is processed. In real deployment, access would be restricted to the responsible clinical team with a defined minimum necessary access policy. All data used in this project is Synthea synthetic EHR — no real patient data was used or accessed at any stage. Data was used only for the stated purpose of building and validating the scoring pipeline.

### DCB0129

DCB0129 (Clinical Risk Management in Health IT) would apply to any real deployment. This proof-of-concept would require a full clinical risk management file — including a hazard log, clinical risk assessment, and safety case report — before operational use. The non-compensatory aggregation design, the explicit DATA_INSUFFICIENT flagging, and the two-layer output architecture were each made with DCB0129 auditability in mind.

### DPIA

A Data Protection Impact Assessment would be required under UK GDPR Article 35 before real deployment. Key considerations would include: legal basis for processing, data minimisation, access controls, retention policy, and patient notification obligations. No DPIA is required for this synthetic data project.

---

## 20. Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| Synthea synthetic data | Observations procedurally generated — does not reproduce NHS clinical complexity | Explicitly proof-of-concept throughout; scoring rules anchored to published guidelines, not dataset |
| 75.4% DATA_INSUFFICIENT for temporal scoring | 361 patients have no trajectory signal | Synthea observation sparsity — real EMIS/SystmOne data would produce substantially higher temporal coverage |
| Retrospective analysis underpowered | n=7 WORSENING+UNSTABLE — no statistical inference possible | Four-method validation pipeline documented as methodology infrastructure, not performance benchmark |
| Unit normalisation not applied | Mixed units within same LOINC code possible | Thresholds calibrated to Synthea unit conventions — documented limitation |
| eGFR LOINC 33914-3 deprecated | CKD-EPI replacement LOINC not present in Synthea | Retained with documentation |
| RxNorm medication coding | UK deployment uses dm+d | Synthea constraint — dm+d mapping identified as deployment prerequisite |
| 4 DATA_INSUFFICIENT rows show mean_i discrepancy between marker_scores and monthly_i_scores | Minor inconsistency (D-81) | No downstream impact — marker_scores.mean_i is single source of truth — inconsistency preserved for reproducibility |

---

## 21. Patient Explorer

Interactive patient drill-down — search by ID, view band, trajectory, variance, and marker scores.

**[Launch Patient Explorer](https://asadqureshi12.github.io/cardiometabolic-deterioration/explorer/)**

Features:
- Search by patient ID with autocomplete
- Deterioration band badge coloured by data sufficiency
- Scoring pathway breakdown
- Priority string with field annotations
- Marker scores table
- Monthly exceedance chart (SBP, HbA1c, LDL)
- WORSENING+UNSTABLE alert banner

---

## 22. Tableau Dashboards

**[Dashboard 1 — Population Overview](https://public.tableau.com/app/profile/33e422.prorton/viz/Cardiometabolic_Deterioration_Monitoring/Dashboard1)**

**[Dashboard 2 — Temporal Signals](https://public.tableau.com/app/profile/33e422.prorton/viz/Cardiometabolic_Deterioration_Monitoring/Dashboard2)**

<p align="center">
  <img src="screenshots/Dashboard1.png" style="max-width:100%;">
</p>

<p align="center">
  <img src="screenshots/Dashboard2.png" style="max-width:100%;">
</p>

---

## 23. Disclaimer

Synthea-generated synthetic EHR data only. No real NHS patient data was used or accessed at any stage. All identifiers are synthetic UUIDs. No machine learning, probabilistic modelling, or predictive calibration was performed. This system has not been validated for clinical use and has not been assessed under DCB0129. It must not be used for clinical decisions about real patients.

---

*Pipeline: BANDS_V6 / PS_V4 / TEMPORAL_V3 — NO_DRIFT confirmed*
*FHIR: HL7 Validator v6.9.4, R4.0.1*
*Terminology: NHS Digital TRUD MonolithRF2 GB_20260311*
*Data: Synthea 1,113-patient cohort*
