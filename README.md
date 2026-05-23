# Cardiometabolic Deterioration Monitoring System

![FHIR Validation](https://img.shields.io/badge/FHIR_R4-Validated-green?style=flat&logo=hl7&logoColor=white)
![Validator](https://img.shields.io/badge/HL7_Validator-v6.9.4-blue?style=flat)
![Structural Errors](https://img.shields.io/badge/Structural_Errors-0-brightgreen?style=flat)
![Resources](https://img.shields.io/badge/Resources-39%2C070-informational?style=flat)
![SQL](https://img.shields.io/badge/Primary_Language-SQL-orange?style=flat&logo=sqlite&logoColor=white)
![Tableau](https://img.shields.io/badge/Visualisation-Tableau_Public-blue?style=flat&logo=tableau&logoColor=white)
![Data](https://img.shields.io/badge/Data-Synthea_Synthetic-lightgrey?style=flat)
[![FHIR Validation](https://github.com/asadqureshi12/cardiometabolic-deterioration/actions/workflows/fhir-validation.yml/badge.svg)](https://github.com/asadqureshi12/cardiometabolic-deterioration/actions/workflows/fhir-validation.yml)

---

## TL;DR

- Rule-based cardiometabolic deterioration monitoring system built in SQL with Python and FHIR export
- 631-patient QOF-derived chronic disease cohort constructed from Synthea 1,113-patient EHR
- Two parallel output layers: deterministic clinician-facing priority string and holistic band assignment
- 4-layer scoring architecture: threshold exceedance → BMI floor → temporal signals → clinical caps
- Flags patients with concurrent deterioration trajectory and instability across biomarker domains
- FHIR R4 export — 39,070 resources, zero structural errors, HL7 Validator v6.9.4
- Four internal consistency and retrospective exploratory analyses
- No machine learning, probabilistic modelling, or predictive calibration
- All clinical reasoning in SQL — Python used for ingestion and FHIR export only

---

## Executive Summary

This system demonstrates a proactive, rule-based cardiometabolic deterioration monitoring architecture built on a 631-patient QOF-derived chronic disease cohort, producing two parallel outputs: a deterministic clinician-facing priority string and a four-band escalation signal.

Built as a synthetic proof-of-concept using Synthea EHR data, the system is designed with NHS operational deployment in mind — guideline-traceable scoring rules, explicit data insufficiency flagging, FHIR R4 interoperability, DCB0129-aware architecture, and a fully deterministic reproducible pipeline. Clinical reasoning lives entirely in SQL. Python handles ingestion and FHIR export only. The system is not validated for clinical use and must not be applied to real patients.

---

## Key Findings

| Metric | Value |
|---|---|
| Source patients | 1,113 |
| QOF chronic disease cohort | 631 |
| Scored patients | 479 |
| Temporal signal computed | 118 |
| Highest-priority (WORSENING + UNSTABLE) | 7 |
| FHIR resources exported | 39,070 |
| Structural FHIR errors | 0 |
| Unit tests | 29 / 29 PASS |
| Drift status | NO_DRIFT_DETECTED |

---

## Live Demo

<p align="center">
  <img src="screenshots/explorer-demo.gif" alt="Patient Explorer — search by ID, view band, priority string, and monthly exceedance chart" style="max-width:100%; border-radius:6px;">
</p>

<p align="center">
  <a href="https://asadqureshi12.github.io/cardiometabolic-deterioration/explorer/">Launch Patient Explorer →</a>
</p>

---

## 1. Clinical Problem

Chronic cardiometabolic deterioration rarely presents as a single catastrophic event. In routine NHS care, deterioration is often distributed across multiple biomarker domains over months or years — rising HbA1c, worsening systolic blood pressure, declining renal function, or persistent LDL elevation. These changes are typically reviewed independently during episodic disease-specific encounters rather than aggregated into a longitudinal deterioration signal.

This project explores whether guideline-defined biomarker exceedance, temporal trajectory, and instability signals can be combined into a transparent rule-based prioritisation architecture for longitudinal surveillance of chronic disease cohorts. All thresholds and escalation criteria are derived from NICE, KDIGO, RCPath, and QOF guidance. No thresholds were invented or calibrated to the dataset.

---

## 2. What the System Does

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw.png" style="max-width:100%;">
</p>

### Cohort

631 patients constructed from a Synthea 1,113-patient EHR using 46 SNOMED codes drawn from NHS England QOF clinical disease register condition groups. 41 of 46 codes confirmed in the NHS England Primary Care Domain refset (release 20260212). CKD-only patients without cardiometabolic comorbidity excluded. CVD status assigned at cohort entry — determines LDL threshold throughout scoring.

### Scoring

Five biomarkers scored against NICE and KDIGO thresholds: SBP (NG136), HbA1c (NG28), LDL (NG238), BMI (CG189), eGFR (KDIGO 2012). Exceedance intensity formula: `I = MAX(0, (x - T) / T)`. All parameters stored in reference tables — no hardcoded values in SQL.

### Temporal Signals

Applied to SBP, HbA1c, and LDL across a fixed 52-week observation window. Non-compensatory aggregation: any marker WORSENING → system WORSENING; any marker UNSTABLE → system UNSTABLE. 118 patients met minimum observation density threshold.

### Outputs

Two parallel layers:
- **Priority string** — four-field deterministic clinician-facing summary: `CVD_STATUS | MARKERS_BREACHING | WORST_MARKER | CONDITION_COUNT`
- **Band assignment** — four-band escalation signal integrating severity, BMI floor, temporal signals, and clinical caps

A single continuous risk score was intentionally avoided to preserve interpretability and prevent compensatory averaging between physiological domains — consistent with the non-compensatory aggregation principle applied throughout (D-51, CPL-006).

### Pipeline Funnel

| Stage | n |
|---|---|
| Source patients (Synthea) | 1,113 |
| QOF chronic disease cohort | 631 |
| Scored | 479 |
| Temporal signal computed | 118 |
| WORSENING + UNSTABLE | 7 |

---

## 3. Governance & Clinical Safety

The system was designed with NHS operational deployment prerequisites in mind. Full governance detail in `docs/clinical_safety_and_validation.md`.

- **Caldicott Principles** — Only five scoring biomarkers processed. No social, behavioural, or unnecessary demographic data. Minimum necessary access principle applied throughout.
- **DCB0129** — Would apply to any real deployment. Non-compensatory aggregation, explicit DATA_INSUFFICIENT flagging, and two-layer output architecture were each designed with DCB0129 auditability in mind. Four design-stage hazards identified and controlled. This proof-of-concept has not been formally assessed under DCB0129.
- **DPIA** — Required under UK GDPR Article 35 before real deployment. Not required for this synthetic data project. Legal basis, data minimisation, access controls, and patient notification obligations scoped in clinical safety document.
- **Data insufficiency** — Patients with insufficient longitudinal data are explicitly flagged as DATA_INSUFFICIENT. The clinician sees the data gap, not an absence of risk.
- **Synthetic data only** — No real NHS patient data was used or accessed at any stage.

---

## 4. Operational Considerations

**Observation density.** 74.5% of scored patients did not meet temporal threshold. EMIS and SystmOne chronic disease review pathways would produce substantially higher coverage. Observation density is the primary operational constraint — not the scoring architecture.

**EHR integration.** The SQL scoring architecture is EHR-agnostic. The integration layer would need to map local encounter classification, SNOMED coding, and LOINC observation codes to pipeline expectations.

**Clinician review capacity.** The system produces a prioritised patient list, not a care plan. Operational value depends on a defined clinical workflow for Band 3 and Band 4 patients — medication review, cardiology referral, or structured GP review.

**Coding quality.** Cohort eligibility depends on accurate SNOMED condition coding in the source EHR. A coding audit is a prerequisite for deployment.

A proposed NHS deployment architecture including data flow, integration prerequisites, scheduling cadence, and governance boundaries is documented in `docs/clinical_safety_and_validation.md` Section 6.

---

## 5. Validation & Reproducibility

Four internal consistency and retrospective exploratory analyses applied. Full results and methodology in `docs/clinical_safety_and_validation.md`.

| Component | Result |
|---|---|
| Unit tests | 29 / 29 PASS |
| Drift detection | NO_DRIFT_DETECTED |
| FHIR structural errors | 0 |
| Tier convergence (V2) | All 7 WORSENING+UNSTABLE patients in Band 4 |
| Retrospective encounter enrichment (V1) | Inverse result — synthetic data limitation, documented explicitly |

Pipeline is fully deterministic. All scoring constants stored in `scoring_constants` — no parameters hardcoded in SQL. Golden set locked at BANDS_V6 / PS_V4 / TEMPORAL_V3.

---

## 6. Repository Structure
cardiometabolic-deterioration/
├── /sql
│   ├── clean_data.sql
│   ├── load_reference.sql
│   ├── prepare_cohort.sql
│   ├── score_patients.sql
│   ├── validate_outputs.sql
│   ├── logic_unit_tests.sql
│   ├── create_golden_set.sql
│   └── drift_detector.sql
├── /python
│   ├── load_data.py
│   ├── load_snomed_map.py
│   └── fhir_export_final_v2.py
├── /fhir
│   ├── output_part1.json
│   ├── output_part2.json
│   └── output_part3.json
├── /screenshots
├── /explorer
│   └── index.html
└── /docs
├── sprint1_log.md
├── project_reference.md
└── clinical_safety_and_validation.md

---

## 7. Further Documentation

- **[Clinical Safety and Validation Report](docs/clinical_safety_and_validation.md)** — full scoring architecture, threshold tables, temporal logic, CPL, governance deep dive, validation results, known limitations
- **[Patient Explorer](https://asadqureshi12.github.io/cardiometabolic-deterioration/explorer/)** — search by patient ID, view band, priority string, marker scores, monthly exceedance chart
- **[Dashboard 1 — Population Overview](https://public.tableau.com/app/profile/33e422.prorton/viz/Cardiometabolic_Deterioration_Monitoring/Dashboard1)**
- **[Dashboard 2 — Temporal Signals](https://public.tableau.com/app/profile/33e422.prorton/viz/Cardiometabolic_Deterioration_Monitoring/Dashboard2)**

<p align="center">
  <img src="screenshots/Dashboard1.png" style="max-width:100%;">
</p>

<p align="center">
  <img src="screenshots/Dashboard2.png" style="max-width:100%;">
</p>

---

## 8. Disclaimer

Synthea-generated synthetic EHR data only. No real NHS patient data was used or accessed at any stage. All identifiers are synthetic UUIDs. No machine learning, probabilistic modelling, or predictive calibration was performed. This system has not been validated for clinical use and has not been assessed under DCB0129. It must not be used for clinical decisions about real patients.

---

*Pipeline: BANDS_V6 / PS_V4 / TEMPORAL_V3 — NO_DRIFT_DETECTED*
*FHIR: HL7 Validator v6.9.4, R4.0.1*
*Terminology: NHS Digital TRUD MonolithRF2 GB_20260311*
*Data: Synthea 1,113-patient cohort*
