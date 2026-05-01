Information Governance

This project uses synthetic data only (Synthea). No real patient data was processed. The following reflects considerations for NHS deployment with real clinical data.

Caldicott Principles

* Purpose is clearly defined — to support identification of cardiometabolic deterioration for clinical review
* Only necessary data is used — a limited set of clinically relevant biomarkers (SBP, HbA1c, LDL, eGFR, BMI)
* Data is minimised — observations restricted to a defined 12-month window with excluded values removed
* Outputs are restricted — system produces scoring summaries, not raw clinical data
* Data sufficiency is explicit — all outputs include DATA_SUFFICIENT / PARTIALLY_SUFFICIENT / DATA_INSUFFICIENT to indicate confidence
* Outputs are designed for shared clinical use — supporting MDT review rather than isolated decision-making
* Transparency would be required — patients should be informed how their data is used in such a system

Clinical Safety (DCB0129)

This system is designed as clinical decision support. It does not make autonomous decisions and requires clinician interpretation.

Key risks considered in the design:

* Misclassification due to insufficient data
* Distortion from single-marker dominance (e.g. BMI)
* Use of non-representative measurements (e.g. acute SBP readings)

These are mitigated through data sufficiency controls, scoring constraints, and clinically grounded thresholds.

DPIA Consideration

A Data Protection Impact Assessment would be required before deployment with real patient data.

Key risks:

* Misclassification due to incomplete or poor-quality data
* Potential misuse of outputs as automated decisions

Mitigation:

* Clear labelling of outputs as decision support
* Explicit data quality indicators alongside every score

Limitation

Validation is based on synthetic data and is underpowered. Prospective validation on real-world NHS data would be required before any clinical use.

⸻
The system was designed with governance in mind from the start — every threshold is traceable to a named NICE or KDIGO guideline, every design decision is documented in the project reference table, and data quality is surfaced as a first-class output rather than hidden.

