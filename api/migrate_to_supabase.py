# api/migrate_to_supabase.py
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Met tes clés directement ici pour la migration
os.environ["SUPABASE_URL"]      = "https://ltlvnkawosvqyrsxbecp.supabase.co"
os.environ["SUPABASE_ANON_KEY"] = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx0bHZua2F3b3N2cXlyc3hiZWNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MzI4NDksImV4cCI6MjA4ODMwODg0OX0.mJo8ZJPQnDD1NYHFNgFSD_Y3uC_Q8vexRP8b0iBsfRM"
os.environ["APP_DATA_MODE"]     = "ONLINE"

from db import set_json

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")

files = {
    "weights":      "weights.json",
    "inventory":    "exercises.json",
    "program":      "program.json",
    "body_weight":  "body_weight.json",
    "user_profile": "user.json",
}

for key, filename in files.items():
    path = os.path.join(DATA_DIR, filename)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        set_json(key, data)
        print(f"✅ {key} migré depuis {filename}")
    else:
        print(f"⚠️  {filename} introuvable — ignoré")

print("\n🚀 Migration terminée !")