"""
P3: Clinical Deterioration Monitoring System
load_snomed_map.py — Reference table loader
============================================
Populates snomed_icd10_map table from:
  1. P2 validated mapping (129 codes, FHIR-validated)
  2. P3 extensions for cardiometabolic codes absent from P2

Run AFTER schema.sql, BEFORE load_data.py:
    exec(open('/Users/asadqureshi/Downloads/p3_/load_snomed_map.py').read())
"""

import sqlite3
from pathlib import Path

DB = Path('/Users/asadqureshi/Downloads/p3_/p3_deterioration_full.db')
conn = sqlite3.connect(DB)
cur  = conn.cursor()

# ── P2 validated mapping (129 codes) ─────────────────────────────────────────
# Format: (snomed_code, icd10_code, icd10_desc, snomed_desc_corrected, p2_category)
P2_MAPPING = [
    ('10509002','J20.9','Acute bronchitis, unspecified','Acute bronchitis (disorder)','PULMONOLOGY'),
    ('109838007','C18.8','Overlapping malignant neoplasm of colon','Overlapping malignant neoplasm of colon','GENERAL SURGERY'),
    ('110030002','S09.9','Unspecified injury of head','Concussion injury of brain','NEUROLOGY / CEREBROVASCULAR'),
    ('124171000119105','G43.7','Chronic migraine without aura — intractable','Chronic intractable migraine without aura (disorder)','NEUROLOGY / CEREBROVASCULAR'),
    ('126906006','D29.1','Benign neoplasm of prostate','Neoplasm of prostate (disorder)','MALE REPRODUCTIVE'),
    ('127013003','E11.2','Type 2 diabetes mellitus : With renal complications','Diabetic renal disease (disorder)','DIABETES COMPLICATIONS'),
    ('128613002','G40.9','Epilepsy, unspecified','Seizure disorder (disorder)','NEUROLOGY / CEREBROVASCULAR'),
    ('1501000119109','E11.3','Type 2 diabetes mellitus : With ophthalmic complications','Proliferative diabetic retinopathy due to type II diabetes mellitus (disorder)','DIABETES COMPLICATIONS'),
    ('1551000119108','E11.3','Type 2 diabetes mellitus : With ophthalmic complications','Nonproliferative retinopathy due to type 2 diabetes mellitus','DIABETES COMPLICATIONS'),
    ('156073000','O36.9','Maternal care for unspecified fetal problem','Fetus with chromosomal abnormality (disorder)','GYNECOLOGY & OBSTETRICS'),
    ('15777000','R73.0','Abnormal glucose — prediabetes','Prediabetes (finding)','ENDOCRINOLOGY'),
    ('16114001','S82.8','Fracture of other parts of lower leg','Fracture of ankle (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('162573006','R91.8','Nonspecific abnormal findings on imaging','Suspected lung cancer (situation)','PULMONOLOGY'),
    ('162864005','E66.9','Obesity, unspecified','Body mass index 30+ - obesity (finding)','ENDOCRINOLOGY'),
    ('185086009','J44.9','Chronic obstructive pulmonary disease, unspecified','Chronic obstructive bronchitis (disorder)','PULMONOLOGY'),
    ('19169002','O03.9','Spontaneous abortion, complete or unspecified, without complication','Miscarriage in first trimester (disorder)','GYNECOLOGY & OBSTETRICS'),
    ('192127007','F90.9','Hyperkinetic disorder, unspecified','Child attention deficit disorder (disorder)','PSYCHIATRY'),
    ('195662009','J02.9','Acute pharyngitis, unspecified','Acute viral pharyngitis (disorder)','ENT'),
    ('196416002','K01.1','Impacted teeth','Impacted molars (disorder)','OTHER'),
    ('197927001','N39.0','Urinary tract infection, site not specified','Recurrent urinary tract infection (disorder)','NEPHROLOGY & ELECTROLYTES DISORDERS'),
    ('198992004','O15.0','Eclampsia in pregnancy','Eclampsia in pregnancy (disorder)','GYNECOLOGY & OBSTETRICS'),
    ('201834006','M19.0','Primary arthrosis of other joints','Localized primary osteoarthritis of the hand (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('22298006','I21.9','Acute myocardial infarction, unspecified','Myocardial infarction (disorder)','CARDIOVASCULAR'),
    ('230265002','G30.0','Alzheimer disease with early onset','Familial Alzheimer disease of early onset (disorder)','NEUROLOGY / CEREBROVASCULAR'),
    ('230690007','I63.9','Cerebral infarction, unspecified','Cerebrovascular accident (disorder)','NEUROLOGY / CEREBROVASCULAR'),
    ('232353008','J30.9','Allergic rhinitis, unspecified','Perennial allergic rhinitis with seasonal variation (disorder)','ENT'),
    ('233604007','J18.9','Pneumonia, unspecified organism','Pneumonia (disorder)','PULMONOLOGY'),
    ('233678006','J45.0','Predominantly allergic asthma','Childhood asthma (disorder)','PULMONOLOGY'),
    ('236077008','K52.9','Noninfective gastroenteritis and colitis, unspecified','Protracted diarrhea (finding)','OTHER'),
    ('237602007','E88.8','Other specified metabolic disorders','Metabolic syndrome X (disorder)','ENDOCRINOLOGY'),
    ('239720000','M23.2','Derangement of meniscus due to old tear or injury','Tear of meniscus of knee (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('239872002','M16.9','Coxarthrosis, unspecified','Osteoarthritis of hip (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('239873007','M17.9','Gonarthrosis, unspecified','Osteoarthritis of knee (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('24079001','L20.9','Atopic dermatitis, unspecified','Atopic dermatitis (disorder)','OTHER'),
    ('241929008','T78.4','Allergy, unspecified','Acute allergic reaction (disorder)','OTHER'),
    ('254632001','C34.9','Malignant neoplasm of bronchus or lung, unspecified','Small cell carcinoma of lung (disorder)','PULMONOLOGY'),
    ('254637007','C34.9','Malignant neoplasm of bronchus or lung, unspecified','Non-small cell lung cancer (disorder)','PULMONOLOGY'),
    ('254837009','C50.9','Malignant neoplasm of breast, unspecified','Malignant neoplasm of breast (disorder)','GYNECOLOGY & OBSTETRICS'),
    ('262574004','T14.8','Other injury of unspecified body region','Bullet wound (disorder)','TRAUMA'),
    ('263102004','S62.0','Fracture of navicular bone of hand','Fracture subluxation of wrist (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('26929004','G30.9','Alzheimer disease, unspecified','Alzheimer\'s disease (disorder)','NEUROLOGY / CEREBROVASCULAR'),
    ('271737000','D64.9','Anaemia, unspecified','Anemia (disorder)','OTHER'),
    ('283371005','S51.8','Open wound of other parts of forearm','Laceration of forearm (disorder)','TRAUMA'),
    ('283385000','S71.1','Open wound of thigh','Laceration of thigh (disorder)','TRAUMA'),
    ('284549007','S61.4','Open wound of hand','Laceration of hand (disorder)','TRAUMA'),
    ('284551006','S91.3','Open wound of foot','Laceration of foot (disorder)','TRAUMA'),
    ('301011002','N39.0','Urinary tract infection, site not specified','Escherichia coli urinary tract infection (disorder)','NEPHROLOGY & ELECTROLYTES DISORDERS'),
    ('302870006','E78.1','Pure hyperglyceridaemia','Hypertriglyceridemia (disorder)','CARDIOVASCULAR'),
    ('307731004','S46.0','Injury of muscle and tendon at shoulder and upper arm level','Injury of tendon of the rotator cuff of shoulder (disorder)','TRAUMA'),
    ('30832001','M76.5','Patellar tendinitis','Rupture of patellar tendon (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('33737001','S22.3','Fracture of rib','Fracture of rib (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('359817006','S72.0','Fracture of neck of femur','Closed fracture of hip (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('35999006','O02.0','Blighted ovum and nonhydatidiform mole','Blighted ovum (disorder)','GYNECOLOGY & OBSTETRICS'),
    ('363406005','C18.9','Malignant neoplasm of colon, unspecified','Malignant neoplasm of colon (disorder)','GENERAL SURGERY'),
    ('367498001','J30.1','Allergic rhinitis due to pollen','Seasonal allergic rhinitis (disorder)','ENT'),
    ('368581000119106','E11.4','Type 2 diabetes mellitus : With neurological complications','Neuropathy due to type 2 diabetes mellitus (disorder)','DIABETES COMPLICATIONS'),
    ('36923009','F32.9','Depressive episode, unspecified','Major depression, single episode (disorder)','PSYCHIATRY'),
    ('36971009','J32.9','Chronic sinusitis, unspecified','Sinusitis (disorder)','ENT'),
    ('370143000','F33.9','Recurrent depressive disorder, unspecified','Major depressive disorder (disorder)','PSYCHIATRY'),
    ('370247008','S01.8','Open wound of other parts of head','Facial laceration (disorder)','TRAUMA'),
    ('398254007','O14.9','Pre-eclampsia, unspecified','Pre-eclampsia (disorder)','GYNECOLOGY & OBSTETRICS'),
    ('39848009','S13.4','Sprain and strain of cervical spine','Whiplash injury to neck (disorder)','TRAUMA'),
    ('399211009','I25.2','Old myocardial infarction','History of myocardial infarction (situation)','CARDIOVASCULAR'),
    ('40055000','J32.9','Chronic sinusitis, unspecified','Chronic sinusitis (disorder)','ENT'),
    ('40275004','L25.9','Unspecified contact dermatitis, unspecified cause','Contact dermatitis (disorder)','OTHER'),
    ('403190006','T30.1','Burn of first degree, body region unspecified','Epidermal burn of skin (disorder)','TRAUMA'),
    ('403191005','T30.2','Burn of second degree, body region unspecified','Partial thickness burn (disorder)','GENERAL SURGERY'),
    ('408512008','E66.0','Morbid obesity due to excess calories','Body mass index 40+ - severely obese (finding)','ENDOCRINOLOGY'),
    ('410429000','I46.9','Cardiac arrest, unspecified','Cardiac arrest (disorder)','CARDIOVASCULAR'),
    ('422034002','E11.3','Type 2 diabetes mellitus : With ophthalmic complications','Diabetic retinopathy associated with type II diabetes mellitus (disorder)','DIABETES COMPLICATIONS'),
    ('424132000','C34.9','Malignant neoplasm of bronchus or lung, unspecified','Non-small cell carcinoma of lung, TNM stage 1 (disorder)','PULMONOLOGY'),
    ('428251008','Z87.3','Personal history of musculoskeletal disorders','History of appendectomy (situation)','GENERAL SURGERY'),
    ('431855005','N18.1','Chronic kidney disease, stage 1','Chronic kidney disease stage 1 (disorder)','NEPHROLOGY & ELECTROLYTES DISORDERS'),
    ('431856006','N18.2','Chronic kidney disease, stage 2','Chronic kidney disease stage 2 (disorder)','NEPHROLOGY & ELECTROLYTES DISORDERS'),
    ('43878008','J02.0','Streptococcal pharyngitis','Streptococcal sore throat (disorder)','ENT'),
    ('44054006','E11.9','Type 2 diabetes mellitus : Without complications','Type 2 diabetes mellitus','ENDOCRINOLOGY'),
    ('443165006','M80.0','Postmenopausal osteoporosis with pathological fracture','Osteoporotic fracture of bone (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('444448004','S83.4','Sprain of lateral collateral ligament of knee','Injury of medial collateral ligament of knee (disorder)','TRAUMA'),
    ('444470001','S83.5','Sprain of anterior cruciate ligament of knee','Injury of anterior cruciate ligament (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('44465007','S93.4','Sprain of ankle','Sprain of ankle (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('444814009','J06.9','Acute upper respiratory infection, unspecified','Viral sinusitis (disorder)','ENT'),
    ('446096008','J30.1','Allergic rhinitis due to pollen','Perennial allergic rhinitis (disorder)','ENT'),
    ('449868002','F17.1','Mental and behavioural disorders due to use of tobacco, harmful use','Smokes tobacco daily (finding)','PULMONOLOGY'),
    ('45816000','N10','Acute tubulo-interstitial nephritis','Pyelonephritis (disorder)','NEPHROLOGY & ELECTROLYTES DISORDERS'),
    ('47693006','K35.2','Acute appendicitis with generalised peritonitis','Rupture of appendix (disorder)','GENERAL SURGERY'),
    ('48333001','T30.0','Burn of unspecified body region, unspecified degree','Burn injury (morphologic abnormality)','TRAUMA'),
    ('49436004','I48.9','Atrial fibrillation, unspecified','Atrial fibrillation (disorder)','CARDIOVASCULAR'),
    ('53741008','I25.1','Atherosclerotic heart disease of native coronary artery','Coronary artery disease (disorder)','CARDIOVASCULAR'),
    ('55680006','T50.9','Poisoning by other and unspecified drugs, medicaments and biological substances','Drug overdose (disorder)','DRUG INTERACTIONS / ADDICTION'),
    ('55822004','E78.5','Hyperlipidaemia, unspecified','Hyperlipidemia (disorder)','CARDIOVASCULAR'),
    ('5602001','F11.1','Mental and behavioural disorders due to use of opioids : Harmful use','Harmful pattern of use of opioid (disorder)','DRUG INTERACTIONS / ADDICTION'),
    ('58150001','S42.0','Fracture of clavicle','Fracture of clavicle (disorder)','TRAUMA'),
    ('59621000','I10','Essential (primary) hypertension','Essential hypertension (disorder)','CARDIOVASCULAR'),
    ('6072007','K62.5','Haemorrhage of anus and rectum','Bleeding from anus (disorder)','GENERAL SURGERY'),
    ('62106007','S09.9','Unspecified injury of head','Concussion with no loss of consciousness (disorder)','NEUROLOGY / CEREBROVASCULAR'),
    ('62564004','S06.0','Concussion','Concussion with loss of consciousness (disorder)','NEUROLOGY / CEREBROVASCULAR'),
    ('64859006','M81.0','Postmenopausal osteoporosis','Osteoporosis (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('65363002','H66.9','Otitis media, unspecified','Otitis media (disorder)','ENT'),
    ('65966004','S52.5','Fracture of lower end of radius','Fracture of forearm (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('67811000119102','C34.9','Malignant neoplasm of bronchus or lung, unspecified','Primary small cell malignant neoplasm of lung, TNM stage 1 (disorder)','PULMONOLOGY'),
    ('68496003','K63.5','Polyp of colon','Polyp of colon (disorder)','GENERAL SURGERY'),
    ('69896004','M06.9','Rheumatoid arthritis, unspecified','Rheumatoid arthritis (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('703151001','G40.9','Epilepsy, unspecified','History of single seizure (situation)','NEUROLOGY / CEREBROVASCULAR'),
    ('70704007','S63.6','Sprain of finger','Sprain of wrist (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('713197008','K63.5','Polyp of colon','Recurrent rectal polyp (disorder)','GENERAL SURGERY'),
    ('7200002','F10.2','Mental and behavioural disorders due to use of alcohol, dependence syndrome','Alcoholism (disorder)','DRUG INTERACTIONS / ADDICTION'),
    ('72892002','Z34.9','Supervision of normal pregnancy, unspecified','Normal pregnancy (finding)','GYNECOLOGY & OBSTETRICS'),
    ('74400008','K37','Unspecified appendicitis','Appendicitis (disorder)','GENERAL SURGERY'),
    ('75498004','J01.9','Acute sinusitis, unspecified','Acute bacterial sinusitis (disorder)','ENT'),
    ('79586000','O00.1','Tubal pregnancy','Tubal pregnancy (disorder)','GYNECOLOGY & OBSTETRICS'),
    ('80394007','R73.0','Abnormal glucose tolerance test','Hyperglycemia (disorder)','ENDOCRINOLOGY'),
    ('82423001','G89.2','Chronic pain, not elsewhere classified','Chronic pain (finding)','OTHER'),
    ('83664006','E03.9','Hypothyroidism, unspecified','Idiopathic atrophic hypothyroidism (disorder)','ENDOCRINOLOGY'),
    ('84757009','G40.9','Epilepsy, unspecified','Epilepsy (disorder)','NEUROLOGY / CEREBROVASCULAR'),
    ('87433001','J43.9','Emphysema, unspecified','Pulmonary emphysema (disorder)','PULMONOLOGY'),
    ('88805009','I50.9','Heart failure, unspecified','Chronic congestive heart failure (disorder)','CARDIOVASCULAR'),
    ('90560007','M10.9','Gout, unspecified','Gout (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('90781000119102','E11.2','Type 2 diabetes mellitus : With renal complications','Microalbuminuria due to type 2 diabetes mellitus (disorder)','DIABETES COMPLICATIONS'),
    ('92691004','D07.5','Carcinoma in situ of prostate','Carcinoma in situ of prostate (disorder)','MALE REPRODUCTIVE'),
    ('93761005','C18.9','Malignant neoplasm of colon, unspecified','Primary malignant neoplasm of colon (disorder)','GENERAL SURGERY'),
    ('94260004','C78.5','Secondary malignant neoplasm of large intestine and rectum','Secondary malignant neoplasm of colon (disorder)','GENERAL SURGERY'),
    ('95417003','M79.3','Panniculitis','Primary fibromyalgia syndrome (disorder)','ORTHOPEDICS & RHEUMATOLOGY'),
    ('97331000119101','E11.3','Type 2 diabetes mellitus : With ophthalmic complications','Macular oedema and retinopathy due to type 2 diabetes mellitus (disorder)','DIABETES COMPLICATIONS'),
]

# ── P3 extensions — cardiometabolic codes absent from P2 ──────────────────────
P3_EXTENSIONS = [
    ('414545008','I25.1','Atherosclerotic heart disease','Ischaemic heart disease','CARDIOVASCULAR','P3-extension'),
    ('401303003','I21.0','Acute transmural myocardial infarction of anterior wall','Acute ST segment elevation myocardial infarction (disorder)','CARDIOVASCULAR','P3-extension'),
    ('401314000','I21.4','Acute subendocardial myocardial infarction','Acute non-ST segment elevation myocardial infarction (disorder)','CARDIOVASCULAR','P3-extension'),
    ('84114007','I50.9','Heart failure, unspecified','Heart failure (disorder)','CARDIOVASCULAR','P3-extension'),
    ('433144002','N18.3','Chronic kidney disease, stage 3','Chronic kidney disease stage 3 (disorder)','NEPHROLOGY & ELECTROLYTES DISORDERS','P3-extension'),
    ('431857002','N18.4','Chronic kidney disease, stage 4','Chronic kidney disease stage 4 (disorder)','NEPHROLOGY & ELECTROLYTES DISORDERS','P3-extension'),
    ('46177005','N18.5','Chronic kidney disease, stage 5','End-stage renal disease (disorder)','NEPHROLOGY & ELECTROLYTES DISORDERS','P3-extension'),
    ('157141000119108','E11.2','Type 2 diabetes mellitus : With renal complications','Proteinuria due to type 2 diabetes mellitus (disorder)','DIABETES COMPLICATIONS','P3-extension'),
    ('60573004','I35.0','Nonrheumatic aortic (valve) stenosis','Aortic valve stenosis (disorder)','CARDIOVASCULAR','P3-extension'),
    ('60234000','I35.1','Aortic (valve) insufficiency','Aortic valve regurgitation (disorder)','CARDIOVASCULAR','P3-extension'),
    ('48724000','I34.0','Mitral (valve) insufficiency','Mitral valve regurgitation (disorder)','CARDIOVASCULAR','P3-extension'),
    ('56786000','I37.0','Pulmonary valve stenosis','Pulmonic valve stenosis (disorder)','CARDIOVASCULAR','P3-extension'),
    ('714628002','R73.0','Abnormal glucose tolerance test','Prediabetes (finding)','ENDOCRINOLOGY','P3-extension'),
    ('274531002','R93.1','Abnormal findings on diagnostic imaging of heart and coronary circulation','Abnormal findings diagnostic imaging heart+coronary circulat (finding)','CARDIOVASCULAR','P3-extension'),
    ('399261000','Z95.1','Presence of aortocoronary bypass graft','History of coronary artery bypass grafting (situation)','CARDIOVASCULAR','P3-extension'),
    ('698306007','Z76.8','Persons encountering health services in other specified circumstances','Awaiting transplantation of kidney (situation)','NEPHROLOGY & ELECTROLYTES DISORDERS','P3-extension'),
    ('161665007','Z94.0','Kidney transplant status','History of renal transplant (situation)','NEPHROLOGY & ELECTROLYTES DISORDERS','P3-extension'),
    ('1231000119100','Z95.2','Presence of prosthetic heart valve','History of aortic valve replacement (situation)','CARDIOVASCULAR','P3-extension'),
]

# ── Insert P2 mapping ─────────────────────────────────────────────────────────
n_p2 = 0
for row in P2_MAPPING:
    try:
        cur.execute("""
            INSERT OR IGNORE INTO snomed_icd10_map
            (snomed_code, icd10_code, icd10_desc, snomed_desc_corrected, p2_category, source)
            VALUES (?,?,?,?,?,'P2-validated')
        """, row)
        n_p2 += 1
    except Exception as e:
        print(f"P2 insert error: {e} — {row[0]}")

# ── Insert P3 extensions ──────────────────────────────────────────────────────
n_p3 = 0
for row in P3_EXTENSIONS:
    try:
        cur.execute("""
            INSERT OR IGNORE INTO snomed_icd10_map
            (snomed_code, icd10_code, icd10_desc, snomed_desc_corrected, p2_category, source)
            VALUES (?,?,?,?,?,?)
        """, row)
        n_p3 += 1
    except Exception as e:
        print(f"P3 insert error: {e} — {row[0]}")

conn.commit()
total = cur.execute("SELECT COUNT(*) FROM snomed_icd10_map").fetchone()[0]
print(f"snomed_icd10_map populated:")
print(f"  P2 validated entries: {n_p2}")
print(f"  P3 extensions:        {n_p3}")
print(f"  Total:                {total}")
conn.close()
