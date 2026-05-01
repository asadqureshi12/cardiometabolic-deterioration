"""
P3: Clinical Deterioration Monitoring System
fhir_pilot.py — FHIR R4 Bundle export (2-patient pilot)
=========================================================
Exports 2 cardiometabolic patients as a FHIR R4 collection bundle.
Resources: Patient, Condition, Observation, MedicationRequest, Encounter.
For validation against official HL7 FHIR validator before full build.

Run AFTER clean_data.sql:
    exec(open('/Users/asadqureshi/Downloads/p3_/fhir_pilot.py').read())

Output:
    /Users/asadqureshi/Downloads/p3_/fhir_pilot_bundle.json

Validate with:
    java -jar validator_cli.jar fhir_pilot_bundle.json -version 4.0.1
"""

import sqlite3
import json
import uuid
from pathlib import Path
from datetime import datetime

DB     = Path('/Users/asadqureshi/Downloads/p3_/p3_deterioration_full.db')
OUTPUT = Path('/Users/asadqureshi/Downloads/p3_/fhir_pilot_bundle.json')
BASE   = 'http://p3-deterioration-pipeline/'

conn = sqlite3.connect(DB)
conn.row_factory = sqlite3.Row
cur  = conn.cursor()

# ── Select 2 patients — prefer Both segment with rich data ──────────────────
patients = cur.execute("""
    SELECT p.*
    FROM patients p
    WHERE p.birthdate IS NOT NULL
      AND p.deathdate IS NULL
    ORDER BY (
        SELECT COUNT(*) FROM conditions c
        WHERE c.patient_id = p.patient_id
        AND c.icd10_code IS NOT NULL
    ) DESC
    LIMIT 2
""").fetchall()

print(f"Exporting {len(patients)} patients to FHIR R4 bundle")

entries = []

def add_entry(resource_type, resource_id, resource):
    entries.append({
        'fullUrl': f'{BASE}{resource_type}/{resource_id}',
        'resource': resource
    })

# ── FHIR encounter class display map ─────────────────────────────────────────
FHIR_CLASS_DISPLAY = {
    'AMB':  'ambulatory',
    'EMER': 'emergency',
    'IMP':  'inpatient encounter',
    'VR':   'virtual',
    'HH':   'home health',
}

# ── Invalid LOINC codes to exclude from FHIR export ──────────────────────────
INVALID_LOINC = {'X9999-2'}

# Display corrections for known Synthea formatting issues
# Synthea uses double spaces where the official display uses commas
LOINC_DISPLAY_CORRECTIONS = {
    '2028-9': 'Carbon dioxide, total [Moles/volume] in Serum or Plasma',
}

RXNORM_DISPLAY_CORRECTIONS = {
    '106892': 'insulin isophane, human 70 UNT/ML / insulin, regular, human 30 UNT/ML Injectable Suspension [Humulin]',
}

def clean_display(text):
    """Normalise display strings — collapse double spaces, strip whitespace."""
    if not text:
        return text
    import re
    return re.sub(r' {2,}', ' ', text).strip()

# ── FHIR gender map ───────────────────────────────────────────────────────────
GENDER_MAP = {'M': 'male', 'F': 'female', 'Other': 'other'}

for p in patients:
    pid = p['patient_id']
    print(f"  Processing patient: {pid[:8]}...")

    # ── Patient resource ──────────────────────────────────────────────────────
    patient_resource = {
        'resourceType': 'Patient',
        'id': pid,
        'meta': {
            'profile': ['http://hl7.org/fhir/StructureDefinition/Patient']
        },
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

    # ── Condition resources ───────────────────────────────────────────────────
    conditions = cur.execute("""
        SELECT * FROM conditions
        WHERE patient_id = ?
        ORDER BY onset_date
    """, (pid,)).fetchall()

    for c in conditions:
        cond_id = f"{pid}-{c['snomed_code']}"
        display = c['snomed_description_corrected'] or c['snomed_description']

        # Skip conditions where snomed_code is not a valid SNOMED integer
        # Synthea occasionally stores ICD-10-CM codes in the CODE field
        if not c['snomed_code'].isdigit():
            continue

        coding = [{
            'system': 'http://snomed.info/sct',
            'code': c['snomed_code'],
            'display': clean_display(display),
            'userSelected': True
        }]

        if c['icd10_code']:
            coding.append({
                'system': 'http://hl7.org/fhir/sid/icd-10',
                'code': c['icd10_code'],
                'display': clean_display(c['icd10_desc'] or c['icd10_code']),
                'userSelected': False
            })

        cond_resource = {
            'resourceType': 'Condition',
            'id': cond_id,
            'meta': {
                'profile': ['http://hl7.org/fhir/StructureDefinition/Condition']
            },
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
            'code': {
                'coding': coding,
                'text': display
            },
            'subject': {
                'reference': f'Patient/{pid}'
            }
        }

        if c['onset_date']:
            cond_resource['onsetDateTime'] = c['onset_date']
        if c['resolution_date']:
            cond_resource['abatementDateTime'] = c['resolution_date']

        add_entry('Condition', cond_id, cond_resource)

    # ── Observation resources (numeric only, valid LOINC, limit 20) ───────────
    observations = cur.execute("""
        SELECT * FROM observations
        WHERE patient_id = ?
          AND value_numeric IS NOT NULL
        ORDER BY observation_date DESC
        LIMIT 20
    """, (pid,)).fetchall()

    for o in observations:
        # Skip invalid or placeholder LOINC codes
        if o['loinc_code'] in INVALID_LOINC:
            continue
        obs_id = str(o['observation_id'])

        obs_resource = {
            'resourceType': 'Observation',
            'id': obs_id,
            'meta': {
                'profile': ['http://hl7.org/fhir/StructureDefinition/Observation']
            },
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
                    'display': LOINC_DISPLAY_CORRECTIONS.get(o['loinc_code'], clean_display(o['description']))
                }],
                'text': LOINC_DISPLAY_CORRECTIONS.get(o['loinc_code'], clean_display(o['description']))
            },
            'subject': {
                'reference': f'Patient/{pid}'
            },
            'effectiveDateTime': o['observation_date'],
            'valueQuantity': {
                'value': o['value_numeric'],
                'unit': o['units'] or 'unit',
                'system': 'http://unitsofmeasure.org',
                'code': o['units'] or '1'
            }
        }

        add_entry('Observation', obs_id, obs_resource)

    # ── MedicationRequest resources (active only, limit 10) ───────────────────
    medications = cur.execute("""
        SELECT * FROM medications
        WHERE patient_id = ?
          AND is_active = 1
        LIMIT 10
    """, (pid,)).fetchall()

    for m in medications:
        med_id = str(m['medication_id'])

        med_resource = {
            'resourceType': 'MedicationRequest',
            'id': med_id,
            'meta': {
                'profile': ['http://hl7.org/fhir/StructureDefinition/MedicationRequest']
            },
            'status': 'active',
            'intent': 'order',
            'medicationCodeableConcept': {
                'coding': [{
                    'system': m['medication_system'] or 'http://www.nlm.nih.gov/research/umls/rxnorm',
                    'code': m['medication_code'],
                    'display': RXNORM_DISPLAY_CORRECTIONS.get(m['medication_code'], clean_display(m['medication_description']))
                }],
                'text': RXNORM_DISPLAY_CORRECTIONS.get(m['medication_code'], clean_display(m['medication_description']))
            },
            'subject': {
                'reference': f'Patient/{pid}'
            },
            'authoredOn': m['start_date']
        }

        add_entry('MedicationRequest', med_id, med_resource)

    # ── Encounter resources (last 5) ──────────────────────────────────────────
    encounters = cur.execute("""
        SELECT * FROM encounters
        WHERE patient_id = ?
        ORDER BY encounter_date DESC
        LIMIT 5
    """, (pid,)).fetchall()

    for e in encounters:
        enc_resource = {
            'resourceType': 'Encounter',
            'id': e['encounter_id'],
            'meta': {
                'profile': ['http://hl7.org/fhir/StructureDefinition/Encounter']
            },
            'status': e['fhir_status'] or 'finished',
            'class': {
                'system': 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
                'code': e['fhir_class'] or 'AMB',
                'display': FHIR_CLASS_DISPLAY.get(e['fhir_class'] or 'AMB', 'ambulatory')
            },
            'subject': {
                'reference': f'Patient/{pid}'
            }
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
                    'display': e['reason_description']
                }]
            }]

        add_entry('Encounter', e['encounter_id'], enc_resource)

conn.close()

# ── Build bundle ──────────────────────────────────────────────────────────────
bundle = {
    'resourceType': 'Bundle',
    'id': str(uuid.uuid4()),
    'meta': {
        'lastUpdated': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
    },
    'type': 'collection',
    'entry': entries
}

with open(OUTPUT, 'w') as f:
    json.dump(bundle, f, indent=2)

# ── Summary ───────────────────────────────────────────────────────────────────
resource_counts = {}
for e in entries:
    rt = e['resource']['resourceType']
    resource_counts[rt] = resource_counts.get(rt, 0) + 1

print(f"\nFHIR R4 Bundle written to: {OUTPUT}")
print(f"Total entries: {len(entries)}")
for rt, count in sorted(resource_counts.items()):
    print(f"  {rt}: {count}")
print(f"\nValidate with:")
print(f"  java -jar validator_cli.jar {OUTPUT} -version 4.0.1")
