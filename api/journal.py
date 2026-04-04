"""
journal.py — Journal guidé avec prompts quotidiens.

Clé KV : "journal_entries" → list[dict] DESC par date

Endpoints exposés dans index.py :
  GET  /api/journal/today_prompt
  POST /api/journal/save
  GET  /api/journal/entries
  GET  /api/journal/search?q=
"""
from __future__ import annotations

from datetime import date as date_cls
import uuid

import db

# ── Prompts quotidiens (rotation par jour de l'année) ─────────────────────────

PROMPTS = [
    "Trois choses pour lesquelles t'es reconnaissant(e) aujourd'hui ?",
    "Qu'est-ce qui t'a donné de l'énergie aujourd'hui ?",
    "Qu'est-ce qui t'a drainé de l'énergie aujourd'hui ?",
    "Décris un moment où t'as été fier(fière) de toi ce mois-ci.",
    "C'est quoi une chose que tu pourrais lâcher prise aujourd'hui ?",
    "Qu'est-ce qui t'a fait sourire aujourd'hui, même un peu ?",
    "Si t'avais une chose à améliorer demain, ce serait quoi ?",
    "Décris comment tu te sens en ce moment en 3 mots.",
    "Qu'est-ce qui t'a rendu(e) fier(fière) cette semaine ?",
    "Y a-tu quelqu'un à qui tu devrais dire merci ? Pourquoi ?",
    "C'est quoi la chose la plus difficile que t'as traversée ce mois-ci ? Comment t'as géré ça ?",
    "Qu'est-ce qui t'empêche de dormir en ce moment ?",
    "Si ton futur toi te regardait aujourd'hui, qu'est-ce qu'il dirait ?",
    "Décris une habitude que tu veux développer et pourquoi.",
    "Qu'est-ce que tu ferais différemment si tu n'avais pas peur ?",
    "C'est quoi ton plus grand accomplissement des 30 derniers jours ?",
    "Qu'est-ce qui te stresse le plus en ce moment ? Peux-tu agir dessus ?",
    "Décris une chose belle que t'as remarquée aujourd'hui.",
    "À qui ou quoi tu accordes trop d'importance en ce moment ?",
    "Qu'est-ce que tu fais pour prendre soin de toi cette semaine ?",
    "Si tu devais donner un conseil à quelqu'un dans ta situation, ce serait quoi ?",
    "Décris un défi que tu relèves en ce moment et ce dont tu as besoin pour y arriver.",
    "C'est quoi une limite que tu aimerais établir dans ta vie ?",
    "Qu'est-ce qui t'a semblé difficile aujourd'hui ? Qu'est-ce que ça t'a appris ?",
    "Qu'est-ce que tu aimes le plus de toi-même en ce moment ?",
    "Décris ta journée idéale. Qu'est-ce qui en est loin en ce moment ?",
    "C'est quoi quelque chose que t'as envie d'explorer ou d'apprendre ?",
    "Comment tu veux te sentir d'ici 3 mois ? Qu'est-ce qui t'en rapproche ?",
    "Qui t'inspire en ce moment et pourquoi ?",
    "C'est quoi une pensée négative récurrente ? Est-elle vraie ?",
    "Décris un moment de la semaine où t'étais vraiment dans le moment présent.",
]


def get_today_prompt() -> str:
    day_of_year = date_cls.today().timetuple().tm_yday
    return PROMPTS[day_of_year % len(PROMPTS)]


# ── CRUD ──────────────────────────────────────────────────────────────────────

def save_entry(prompt: str, content: str) -> dict:
    if not content or not content.strip():
        raise ValueError("Le contenu ne peut pas être vide.")

    entry = {
        "id":      str(uuid.uuid4()),
        "date":    date_cls.today().isoformat(),
        "prompt":  prompt,
        "content": content.strip(),
    }
    db.insert_journal_entry(entry)
    return entry


def get_entries(limit: int = 20, offset: int = 0) -> dict:
    all_entries = db.get_journal_entries_all()
    total = len(all_entries)
    page  = all_entries[offset: offset + limit]
    return {
        "items":      page,
        "offset":     offset,
        "limit":      limit,
        "total":      total,
        "has_more":   offset + limit < total,
        "next_offset": offset + limit if offset + limit < total else None,
    }


def search_entries(query: str) -> list:
    q = query.strip()
    if not q:
        return db.get_journal_entries_all()
    return db.search_journal_entries_db(q)


def get_entry_count(days: int = 7) -> int:
    from datetime import timedelta
    cutoff = (date_cls.today() - timedelta(days=days)).isoformat()
    return db.count_journal_entries_since(cutoff)
