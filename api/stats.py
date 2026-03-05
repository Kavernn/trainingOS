# stats.py
import json
import webbrowser
import tempfile
from pathlib import Path
from collections import defaultdict
from datetime import datetime

BASE_DIR  = Path(__file__).parent
DATA_FILE = BASE_DIR / "data" / "weights.json"
HIIT_FILE = BASE_DIR / "data" / "hiit_log.json"


def load_weights() -> dict:
    if not DATA_FILE.exists():
        return {}
    with open(DATA_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def load_hiit_log() -> list:
    if not HIIT_FILE.exists():
        return []
    with open(HIIT_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


# ─────────────────────────────────────────────────────────────
# CALCULS MUSCU
# ─────────────────────────────────────────────────────────────

def compute_volume_par_seance(weights: dict) -> list[dict]:
    volume_par_date = defaultdict(float)
    for ex, data in weights.items():
        if ex == "sessions":
            continue
        for entry in data.get("history", []):
            date     = entry.get("date", "")
            w        = entry.get("weight", 0)
            reps_str = entry.get("reps", "")
            try:
                reps_list = [int(r) for r in reps_str.split(",") if r.strip()]
                volume    = w * sum(reps_list)
                volume_par_date[date] += volume
            except:
                continue
    return [{"date": d, "volume": round(v, 1)}
            for d, v in sorted(volume_par_date.items())]


def compute_frequence_hebdo(weights: dict, hiit_log: list) -> dict:
    from datetime import datetime
    sessions_par_semaine = defaultdict(int)

    # 1. On compte les séances de muscu (depuis l'historique de chaque exo)
    dates_vues = set()
    for ex, data in weights.items():
        if isinstance(data, dict):
            for entry in data.get("history", []):
                dates_vues.add(entry.get("date"))

    # 2. On ajoute les séances de HIIT
    for entry in hiit_log:
        dates_vues.add(entry.get("date"))

    # 3. On groupe par numéro de semaine
    for date_str in dates_vues:
        if not date_str: continue
        try:
            dt = datetime.strptime(date_str, "%Y-%m-%d")
            # Format: "Semaine 12"
            num_semaine = dt.isocalendar()[1]
            sessions_par_semaine[f"Sem {num_semaine}"] += 1
        except:
            continue

    return dict(sorted(sessions_par_semaine.items()))


from datetime import datetime
from collections import defaultdict


def get_frequence_hebdo_data(weights, hiit_log):
    jours_entrainement = set()

    # 1. On récupère les dates des séances de muscu
    for ex_name, data in weights.items():
        if isinstance(data, dict) and "history" in data:
            for entry in data["history"]:
                if "date" in entry:
                    jours_entrainement.add(entry["date"])

    # 2. On récupère les dates des séances de HIIT
    for entry in hiit_log:
        if isinstance(entry, dict) and "date" in entry:
            jours_entrainement.add(entry["date"])

    # 3. On groupe par semaine
    frequence_par_semaine = defaultdict(int)
    # On trie les dates pour avoir un graphique chronologique
    for date_str in sorted(jours_entrainement):
        try:
            dt = datetime.strptime(date_str, "%Y-%m-%d")
            # Création du label "Sem XX" (numéro de semaine)
            semaine_label = f"Sem {dt.isocalendar()[1]}"
            frequence_par_semaine[semaine_label] += 1
        except:
            continue

    # On prépare les données pour Chart.js
    labels = list(frequence_par_semaine.keys())
    values = list(frequence_par_semaine.values())

    # On retourne les 6 dernières semaines pour le dashboard
    return labels[-6:], values[-6:]
def compute_frequence_par_semaine(weights: dict) -> list[dict]:
    seances_par_semaine = defaultdict(set)
    for ex, data in weights.items():
        if ex == "sessions":
            continue
        for entry in data.get("history", []):
            date_str = entry.get("date", "")
            try:
                d       = datetime.strptime(date_str, "%Y-%m-%d")
                semaine = d.strftime("%Y-S%W")
                seances_par_semaine[semaine].add(date_str)
            except:
                continue
    return [{"semaine": s, "seances": len(days)}
            for s, days in sorted(seances_par_semaine.items())]


def compute_volume_par_semaine(volume_par_seance: list[dict]) -> list[dict]:
    volume_semaine = defaultdict(float)
    for entry in volume_par_seance:
        try:
            d       = datetime.strptime(entry["date"], "%Y-%m-%d")
            semaine = d.strftime("%Y-S%W")
            volume_semaine[semaine] += entry["volume"]
        except:
            continue
    return [{"semaine": s, "volume": round(v, 1)}
            for s, v in sorted(volume_semaine.items())]


def compute_rpe_par_seance() -> list[dict]:
    from sessions import load_sessions
    sessions = load_sessions()
    result   = []
    for date_key in sorted(sessions.keys()):
        s = sessions[date_key]
        if s.get("rpe"):
            result.append({"date": date_key, "rpe": s["rpe"]})
    return result


# ─────────────────────────────────────────────────────────────
# CALCULS HIIT
# ─────────────────────────────────────────────────────────────

def compute_hiit_rpe(hiit_log: list) -> list[dict]:
    return [
        {"date": e["date"], "rpe": e["rpe"]}
        for e in hiit_log if e.get("rpe")
    ]


def compute_hiit_rounds(hiit_log: list) -> list[dict]:
    return [
        {
            "date":      e["date"],
            "completes": e["rounds_complétés"],
            "planifies": e["rounds_planifiés"]
        }
        for e in hiit_log
    ]


# ─────────────────────────────────────────────────────────────
# CALCULS POIDS CORPOREL
# ─────────────────────────────────────────────────────────────

def compute_courbe_poids() -> list[dict]:
    from body_weight import load_body_weight
    entries = load_body_weight()
    return [{"date": e["date"], "poids": e["poids"]}
            for e in sorted(entries, key=lambda x: x["date"])]


# ─────────────────────────────────────────────────────────────
# GÉNÉRATION DU DASHBOARD
# ─────────────────────────────────────────────────────────────

def generate_dashboard():
    weights  = load_weights()
    hiit_log = load_hiit_log()

    if not weights and not hiit_log:
        print("\nPas encore assez de données pour générer des stats.")
        print("Logge quelques séances d'abord ! 💪")
        return

    # Muscu
    volume_seance  = compute_volume_par_seance(weights)
    frequence      = compute_frequence_par_semaine(weights)
    volume_semaine = compute_volume_par_semaine(volume_seance)
    rpe_seances    = compute_rpe_par_seance()

    # HIIT
    hiit_log_sorted = sorted(hiit_log, key=lambda x: x["date"])
    hiit_rpe        = compute_hiit_rpe(hiit_log_sorted)
    hiit_rounds     = compute_hiit_rounds(hiit_log_sorted)

    # Poids corporel
    courbe_poids = compute_courbe_poids()
    poids_dates  = [e["date"]  for e in courbe_poids]
    poids_vals   = [e["poids"] for e in courbe_poids]
    min_poids    = min(poids_vals) - 2 if poids_vals else 60
    max_poids    = max(poids_vals) + 2 if poids_vals else 100

    # Listes JS
    vol_dates      = [e["date"]      for e in volume_seance]
    vol_vals       = [e["volume"]    for e in volume_seance]
    freq_labels    = [e["semaine"]   for e in frequence]
    freq_vals      = [e["seances"]   for e in frequence]
    vsem_labels    = [e["semaine"]   for e in volume_semaine]
    vsem_vals      = [e["volume"]    for e in volume_semaine]
    rpe_dates      = [e["date"]      for e in rpe_seances]
    rpe_vals       = [e["rpe"]       for e in rpe_seances]
    hiit_dates     = [e["date"]      for e in hiit_rpe]
    hiit_rpe_vals  = [e["rpe"]       for e in hiit_rpe]
    hiit_rdates    = [e["date"]      for e in hiit_rounds]
    hiit_completed = [e["completes"] for e in hiit_rounds]
    hiit_planned   = [e["planifies"] for e in hiit_rounds]

    html = f"""<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>TrainingOS – Dashboard</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    body {{
      font-family: 'Segoe UI', sans-serif;
      background: #0f0f13;
      color: #e0e0e0;
      padding: 30px;
    }}
    h1 {{
      text-align: center;
      font-size: 2rem;
      color: #f97316;
      margin-bottom: 6px;
      letter-spacing: 2px;
    }}
    .subtitle {{
      text-align: center;
      color: #666;
      margin-bottom: 40px;
      font-size: 0.9rem;
    }}
    .section-title {{
      grid-column: span 2;
      color: #888;
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 2px;
      padding: 10px 0 4px 4px;
      border-bottom: 1px solid #2a2a3a;
      margin-bottom: 4px;
    }}
    .grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 24px;
      max-width: 1200px;
      margin: 0 auto;
    }}
    .card {{
      background: #1a1a24;
      border: 1px solid #2a2a3a;
      border-radius: 12px;
      padding: 24px;
    }}
    .card.wide {{
      grid-column: span 2;
    }}
    .card h2 {{
      font-size: 1rem;
      color: #f97316;
      margin-bottom: 20px;
      text-transform: uppercase;
      letter-spacing: 1px;
    }}
    canvas {{ width: 100% !important; }}
  </style>
</head>
<body>
  <h1>💪 TRAININGOS</h1>
  <p class="subtitle">Dashboard de performance – généré le {datetime.now().strftime("%Y-%m-%d %H:%M")}</p>

  <div class="grid">

    <!-- MUSCU -->
    <div class="section-title">🏋️ Entraînement musculaire</div>

    <div class="card wide">
      <h2>📊 Volume total par séance (lbs × reps)</h2>
      <canvas id="volumeSeance"></canvas>
    </div>

    <div class="card">
      <h2>📅 Fréquence par semaine (nb séances)</h2>
      <canvas id="frequence"></canvas>
    </div>

    <div class="card">
      <h2>📈 Volume total par semaine</h2>
      <canvas id="volumeSemaine"></canvas>
    </div>

    <div class="card wide">
      <h2>🎯 RPE des séances muscu dans le temps</h2>
      <canvas id="rpeSeances"></canvas>
    </div>

    <!-- HIIT -->
    <div class="section-title">🏃 HIIT</div>

    <div class="card">
      <h2>🏃 HIIT – RPE dans le temps</h2>
      <canvas id="hiitRpe"></canvas>
    </div>

    <div class="card">
      <h2>🔄 HIIT – Rounds complétés vs planifiés</h2>
      <canvas id="hiitRounds"></canvas>
    </div>

    <!-- POIDS CORPOREL -->
    <div class="section-title">⚖️ Poids corporel</div>

    <div class="card wide">
      <h2>⚖️ Poids corporel dans le temps (kg)</h2>
      <canvas id="poidsCorps"></canvas>
    </div>

  </div>

  <script>
    const orange = '#f97316';
    const blue   = '#3b82f6';
    const green  = '#22c55e';
    const purple = '#a855f7';
    const rose   = '#f43f5e';

    const defaults = {{
      responsive: true,
      plugins: {{ legend: {{ display: false }} }},
      scales: {{
        x: {{ ticks: {{ color: '#888' }}, grid: {{ color: '#222' }} }},
        y: {{ ticks: {{ color: '#888' }}, grid: {{ color: '#222' }} }}
      }}
    }};

    const rpeScale = {{
      responsive: true,
      plugins: {{ legend: {{ display: false }} }},
      scales: {{
        x: {{ ticks: {{ color: '#888' }}, grid: {{ color: '#222' }} }},
        y: {{ min: 1, max: 10, ticks: {{ color: '#888', stepSize: 1 }}, grid: {{ color: '#222' }} }}
      }}
    }};

    // ── Volume par séance ──────────────────────────────────
    new Chart(document.getElementById('volumeSeance'), {{
      type: 'bar',
      data: {{
        labels: {vol_dates},
        datasets: [{{
          data: {vol_vals},
          backgroundColor: orange + '99',
          borderColor: orange,
          borderWidth: 1,
          borderRadius: 4
        }}]
      }},
      options: {{ ...defaults }}
    }});

    // ── Fréquence par semaine ──────────────────────────────
    new Chart(document.getElementById('frequence'), {{
      type: 'bar',
      data: {{
        labels: {freq_labels},
        datasets: [{{
          data: {freq_vals},
          backgroundColor: blue + '99',
          borderColor: blue,
          borderWidth: 1,
          borderRadius: 4
        }}]
      }},
      options: {{ ...defaults }}
    }});

    // ── Volume par semaine ─────────────────────────────────
    new Chart(document.getElementById('volumeSemaine'), {{
      type: 'line',
      data: {{
        labels: {vsem_labels},
        datasets: [{{
          data: {vsem_vals},
          borderColor: green,
          backgroundColor: green + '22',
          borderWidth: 2,
          pointBackgroundColor: green,
          pointRadius: 5,
          fill: true,
          tension: 0.3
        }}]
      }},
      options: {{ ...defaults }}
    }});

    // ── RPE séances muscu ──────────────────────────────────
    new Chart(document.getElementById('rpeSeances'), {{
      type: 'line',
      data: {{
        labels: {rpe_dates},
        datasets: [{{
          data: {rpe_vals},
          borderColor: purple,
          backgroundColor: purple + '22',
          borderWidth: 2,
          pointBackgroundColor: purple,
          pointRadius: 5,
          fill: true,
          tension: 0.3
        }}]
      }},
      options: {{ ...rpeScale }}
    }});

    // ── HIIT RPE ───────────────────────────────────────────
    new Chart(document.getElementById('hiitRpe'), {{
      type: 'line',
      data: {{
        labels: {hiit_dates},
        datasets: [{{
          data: {hiit_rpe_vals},
          borderColor: orange,
          backgroundColor: orange + '22',
          borderWidth: 2,
          pointBackgroundColor: orange,
          pointRadius: 5,
          fill: true,
          tension: 0.3
        }}]
      }},
      options: {{ ...rpeScale }}
    }});

    // ── HIIT Rounds ────────────────────────────────────────
    new Chart(document.getElementById('hiitRounds'), {{
      type: 'bar',
      data: {{
        labels: {hiit_rdates},
        datasets: [
          {{
            label: 'Planifiés',
            data: {hiit_planned},
            backgroundColor: blue + '44',
            borderColor: blue,
            borderWidth: 1,
            borderRadius: 4
          }},
          {{
            label: 'Complétés',
            data: {hiit_completed},
            backgroundColor: green + '99',
            borderColor: green,
            borderWidth: 1,
            borderRadius: 4
          }}
        ]
      }},
      options: {{
        ...defaults,
        plugins: {{ legend: {{ display: true, labels: {{ color: '#888' }} }} }}
      }}
    }});

    // ── Poids corporel ─────────────────────────────────────
    new Chart(document.getElementById('poidsCorps'), {{
      type: 'line',
      data: {{
        labels: {poids_dates},
        datasets: [{{
          data: {poids_vals},
          borderColor: rose,
          backgroundColor: rose + '22',
          borderWidth: 2,
          pointBackgroundColor: rose,
          pointRadius: 4,
          fill: true,
          tension: 0.3
        }}]
      }},
      options: {{
        responsive: true,
        plugins: {{ legend: {{ display: false }} }},
        scales: {{
          x: {{ ticks: {{ color: '#888' }}, grid: {{ color: '#222' }} }},
          y: {{
            ticks: {{ color: '#888' }},
            grid:  {{ color: '#222' }},
            suggestedMin: {min_poids},
            suggestedMax: {max_poids}
          }}
        }}
      }}
    }});

  </script>
</body>
</html>"""

    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".html", delete=False,
        encoding="utf-8", prefix="trainingOS_stats_"
    )
    tmp.write(html)
    tmp.close()

    webbrowser.open(f"file://{tmp.name}")
    print(f"\n✅ Dashboard ouvert dans ton navigateur !")
    print(f"   Fichier : {tmp.name}")