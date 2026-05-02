## TL;DR

- Built a rule-based cardiometabolic deterioration monitoring system (SQL + Python + FHIR)
- 631-patient synthetic cohort (Synthea)
- 4-layer scoring: threshold exceedance → BMI floor → temporal signals → clinical caps
- Identifies high-risk patients via WORSENING + UNSTABLE trajectories
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

```mermaid
flowchart TD
    A["Source Population\n1,113 Synthea patients\nSynthetic EHR"]
    B["Cardiometabolic Cohort\n631 patients\nQualifying cardiometabolic condition\nCKD retained only with T2DM or HTN"]
    C["Scored Patients\n479 patients\nNICE threshold exceedance\nBands 1-4 assigned"]
    D["Temporally Evaluable\n118 patients\nTrajectory and variance\ncalculated — 1yr window"]
    E["Highest Priority\n7 patients\nWORSENING + UNSTABLE\nBoth signals active"]

    A -->|"482 excluded\nNo qualifying condition"| B
    B -->|"152 excluded\nInsufficient observations"| C
    C -->|"361 DATA_INSUFFICIENT\nSynthea observation sparsity"| D
    D -->|"111 — one signal only\nnot both simultaneously"| E

    style A fill:#f0f0f0,stroke:#999,color:#000000
    style B fill:#dce8f5,stroke:#4a90d9,color:#000000
    style C fill:#d5e8d4,stroke:#5a9e6f,color:#000000
    style D fill:#fff2cc,stroke:#d6a500,color:#000000
    style E fill:#f8cecc,stroke:#b85450,color:#000000
```

---

## 3. Cohort Inclusion and Exclusion Logic

```mermaid
flowchart TD
    START["All 1,113 Synthea patients"]

    Q1{"Qualifying condition\nfrom 46-code\ncardiometabolic set?\nclinical_active + is_active=1"}

    Q2{"CKD present?"}

    Q3{"T2DM or HTN\nalso present?"}

    EXCLUDE1["Excluded\nNo qualifying condition"]
    EXCLUDE2["Excluded — CKD only\nNo scoring target\nNo SBP/HbA1c/LDL pathway\nCPL-004"]
    INCLUDE["Included\n631 patients\ncvd_status assigned\nRECENT / ESTABLISHED / NONE"]

    START --> Q1
    Q1 -->|No| EXCLUDE1
    Q1 -->|Yes| Q2
    Q2 -->|No| INCLUDE
    Q2 -->|Yes| Q3
    Q3 -->|No| EXCLUDE2
    Q3 -->|Yes| INCLUDE

    style EXCLUDE1 fill:#f8cecc,stroke:#b85450,color:#000000
    style EXCLUDE2 fill:#f8cecc,stroke:#b85450,color:#000000
    style INCLUDE fill:#d5e8d4,stroke:#5a9e6f,color:#000000
```

---

## 4. CVD Status Assignment

```mermaid
flowchart TD
    P["Patient in cohort"]

    Q1{"STEMI or NSTEMI\nwithin 365 days?\nSNOMED 401303003\nor 401314000"}

    Q2{"Any CVD condition\nat any time?\nIHD, HF, AF, valve,\nMI/CABG history"}

    RECENT["RECENT — n=4\nBand floor = 2\nLDL target 77.3 mg/dL\nNICE NG238 post-ACS"]
    ESTABLISHED["ESTABLISHED — n=204\nLDL target 77.3 mg/dL\nNICE NG238"]
    NONE["NONE — n=423\nLDL target 116.0 mg/dL\nNICE NG238"]

    P --> Q1
    Q1 -->|Yes| RECENT
    Q1 -->|No| Q2
    Q2 -->|Yes| ESTABLISHED
    Q2 -->|No| NONE

    style RECENT fill:#f8cecc,stroke:#b85450,color:#000000
    style ESTABLISHED fill:#fff2cc,stroke:#d6a500,color:#000000
    style NONE fill:#d5e8d4,stroke:#5a9e6f,color:#000000
```

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

---

## 6. Scoring Pipeline — Four Layers

```mermaid
flowchart TD
    L1["Layer 1 — NICE Threshold Exceedance\nI = max(0, x-T / T) per marker per month\nSBP · HbA1c · LDL · eGFR\nNICE NG136 · NG28 · NG238 · NG203/KDIGO\nAcute inpatient SBP excluded\nNICE NG136 specifies resting BP — D-80"]

    L2["Layer 2 — BMI Floor Rule\nNICE CG189 / D-79\nBMI excluded from exceedance argmax\nSets minimum band only\nClass I BMI 30-34.9 — floor Band 2\nClass II BMI 35-39.9 — floor Band 3\nClass III BMI 40+ — floor Band 3\nbase_band = MAX(dynamic, bmi_floor)"]

    L3["Layer 3 — Temporal Elevation\nNon-compensatory — D-51\nWORSENING marker — trajectory +1\nUNSTABLE marker — variance +1\nImprovement in one marker\ndoes not offset deterioration\nin another"]

    L4["Layer 4 — Cap and CVD Floor\nfinal_band = MIN(interim, 4)\nRECENT CVD — floor Band 2\nMI/NSTEMI within 365 days\ncannot score below Band 2"]

    L1 --> L2 --> L3 --> L4

    style L1 fill:#dce8f5,stroke:#4a90d9,color:#000000
    style L2 fill:#fff2cc,stroke:#d6a500,color:#000000
    style L3 fill:#ffe6cc,stroke:#d6820a,color:#000000
    style L4 fill:#f8cecc,stroke:#b85450,color:#000000
```

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

```mermaid
flowchart TD
    M["SBP · HbA1c · LDL\nBMI and eGFR excluded\nfrom temporal model — D-76\n118 evaluable patients"]

    T["Trajectory per marker\nWORSENING if delta > threshold\nSBP/HbA1c: 0.038\nLDL: 0.090\nIMPROVING if delta < -threshold\nSTABLE otherwise"]

    V["Variance per marker\nThreshold = 0.001 — D-62\nRCPath analytical variation\nAbove = UNSTABLE\nBelow = STABLE"]

    AGG["Non-compensatory aggregation\nD-51\nAny WORSENING — system WORSENING\nAny UNSTABLE — system UNSTABLE\nImprovement does NOT\noffset deterioration"]

    RESULT["7 patients\nWORSENING + UNSTABLE\nBoth signals active\nHighest priority flag"]

    M --> T
    M --> V
    T --> AGG
    V --> AGG
    AGG --> RESULT

    style AGG fill:#ffe6cc,stroke:#d6820a,color:#000000
    style RESULT fill:#f8cecc,stroke:#b85450,color:#000000
```

---

## 9. Priority String

```mermaid
flowchart LR
    S["ESTABLISHED | 3 | HbA1c:8.2/7.0 +17% | 4"]

    F1["Field 1\nCVD Status\nESTABLISHED\nRECENT / NONE"]
    F2["Field 2\nBreach Count\nMarkers above\nNICE threshold"]
    F3["Field 3\nWorst Marker\nName:value/threshold\n+deviation %"]
    F4["Field 4\nCondition Count\nQOF qualifying\nconditions total"]

    S --> F1
    S --> F2
    S --> F3
    S --> F4

    style S fill:#dce8f5,stroke:#4a90d9,color:#000000
    style F1 fill:#f0f0f0,stroke:#999,color:#000000
    style F2 fill:#f0f0f0,stroke:#999,color:#000000
    style F3 fill:#f0f0f0,stroke:#999,color:#000000
    style F4 fill:#f0f0f0,stroke:#999,color:#000000
```

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

## 16. Disclaimer

Synthea-generated synthetic EHR data only. No real NHS patient data used or accessed. All identifiers are synthetic UUIDs. Not validated for clinical use. Not assessed under DCB0129. Must not be used for clinical decisions about real patients.

---

## 17. Patient Explorer

Interactive patient drill-down — search by ID, view band, trajectory, variance, marker scores.

**[Launch Patient Explorer](https://asadqurashi12.github.io/cardiometabolic-deterioration/explorer/)**

Features:
- Search by patient ID with autocomplete
- Deterioration band badge coloured by data sufficiency
- Scoring pathway breakdown
- Priority string with field annotations
- Marker scores table
- Monthly exceedance chart (SBP, HbA1c, LDL)
- WORSENING+UNSTABLE alert banner

*Pipeline: BANDS_V6 / PS_V4 / TEMPORAL_V3 — NO_DRIFT confirmed*
*FHIR: HL7 Validator v6.9.4, R4.0.1*
*Terminology: NHS Digital TRUD MonolithRF2 GB_20260311*
*Data: Synthea 1,113-patient cohort*