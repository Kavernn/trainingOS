import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Requires env vars:
#   SUPABASE_URL
#   SUPABASE_ANON_KEY
#   APP_DATA_MODE=ONLINE
# Never hardcode keys in the repo.

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
