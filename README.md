---

## 1. Clinical Context

Cardiometabolic disease — encompassing Type 2 diabetes, cardiovascular disease, hypertension, and chronic kidney disease — represents the highest burden of morbidity and hospitalisation in NHS secondary care. Deterioration in this population is characterised by gradual biomarker trajectory changes across multiple domains simultaneously. Standard clinical monitoring is episodic and reactive. This system demonstrates a proactive, longitudinal monitoring architecture that aggregates biomarker signals into a structured risk stratification output.

This is not a diagnostic tool. It is a population-level prioritisation system designed to surface patients whose biomarker trajectories warrant earlier clinical review, reducing the probability of unplanned emergency admission.

---

## 2. Cohort Pipeline

```mermaid
flowchart TD
    A["📋 Source Population\n1,113 Synthea patients\nSynthetic EHR — not real NHS data"]
    B["🫀 Cardiometabolic Cohort\n631 patients\nHas qualifying condition from snomed_icd10_map_p3\nCKD retained only if co-occurring with T2DM or HTN"]
    C["📊 Scored Patients\n479 patients\nSufficient observations for NICE threshold exceedance scoring\nBands 1–4 assigned"]
    D["📈 Temporally Evaluable\n118 patients\n≥2 readings across ≥3 distinct months\nTrajectory and variance signals calculated"]
    E["🚨 Highest Priority — WORSENING + UNSTABLE\n7 patients\nWORSENING trajectory AND UNSTABLE variance\nBoth deterioration signals active simultaneously"]

    A -->|"482 excluded\nNo qualifying cardiometabolic condition\nin 46-code snomed_icd10_map_p3 set"| B
    B -->|"152 excluded\nInsufficient observation density\nfor exceedance scoring"| C
    C -->|"361 flagged DATA_INSUFFICIENT\nSynthea observation sparsity\nReal EMIS/SystmOne data would produce higher coverage"| D
    D -->|"111 patients\nWORSENING or UNSTABLE\nbut not both simultaneously"| E

    style A fill:#f0f0f0,stroke:#999
    style B fill:#dce8f5,stroke:#4a90d9
    style C fill:#d5e8d4,stroke:#5a9e6f
    style D fill:#fff2cc,stroke:#d6a500
    style E fill:#f8cecc,stroke:#b85450
```

---

## 3. Cohort Inclusion and Exclusion Logic

```mermaid
flowchart TD
    START["All 1,113 Synthea patients"]

    Q1{"Has at least one condition\nfrom snomed_icd10_map_p3\n46-code cardiometabolic set?\ncomplication_category = clinical_active\nis_active = 1"}

    Q2{"CKD present?"}

    Q3{"T2DM or HTN\nalso present?"}

    EXCLUDE1["❌ Excluded\nNo qualifying condition"]
    EXCLUDE2["❌ Excluded\nCKD-only — no cardiometabolic\nscoring target\nNo SBP/HbA1c/LDL pathway applies\n(CPL-004)"]
    INCLUDE["✅ Included in cohort\n631 patients\ncvd_status assigned:\nRECENT / ESTABLISHED / NONE"]

    START --> Q1
    Q1 -->|No| EXCLUDE1
    Q1 -->|Yes| Q2
    Q2 -->|No| INCLUDE
    Q2 -->|Yes| Q3
    Q3 -->|No| EXCLUDE2
    Q3 -->|Yes| INCLUDE

    style EXCLUDE1 fill:#f8cecc,stroke:#b85450
    style EXCLUDE2 fill:#f8cecc,stroke:#b85450
    style INCLUDE fill:#d5e8d4,stroke:#5a9e6f
```

---

## 4. CVD Status Assignment

```mermaid
flowchart TD
    P["Patient in cohort"]

    Q1{"STEMI or NSTEMI\nonset within 365 days\nof 2026-04-06?\nSNOMED: 401303003 or 401314000"}

    Q2{"Any CVD qualifying condition\nat any time?\nIHD, HF, AF, valve disease,\nMI history, CABG history"}

    RECENT["cvd_status = RECENT\nn = 4 patients\nFinal band floor = 2\nLDL threshold = 77.3 mg/dL\n(NICE NG238 — post-ACS target)"]
    ESTABLISHED["cvd_status = ESTABLISHED\nn = 204 patients\nLDL threshold = 77.3 mg/dL\n(NICE NG238)"]
    NONE["cvd_status = NONE\nn = 423 patients\nLDL threshold = 116.0 mg/dL\n(NICE NG238)"]

    P --> Q1
    Q1 -->|Yes| RECENT
    Q1 -->|No| Q2
    Q2 -->|Yes| ESTABLISHED
    Q2 -->|No| NONE

    style RECENT fill:#f8cecc,stroke:#b85450
    style ESTABLISHED fill:#fff2cc,stroke:#d6a500
    style NONE fill:#d5e8d4,stroke:#5a9e6f
```

---

## 5. Data Sufficiency Tiers

```mermaid
flowchart TD
    OBS["Observations for patient-marker pair\nwithin scoring window\n2025-04-06 to 2026-04-06"]

    Q1{"obs_count ≥ 2\nAND distinct_months ≥ 3?"}
    Q2{"obs_count ≥ 2\nAND distinct_months ≥ 2?"}

    DS["🟢 DATA_SUFFICIENT\n51 patients\nFull scoring:\nexceedance + trajectory + variance"]
    PS["🟡 PARTIALLY_SUFFICIENT\n56 patients\nSeverity scoring only:\nexceedance, no trajectory"]
    DI["⚪ DATA_INSUFFICIENT\n372 patients\nExceedance from mean_x only\nNo temporal signal\nHonest flag — not imputed\n(CPL-008)"]

    OBS --> Q1
    Q1 -->|Yes| DS
    Q1 -->|No| Q2
    Q2 -->|Yes| PS
    Q2 -->|No| DI

    style DS fill:#d5e8d4,stroke:#5a9e6f
    style PS fill:#fff2cc,stroke:#d6a500
    style DI fill:#f0f0f0,stroke:#999
```

---

## 6. Scoring Pipeline — Four Layers

```mermaid
flowchart TD
    L1["⚡ Layer 1 — NICE Threshold Exceedance\nI = max(0, (x − T) / T) per marker per month\nMarkers: SBP · HbA1c · LDL · eGFR\nThresholds: NICE NG136 · NG28 · NG238 · NG203/KDIGO\nAcute inpatient SBP excluded — NICE NG136 specifies resting BP (D-80)\nmonthly_i_scores → marker_scores"]

    L2["🏋️ Layer 2 — BMI Floor Rule (D-79 / NICE CG189)\nBMI does NOT compete in exceedance argmax\nBMI is static — no month-to-month fluctuation\nBMI obesity class → minimum band floor only\nClass I (BMI 30–34.9) → floor Band 2\nClass II (BMI 35–39.9) → floor Band 3\nClass III (BMI ≥40) → floor Band 3\nbase_band = MAX(dynamic_base_band, bmi_floor)"]

    L3["📈 Layer 3 — Temporal Signal Elevation\nSystem trajectory: any WORSENING marker → WORSENING (D-51)\nSystem variance: any UNSTABLE marker → UNSTABLE (D-51)\nNon-compensatory — improvement in one marker\ndoes not offset deterioration in another\nWORSENING → trajectory_adjust +1\nUNSTABLE → variance_adjust +1\ninterim_band = base_band + trajectory_adjust + variance_adjust"]

    L4["🔒 Layer 4 — Cap and CVD Floor\nfinal_band = MIN(interim_band, 4)\nRECENT CVD floor: final_band = MAX(final_band, 2)\nPatients with recent MI/NSTEMI within 365 days\ncannot score below Band 2 regardless of biomarkers"]

    L1 --> L2 --> L3 --> L4

    style L1 fill:#dce8f5,stroke:#4a90d9
    style L2 fill:#fff2cc,stroke:#d6a500
    style L3 fill:#ffe6cc,stroke:#d6820a
    style L4 fill:#f8cecc,stroke:#b85450
```

---

## 7. Deterioration Band System

```mermaid
flowchart LR
    B1["🟢 Band 1 — Stable\n166 patients (34.7%)\nAll markers within NICE thresholds\nNo adverse trajectory\nRoutine monitoring pathway"]
    B2["🟡 Band 2 — Monitor\n179 patients (37.4%)\nOne marker outside NICE threshold\nOR BMI Class I floor applied\nOR RECENT CVD floor applied\nIncreased monitoring frequency"]
    B3["🟠 Band 3 — Concern\n56 patients (11.7%)\nTwo or more markers outside threshold\nOR BMI Class II/III floor applied\nOR WORSENING or UNSTABLE signal\nClinical review recommended"]
    B4["🔴 Band 4 — Alert\n78 patients (16.3%)\nHighest deterioration risk\nMultiple markers breaching\nAND/OR WORSENING + UNSTABLE signals\nPriority clinical review"]

    B1 --> B2 --> B3 --> B4

    style B1 fill:#d5e8d4,stroke:#5a9e6f
    style B2 fill:#fff2cc,stroke:#d6a500
    style B3 fill:#ffe6cc,stroke:#d6820a
    style B4 fill:#f8cecc,stroke:#b85450
```

---

## 8. Temporal Signal Logic

```mermaid
quadrantChart
    title Temporal Signal Matrix — 118 Evaluable Patients
    x-axis STABLE --> UNSTABLE
    y-axis IMPROVING --> WORSENING
    quadrant-1 "🔴 WORSENING + UNSTABLE\nn=7 — Highest Priority"
    quadrant-2 "🟠 WORSENING + STABLE\nn=9"
    quadrant-3 "🟢 IMPROVING + STABLE\nn=13"
    quadrant-4 "🟡 IMPROVING + UNSTABLE\nn=2"
```

```mermaid
flowchart TD
    M["Multiple markers per patient\nSBP · HbA1c · LDL only\nBMI and eGFR excluded from temporal model (D-76)"]

    T["Trajectory per marker\nWORSENING if avg monthly delta > threshold\nSBP/HbA1c threshold: 0.038\nLDL threshold: 0.090\nIMPROVING if avg monthly delta < -threshold\nSTABLE otherwise"]

    V["Variance per marker\nInstability threshold = 0.001 (D-62)\nDerived from RCPath analytical variation\nBelow 0.001 = STABLE\nAbove 0.001 = UNSTABLE"]

    AGG["Non-compensatory aggregation (D-51)\nAny marker WORSENING → system_trajectory = WORSENING\nAny marker UNSTABLE → system_variance = UNSTABLE\nImprovement in one marker does NOT\noffset deterioration in another"]

    M --> T
    M --> V
    T --> AGG
    V --> AGG

    style AGG fill:#f8cecc,stroke:#b85450
```

---

## 9. Priority String

```mermaid
flowchart LR
    S["Priority String — one per patient\nExample:\nESTABLISHED | 3 (SBP, HbA1c, LDL) | HbA1c:8.2/7.0 (+17.1%) | 4"]

    F1["Field 1\nCVD Status\nESTABLISHED\nRECENT\nNONE"]
    F2["Field 2\nBreach Count\nNumber of markers\nabove NICE threshold"]
    F3["Field 3\nBreaching Markers\nComma-separated list\nof markers in breach"]
    F4["Field 4\nWorst Marker Detail\nMarker name : value / threshold\n(+deviation %)"]
    F5["Field 5\nCondition Count\nTotal QOF qualifying\nconditions"]

    S --> F1
    S --> F2
    S --> F3
    S --> F4
    S --> F5

    style S fill:#dce8f5,stroke:#4a90d9
```

---

## 10. FHIR R4 Export Architecture

```mermaid
flowchart TD
    DB["SQLite Database\np3_deterioration_full.db\n631 cohort patients"]

    PY["fhir_export_final_v2.py\nPython — export layer only\nNo scoring logic in Python\nAll scoring done in SQL"]

    B1["fhir_bundle_part1.json\n210 patients\n12,958 resources"]
    B2["fhir_bundle_part2.json\n210 patients\n12,468 resources"]
    B3["fhir_bundle_part3.json\n211 patients\n13,644 resources"]

    RES["Resources per patient:\n👤 Patient\n🏥 Condition (SNOMED CT primary, ICD-10 secondary)\n🔬 Observation (BP panel + HbA1c + LDL + eGFR + BMI)\n💊 MedicationRequest (active medications)\n📅 Encounter (last 5)\n⚠️ RiskAssessment (deterioration band + trajectory)"]

    VAL["HL7 FHIR Validator v6.9.4\nFHIR R4.0.1\n349 residual errors across 3 bundles\nAll errors: ICD-10 terminology version mismatch\nor SNOMED display drift\nZero structural FHIR errors"]

    DB --> PY
    PY --> B1
    PY --> B2
    PY --> B3
    B1 & B2 & B3 --> RES
    B1 & B2 & B3 --> VAL

    style VAL fill:#d5e8d4,stroke:#5a9e6f
```

---

## 11. Validation Architecture

```mermaid
flowchart TD
    U["Unit Tests — logic_unit_tests.sql\n29/29 PASS\nLayer 0: observation window integrity\nLayer 1: cohort qualification logic\nLayer 2: marker scoring accuracy\nLayer 3: priority score consistency\nLayer 5-6: band monotonicity and BMI floor binding"]

    G["Golden Set — create_golden_set.sql\nBaseline snapshot locked at\nBANDS_V6 / PS_V4 / TEMPORAL_V3\nDrift detection on every pipeline run"]

    D["Drift Detector — drift_detector.sql\n12 metrics monitored\n0 drifted rows confirmed\nNO_DRIFT_DETECTED"]

    R["Retrospective Validation — retrospective_validation.sql\nT0 window: 2025-04-06 to 2025-10-06\nOutcome window: 2025-10-06 to 2026-04-06\nWORSENING+UNSTABLE: n=8, events=1, rate=12.5%\nAll other patients: n=623, events=47, rate=7.5%\nLift ratio: 1.42\nUnderpowered — methodology demonstration only\nNot statistically inferential (CPL-010)"]

    U --> G --> D
    D --> R

    style D fill:#d5e8d4,stroke:#5a9e6f
    style R fill:#fff2cc,stroke:#d6a500
```

---

## 12. Technical Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| Primary language | SQL (SQLite / DB Browser) | All cleaning, cohort preparation, scoring, validation |
| Data ingestion | Python (`load_data.py`) | Loading Synthea CSVs into SQLite |
| Terminology loading | Python (`load_snomed_map.py`) | Loading NHS Digital MonolithRF2 SNOMED→ICD-10 map |
| FHIR export | Python (`fhir_export_final_v2.py`) | Building FHIR R4 Bundle JSON from database |
| Visualisation | Tableau Public | Clinical dashboards |
| Patient explorer | HTML/JS (GitHub Pages) | Individual patient drill-down |
| Terminology | SNOMED CT (MonolithRF2 GB_20260311) | Condition coding |
| Terminology | ICD-10 5th Edition | Secondary condition coding |
| Terminology | LOINC | Observation coding |
| Terminology | RxNorm | Medication coding |
| Clinical standards | NICE NG136, NG28, NG238, NG203 | Exceedance thresholds |
| Clinical standards | KDIGO 2012 | eGFR staging |
| Clinical standards | NICE CG189 | BMI floor tiers |
| Clinical standards | RCPath | Analytical variation threshold (D-62) |
| FHIR standard | HL7 FHIR R4.0.1 | Interoperability export |
| Validation | HL7 FHIR Validator v6.9.4 | Structural FHIR compliance |

---

## 13. Clinical Problem Log — Summary

Ten design decisions documented with problem, decision, rationale, and limitation. Full entries in database table `clinical_problem_log`.

| Reference | Decision Type | Summary |
|-----------|--------------|---------|
| CPL-001 | Architecture | Synthea used — UCLH unavailable, MIMIC-IV requires credentialing |
| CPL-002 | Architecture | RTT design pivoted to deterioration monitoring — Synthea has no waiting list fields |
| CPL-003 | Clinical Rule | BMI floor rule — BMI excluded from dynamic exceedance argmax (D-79, NICE CG189) |
| CPL-004 | Clinical Rule | Acute SBP excluded — NICE NG136 specifies resting clinic BP (D-80) |
| CPL-005 | Clinical Rule | Variance threshold 0.001 — derived from RCPath analytical variation (D-62) |
| CPL-006 | Clinical Rule | Non-compensatory aggregation — any WORSENING/UNSTABLE marker fires system signal (D-51) |
| CPL-007 | Clinical Rule | Acute event scope — system detects metabolic deterioration, not plaque rupture |
| CPL-008 | Architecture | 361 patients DATA_INSUFFICIENT — flagged honestly, not imputed or dropped |
| CPL-009 | Clinical Rule | CKD-only excluded — no SBP/HbA1c/LDL scoring target without cardiometabolic comorbidity |
| CPL-010 | Validation | Retrospective validation underpowered (n=7) — methodology demonstration, not predictive evidence |

---

## 14. Information Governance

> **Version: v1.0 | Date: 2026-04-28**

### Caldicott Principles

This project was designed in compliance with the eight Caldicott Principles:

1. **Justify the purpose** — Cardiometabolic deterioration monitoring serves a defined clinical purpose: reducing unplanned emergency admission through earlier biomarker signal detection.
2. **Use only what is necessary** — Only five biomarkers (SBP, HbA1c, LDL, eGFR, BMI) are scored. No social, behavioural, or demographic data is used in clinical scoring.
3. **Access on a need-to-know basis** — In real deployment, access would be restricted to the clinical team responsible for the monitored patient cohort.
4. **Be aware of your responsibilities** — The builder is an MBBS graduate with clinical training. Clinical thresholds were applied with awareness of their guideline basis and limitations.
5. **Comply with the law** — No real patient data was used at any stage. All data is Synthea synthetic EHR.
6. **The duty to share can be as important as the duty to protect** — The FHIR R4 export layer is designed to enable safe, structured data sharing in a real deployment context.
7. **The primary purpose rule** — Data was used only for the stated purpose of building and validating the scoring pipeline.
8. **Do not be an obstacle to sharing** — The FHIR R4 export and GitHub Pages explorer are designed to make outputs accessible to clinical and informatics reviewers.

### DCB0129 Reference

DCB0129 (Clinical Risk Management: its Application in the Manufacture of Health IT Systems) applies to health IT systems intended for clinical use. This system is a proof-of-concept built on synthetic data and is not intended for clinical deployment. A real deployment would require a full DCB0129 clinical risk management file including hazard log, clinical risk assessment, and safety case report.

### DPIA Note

A Data Protection Impact Assessment (DPIA) would be required before any real deployment under UK GDPR Article 35. Key considerations would include: legal basis for processing, data minimisation review, access controls, retention policy, and patient notification obligations. No DPIA is required for this synthetic data project.

---

## 15. Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| Synthea synthetic data — not real NHS EHR | Observation values procedurally generated, not clinically realistic | Explicitly framed as proof-of-concept throughout |
| 75.4% DATA_INSUFFICIENT temporal coverage | 361 of 479 scored patients have no trajectory signal | Synthea observation sparsity — real EMIS/SystmOne data would produce higher coverage |
| Retrospective validation underpowered (n=7) | No statistical inference possible | Methodology demonstrated — infrastructure is the evidence |
| Unit normalisation not applied | Synthea mixes mmol/L and mg/dL within same LOINC code | Thresholds calibrated to Synthea units — documented limitation |
| eGFR LOINC 33914-3 deprecated | CKD-EPI replacement (62238-1) not in Synthea | Retained with documentation — threshold values are equivalent |
| ICD-10 2019-covid-expanded version mismatch | 349 FHIR validator errors across 3 bundles | Terminology version constraint — not a structural FHIR error |
| RxNorm medication coding | UK deployment uses dm+d via TRUD | Synthea constraint — documented known limitation |

---

## 16. Patient Explorer

An interactive HTML patient explorer is available at:

**[GitHub Pages — Patient Explorer](https://asadqureshi12.github.io/cardiometabolic-deterioration/explorer/)**

Features:
- Search by patient ID with autocomplete
- Deterioration band badge coloured by data sufficiency
- Scoring pathway breakdown
- Priority string with field annotations
- Marker scores table (mean_i, data tier, trajectory, variance)
- Monthly exceedance chart (SBP, HbA1c, LDL)
- WORSENING+UNSTABLE alert banner

---

## 17. Disclaimer

This project uses Synthea-generated synthetic EHR data only. No real NHS patient data was used or accessed at any stage. All patient identifiers are synthetic UUIDs generated by the Synthea engine. This system is not validated for clinical use, has not undergone clinical risk assessment under DCB0129, and must not be used to make clinical decisions about real patients.

---

*Pipeline version: BANDS_V6 / PS_V4 / TEMPORAL_V3*
*Golden set: confirmed NO_DRIFT*
*FHIR validation: HL7 FHIR Validator v6.9.4, FHIR R4.0.1*
*Data: Synthea v3.x, 1,113-patient cohort*
*Terminology: NHS Digital TRUD MonolithRF2 GB_20260311*