"""
Insert Styku scan from 2026-05-11 into body_weight_logs.
Run from the api/ directory: python insert_styku_2026_05_11.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import db

ok = db.upsert_body_weight(
    date="2026-05-11",
    weight=184.1,       # lbs
    body_fat=25.2,      # %
    waist_cm=84.8,      # taille (le plus étroit)
    arms_cm=33.0,       # biceps
    chest_cm=102.4,     # poitrine
    thighs_cm=68.6,     # cuisse
    hips_cm=103.6,      # hanche
)

if ok:
    print("✓ Scan Styku 2026-05-11 inséré avec succès")
else:
    print("✗ Échec de l'insertion — vérifier les logs Supabase")
