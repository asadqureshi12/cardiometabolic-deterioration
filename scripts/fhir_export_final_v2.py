"""
P3: Cardiometabolic Deterioration Monitoring System
fhir_export_final_v2.py — FHIR R4 Bundle export, production version
=====================================================================
631 cohort patients, 3 bundles of ~210 patients each.
Resources: Patient, Condition, Observation (BP panel + scoring markers),
           MedicationRequest, Encounter, RiskAssessment
Changes vs v1:
  - Encounter linkage added to Condition, Observation, MedicationRequest
  - RiskAssessment resource added per patient for scoring outputs
    (deterioration band, trajectory, variance, priority string)
  - Reference ranges added to scoring Observations from nice_thresholds
    Source: NICE NG136 (SBP), NICE NG28 (HbA1c, BMI), NICE NG238 (LDL),
            NICE NG203/KDIGO 2012 (eGFR)
Known limitations:
  - ICD-10 codes E11.21, E11.22, E11.29, E11.40, E11.39, C34.90, E66.01,
    G43.7, G89.2 not in validator ICD-10 2019-covid-expanded version
  - SNOMED display drift: Synthea strings differ from SNOMED FSN for
    a small number of concepts
  - dom-6 narrative: best practice recommendation, not a structural error
  - Medications coded in RxNorm — Synthea constraint.
    Real NHS deployment uses dm+d via TRUD.
"""

import sqlite3
import json
import uuid
import re
from pathlib import Path
from datetime import datetime, timezone

DB      = Path('/Users/asadqureshi/Downloads/p3_/p3_deterioration_full.db')
OUTPUT1 = Path('/Users/asadqureshi/Downloads/p3_/fhir_bundle_part1.json')
OUTPUT2 = Path('/Users/asadqureshi/Downloads/p3_/fhir_bundle_part2.json')
OUTPUT3 = Path('/Users/asadqureshi/Downloads/p3_/fhir_bundle_part3.json')
BASE    = 'http://p3-deterioration-pipeline/'

conn = sqlite3.connect(DB)
conn.row_factory = sqlite3.Row

GENDER_MAP = {'M': 'male', 'F': 'female', 'Other': 'other'}

FHIR_CLASS_DISPLAY = {
    'AMB':  'ambulatory',
    'EMER': 'emergency',
    'IMP':  'inpatient encounter',
    'VR':   'virtual',
    'HH':   'home health',
}

# RxNorm display normalisation
# Source: NLM RxNorm canonical names
# https://bioportal.bioontology.org/ontologies/RXNORM?p=classes&conceptid=106892
RXNORM_DISPLAY_CORRECTIONS = {
    '106892': 'insulin isophane, human 70 UNT/ML / insulin, regular, human 30 UNT/ML Injectable Suspension [Humulin]',
}

# ICD-10 secondary coding scoped to snomed_icd10_map_p3 only
MAPPED_SNOMED_CODES = set(
    row[0] for row in conn.execute(
        "SELECT snomed_code FROM snomed_icd10_map_p3"
    ).fetchall()
)

# Reference ranges from nice_thresholds
# Keyed by loinc_code and cvd_status
NICE_THRESHOLDS = {}
for row in conn.execute("SELECT * FROM nice_thresholds").fetchall():
    NICE_THRESHOLDS[(row['loinc_code'], row['cvd_status'])] = row

# Band to risk probability mapping (documented design decision)
# Band 1 = low risk, Band 4 = high risk
# Probability estimates are ordinal proxies only — not statistically derived
BAND_PROBABILITY = {1: 0.05, 2: 0.25, 3: 0.55, 4: 0.85}

def clean_display(text):
    if not text:
        return text
    return re.sub(r' {2,}', ' ', text).strip()

UCUM_UNITS = {
    'mmHg':              'mm[Hg]',
    'mm[Hg]':            'mm[Hg]',
    '%':                 '%',
    'mg/dL':             'mg/dL',
    'kg/m2':             'kg/m2',
    'mL/min/1.73m2':     'mL/min/{1.73_m2}',
}

def get_reference_range(loinc_code, cvd_status):
    """Return FHIR referenceRange list for a scoring marker.
    Unit codes normalised to UCUM via UCUM_UNITS map.
    Thresholds sourced from nice_thresholds table:
    NICE NG136 (SBP), NICE NG28 (HbA1c, BMI), NICE NG238 (LDL),
    NICE NG203/KDIGO 2012 (eGFR).
    """
    row = NICE_THRESHOLDS.get((loinc_code, cvd_status)) or \
          NICE_THRESHOLDS.get((loinc_code, 'ALL'))
    if not row:
        return None

    unit = UCUM_UNITS.get(row['unit'], row['unit'])

    if loinc_code == '33914-3':
        return [{
            'low': {
                'value': row['t_value'],
                'unit': unit,
                'system': 'http://unitsofmeasure.org',
                'code': unit
            },
            'text': f"NICE NG203/KDIGO 2012 — CKD stage 3a threshold: {row['t_value']} {row['unit']}"
        }]

    return [{
        'high': {
            'value': row['t_value'],
            'unit': unit,
            'system': 'http://unitsofmeasure.org',
            'code': unit
        },
        'text': f"{row['guideline_source']} threshold: {row['t_value']} {row['unit']}"
    }]


def build_bundle(patients, part_label):
    entries = []

    def add_entry(resource_type, resource_id, resource):
        entries.append({
            'fullUrl': f'{BASE}{resource_type}/{resource_id}',
            'resource': resource
        })

    for p in patients:
        pid = p['patient_id']
        cvd_status = p['cvd_status'] if 'cvd_status' in p.keys() else 'NONE'

        # ── Patient ──────────────────────────────────────────────────────────
        patient_resource = {
            'resourceType': 'Patient',
            'id': pid,
            'meta': {'profile': ['http://hl7.org/fhir/StructureDefinition/Patient']},
            'identifier': [{
                'use': 'secondary',
                'type': {
                    'coding': [{
                        'system': 'http://terminology.hl7.org/CodeSystem/v2-0203',
                        'code': 'MR',
                        'display': 'Medical record number'
                    }],
                    'text': 'Synthetic identifier — not a real NHS number'
                },
                'system': 'http://p3-deterioration-pipeline/synthetic-id',
                'value': p['nhs_number_hash']
            }],
            'active': True,
            'gender': GENDER_MAP.get(p['sex'], 'unknown'),
            'birthDate': p['birthdate']
        }
        add_entry('Patient', pid, patient_resource)

        # ── RiskAssessment ────────────────────────────────────────────────────
        # FHIR-native home for deterioration band, trajectory, variance
        # Only exported for patients with a final_band score
        if p['final_band'] is not None:
            ra_id = f"ra-{pid}"
            band = p['final_band']
            probability = BAND_PROBABILITY.get(band, 0.05)

            prediction = [{
                'outcome': {
                    'coding': [{
                        'system': 'http://p3-deterioration-pipeline/deterioration-band',
                        'code': str(band),
                        'display': f'Deterioration Band {band}'
                    }],
                    'text': f'Cardiometabolic deterioration band {band} of 4'
                },
                'probabilityDecimal': probability,
                'rationale': f"Rule-based exceedance scoring. Band {band} assigned from "
                             f"NICE-threshold exceedance, BMI floor rule (NICE CG189), "
                             f"and temporal trajectory/variance signals. "
                             f"Probability is an ordinal proxy only — not statistically derived."
            }]

            ra_resource = {
                'resourceType': 'RiskAssessment',
                'id': ra_id,
                'meta': {'profile': ['http://hl7.org/fhir/StructureDefinition/RiskAssessment']},
                'status': 'final',
                'subject': {'reference': f'Patient/{pid}'},
                'occurrenceDateTime': '2026-04-06',
                'method': {
                    'coding': [{
                        'system': 'http://p3-deterioration-pipeline/scoring-method',
                        'code': 'rule-based-exceedance',
                        'display': 'Rule-based NICE threshold exceedance scoring'
                    }],
                    'text': 'Non-compensatory worst-case aggregation with BMI floor rule. '
                            'Clinical logic designed by builder using medical training. '
                            'Pipeline version: BANDS_V6/PS_V4/TEMPORAL_V3.'
                },
                'prediction': prediction,
                'note': []
            }

            # Add trajectory note if available
            if p['system_trajectory']:
                ra_resource['note'].append({
                    'text': f"System trajectory: {p['system_trajectory']}. "
                            f"System variance: {p['system_variance'] or 'NOT_EVALUATED'}. "
                            f"Data sufficiency: {p['data_sufficiency_display'] or 'DATA_INSUFFICIENT'}."
                })

            # Add priority string note if available
            if p['patient_string']:
                ra_resource['note'].append({
                    'text': f"Priority string: {p['patient_string']}"
                })

            if not ra_resource['note']:
                del ra_resource['note']

            add_entry('RiskAssessment', ra_id, ra_resource)

        # ── Conditions ───────────────────────────────────────────────────────
        conditions = conn.execute("""
            SELECT * FROM conditions
            WHERE patient_id = ?
              AND is_active = 1
              AND complication_category = 'clinical_active'
            ORDER BY onset_date
        """, (pid,)).fetchall()

        for c in conditions:
            snomed_code = c['snomed_code'] or ''
            if not snomed_code.isdigit():
                continue

            cond_id = f"{pid}-{snomed_code}"
            display = clean_display(
                c['snomed_description_corrected'] or c['snomed_description'] or snomed_code
            )

            coding = [{
                'system': 'http://snomed.info/sct',
                'code': snomed_code,
                'display': display,
                'userSelected': True
            }]

            if c['icd10_code'] and snomed_code in MAPPED_SNOMED_CODES:
                coding.append({
                    'system': 'http://hl7.org/fhir/sid/icd-10',
                    'code': c['icd10_code'],
                    'userSelected': False
                })

            cond_resource = {
                'resourceType': 'Condition',
                'id': cond_id,
                'meta': {'profile': ['http://hl7.org/fhir/StructureDefinition/Condition']},
                'clinicalStatus': {
                    'coding': [{
                        'system': 'http://terminology.hl7.org/CodeSystem/condition-clinical',
                        'code': 'active' if c['is_active'] == 1 else 'resolved',
                        'display': 'Active' if c['is_active'] == 1 else 'Resolved'
                    }]
                },
                'verificationStatus': {
                    'coding': [{
                        'system': 'http://terminology.hl7.org/CodeSystem/condition-ver-status',
                        'code': c['verification_status'] or 'confirmed',
                        'display': (c['verification_status'] or 'confirmed').capitalize()
                    }]
                },
                'code': {'coding': coding, 'text': display},
                'subject': {'reference': f'Patient/{pid}'}
            }

            if c['encounter_id']:
                cond_resource['encounter'] = {'reference': f'Encounter/{c["encounter_id"]}'}
            if c['onset_date']:
                cond_resource['onsetDateTime'] = c['onset_date']
            if c['resolution_date']:
                cond_resource['abatementDateTime'] = c['resolution_date']

            add_entry('Condition', cond_id, cond_resource)

        # ── BP Panel observations (paired SBP + DBP) ──────────────────────────
        bp_pairs = conn.execute("""
            SELECT
                o1.observation_id AS sbp_id,
                o2.observation_id AS dbp_id,
                o1.encounter_id,
                o1.observation_date,
                o1.value_numeric AS sbp,
                o2.value_numeric AS dbp,
                o1.observation_status
            FROM observations o1
            JOIN observations o2
              ON o1.patient_id = o2.patient_id
             AND o1.encounter_id = o2.encounter_id
             AND o1.observation_date = o2.observation_date
            WHERE o1.patient_id = ?
              AND o1.loinc_code = '8480-6'
              AND o2.loinc_code = '8462-4'
              AND o1.value_excluded = 0
              AND o2.value_excluded = 0
              AND o1.value_numeric IS NOT NULL
              AND o2.value_numeric IS NOT NULL
            ORDER BY o1.observation_date DESC
            LIMIT 50
        """, (pid,)).fetchall()

        for bp in bp_pairs:
            bp_panel_id = f"bp-{bp['sbp_id']}-{bp['dbp_id']}"

            # Reference ranges for SBP from NICE NG136
            sbp_ref = get_reference_range('8480-6', cvd_status)

            bp_resource = {
                'resourceType': 'Observation',
                'id': bp_panel_id,
                'meta': {'profile': ['http://hl7.org/fhir/StructureDefinition/bp']},
                'status': bp['observation_status'] or 'final',
                'category': [{
                    'coding': [{
                        'system': 'http://terminology.hl7.org/CodeSystem/observation-category',
                        'code': 'vital-signs',
                        'display': 'Vital Signs'
                    }]
                }],
                'code': {
                    'coding': [{
                        'system': 'http://loinc.org',
                        'code': '85354-9',
                        'display': 'Blood pressure panel with all children optional'
                    }],
                    'text': 'Blood pressure panel'
                },
                'subject': {'reference': f'Patient/{pid}'},
                'effectiveDateTime': bp['observation_date'],
                'component': [
                    {
                        'code': {
                            'coding': [{
                                'system': 'http://loinc.org',
                                'code': '8480-6',
                                'display': 'Systolic blood pressure'
                            }]
                        },
                        'valueQuantity': {
                            'value': round(bp['sbp'], 1),
                            'unit': 'mm[Hg]',
                            'system': 'http://unitsofmeasure.org',
                            'code': 'mm[Hg]'
                        }
                    },
                    {
                        'code': {
                            'coding': [{
                                'system': 'http://loinc.org',
                                'code': '8462-4',
                                'display': 'Diastolic blood pressure'
                            }]
                        },
                        'valueQuantity': {
                            'value': round(bp['dbp'], 1),
                            'unit': 'mm[Hg]',
                            'system': 'http://unitsofmeasure.org',
                            'code': 'mm[Hg]'
                        }
                    }
                ]
            }

            if bp['encounter_id']:
                bp_resource['encounter'] = {'reference': f'Encounter/{bp["encounter_id"]}'}
            if sbp_ref:
                bp_resource['referenceRange'] = sbp_ref

            add_entry('Observation', bp_panel_id, bp_resource)

        # ── Non-BP scoring observations (HbA1c, LDL, eGFR, BMI) ──────────────
        observations = conn.execute("""
            SELECT * FROM observations
            WHERE patient_id = ?
              AND loinc_code IN ('4548-4','18262-6','39156-5','33914-3')
              AND value_excluded = 0
              AND value_numeric IS NOT NULL
            ORDER BY observation_date DESC
            LIMIT 50
        """, (pid,)).fetchall()

        for o in observations:
            obs_id = str(o['observation_id'])
            ref_range = get_reference_range(o['loinc_code'], cvd_status)

            # LDL uses CVD-specific threshold — look up correctly
            if o['loinc_code'] == '18262-6':
                cvd_key = 'CVD' if cvd_status in ('ESTABLISHED', 'RECENT') else 'NONE'
                ref_range = get_reference_range('18262-6', cvd_key)

            obs_resource = {
                'resourceType': 'Observation',
                'id': obs_id,
                'meta': {'profile': ['http://hl7.org/fhir/StructureDefinition/Observation']},
                'status': o['observation_status'] or 'final',
                'category': [{
                    'coding': [{
                        'system': 'http://terminology.hl7.org/CodeSystem/observation-category',
                        'code': o['category'] or 'laboratory',
                        'display': (o['category'] or 'laboratory').replace('-', ' ').title()
                    }]
                }],
                'code': {
                    'coding': [{
                        'system': 'http://loinc.org',
                        'code': o['loinc_code'],
                        'display': clean_display(o['description'])
                    }],
                    'text': clean_display(o['description'])
                },
                'subject': {'reference': f'Patient/{pid}'},
                'effectiveDateTime': o['observation_date'],
                'valueQuantity': {
                    'value': round(o['value_numeric'], 4),
                    'unit': o['units'] or 'unit',
                    'system': 'http://unitsofmeasure.org',
                    'code': o['units'] or '1'
                }
            }

            if o['encounter_id']:
                obs_resource['encounter'] = {'reference': f'Encounter/{o["encounter_id"]}'}
            if ref_range:
                obs_resource['referenceRange'] = ref_range

            add_entry('Observation', obs_id, obs_resource)

        # ── Medications ───────────────────────────────────────────────────────
        medications = conn.execute("""
            SELECT * FROM medications
            WHERE patient_id = ?
              AND is_active = 1
            ORDER BY start_date DESC
            LIMIT 10
        """, (pid,)).fetchall()

        for m in medications:
            med_id = str(m['medication_id'])
            med_display = RXNORM_DISPLAY_CORRECTIONS.get(
                m['medication_code'],
                clean_display(m['medication_description'])
            )
            med_resource = {
                'resourceType': 'MedicationRequest',
                'id': med_id,
                'meta': {'profile': ['http://hl7.org/fhir/StructureDefinition/MedicationRequest']},
                'status': 'active',
                'intent': 'order',
                'medicationCodeableConcept': {
                    'coding': [{
                        'system': m['medication_system'] or 'http://www.nlm.nih.gov/research/umls/rxnorm',
                        'code': m['medication_code'],
                        'display': med_display
                    }],
                    'text': med_display
                },
                'subject': {'reference': f'Patient/{pid}'},
                'authoredOn': m['start_date']
            }

            if m['encounter_id']:
                med_resource['encounter'] = {'reference': f'Encounter/{m["encounter_id"]}'}

            add_entry('MedicationRequest', med_id, med_resource)

        # ── Encounters ────────────────────────────────────────────────────────
        encounters = conn.execute("""
            SELECT * FROM encounters
            WHERE patient_id = ?
            ORDER BY encounter_date DESC
            LIMIT 5
        """, (pid,)).fetchall()

        for e in encounters:
            fhir_class = e['fhir_class'] or 'AMB'
            enc_resource = {
                'resourceType': 'Encounter',
                'id': e['encounter_id'],
                'meta': {'profile': ['http://hl7.org/fhir/StructureDefinition/Encounter']},
                'status': e['fhir_status'] or 'finished',
                'class': {
                    'system': 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
                    'code': fhir_class,
                    'display': FHIR_CLASS_DISPLAY.get(fhir_class, 'ambulatory')
                },
                'subject': {'reference': f'Patient/{pid}'}
            }

            if e['encounter_date']:
                enc_resource['period'] = {'start': e['encounter_date']}
                if e['encounter_end']:
                    enc_resource['period']['end'] = e['encounter_end']
            if e['reason_code'] and e['reason_description']:
                enc_resource['reasonCode'] = [{
                    'coding': [{
                        'system': 'http://snomed.info/sct',
                        'code': e['reason_code'],
                        'display': clean_display(e['reason_description'])
                    }]
                }]

            add_entry('Encounter', e['encounter_id'], enc_resource)

    bundle = {
        'resourceType': 'Bundle',
        'id': str(uuid.uuid4()),
        'meta': {
            'lastUpdated': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        },
        'type': 'collection',
        'entry': entries
    }

    resource_counts = {}
    for e in entries:
        rt = e['resource']['resourceType']
        resource_counts[rt] = resource_counts.get(rt, 0) + 1

    print(f"\n{part_label}: {len(entries)} entries")
    for rt, count in sorted(resource_counts.items()):
        print(f"  {rt}: {count}")

    return bundle


# ── Load all 631 patients ─────────────────────────────────────────────────────
all_patients = conn.execute("""
    SELECT p.*,
           pc.cvd_status,
           pb.final_band, pb.data_sufficiency_display,
           ps.patient_string,
           pts.system_trajectory, pts.system_variance
    FROM patients p
    JOIN patient_cohort pc ON p.patient_id = pc.patient_id
    LEFT JOIN patient_bands pb ON p.patient_id = pb.patient_id
    LEFT JOIN priority_scores ps ON p.patient_id = ps.patient_id
    LEFT JOIN patient_temporal_signals pts ON p.patient_id = pts.patient_id
    ORDER BY p.patient_id
""").fetchall()

n = len(all_patients)
split1 = n // 3
split2 = 2 * (n // 3)

part1 = all_patients[:split1]
part2 = all_patients[split1:split2]
part3 = all_patients[split2:]

print(f"Total patients: {n}")
print(f"Part 1: {len(part1)} | Part 2: {len(part2)} | Part 3: {len(part3)}")

b1 = build_bundle(part1, 'Part 1')
b2 = build_bundle(part2, 'Part 2')
b3 = build_bundle(part3, 'Part 3')

with open(OUTPUT1, 'w') as f: json.dump(b1, f, indent=2)
with open(OUTPUT2, 'w') as f: json.dump(b2, f, indent=2)
with open(OUTPUT3, 'w') as f: json.dump(b3, f, indent=2)

conn.close()

print(f"\nBundles written. Run validator:")
print(f"  java -Xmx4g -jar ~/Downloads/validator_cli.jar ~/Downloads/p3_/fhir_bundle_part1.json -version 4.0.1 > ~/Desktop/fhir_report_part1.txt 2>&1")
print(f"  java -Xmx4g -jar ~/Downloads/validator_cli.jar ~/Downloads/p3_/fhir_bundle_part2.json -version 4.0.1 > ~/Desktop/fhir_report_part2.txt 2>&1")
print(f"  java -Xmx4g -jar ~/Downloads/validator_cli.jar ~/Downloads/p3_/fhir_bundle_part3.json -version 4.0.1 > ~/Desktop/fhir_report_part3.txt 2>&1")