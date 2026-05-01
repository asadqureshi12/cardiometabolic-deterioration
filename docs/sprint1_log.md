# P3: Clinical Deterioration Monitoring System
# Sprint 1 Log — Schema, Load, Clean, FHIR Pilot Validation
# Date: 2026-04-08
# Builder: MBBS Graduate, MSc Health Informatics (Swansea, Sept 2026)
# Role framing: Clinical Systems Lead / Product Owner

---

## Sprint 1 Objectives

1. Define and create the database schema
2. Load raw Synthea CSV data
3. Run data quality checks
4. Apply data cleaning and FHIR preparation
5. Export a 2-patient FHIR R4 pilot bundle
6. Validate against the official HL7 FHIR validator
7. Achieve parity with P2 validation results before proceeding to full build

---

## Final Deliverables

| File | Purpose |
|------|---------|
| schema.sql v3.0 | 9-table SQLite schema with FHIR fields |
| load_snomed_map.py | Populates snomed_icd10_map reference table |
| load_data.py | Pure CSV to SQLite loader |
| data_quality.sql | 29 data quality rules |
| run_quality_check.py | Python runner for quality checks |
| clean_data.sql | 16-section cleaning and FHIR prep script |
| fhir_pilot.py | 2-patient FHIR R4 bundle exporter |
| p3_deterioration_full.db | Populated database |
| clean_data.sql | Extended to 24 sections — Sections 20-23 added in Sprint 2 pre-work covering Step 0 classification |

---

## Database Statistics (post-clean)

| Table | Rows |
|-------|------|
| patients | 1,113 |
| conditions | 22,006 |
| encounters | 62,745 |
| observations | 766,553 (final status) |
| medications | 46,271 |
| snomed_icd10_map | 135 |
| Conditions clinical_active | 21,204 |
| Conditions excluded_admin | 46 |
| Conditions excluded_field_error | 716 |

---

## FHIR Validation Result

| Round | Errors | Warnings | Notes |
|-------|--------|----------|-------|
| Round 1 (baseline) | 70 | 245 | 221 |
| Round 2 (ICD-10-CM filter, extension removal, encounter display) | 8 | 208 | 10 |
| Round 3 (T2DM display, double space normalisation) | 6 | 208 | 10 |
| Round 4 (LOINC and RxNorm display corrections) | **2** | 208 | 10 |

Residual 2 errors: G43.7 and G89.2 not in terminology server version
2019-covid-expanded. These are valid UK ICD-10 5th Edition codes.
Documented limitation identical to P2. Not fixable at this stage.

---

## Key Decisions and Rationale

### D-01: Pipeline Architecture — Python reads CSV, SQL does everything else
**Decision:** Python's role is strictly limited to reading Synthea CSV files
and inserting rows into SQLite. No filtering, no selection, no clinical logic,
no date calculations, no is_active flags in Python.

**Rationale:** The project brief states SQL as the primary language. Any
clinical or analytical logic in Python would undermine that framing and
reduce the portfolio's auditability. SQL is inherently auditable — every
decision is visible and version-controlled as a query. Python logic buried
in a loader script is not.

**Implication:** Three violations were identified and corrected mid-sprint —
age calculation from snapshot date, is_active derivation for conditions,
and is_active derivation for medications. All three were removed from
load_data.py and moved to clean_data.sql.

---

### D-02: Snapshot Date — Set to last recorded date in Synthea output
**Decision:** Snapshot date set to 2026-04-06, the last date present across
all five Synthea CSV files.

**Rationale:** An arbitrary snapshot date (initially 2025-04-01) was set
without clinical justification. The correct approach is to use all available
synthetic data by setting the snapshot to the last generated date. This
maximises trajectory data available to Sprint 2 and eliminates the entire
post-snapshot warning category (77,496 observations, 911 conditions, 4,860
encounters) that would otherwise require clean_data.sql to delete valid data.

**Method:** Last date identified programmatically by scanning all CSV files
before the load, not hardcoded.

---

### D-03: Data Quality Check Approach — SQL reports, does not modify
**Decision:** data_quality.sql is a read-only reporting script. It identifies
issues and produces a report. All modifications are in clean_data.sql.

**Rationale:** Separation of concerns. The quality check script is a
diagnostic tool — running it multiple times should produce the same output
without side effects. Mixing diagnostic and modification logic in one script
would make auditing impossible. This also matches NHS informatics practice
where data quality reporting is a distinct process from data remediation.

---

### D-04: Two-Script Cleaning Architecture — clean_data.sql and prepare_cohort.sql
**Decision:** Data cleaning is split across two SQL scripts. clean_data.sql
fixes genuine data errors and prepares FHIR fields. prepare_cohort.sql
applies clinical scoring logic and cohort assignment in Sprint 2.

**Rationale:** The first clean pass fixes things that are factually wrong —
orphaned records, corrupt medications, off-by-one dates, empty strings, FHIR
mandatory fields. The second pass applies clinical rules — segment assignment,
trajectory scoring thresholds, is_high_value flags — which cannot be defined
until Sprint 2 scoring logic is locked. Running cleanup twice avoids locking
in scoring decisions during Sprint 1.

---

### D-05: Orphaned Records — Delete, do not attempt repair
**Decision:** 40 conditions, 74 encounters, 756 observations, and 16
medications belonging to 2 missing patients were deleted in clean_data.sql.

**Rationale:** The 2 missing patients have duplicate SSN hashes — the UNIQUE
constraint on nhs_number_hash correctly rejected the second insert. Their
records cannot be scored or analysed without a parent patient row. Attempting
to create placeholder patient rows would introduce synthetic data not present
in the original Synthea output. Deletion is the only defensible option.

**Confirmed by validation:** Both orphaned patient IDs (2d225d70 and 7a1262f2)
were identified programmatically. All orphaned records belong exclusively to
these two patients with no other missing patients detected.

---

### D-06: Corrupt Medications — Delete, do not repair stop date
**Decision:** 57 medication records where stop_date is before start_date were
deleted. The stop date was not nullified or corrected.

**Rationale:** A medication with an impossible stop date is a corrupt record.
We cannot determine whether the patient actually stopped the medication or not.
Nullifying the stop date would set is_active to 1 — asserting the medication
is currently active — which is an assumption we cannot justify from the data.
46,271 medication records remain. Losing 57 corrupt ones has no material
impact on the analysis.

**Distribution:** 14 patients affected, ranging from 1 to 11 violations per
patient, confirming this is a Synthea generation error not specific to one
patient.

---

### D-07: Off-by-One Observation Dates — Correct, do not delete
**Decision:** 475 observations dated exactly 1 day before the patient's
birthdate were corrected by setting observation_date to birthdate.

**Rationale:** All 475 violations were a uniform 1-day offset — confirmed by
distribution analysis. This is a known Synthea artefact where the delivery
encounter generates observations dated the day before the recorded birthdate.
The clinical data (body weight, height, pain score at birth) is real and
relevant for longitudinal analysis. Deleting these records would remove valid
neonatal baseline observations. Correcting by adding one day is auditable and
clinically defensible.

---

### D-08: is_active Flags — Derived from stop date, set in SQL
**Decision:** is_active for conditions = 1 where resolution_date is NULL,
0 where resolution_date is populated. Same logic for medications using
stop_date.

**Rationale:** Synthea generates completed records — every condition has
either an explicit resolution date or none. The derivation is deterministic
and requires no clinical judgement. SQL CASE logic is the appropriate tool.
Originally implemented in Python (D-01 violation), corrected to SQL.

---

### D-09: FHIR Mandatory Fields — Set defaults in schema, confirm in clean_data.sql
**Decision:** Five FHIR-required fields added to schema v3.0:
- conditions.verification_status DEFAULT 'confirmed'
- conditions.icd10_code (populated from snomed_icd10_map)
- encounters.fhir_status (derived from encounter_end date)
- encounters.fhir_class (mapped from Synthea encounterclass)
- observations.observation_status (derived from value type)

**Rationale:** P2 experience showed that missing mandatory FHIR fields
generate structural errors that cannot be resolved at export time. Fixing
at source in the schema and cleaning step is more robust than patching at
export. Setting defaults in the schema guarantees no NULL mandatory fields
reach the FHIR exporter regardless of what data is loaded.

---

### D-10: verification_status = confirmed for all Synthea conditions
**Decision:** All conditions set to verification_status = confirmed.

**Rationale:** FHIR R4 Condition resource requires verification_status as a
mandatory field. Synthea generates completed synthetic records — there are
no provisional diagnoses, rule-out conditions, or differential diagnoses in
the dataset. Every condition in Synthea represents a completed clinical fact.
Setting confirmed is accurate for the data as generated.

**Limitation:** In real NHS deployment, verification_status would be sourced
from the clinical system. Conditions might be entered as suspected, refuted,
or differential pending investigation. This is documented as a synthetic data
constraint, not a design error.

---

### D-11: observation_status = final for numeric observations
**Decision:** Observations with value_numeric populated set to final.
Observations with no numeric or categorical value set to unknown.

**Rationale:** FHIR R4 Observation resource requires status as a mandatory
field. Synthea generates completed measurements — a recorded observation
represents a finalised result. final is the accurate status for Synthea data.
Observations with no value cannot be confirmed as final and are set to
unknown, which is the correct FHIR status for an observation where the
result is not available.

---

### D-12: Deprivation Decile — Proxy from income field
**Decision:** Deprivation decile assigned by banding the Synthea income field
into 10 equal groups. Decile 1 = most deprived (lowest income), decile 10 =
least deprived (highest income).

**Rationale:** UK IMD scores are not available in Synthea data. The income
field provides the only proxy for socioeconomic status. Ten bands allow
equity analysis across a deprivation spectrum. This is explicitly documented
as a proxy and a known limitation.

**Limitation:** Real deployment would use NHS Digital IMD 2019 scores mapped
to patient postcode. The income proxy does not capture the multiple deprivation
dimensions of the UK IMD (income, employment, health, education, housing,
crime, living environment). Analysis using this proxy should be interpreted
with caution.

---

### D-13: is_high_value Flag — Deferred to Sprint 2
**Decision:** The is_high_value flag column was retained in the schema as a
placeholder but is not populated in Sprint 1. LOINC code classification for
trajectory scoring will be defined in Sprint 2 with guideline references
(NICE NG28, NICE NG136, KDIGO, ESC).

**Rationale:** Locking down a specific LOINC code list in Sprint 1 would
constitute premature Sprint 2 decision-making. The scoring engine in Sprint 2
will define which observation types are clinically relevant for cardiometabolic
deterioration. Pre-flagging without that framework would require a second
clean pass anyway. One comprehensive classification in Sprint 2 is more
efficient and more defensible.

---

### D-14: SNOMED to ICD-10 Mapping — P2 validated mapping reused, P3 extensions added
**Decision:** The 129-code P2 validated mapping was imported directly into
snomed_icd10_map. 12 P3 extensions were added for cardiometabolic codes
absent from P2 (ischaemic heart disease, STEMI, NSTEMI, heart failure, CKD
stages 3-4, ESRD, valve disease codes).

**Rationale:** P2's mapping was validated through 8 rounds of HL7 FHIR
validator testing achieving 97.7% error reduction. Rebuilding from scratch
would risk reintroducing errors already resolved. Reuse with documented
extensions is the most efficient and evidence-based approach.

**Deduplication:** 6 of 129 P2 entries were deduplicated by the UNIQUE
constraint on snomed_code, reducing to 123 P2 entries. Total mapping: 135
entries (123 P2 + 12 P3).

---

### D-15: ICD-10-CM Codes in Synthea SNOMED Field
**Decision:** Conditions where the snomed_code field contains non-numeric
values (ICD-10-CM codes like K08.409, Z01.20, C61) are excluded from the
SNOMED coding layer in the FHIR export. They are not mapped to an alternative
code.

**Rationale:** Synthea occasionally stores ICD-10-CM codes in the CODE field
for dental, administrative, and procedural conditions. These are not valid
SNOMED CT concept IDs — the SNOMED system requires numeric integer codes.
Presenting ICD-10-CM codes under the http://snomed.info/sct system URL is
a structural FHIR error. Excluding them from the SNOMED layer is the only
valid option. These conditions have no SNOMED equivalent in our mapping and
are not cardiometabolic conditions relevant to the scoring engine.

---

### D-16: FHIR Custom Extension — Removed
**Decision:** The custom Patient extension
http://p3-deterioration-pipeline/synthetic-record was removed from the
FHIR export.

**Rationale:** Custom extensions must be registered in an Implementation
Guide to be valid in FHIR R4. An unregistered extension URL generates a
structural error. The synthetic identity information is already captured in
the Patient.identifier.type.text field. Removing the extension eliminates
the error with no loss of clinical information.

---

### D-17: Encounter Class Display — Corrected to full display names
**Decision:** FHIR Encounter.class.display values corrected from codes
(AMB, EMER, IMP) to their official full display names (ambulatory, emergency,
inpatient encounter).

**Rationale:** The FHIR validator checks that the display field matches the
official display name from the ActEncounterCode vocabulary. Using the code
as both code and display generated errors on every encounter resource. The
fix is a lookup map in the exporter applied at export time.

---

### D-18: SNOMED Display Name Corrections — Applied from P2 validated mapping
**Decision:** 16 SNOMED display names corrected using P2 validated preferred
terms stored in snomed_icd10_map.snomed_desc_corrected. Applied to conditions
table in clean_data.sql Section 9.

**Rationale:** Synthea uses abbreviated display names that do not match SNOMED
CT preferred terms. The FHIR validator checks display names against the
terminology server. Incorrect display names generate errors for every patient
who has that condition. Corrections applied at source in the database
eliminate errors systematically rather than patching the exporter.

**Key corrections:**
- Hypertension → Essential hypertension (disorder)
- Diabetes → Type 2 diabetes mellitus
- Atrial Fibrillation → Atrial fibrillation (disorder)
- Hyperlipidemia → Hyperlipidemia (disorder) [US spelling required]
- Hyperglycaemia → Hyperglycemia (disorder) [US spelling required]
- Diabetic nephropathy (disorder) → Diabetic renal disease (disorder)
- Opioid abuse (disorder) → Harmful pattern of use of opioid (disorder)

---

### D-19: ICD-10 Display Name Format — Colon separator required
**Decision:** ICD-10 display names for Type 2 diabetes complications updated
to use the FHIR-required colon separator format.

**Rationale:** The FHIR terminology server expects ICD-10 display names in
the format `Type 2 diabetes mellitus : With renal complications` not
`Type 2 diabetes mellitus with renal complications`. This is a terminology
server requirement not documented in the ICD-10 specification itself. It was
identified empirically through validator testing.

**Affected codes:** E11.2, E11.3, E11.4, E11.9, F11.1

---

### D-20: Synthea Double-Space Descriptions — Normalised then corrected
**Decision:** Two-pass fix applied. First, a generic clean_display() function
collapses all double spaces to single spaces. Second, explicit display
correction lookups override known Synthea descriptions that use double spaces
as comma substitutes.

**Rationale:** Synthea's raw description strings for some medications and
observations use double spaces where the official terminology display uses
commas — e.g. `insulin isophane  human` vs `insulin isophane, human`. The
generic normalisation alone produces single-spaced but still incorrect
descriptions. The explicit lookup provides the correct official display name.

**Corrections applied:**
- LOINC 2028-9: `Carbon dioxide, total [Moles/volume] in Serum or Plasma`
- RxNorm 106892: `insulin isophane, human 70 UNT/ML / insulin, regular, human 30 UNT/ML Injectable Suspension [Humulin]`

---

### D-21: G43.7 and G89.2 — Documented limitation, not fixable
**Decision:** ICD-10 codes G43.7 (chronic migraine without aura, intractable)
and G89.2 (chronic pain NEC) remain as errors in the validator output.

**Rationale:** These are valid UK ICD-10 5th Edition codes that are not
present in the terminology server version 2019-covid-expanded used by the
HL7 FHIR validator. This is a terminology server coverage gap, not an error
in our mapping. The same codes generated the same errors in P2 after 8
validation rounds and were accepted as known limitations. This is documented
in the Clinical Problem Log and does not affect the clinical validity of the
data.

---

### D-22: UNIQUE Constraint on Observations — Added to prevent duplicate loads
**Decision:** UNIQUE constraint added to observations table on
(patient_id, encounter_id, loinc_code, observation_date).

**Rationale:** During Sprint 1 the database was accidentally loaded twice
producing 1,546,756 observations instead of 773,378. The observations table
had no deduplication mechanism. The UNIQUE constraint prevents this from
occurring in Sprint 2 or the full build regardless of how many times the
loader is run. All other tables already had appropriate constraints —
conditions had UNIQUE(patient_id, snomed_code), patients had UNIQUE on
nhs_number_hash.

D-24: SNOMED mapping extensions — derived from data, not assumption
Six new P3 extensions added only after querying conditions table for unmapped codes. All 12 existing P3 extensions confirmed present in data with patient counts. Sleep apnoea excluded — no biomarker trajectory contribution. 714628002, 274531002, 399261000, 698306007, 161665007, 1231000119100 added. Total mapping: 141 entries. Decision principle: no code added without confirmed presence in conditions table.
D-25: RCPath physiological ranges as Sprint 1 cleaning threshold
Clinical range validation split into two stages. Sprint 1 uses RCPath physiological limits — absolute biological floors and ceilings. Sprint 2 will apply NICE and specialty guideline thresholds for scoring. Rationale: RCPath answers "is this a real measurement", NICE answers "is this clinically concerning". These are distinct questions requiring distinct sources.
D-26: Negative LDL deleted — Friedewald artefact, mathematically impossible
LDL below 0 deleted from observations table. Friedewald equation produces negative results when triglycerides exceed approximately 400 mg/dL. A negative cholesterol concentration has no biological interpretation. Reference: RCPath laboratory medicine guidelines.
D-27: LDL 0-20 mg/dL flagged, not deleted — PCSK9 therapy ruled out by medication query
Before flagging, medication table queried for evolocumab, alirocumab, inclisiran, and brand equivalents. Zero patients with LDL below 20 are on any PCSK9 inhibitor. FOURIER and ODYSSEY trials document genuine LDL as low as 15 mg/dL in treated patients — deletion without therapy confirmation is not defensible. Decision: retain records, set value_excluded = 1, exclude from trajectory scoring. 22 records flagged across 8 patients.
D-28: HbA1c below 2.0% and systolic BP below 50 flagged using RCPath floor
HbA1c floor: RCPath position that values below 2.0% are below analytical reliability threshold, likely representing haemoglobin variant interference. One reading of 1.9 flagged. Systolic BP floor: 50 mmHg incompatible with conscious ambulatory monitoring in a Synthea outpatient encounter context. One reading of 48 flagged. Both set value_excluded = 1. Reference: RCPath Guidelines for Evaluation of HbA1c Analysers.
D-29: SNOMED mapping completeness audit — Sprint 1 gap identified and remediated
A post-Sprint-1 audit revealed that 14,950 unmapped conditions were assumed to be dental, social, or administrative without verification. Query of conditions table confirmed this assumption was incorrect — clinically significant conditions including sepsis, OSA, fibromyalgia, malignancies, HIV, neurological disorders, and respiratory conditions were outside the 141-code map. Root cause: Sprint 1 definition of done did not include a completeness check requiring every active unmapped code to be explicitly classified or excluded. Remediation: full audit of all distinct SNOMED codes completed in Sprint 2 pre-work. Chronic classification will operate on explicitly classified population only.

D-30: Step 0 semantic tag filter — non-clinical concepts flagged using SNOMED hierarchy
Conditions where snomed_description ends with (person), (procedure), or (observable entity) flagged as excluded_admin in complication_category. 46 rows affected, all confirmed as non-clinical concepts with no ICD-10 equivalent. Rule is automated and reproducible — no manual review required. Rationale: SNOMED CT hierarchy formally encodes concept type in the fully specified name suffix. These semantic tags are definitionally non-clinical. Applied in clean_data.sql Section 20.

D-31: ICD-10 codes misfiled in snomed_code column — detected and routed
716 rows confirmed where Synthea placed ICD-10 codes in the snomed_code field. Detected using GLOB pattern [A-Z][0-9][0-9]*. For all 716 rows, the value was copied to icd10_code where icd10_code was NULL. snomed_code column was not nulled — FHIR export layer resolves coding system dynamically using the same GLOB pattern at export time. Zero field conflicts confirmed — all 716 rows had matching values in both fields after routing. Flagged as excluded_field_error. Applied in clean_data.sql Section 21. Largely dental, oral oncology, and administrative codes.

D-32: snomed_description_corrected backfill — Sprint 1 gap closed
Sprint 1 Section 9 populated snomed_description_corrected only for the 141 codes present in snomed_icd10_map. All other codes were left NULL. Backfill applied in clean_data.sql Section 22: snomed_description copied to snomed_description_corrected where corrected was NULL. Zero NULL descriptions remaining after backfill. This ensures FHIR export has a display name for every condition regardless of mapping status.

D-33: clinical_active explicit label — ambiguity in complication_category resolved
After Steps 20-22, 21,204 conditions had complication_category = NULL representing the clean clinical population. NULL is ambiguous — it represents both not yet classified and not excluded. All NULL rows explicitly set to clinical_active in clean_data.sql Section 23. This ensures Step 1 chronic classification in prepare_cohort.sql operates on an explicitly defined population with no hidden logic dependency. Every row in the conditions table now has an explicit state label.

Final Sprint 1 validation state:

value_excluded flags: 24 total — 22 LDL, 1 HbA1c, 1 systolic BP
Negative LDL deleted: confirmed 0 remaining
Total observations: 766,549
Zero CRITICAL violations remaining after flagging
Database ready for Sprint 2

---

## Data Quality Findings Summary

| Rule | Severity | Count | Action |
|------|----------|-------|--------|
| Orphaned records | CRITICAL | 878 | Deleted in clean_data.sql S1 |
| Corrupt medications (stop before start) | CRITICAL | 57 | Deleted in clean_data.sql S2 |
| Observations before birthdate | CRITICAL | 475 | Corrected in clean_data.sql S3 |
| Post-snapshot records | WARNING | Resolved by correct snapshot date | No action needed |
| NULL is_active (conditions) | WARNING | 22,006 → 0 | Set in clean_data.sql S5 |
| NULL is_active (medications) | WARNING | 46,271 → 0 | Set in clean_data.sql S6 |
| NULL fhir_status (encounters) | WARNING | 62,745 → 0 | Set in clean_data.sql S7 |
| Conditions without ICD-10 | INFO | 14,950 | Expected — outside 135-code mapping |

---

## Residual Known Limitations

1. **US SNOMED CT edition**: Synthea uses the US SNOMED CT edition. UK Core
   FHIR requires UK edition where possible. We cannot replace the codes but
   the limitation is documented. snomed_edition field set to 'US' for all
   conditions.

2. **ICD-10 coverage gap**: 14,950 conditions (68%) have no ICD-10 mapping.
   These are dental, social determinant, administrative, and non-cardiometabolic
   conditions outside our 135-code mapping table. They are not relevant to the
   scoring engine but will appear in the FHIR export without ICD-10 dual coding.

3. **Deprivation decile proxy**: Income-based proxy, not real UK IMD. See D-12.

4. **G43.7 and G89.2**: Not in terminology server. See D-21.

5. **eGFR LOINC 33914-3 discouraged**: The MDRD-based eGFR LOINC code is
   flagged as DISCOURAGED by the terminology server. The recommended replacement
   is CKD-EPI based. Sprint 2 decision on whether to remap in the LOINC lookup
   table.

6. **Observation performer missing**: Best practice recommendation on all
   Observation resources. Synthea does not provide practitioner data. Not a
   structural error.

7. **dom-6 narrative**: Best practice recommendation on all resources.
   Not a structural error. Would require adding a human-readable narrative
   text block to every resource in production.
8. ICD-10 coverage gap revised: Original Sprint 1 mapping of 141 codes covered the initial cardiometabolic cohort only. Full audit in Sprint 2 pre-work confirmed clinically significant conditions exist outside this map. New design: ICD-10 mapping is performed after chronic classification and domain segmentation, not before. Only conditions confirmed as chronic and clinically relevant to the scoring engine will be mapped. This eliminates unnecessary mapping work on acute, dental, obstetric, and administrative conditions that will never reach the scoring engine.

---

## Sprint 1 Validation Sign-off

- Zero CRITICAL data quality violations remaining
- Zero orphaned records
- Zero corrupt medications
- All FHIR mandatory fields populated
- FHIR pilot: 2 patients, 189 entries, 2 residual errors (documented limitations)
- Error reduction: 70 → 2 (97.1% reduction, matching P2's 97.7%)
- Database ready for Sprint 2 scoring engine

---

## Sprint 2 Preview

- prepare_cohort.sql: segment assignment, is_high_value flag, trajectory readiness
- LOINC lookup table with guideline references (NICE NG28, NG136, KDIGO, ESC)
- Trajectory scoring engine: delta calculation, acute cluster exclusion,
  high-density episode collapsing
- Deterioration band assignment
- Clinical alert generation

---

*Sprint 1 complete. All files version-controlled. Next session: Sprint 2.*
**UPDATED DECISION LOG — P3 Sprint 2 Pre-Implementation**
**Date: 2026-04-13**
**Covers: All decisions made after sprint1_log.md D-29 through D-33**

---

**D-34: Step 0 clinical_active explicit label — ambiguity resolved**
Every condition row now has an explicit complication_category state. NULL replaced with clinical_active for all rows not excluded by Step 0. Four states in conditions table: clinical_active, excluded_admin, excluded_field_error, field_conflict (0 rows confirmed). Rationale: NULL is ambiguous — it represents both not yet classified and not excluded. Explicit labelling ensures prepare_cohort.sql operates on a defined population with no hidden logic dependency. Confirmed by validation: clinical_active = 21,204, complication_category NULL = 0.

---

**D-35: Chronic classification primary rule — QOF SNOMED codes**
Primary chronic classification uses NHS England QOF Business Rules SNOMED code lists. A condition is chronic if its SNOMED code appears on a QOF register. Source: NHS Digital TRUD QOF Business Rules. Rationale: QOF is the NHS-endorsed operational definition of long-term conditions in clinical practice. It is SNOMED-based, directly applicable to your data without ICD-10 dependency, and publicly citable. ICD-10 mapping is performed after chronic classification, not before.

---

**D-36: Chronic classification secondary rule — SNOMED CORE Problem List**
For conditions not covered by QOF, chronic classification uses the SNOMED CT CORE Problem List Subset (NLM UMLS). Pending UMLS licence acquisition. Until licence received, non-QOF conditions flagged as unclassified in DCB0129 hazard log. Rationale: CORE Problem List is the closest SNOMED equivalent to AHRQ CCI — a curated, peer-reviewed list of clinically significant conditions used in EHR problem lists.

---

**D-37: Tier 2 non-cardiometabolic conditions — deferred**
Non-cardiometabolic chronic conditions (Tier 2) excluded from current project scope. The scoring engine, band assignment, and clinical output are complete using QOF cardiometabolic conditions only. Tier 2 expansion documented as planned future iteration pending UMLS licence. Rationale: Tier 2 does not affect NICE scoring, trajectory, variance, CVD status, or band assignment. Including an incomplete Tier 2 weakens the portfolio. Scope discipline is architecturally stronger than an incomplete expansion.

---

**D-38: ICD-10 mapping sequence — after chronic classification**
ICD-10 mapping performed only after chronic classification and domain segmentation are complete. Only conditions confirmed as chronic and clinically relevant to the scoring engine receive ICD-10 mapping. Rationale: eliminates unnecessary mapping of acute, dental, obstetric, and administrative conditions that will never reach the scoring engine. Reduces mapping scope from 400+ codes to approximately 60-80 chronic conditions.

---

**D-39: Risk group assignment — three tiers, NICE-anchored**
Three risk groups assigned before NICE threshold scoring. Standard: no established CVD, QRISK3 <10%, no T2DM complication. BP target 140/90, LDL 3.0. Elevated: QRISK3 ≥10% OR T2DM without complication. BP target 130/80, LDL 2.0. High Risk: established CVD OR CKD stage 3+ OR T2DM with complication. BP target 130/80, LDL 2.0. Sources: NICE NG136 sections 1.4.1 and 1.4.4, NICE CG181 sections 1.1 and 1.3, NICE NG28. Every threshold directly citable. No clinical inference.

---

**D-40: Established CVD definition — QOF SNOMED clusters**
Established CVD defined per NICE NG136 clinical criteria, operationalised using NHS England QOF Business Rules CHD, HF, AF, and Stroke SNOMED code clusters. Qualifying conditions: IHD, prior MI, STEMI, NSTEMI, heart failure, AF, CVA, valve disease, history of CABG, history of valve replacement. Source: NICE NG136, NHS Digital TRUD QOF Business Rules. Rationale: QOF clusters are the NHS operational definition — not clinical opinion.

---

**D-41: CVD recency definition — RECENT vs ESTABLISHED**
CVD+ RECENT: MI, STEMI, NSTEMI, CVA with onset_date within 12 months of snapshot. OR heart failure with onset_date within 12 months OR heart failure with linked INPATIENT encounter within 12 months. CVD+ ESTABLISHED: all other CVD conditions or qualifying acute events beyond 12 months. Source: NICE NG185, ACC/AHA 2019, NICE NG106. Rationale: 12-month post-acute event period is explicitly defined in NICE NG185 and ACC/AHA as requiring intensive monitoring. HF recency uses hospitalisation as the acute decompensation signal per NICE NG106 distinction between acute and chronic heart failure.

---

**D-42: Acute context filter — final rule**
Encounters where encounter_class IN (EMERGENCY, INPATIENT). If encounter_end IS NULL, encounter_end = encounter_start — single day window, no invented duration. Observations excluded where observation_date BETWEEN encounter_start AND encounter_end for systolic BP (8480-6) and diastolic BP (8462-4) only. HbA1c excluded from filtering — long biological integration period 8-12 weeks, RCPath HbA1c analytical guidance. LDL excluded from filtering — acute-phase physiological reduction handled by marker comparability rule. eGFR excluded from filtering — handled by marker comparability rule. HR and RR confirmed present in observations table but removed from filter — not scored markers in current scope. Source: BHS validated device measurement standards, RCPath, NICE NG203, KDIGO.

---

**D-43: Marker comparability rule — eGFR and LDL**
eGFR excluded from trajectory and variance calculations. Rationale: state-dependent biomarker — values not physiologically comparable across acute and non-acute conditions. Inpatient eGFR reflects AKI, fluid shifts, contrast nephropathy — a different physiological regime from baseline CKD. Source: KDIGO 2012, NICE NG203. LDL excluded from trajectory and variance. Rationale: acute-phase physiological reduction during systemic illness produces non-representative lipid levels. After acute context filter removes inpatient readings, remaining LDL readings represent outpatient baseline. Source: NICE CG181. Both markers retained in severity scoring.

---

**D-44: Marker eligibility for trajectory and variance**
Include if NICE defines a quantitative target OR minimum clinically meaningful change threshold for longitudinal interpretation. Eligible: systolic BP (NG136), HbA1c (NG28), LDL (CG181), eGFR (NG203 — trajectory via stage transition only). Excluded: BMI — no NICE longitudinal threshold structure. BMI retained in severity scoring only. Rationale: trajectory and variance require a published reference point for stability threshold definition. Without that reference, the calculation cannot be audit-safe.

---

**D-45: eGFR scoring — ordinal stage transition model**
eGFR scored using KDIGO ordinal staging, not exceedance intensity. CKD only included when HTN or T2DM present — complication depth indicator, not standalone renal epidemiology marker. Stage scored as ordinal integer: G1=1, G2=2, G3a=3, G3b=4, G4=5, G5=6. Trajectory defined as confirmed stage change — two eGFR readings at new stage more than 90 days apart. Baseline stage = first confirmed stage in observation window. Stable = no confirmed stage change. Variance not calculated for eGFR — categorical stage model has no continuous variance equivalent. Source: KDIGO 2012, NICE NG203, NICE NG28, NICE NG136.

---

**D-46: Exceedance intensity formula — locked**
I = max(0, (x - T) / T). Where x = observed value, T = NICE threshold for patient risk group. Output is unbounded continuous severity above target. Zero means controlled. Positive means uncontrolled — magnitude represents percentage above target. T stored as versioned constant in nice_thresholds reference table. I calculated at scoring time from stored x and T. Not stored permanently — recalculated on each scoring run. Source: NICE NG136, NG28, CG181, NG203.

---

**D-47: Monthly aggregation — frequency bias removal**
Month_score = mean(I values within calendar month). Each calendar month = one time unit regardless of reading frequency. Patient severity = mean(Month_scores) over observation window. Equal weighting of months. No recency decay. Limitation: does not capture recent deterioration — addressed independently by trajectory signal. Rationale: chronic disease burden is cumulative. Mean is consistent with chronic disease epidemiology literature and analogous to HbA1c biological averaging.

---

**D-48: Observation window — 12 months fixed**
All longitudinal metrics (mean_I, trajectory, variance) use a fixed 12-month window applied identically to all patients and all markers. Window = observation_date >= DATE(snapshot, '-12 months') AND observation_date <= snapshot. Source: NICE annual review cycle, ACC/AHA 12-month post-event monitoring period. Window stored in scoring_parameters table with version binding. Rationale: fixed window ensures cross-patient comparability. Without fixed window, mean(I) values are not comparable across patients with different data histories.

---

**D-49: Data sufficiency gate — single rule**
Minimum 3 calendar months with at least one reading AND minimum 2 total readings within observation window. Applies to: severity score, trajectory, variance, observation coverage. Below minimum: output flagged as DATA_INSUFFICIENT. Not scored as zero. Zero and DATA_INSUFFICIENT are clinically distinct states — zero means controlled, DATA_INSUFFICIENT means unknown. Rationale: statistical minimum for meaningful longitudinal calculation. Documented as clinical governance decision.

---

**D-50: Trajectory stability threshold — measurement error**
Primary rule: trajectory classified as stable if abs(mean month-to-month change in I) ≤ measurement_error/T. Measurement error thresholds: BP ±5 mmHg (BHS), HbA1c ±2 mmol/mol (RCPath), LDL ±9% biological variation (RCPath), eGFR ±5 ml/min per year (NICE NG203, KDIGO). Secondary interpretive overlay: clinically meaningful difference labels applied where published — HbA1c 5 mmol/mol (NICE NG28), eGFR 5 ml/min per year (NICE NG203), BP 10 mmHg (BHS). MCID overlay does not change classification — parallel descriptor only. Rationale: measurement error is externally defined, constant across patients, independent of disease state. Avoids patient-derived thresholds.

---

**D-51: Non-compensatory aggregation — patient-level summary**
Patient trajectory and variance derived using non-compensatory risk-maximising aggregation. Any worsening marker → patient trajectory = WORSENING. Any unstable marker → patient variance = UNSTABLE. Improvement in one marker does not offset deterioration in another. Rationale: consistent with clinical safety monitoring principles — alerts triggered by worst active parameter not average. Formally defined as non-compensatory to satisfy audit requirement.

---

**D-52: Worst marker tiebreak cascade**
Step 1: highest mean(I) across scored markers. Step 2: if tied → highest max(I) of Month_scores. Step 3: if still tied → most recent timestamp of max(I). All steps operate on I values — consistent framework, no signal switching. Reported value = mean(x)/T displayed as MARKER:mean(x)/target where mean(x) derived from stored x values. Both x and T stored permanently. I calculated from stored values — no back-calculation needed. Audit trail: x stored in observations, T stored in nice_thresholds, mean(x) calculated directly.

---

**D-53: Universal patient string — six fields, fixed positions**

```
CVD_STATUS | MARKERS_BREACHING | WORST_SEVERITY | SYSTEM_TRAJECTORY | SYSTEM_VARIANCE | CONDITION_COUNT
```

Field definitions locked:
- CVD_STATUS: NONE / ESTABLISHED / RECENT
- MARKERS_BREACHING: integer count of markers with mean(I) > 0, or DATA_INSUFFICIENT
- WORST_SEVERITY: MARKER:mean(x)/target e.g. HBA1C:84/53, or NO_DEVIATION if count=0, or DATA_INSUFFICIENT
- SYSTEM_TRAJECTORY: STABLE / WORSENING / IMPROVING / DATA_INSUFFICIENT — non-compensatory
- SYSTEM_VARIANCE: STABLE / UNSTABLE / DATA_INSUFFICIENT — non-compensatory
- CONDITION_COUNT: integer count of active QOF chronic conditions

Semantic map: NULL = calculated, result is absence of breach. DATA_INSUFFICIENT = could not calculate. NO_DEVIATION = all markers within target. Each field fixed position — same meaning across every patient. DOMINANT_MARKER retained as separate database column, available in Tableau Mode 1, not in primary string.

---

**D-54: Two output modes**
Mode 1: full information display in Tableau — per marker detail, all signals, interactive drill-down from population to patient to observation. No algorithmic judgement. Clinician interprets. Mode 2: universal patient string — objective, six fixed fields, one row per patient. Primary output of the system. Band and colour are secondary operational tools clearly labelled as decision support. Rationale: Mode 1 satisfies DCB0129 — system surfaces all relevant data and leaves clinical judgement to clinician. Mode 2 satisfies operational requirement — single actionable summary per patient.

---

**D-55: Guideline bundle version binding**
All scoring parameters and NICE thresholds bound to a named bundle version. Bundle naming convention: YYYYMMDD_BUNDLE_V{n} e.g. 20260406_BUNDLE_V1. Bundle contains: all active guideline versions per marker, all scoring parameters. Every priority_scores row references scoring_bundle. When any guideline updates, new bundle created, old bundle deprecated with deprecated_date. Old scores remain traceable to original bundle. Rationale: DCB0129 requires scores to be reproducible — bundle binding ensures any score row can be independently verified given the same bundle parameters. Tables required: guideline_bundle, guideline_bundle_items, scoring_parameters.

---

**D-56: x and T stored as permanent columns**
Observed value x stored in observations table (value_numeric — already exists). NICE threshold T stored in nice_thresholds reference table as versioned constant. I calculated at scoring time from x and T — not stored permanently. Recalculated on each scoring run. Rationale: storing x and T permanently ensures full audit traceability. I is always derivable from stored values. If T changes, new bundle version created, I automatically updated on next scoring run without modifying historical data.

---

**MODIFIED DECISIONS FROM SPRINT 1 LOG:**

**D-15 MODIFIED — ICD-10 codes in SNOMED field**
Original decision: exclude from SNOMED coding layer in FHIR export. Modified: ICD-10 codes misfiled in snomed_code column detected using GLOB pattern and routed to icd10_code column where NULL. snomed_code column retained — FHIR export layer resolves coding system dynamically using GLOB at export time. 716 rows affected, 670 successfully routed. Zero field conflicts confirmed. complication_category = excluded_field_error for all 716 rows. Added clean_data.sql Sections 20-24.

**D-14 MODIFIED — SNOMED to ICD-10 mapping sequence**
Original decision: mapping performed in Sprint 1 for 141 cardiometabolic codes. Modified: ICD-10 mapping now performed after chronic classification and domain segmentation. Only chronic, scoring-relevant conditions mapped. Mapping scope reduced from 400+ to approximately 60-80 conditions. Sprint 1 141-code map retained as foundation. New mappings added in prepare_cohort.sql not load_snomed_map.py.
