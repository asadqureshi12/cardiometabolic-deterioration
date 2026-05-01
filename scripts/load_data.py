"""
P3: Clinical Deterioration Monitoring System
load_data.py — Pure CSV to SQLite loader
=========================================
Python's only job: read Synthea CSV files, insert every row.
No filtering, no selection, no cleaning, no logic.
All clinical decisions happen in SQL.

Prerequisites:
  1. Run schema.sql in DB Browser first to create all 8 tables.
  2. Place this file in Downloads/p3_/
  3. Run in Jupyter: exec(open('/Users/asadqureshi/Downloads/p3_/load_data.py').read())
"""

import sqlite3
import csv
import hashlib
from pathlib import Path

SYNTHEA = Path('/Users/asadqureshi/Downloads/output/csv')
DB      = Path('/Users/asadqureshi/Downloads/p3_/p3_deterioration_full.db')

conn = sqlite3.connect(DB)
conn.execute("PRAGMA foreign_keys = OFF")
conn.execute("PRAGMA journal_mode = WAL")
conn.execute("PRAGMA synchronous = NORMAL")
cur  = conn.cursor()

def hash_val(val):
    return hashlib.sha256(val.encode()).hexdigest()[:16]

def safe_float(val):
    try: return float(val)
    except: return None

def safe_int(val):
    try: return int(val)
    except: return None

def safe_date(val):
    if not val or not val.strip(): return None
    return val.strip()[:10]

# ── 1. PATIENTS ───────────────────────────────────────────────────────────────
print("Loading patients...")
n = 0
with open(SYNTHEA / 'patients.csv') as f:
    for row in csv.DictReader(f):
        cur.execute("""
            INSERT OR IGNORE INTO patients (
                patient_id, nhs_number_hash, birthdate, deathdate,
                age, sex, race, ethnicity, income,
                city, state
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?)
        """, (
            row['Id'],
            hash_val(row.get('SSN','')),
            safe_date(row['BIRTHDATE']),
            safe_date(row.get('DEATHDATE','')),
            None,
            'F' if row.get('GENDER') == 'F' else 'M',
            row.get('RACE'),
            row.get('ETHNICITY'),
            safe_float(row.get('INCOME','')),
            row.get('CITY'),
            row.get('STATE'),
        ))
        n += 1
conn.commit()
print(f"  {n} rows processed")

# ── 2. CONDITIONS ─────────────────────────────────────────────────────────────
print("Loading conditions...")
n = 0
with open(SYNTHEA / 'conditions.csv') as f:
    for row in csv.DictReader(f):
        try:
            cur.execute("""
                INSERT OR IGNORE INTO conditions (
                    patient_id, snomed_code, snomed_description,
                    condition_name, onset_date, resolution_date,
                    is_active, encounter_id, recorded_date
                ) VALUES (?,?,?,?,?,?,?,?,?)
            """, (
                row['PATIENT'],
                row['CODE'],
                row['DESCRIPTION'],
                row['DESCRIPTION'],
                safe_date(row.get('START','')),
                safe_date(row.get('STOP','')),
                None,
                row.get('ENCOUNTER'),
                safe_date(row.get('START','')),
            ))
            n += 1
        except: pass
conn.commit()
print(f"  {n} rows processed")

# ── 3. ENCOUNTERS ─────────────────────────────────────────────────────────────
print("Loading encounters...")
n = 0
with open(SYNTHEA / 'encounters.csv') as f:
    for row in csv.DictReader(f):
        try:
            cur.execute("""
                INSERT OR IGNORE INTO encounters (
                    encounter_id, patient_id, encounter_date, encounter_end,
                    encounter_class, reason_code, reason_description
                ) VALUES (?,?,?,?,?,?,?)
            """, (
                row['Id'],
                row['PATIENT'],
                safe_date(row.get('START','')),
                safe_date(row.get('STOP','')),
                row.get('ENCOUNTERCLASS'),
                row['REASONCODE']        if row.get('REASONCODE','').strip()        else None,
                row['REASONDESCRIPTION'] if row.get('REASONDESCRIPTION','').strip() else None,
            ))
            n += 1
        except: pass
conn.commit()
print(f"  {n} rows processed")

# ── 4. OBSERVATIONS ───────────────────────────────────────────────────────────
print("Loading observations... (this is the large one)")
n = 0
with open(SYNTHEA / 'observations.csv') as f:
    for row in csv.DictReader(f):
        try:
            val = row.get('VALUE','').strip() or None
            try:
                val_numeric = float(val)
                obs_type    = 'numeric'
                val_cat     = None
            except:
                val_numeric = None
                obs_type    = 'text'
                val_cat     = val
            cur.execute("""
                INSERT INTO observations (
                    patient_id, encounter_id, observation_date,
                    category, loinc_code, description,
                    value, value_numeric, value_categorical,
                    units, observation_type
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """, (
                row['PATIENT'],
                row['ENCOUNTER'] if row.get('ENCOUNTER','').strip() else None,
                safe_date(row.get('DATE','')),
                row.get('CATEGORY') or None,
                row['CODE'],
                row['DESCRIPTION'],
                val,
                val_numeric,
                val_cat,
                row.get('UNITS') or None,
                obs_type,
            ))
            n += 1
            if n % 100000 == 0:
                conn.commit()
                print(f"    {n:,} observations inserted...")
        except: pass
conn.commit()
print(f"  {n} rows processed")

# ── 5. MEDICATIONS ────────────────────────────────────────────────────────────
print("Loading medications...")
n = 0
with open(SYNTHEA / 'medications.csv') as f:
    for row in csv.DictReader(f):
        try:
            cur.execute("""
                INSERT INTO medications (
                    patient_id, encounter_id, medication_code,
                    medication_description, start_date, stop_date,
                    is_active, reason_code, reason_description,
                    dispenses, total_cost
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """, (
                row['PATIENT'],
                row.get('ENCOUNTER') or None,
                row['CODE'],
                row['DESCRIPTION'],
                safe_date(row.get('START','')),
                safe_date(row.get('STOP','')),
                None,
                row.get('REASONCODE')        or None,
                row.get('REASONDESCRIPTION') or None,
                safe_int(row.get('DISPENSES','')),
                safe_float(row.get('TOTALCOST','')),
            ))
            n += 1
        except: pass
conn.commit()
print(f"  {n} rows processed")

# ── SUMMARY ───────────────────────────────────────────────────────────────────
print("\nLoad complete. Row counts:")
for table in ['patients','conditions','encounters','observations','medications',
              'deterioration_scores','clinical_alerts','clinical_problem_log']:
    count = cur.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"  {table:<30} {count:>8,}")

conn.close()
print(f"\nDatabase: {DB}")
