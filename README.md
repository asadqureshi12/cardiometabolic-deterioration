## TL;DR

- Built a rule-based cardiometabolic deterioration monitoring system (SQL + Python + FHIR)
- 631-patient synthetic cohort (Synthea)
- 4-layer scoring: threshold exceedance → BMI floor → temporal signals → clinical caps
- Flags patients with concurrent deterioration and instability trajectories
- FHIR R4 export (39k+ resources), structurally valid
- Full validation pipeline: unit tests, golden set, drift detection
- Designed as a population prioritisation system, not diagnostic tool

![FHIR Validation](https://img.shields.io/badge/FHIR_R4-Validated-green?style=flat&logo=hl7&logoColor=white)
![Validator](https://img.shields.io/badge/HL7_Validator-v6.9.4-blue?style=flat)
![Structural Errors](https://img.shields.io/badge/Structural_Errors-0-brightgreen?style=flat)
![Resources](https://img.shields.io/badge/Resources-39%2C070-informational?style=flat)
![SQL](https://img.shields.io/badge/Primary_Language-SQL-orange?style=flat&logo=sqlite&logoColor=white)
![Tableau](https://img.shields.io/badge/Visualisation-Tableau_Public-blue?style=flat&logo=tableau&logoColor=white)
![Data](https://img.shields.io/badge/Data-Synthea_Synthetic-lightgrey?style=flat)
[![FHIR Validation](https://github.com/asadqureshi12/cardiometabolic-deterioration/actions/workflows/fhir-validation.yml/badge.svg)](https://github.com/asadqureshi12/cardiometabolic-deterioration/actions/workflows/fhir-validation.yml)

---


## 1. Clinical Context

Cardiometabolic disease — encompassing Type 2 diabetes, cardiovascular disease, hypertension, and chronic kidney disease — represents the highest burden of morbidity and hospitalisation in NHS secondary care. Deterioration in this population is characterised by gradual biomarker trajectory changes across multiple domains simultaneously. Standard clinical monitoring is episodic and reactive. This system demonstrates a proactive, longitudinal monitoring architecture that aggregates biomarker signals into a structured risk stratification output using a one-year observation window.

---

## 2. Cohort Pipeline

<p align="center">
  <img src="screenshots/excalidraw-2026-05-07-1511.png" style="max-width:100%;">
</p>
<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (3).png" width="400">
  
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (4).png" width="400">
</p>
---

## 3. Cohort Inclusion and Exclusion Logic

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (4).png" width="900">
</p>
</p>


---

## 4. CVD Status Assignment

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (3).png" style="max-width:100%;">
</p>

---

## 5. Data Sufficiency Tiers

```mermaid
flowchart TD
    OBS["Observations — 1yr window\n2025-04-06 to 2026-04-06\nper patient per marker"]

    Q1{"obs_count >= 2\nAND months >= 3?"}
    Q2{"obs_count >= 2\nAND months >= 2?"}

    DS["DATA_SUFFICIENT\nFull scoring\nexceedance + trajectory\n+ variance"]
    PS["PARTIALLY_SUFFICIENT\nSeverity only\nexceedance scored\nno trajectory"]
    DI["DATA_INSUFFICIENT\nMean exceedance only\nNo temporal signal\nNot imputed — CPL-008"]

    OBS --> Q1
    Q1 -->|Yes| DS
    Q1 -->|No| Q2
    Q2 -->|Yes| PS
    Q2 -->|No| DI

    style DS fill:#d5e8d4,stroke:#5a9e6f,color:#000000
    style PS fill:#fff2cc,stroke:#d6a500,color:#000000
    style DI fill:#f0f0f0,stroke:#999,color:#000000
```
### Data Sufficiency Interpretation

Temporal deterioration analysis requires repeated observations across time. Patients without sufficient longitudinal density cannot safely generate trajectory or variance signals without introducing synthetic assumptions or imputation bias.

Three sufficiency states were therefore implemented:

| State | Logic | Behaviour |

|---|---|---|

| `DATA_SUFFICIENT` | ≥2 observations across ≥3 months | Full temporal scoring enabled |

| `PARTIALLY_SUFFICIENT` | ≥2 observations across ≥2 months | Severity scoring only |

| `DATA_INSUFFICIENT` | Does not meet minimum temporal criteria | Mean exceedance only |

No imputation, interpolation, or synthetic trajectory reconstruction was performed. Patients with sparse data remain explicitly flagged as `DATA_INSUFFICIENT` in accordance with CPL-008.

This design prioritises transparency and auditability over artificial signal completion.

---
---

## 6. Scoring Pipeline

| Marker | Guideline | Tier 0 | Tier 1 | Tier 2 | Tier 3 |
|--------|-----------|--------|--------|--------|--------|
| Systolic BP | NICE NG136 | <140 mmHg | 140–159 | 160–179 | ≥180 |
| HbA1c | NICE NG28 | <7.0% | 7.0–8.4% | 8.5–9.9% | ≥10.0% |
| LDL (CVD) | NICE NG238 | No breach | Low excess | Moderate | High excess |
| LDL (no CVD) | NICE NG238 | No breach | Low excess | Moderate | High excess |
| eGFR | KDIGO 2012 | ≥60 | 45–59 | 30–44 | <30 |
| BMI | NICE CG189 | <25 — no floor | 25–29.9 — no floor | 30–34.9 — Band 2 floor | ≥35 — Band 3 floor |
| **Band** | | **1** | **2** | **3** | **4** |

---

## 6a. Four Layers

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (1).png" style="max-width:100%;">
</p>

### Threshold Interpretation

Threshold tiers were derived from NICE and KDIGO guidance to represent clinically interpretable exceedance severity bands rather than mathematically optimised risk coefficients.

The scoring architecture intentionally avoids probabilistic weighting or machine learning optimisation. Each marker contributes independently to escalation behaviour through transparent rule-based logic.

LDL thresholds were separated by cardiovascular disease status in alignment with NICE NG238 secondary prevention guidance.

BMI operates differently from the remaining biomarkers. Rather than contributing proportionally to score escalation, BMI functions as a minimum band floor mechanism based on obesity class severity.

---

## 7. Deterioration Band System

```mermaid
flowchart LR
    B1["Band 1 — Stable\n166 patients 34.7%\nAll markers within\nNICE thresholds\nRoutine monitoring"]
    B2["Band 2 — Monitor\n179 patients 37.4%\nOne marker outside\nthreshold or BMI\nClass I floor or\nRECENT CVD floor"]
    B3["Band 3 — Concern\n56 patients 11.7%\nTwo+ markers outside\nor BMI Class II/III\nor WORSENING/UNSTABLE"]
    B4["Band 4 — Alert\n78 patients 16.3%\nHighest risk\nMultiple breaches\nand/or both\ntemporal signals"]

    B1 --> B2 --> B3 --> B4

    style B1 fill:#d5e8d4,stroke:#5a9e6f,color:#000000
    style B2 fill:#fff2cc,stroke:#d6a500,color:#000000
    style B3 fill:#ffe6cc,stroke:#d6820a,color:#000000
    style B4 fill:#f8cecc,stroke:#b85450,color:#000000
```

---

## 8. Temporal Signal Logic

Temporal deterioration modelling was applied only to:

- systolic blood pressure (SBP)
- HbA1c
- LDL cholesterol

BMI and eGFR were intentionally excluded from temporal modelling (D-76) due to differing physiological behaviour and reduced interpretability of short-term directional change.

A total of **118 patients** met minimum temporal sufficiency criteria for longitudinal analysis.

---

### 8.1 Trajectory Classification

For each eligible marker, directional change was calculated across the one-year observation window.

Trajectory states were assigned as follows:

| State | Logic |
|---|---|
| `WORSENING` | Delta exceeds deterioration threshold |
| `IMPROVING` | Delta exceeds improvement threshold |
| `STABLE` | Delta remains within threshold bounds |

Marker-specific thresholds:

| Marker | Threshold |
|---|---|
| SBP | 0.038 |
| HbA1c | 0.038 |
| LDL | 0.090 |

---

### 8.2 Variance Classification

Trajectory direction alone may fail to identify unstable physiological behaviour. A second variance layer was therefore implemented independently of directional change.

Variance was calculated per marker using a threshold of **0.001** (D-62), derived from RCPath analytical variation guidance.

| Variance State | Logic |
|---|---|
| `UNSTABLE` | Variance above threshold |
| `STABLE` | Variance below threshold |

This allows detection of patients with fluctuating biomarker behaviour even where mean directional change is limited.

---

### 8.3 System-Level Aggregation

Marker-level outputs were aggregated using a **non-compensatory escalation model** (D-51).

System rules:

- any marker classified as `WORSENING` activates system-level `WORSENING`
- any marker classified as `UNSTABLE` activates system-level `UNSTABLE`
- improving markers do not offset deterioration elsewhere

This design intentionally mirrors conservative chronic disease escalation logic where clinically significant deterioration in one domain should not be cancelled out by improvement in another.

---

### 8.4 Highest-Priority Temporal State

Patients simultaneously classified as:

- `WORSENING`
- and `UNSTABLE`

were treated as the highest-priority temporal deterioration group.

Within the evaluated cohort:

| Group | Patients |
|---|---|
| `WORSENING + UNSTABLE` | 7 |

These patients represent concurrent directional deterioration and physiological instability across the monitored biomarker set.

---


## 9. Priority String

<p align="center">
  <img src="screenshots/Untitled-2026-05-07-1511.excalidraw (2).png" style="max-width:100%;">
</p>


---

## 10. FHIR R4 Export Architecture

```mermaid
flowchart TD
    DB["SQLite Database\n631 cohort patients\nAll scoring complete"]

    PY["fhir_export_final_v2.py\nPython — export only\nNo scoring logic in Python\nAll scoring in SQL"]

    B1["Part 1\n210 patients\n12,958 resources"]
    B2["Part 2\n210 patients\n12,468 resources"]
    B3["Part 3\n211 patients\n13,644 resources"]

    RES["Resources per patient\nPatient\nCondition — SNOMED + ICD-10\nObservation — BP panel + markers\nMedicationRequest\nEncounter\nRiskAssessment — band + trajectory"]

    VAL["HL7 FHIR Validator v6.9.4\nFHIR R4.0.1\nTerminology-related warnings only\nNo structural FHIR errors"]

    DB --> PY
    PY --> B1 & B2 & B3
    B1 & B2 & B3 --> RES
    B1 & B2 & B3 --> VAL

    style VAL fill:#d5e8d4,stroke:#5a9e6f,color:#000000
    style PY fill:#f0f0f0,stroke:#999,color:#000000
```

---

## 11. Validation Approach

```mermaid
flowchart TD
    U["Unit Tests\nlogic_unit_tests.sql\n29/29 PASS\nObservation window\nCohort logic\nScoring accuracy\nBand monotonicity"]

    G["Golden Set\ncreate_golden_set.sql\nBaseline locked\nBANDS_V6 / PS_V4\nTEMPORAL_V3"]

    D["Drift Detector\ndrift_detector.sql\n12 metrics\n0 drifted rows\nNO_DRIFT_DETECTED"]

    R["Retrospective Validation\n1yr observation window\nWORSENING+UNSTABLE n=7\nEvent rate 12.5%\nAll other patients 7.5%\nLift 1.42\nUnderpowered — methodology\ndemonstration only\nCPL-010"]

    U --> G --> D --> R

    style D fill:#d5e8d4,stroke:#5a9e6f,color:#000000
    style R fill:#fff2cc,stroke:#d6a500,color:#000000
```

---

## 12. Technical Stack

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
| Thresholds | NICE NG136, NG28, NG238, NG203 | Exceedance thresholds |
| Thresholds | KDIGO 2012 | eGFR staging |
| Thresholds | NICE CG189 | BMI floor tiers |
| Thresholds | RCPath | Variance threshold D-62 |
| Interoperability | HL7 FHIR R4.0.1 | Export standard |

---

## 13. Clinical Problem Log — Summary

| Reference | Type | Summary |
|-----------|------|---------|
| CPL-001 | Architecture | Synthea used — UCLH unavailable, MIMIC-IV requires credentialing |
| CPL-002 | Architecture | RTT design pivoted — Synthea has no waiting list fields |
| CPL-003 | Clinical Rule | BMI floor rule — excluded from dynamic argmax — D-79 NICE CG189 |
| CPL-004 | Clinical Rule | Acute SBP excluded — NICE NG136 resting BP only — D-80 |
| CPL-005 | Clinical Rule | Variance threshold 0.001 — RCPath analytical variation — D-62 |
| CPL-006 | Clinical Rule | Non-compensatory aggregation — any signal fires system flag — D-51 |
| CPL-007 | Clinical Rule | Acute event scope — metabolic deterioration not plaque rupture |
| CPL-008 | Architecture | 361 DATA_INSUFFICIENT — flagged honestly, not imputed |
| CPL-009 | Clinical Rule | CKD-only excluded — no cardiometabolic scoring target |
| CPL-010 | Validation | Retrospective validation underpowered — methodology demonstration |

---

## 14. Information Governance

### Caldicott Principles

This project was designed in compliance with the Caldicott Principles. Only the five scoring biomarkers are used — no social, behavioural, or unnecessary demographic data. In real deployment, access would be restricted to the responsible clinical team. All data is Synthea synthetic EHR — no real patient data was used at any stage. The FHIR R4 export layer is designed to enable safe, structured data sharing in a real deployment context. Data was used only for the stated purpose of building and validating the scoring pipeline.

### DCB0129

DCB0129 (Clinical Risk Management in Health IT) would apply to any real deployment. This proof-of-concept would require a full clinical risk management file — hazard log, clinical risk assessment, and safety case report — before operational use.

### DPIA

A Data Protection Impact Assessment would be required under UK GDPR Article 35 before real deployment. Key considerations: legal basis, data minimisation, access controls, retention policy, and patient notification. No DPIA is required for this synthetic data project.

---

## 15. Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| Synthea synthetic data | Observations procedurally generated | Explicitly proof-of-concept throughout |
| 75.4% DATA_INSUFFICIENT | 361 patients have no trajectory signal | Synthea sparsity — real EMIS/SystmOne would produce higher coverage |
| Retrospective validation underpowered | No statistical inference from n=7 | Methodology infrastructure is the evidence |
| Unit normalisation not applied | Mixed units within same LOINC | Thresholds calibrated to Synthea units |
| eGFR LOINC 33914-3 deprecated | CKD-EPI replacement not in Synthea | Retained with documentation |
| RxNorm medication coding | UK deployment uses dm+d | Synthea constraint — documented |

---


## 16. Patient Explorer

Interactive patient drill-down — search by ID, view band, trajectory, variance, marker scores.

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

## 17. Tableau

<p align="center">
  <img src="screenshots/Dashboard1.png" style="max-width:100%;">
</p>

<p align="center">
  <img src="screenshots/Dashboard2.png" style="max-width:100%;">
</p>

---

## 18. Disclaimer

Synthea-generated synthetic EHR data only. No real NHS patient data used or accessed. All identifiers are synthetic UUIDs. Not validated for clinical use. Not assessed under DCB0129. Must not be used for clinical decisions about real patients.

---

*Pipeline: BANDS_V6 / PS_V4 / TEMPORAL_V3 — NO_DRIFT confirmed*
*FHIR: HL7 Validator v6.9.4, R4.0.1*
*Terminology: NHS Digital TRUD MonolithRF2 GB_20260311*
*Data: Synthea 1,113-patient cohort*
