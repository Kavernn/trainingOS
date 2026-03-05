# index.py

import sys
from datetime import date, datetime
import os
import json

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE_DIR)

from planner import get_today, get_week_schedule, get_suggested_weights_for_today, load_program, save_program
from hiit import get_hiit_str
from log_workout import load_weights, save_weights, log_single_exercise, show_exercise_history
from inventory import load_inventory, add_exercise
from user_profile import load_user_profile
from stats import generate_dashboard
from sessions import load_sessions, save_sessions, log_session, get_last_sessions, migrate_sessions_from_weights
from deload import afficher_rapport_deload, analyser_deload, load_deload_state
from body_weight import log_body_weight, afficher_historique_poids, load_body_weight, get_tendance
from goals import gerer_objectifs, afficher_objectifs, check_goals_achieved


from flask import Flask, render_template


app = Flask(__name__,
            template_folder='../templates',   # monte d'un niveau pour trouver templates/
            static_folder='../static')

@app.route('/')
def home():
    return render_template('index.html')

START_DATE = date(2026, 3, 3)  # ← Change cette date si tu recommences un cycle

def get_current_week() -> int:
    """Retourne la semaine réelle du programme basée sur START_DATE."""
    delta = date.today() - START_DATE
    return max(1, (delta.days // 7) + 1)


class TrainingOSApp:

    def __init__(self):
        self.weights = load_weights()
        self.inventory = load_inventory()
        self.program = load_program()

        # Migration one-shot : déplace sessions de weights.json → sessions.json
        if "sessions" in self.weights:
            n = migrate_sessions_from_weights(self.weights)
            if n > 0:
                print(f"✅ {n} sessions migrées vers sessions.json")
            del self.weights["sessions"]
            save_weights(self.weights)

            achieved = check_goals_achieved(self.weights)
            for ex in achieved:
                print(f"\n  🏆 OBJECTIF ATTEINT : {ex} ! Félicitations ! 🎉")

            # Alerte deload au démarrage
            self._check_deload_alerte()

        def _check_deload_alerte(self):
            """Affiche une alerte discrète si deload recommandé."""
            from deload import analyser_deload, load_deload_state
            state = load_deload_state()
            rapport = analyser_deload(self.weights)

            if state["active"]:
                print(f"\n  🔄 RAPPEL : Semaine de deload en cours (depuis {state['since']})")
            elif rapport["recommande"]:
                print(f"\n  ⚠️  Deload recommandé – consulte l'option 15 pour les détails")

    def clear_screen(self):
        print("\033[H\033[J", end="")

    def afficher_menu_principal(self):
        self.clear_screen()
        week = get_current_week()
        print("\n" + "═" * 60)
        print("      LET'S GO !!")
        print("═" * 60)
        print(f"Aujourd'hui : {datetime.now().strftime('%Y-%m-%d')} → {get_today()}  |  Semaine {week}")
        print("═" * 60 + "\n")

    def run(self):
        from menu_select import menu_principal

        MENU = [
            "1.  Log ma séance d'aujourd'hui",
            "2.  Voir les poids recommandés",
            "3.  Planning de la semaine",
            "4.  HIIT de la semaine",
            "5.  Historique d'un exercice",
            "6.  Voir notes / RPE des séances",
            "7.  Gérer l'inventaire des exercices",
            "8.  Modifier le programme hebdomadaire",
            "9.  Configurer / modifier mon profil",
            "10. Voir mon récap intelligent",
            "11. Voir catalogue des exercices",
            "12. 📊 Dashboard stats (navigateur)",
            "13. 🏃 Historique HIIT",
            "14. 📋 Voir mes programmes",
            "15. 🔄 Analyse deload",
            "16. ⚖️  Suivi poids corporel",
            "17. 🎯 Mes objectifs personnels",
            "──────────────────────────────",
            "0.  Quitter"
        ]

        while True:
            self.afficher_menu_principal()
            choix = menu_principal("Que veux-tu faire ?", MENU)

            if not choix or choix.startswith("0.") or choix.startswith("──"):
                if choix and choix.startswith("0."):
                    print("\nGarde la promesse que tu t'es fait à toi même, lock n loaded !\n")
                    sys.exit(0)
                continue

            if choix.startswith("1."):
                self.log_seance_aujourdhui()
            elif choix.startswith("2."):
                self.voir_poids_recommandes()
            elif choix.startswith("3."):
                self.afficher_planning_semaine()
            elif choix.startswith("4."):
                self.voir_hiit_semaine()
            elif choix.startswith("5."):
                self.voir_historique_exercice()
            elif choix.startswith("6."):
                self.voir_notes_seances()
            elif choix.startswith("7."):
                self.gerer_inventaire()
            elif choix.startswith("8."):
                self.modifier_programme()
            elif choix.startswith("9."):
                self.setup_or_edit_profile()
            elif choix.startswith("10."):
                self.show_recap_intelligent()
            elif choix.startswith("11."):
                self.voir_catalogue_exercices()
            elif choix.startswith("12."):
                self.voir_dashboard_stats()
            elif choix.startswith("13."):
                self.voir_historique_hiit()
            elif choix.startswith("14."):
                self.voir_programme_complet()
            elif choix.startswith("15."):
                self.voir_analyse_deload()
            elif choix.startswith("16."):
                self.voir_suivi_poids()
            elif choix.startswith("17."):
                self.voir_objectifs()

            input("\nAppuie sur Entrée pour revenir au menu...")


    # ────────────────────────────────────────────────
    def voir_objectifs(self):
        gerer_objectifs(self.weights)

    def log_seance_aujourdhui(self):
        from menu_select import selectionner
        from sessions import log_session

        today_session = get_today()
        today_date = datetime.now().strftime('%Y-%m-%d')

        print(f"\n{'═' * 70}")
        print(f"  SÉANCE DU {today_date} → {today_session}")
        print(f"{'═' * 70}\n")

        suggestions = get_suggested_weights_for_today(self.weights)
        if suggestions:
            print("POIDS RECOMMANDÉS POUR AUJOURD'HUI :")
            for item in suggestions:
                print(f"  {item['exercise']:<25} {item['display']}")
            print()
        state = load_deload_state()
        if state["active"]:
            print(f"  🔄 DELOAD EN COURS – utilise les poids à -15% aujourd'hui !")
            print(f"     Depuis le {state['since']} – raison : {state['reason']}\n")
        # ── HIIT ─────────────────────────────────────────────
        if "HIIT" in today_session or today_session in ["Yoga", "Recovery"]:
            if "HIIT" in today_session:
                week = get_current_week()
                print(f"🏃 HIIT DU JOUR  (Semaine {week})\n   " + get_hiit_str(week))
                reponse = selectionner(
                    "As-tu fait ton HIIT ?",
                    ["Oui 🏃", "Non"]
                )
                if reponse == "Oui 🏃":
                    from log_workout import log_hiit_session
                    log_hiit_session(week)
            else:
                emoji = "🧘" if today_session == "Yoga" else "😴"
                print(f"{emoji} Jour de {today_session.lower()} – récupération")
            input("\nAppuie Entrée pour continuer...")
            return

        # ── SÉANCE MUSCU ──────────────────────────────────────
        if today_session not in self.program:
            print("Aucun programme défini pour ce jour.")
            return

        exercises = list(self.program[today_session].keys())
        print(f"Exercices prévus ({len(exercises)}) :")
        for i, ex in enumerate(exercises, 1):
            print(f"  {i:2}. {ex}  {self.program[today_session][ex]}")
        print()

        reponse = selectionner(
            "As-tu fait ta séance aujourd'hui ?",
            ["Oui 💪", "Non, à demain"]
        )
        if reponse != "Oui 💪":
            print("OK, à demain ! 💪")
            return

        print("\nC'est parti...\n")

        faits = 0
        for exercise in exercises:
            self.weights = log_single_exercise(exercise, self.weights)
            if exercise in self.weights and self.weights[exercise].get("last_logged", "").startswith(today_date):
                faits += 1

        if faits > 0:
            save_weights(self.weights)

            from goals import check_goals_achieved
            achieved = check_goals_achieved(self.weights)
            for ex in achieved:
                print(f"\n  🏆 OBJECTIF ATTEINT : {ex} ! Félicitations Vincent ! 🎉")

            print(f"\n{faits} exos enregistrés – super boulot ! 🔥")

        # ── RPE + COMMENTAIRE ─────────────────────────────────
        print("\n" + "─" * 50)
        rpe_str = input("RPE global (1-10, Entrée=skip) → ").strip()
        rpe = int(rpe_str) if rpe_str.isdigit() and 1 <= int(rpe_str) <= 10 else None
        comment = input("Commentaire / ressenti (Entrée=rien) → ").strip()

        log_session(today_date, rpe, comment, exercises)
        print("Note séance sauvegardée ✓")

        # ── MESSAGE MOTIVATIONNEL ─────────────────────────────
        profile = load_user_profile()
        goal = profile.get("goal", "force")

        print("\n" + "─" * 50)
        if goal == "force":
            print("   Objectif force activé : continue à pousser les charges !")
            if faits > 0:
                print("   +5 lbs ou + reps sur un gros lift ? T'es sur la voie royale 💪")
        elif goal == "hypertrophie":
            print("   Objectif hypertrophie : bon volume – garde la tension musculaire !")
            print("   Pense à bien manger après, c'est là que ça se construit 🔥")
        elif goal == "perte de poids":
            print("   Objectif perte de poids : séance solide – continue le déficit calorique malin")
            print("   Hydrate-toi bien et protège tes articulations !")
        elif goal == "recomposition":
            print("   Objectif recomposition : équilibre parfait entre force et esthétique")
            print("   T'as bien géré – prot et glucides post-entraînement !")
        else:
            print("   Objectif non défini – mets-le dans ton profil (option 9) !")

        if today_session in ["Upper A", "Upper B"]:
            print("   Jour Upper : tes pecs, dos et épaules te remercient déjà !")
        elif today_session == "Lower":
            print("   Jour Lower : jambes et fessiers en feu – t'as tout donné !")
        print("─" * 50)

    def voir_suivi_poids(self):
        from menu_select import selectionner

        while True:
            action = selectionner(
                "Suivi poids corporel :",
                [
                    "⚖️  Logger mon poids aujourd'hui",
                    "📋 Voir l'historique",
                ]
            )

            if not action or action == "↩ Annuler":
                break

            if action.startswith("⚖️"):
                poids_str = input("Ton poids aujourd'hui (kg) → ").strip()
                if not poids_str:
                    continue
                try:
                    poids = float(poids_str.replace(",", "."))
                except ValueError:
                    print("❌ Valeur invalide.")
                    continue
                note = input("Note (Entrée=rien) → ").strip()
                log_body_weight(poids, note)

            elif action.startswith("📋"):
                afficher_historique_poids()
                input("\nAppuie sur Entrée pour continuer...")

    def voir_poids_recommandes(self):
        suggestions = get_suggested_weights_for_today(self.weights)
        if not suggestions:
            print("\nAucune suggestion aujourd'hui.\n")
            return
        print("\nPOIDS RECOMMANDÉS :")
        print("-" * 70)
        for item in suggestions:
            print(f"  {item['exercise']:<25} → {item['display']}")
        print("-" * 70)

    def afficher_planning_semaine(self):
        schedule = get_week_schedule()
        today = get_today()
        week = get_current_week()
        print(f"\nPLANNING SEMAINE {week}")
        print("-" * 40)
        for d, s in schedule.items():
            marker = " ◀ AUJOURD'HUI" if s == today else ""
            print(f"  {d} → {s}{marker}")
        print("-" * 40)

    def voir_hiit_semaine(self):
        week = get_current_week()
        print(f"\nHIIT SEMAINE {week} : {get_hiit_str(week)}")

    def voir_historique_exercice(self):
        from menu_select import selectionner
        exercices = [k for k in self.weights if k != "sessions"]
        if not exercices:
            print("Aucun exercice loggué pour l'instant.")
            return
        exo = selectionner("Quel exercice voir ?", exercices)
        if exo and exo != "↩ Annuler":
            show_exercise_history(exo, self.weights)

    def voir_notes_seances(self):
        sessions = get_last_sessions(10)

        if not sessions:
            print("\nAucune note enregistrée pour l'instant.")
            print("Logge une séance et entre ton RPE à la fin ! 💪")
            return

        print("\n" + "═" * 65)
        print("   NOTES & RPE DES DERNIÈRES SÉANCES")
        print("═" * 65)
        print(f"{'Date':<12} {'RPE':<6} {'Exercices':<30} Commentaire")
        print("─" * 65)

        for s in sessions:
            rpe_txt = f"  {s['rpe']}/10" if s.get("rpe") else "  —"
            exos_txt = ", ".join(s.get("exos", [])) or "—"
            if len(exos_txt) > 28:
                exos_txt = exos_txt[:25] + "..."
            comment = s.get("comment", "—") or "—"
            print(f"{s['date']:<12} {rpe_txt:<6} {exos_txt:<30} {comment}")

        print("─" * 65)

        # Moyenne RPE
        rpes = [s["rpe"] for s in sessions if s.get("rpe")]
        if rpes:
            print(f"\n  RPE moyen (dernières {len(rpes)} séances) : {sum(rpes) / len(rpes):.1f}/10")
        print("═" * 65)
    def gerer_inventaire(self):
        from menu_select import selectionner, selectionner_exercice_inventaire

        while True:
            print("\n" + "═" * 55)
            print("   GESTION INVENTAIRE DES EXERCICES")
            print("═" * 55)

            action = selectionner("Que veux-tu faire ?", [
                "➕  Créer un nouvel exercice",
                "✏️   Modifier un exercice existant",
                "🗑️   Supprimer un exercice",
                "📋  Voir le catalogue complet"
            ])

            if not action or action == "↩ Annuler":
                break

            inv = load_inventory()

            # ── CRÉER ────────────────────────────────────────
            if action.startswith("➕"):
                print("\n── NOUVEL EXERCICE ──────────────────────────────")

                nom = input("Nom de l'exercice → ").strip()
                if not nom:
                    print("Nom vide, annulé.")
                    continue

                if nom in inv:
                    confirmer = selectionner(
                        f"'{nom}' existe déjà. Écraser ?",
                        ["Oui, écraser", "Non, annuler"]
                    )
                    if confirmer != "Oui, écraser":
                        continue

                ex_type = selectionner("Type d'équipement :", [
                    "barbell", "dumbbell", "machine", "bodyweight", "cable"
                ])
                if not ex_type or ex_type == "↩ Annuler":
                    continue

                inc_str = input(f"Incrément par défaut (lbs) [5] → ").strip()
                inc = float(inc_str.replace(",", ".")) if inc_str else 5.0

                scheme = input("Scheme par défaut (ex: 4x5-7) [3x8-12] → ").strip() or "3x8-12"

                muscles_input = input("Muscles ciblés (séparés par virgule) → ").strip()
                muscles = [m.strip() for m in muscles_input.split(",") if m.strip()] if muscles_input else []

                bar_w = 45.0
                if ex_type == "barbell":
                    bar_str = input("Poids de la barre (lbs) [45] → ").strip()
                    bar_w = float(bar_str) if bar_str.replace(".", "", 1).isdigit() else 45.0

                # Résumé avant confirmation
                print(f"\n── Résumé ───────────────────────────────────────")
                print(f"  Nom       : {nom}")
                print(f"  Type      : {ex_type}")
                print(f"  Incrément : +{inc} lbs")
                print(f"  Scheme    : {scheme}")
                print(f"  Muscles   : {', '.join(muscles) or '—'}")
                if ex_type == "barbell":
                    print(f"  Barre     : {bar_w} lbs")
                print(f"─────────────────────────────────────────────────")

                confirmer = selectionner("Confirmer la création ?", ["Oui ✅", "Non, annuler"])
                if confirmer != "Oui ✅":
                    print("Annulé.")
                    continue

                add_exercise(nom, ex_type, inc, bar_w, scheme, muscles)
                self.inventory = load_inventory()

            # ── MODIFIER ─────────────────────────────────────
            elif action.startswith("✏️"):
                exo = selectionner_exercice_inventaire(
                    "Quel exercice modifier ?", inv
                )
                if not exo or exo == "↩ Annuler":
                    continue

                info = inv[exo]
                print(f"\n── Modification de '{exo}' ───────────────────────")
                print("  Laisse vide + Entrée pour garder la valeur actuelle\n")

                # Nom
                nouveau_nom = input(f"Nom [{exo}] → ").strip() or exo

                # Type
                nouveau_type = selectionner(
                    f"Type [{info['type']}] :",
                    ["barbell", "dumbbell", "machine", "bodyweight", "cable", f"↩ Garder ({info['type']})"]
                )
                if nouveau_type and nouveau_type.startswith("↩ Garder"):
                    nouveau_type = info["type"]

                # Incrément
                inc_str = input(f"Incrément [{info['increment']} lbs] → ").strip()
                nouvel_inc = float(inc_str.replace(",", ".")) if inc_str else info["increment"]

                # Scheme
                nouveau_scheme = input(f"Scheme [{info.get('default_scheme', '3x8-12')}] → ").strip() or info.get(
                    "default_scheme", "3x8-12")

                # Muscles
                muscles_actuels = ", ".join(info.get("muscles", []))
                muscles_input = input(f"Muscles [{muscles_actuels or '—'}] → ").strip()
                nouveaux_muscles = [m.strip() for m in muscles_input.split(",") if
                                    m.strip()] if muscles_input else info.get("muscles", [])

                # Barre si barbell
                nouvelle_barre = info.get("bar_weight", 45.0)
                if nouveau_type == "barbell":
                    bar_str = input(f"Poids barre [{info.get('bar_weight', 45.0)} lbs] → ").strip()
                    nouvelle_barre = float(bar_str) if bar_str.replace(".", "", 1).isdigit() else info.get("bar_weight",
                                                                                                           45.0)

                # Résumé
                print(f"\n── Résumé des modifications ─────────────────────")
                print(f"  Nom       : {exo} → {nouveau_nom}")
                print(f"  Type      : {info['type']} → {nouveau_type}")
                print(f"  Incrément : {info['increment']} → {nouvel_inc} lbs")
                print(f"  Scheme    : {info.get('default_scheme', '—')} → {nouveau_scheme}")
                print(f"  Muscles   : {muscles_actuels or '—'} → {', '.join(nouveaux_muscles) or '—'}")
                if nouveau_type == "barbell":
                    print(f"  Barre     : {info.get('bar_weight', 45.0)} → {nouvelle_barre} lbs")
                print(f"─────────────────────────────────────────────────")

                confirmer = selectionner("Confirmer les modifications ?", ["Oui ✅", "Non, annuler"])
                if confirmer != "Oui ✅":
                    print("Annulé.")
                    continue

                # Si le nom a changé, supprime l'ancien
                if nouveau_nom != exo:
                    del inv[exo]

                inv[nouveau_nom] = {
                    "type": nouveau_type,
                    "increment": nouvel_inc,
                    "bar_weight": nouvelle_barre if nouveau_type == "barbell" else 0.0,
                    "default_scheme": nouveau_scheme,
                    "muscles": nouveaux_muscles
                }

                from inventory import save_inventory
                save_inventory(inv)
                self.inventory = load_inventory()
                print(f"✅ '{nouveau_nom}' mis à jour !")

            # ── SUPPRIMER ─────────────────────────────────────
            elif action.startswith("🗑️"):
                exo = selectionner_exercice_inventaire(
                    "Quel exercice supprimer ?", inv
                )
                if not exo or exo == "↩ Annuler":
                    continue

                confirmer = selectionner(
                    f"⚠️  Supprimer définitivement '{exo}' ?",
                    ["Oui, supprimer", "Non, annuler"]
                )
                if confirmer == "Oui, supprimer":
                    del inv[exo]
                    from inventory import save_inventory
                    save_inventory(inv)
                    self.inventory = load_inventory()
                    print(f"✅ '{exo}' supprimé de l'inventaire.")
                else:
                    print("Annulé.")

            # ── VOIR CATALOGUE ────────────────────────────────
            elif action.startswith("📋"):
                self.voir_catalogue_exercices()
                input("\nAppuie sur Entrée pour revenir...")

    def modifier_programme(self):
        from menu_select import selectionner, selectionner_exercice_inventaire, selectionner_exercice_programme

        while True:
            print("\n" + "═" * 50)
            print("   MODIFIER LE PROGRAMME HEBDOMADAIRE")
            print("═" * 50)

            # Sélection du jour avec flèches
            jour = selectionner(
                "Quel jour modifier ?",
                list(self.program.keys())
            )

            if not jour or jour == "↩ Annuler":
                print("Retour au menu principal...")
                break

            # Affiche les exercices du jour sélectionné
            print(f"\nExercices actuels pour {jour} :")
            print("─" * 45)
            for ex, sch in self.program[jour].items():
                print(f"  • {ex:<25} {sch}")
            print("─" * 45)

            action = selectionner(
                "Que veux-tu faire ?",
                [
                    "Ajouter un exercice",
                    "Supprimer un exercice",
                    "Remplacer un exercice",
                    "Changer le scheme"
                ]
            )

            if not action or action == "↩ Annuler":
                continue

            inv = load_inventory()

            # ── AJOUTER ──────────────────────────────────
            if action == "Ajouter un exercice":
                exo = selectionner_exercice_inventaire(
                    "Quel exercice ajouter ?", inv
                )
                if not exo:
                    continue

                if exo in self.program[jour]:
                    print(f"⚠️  '{exo}' est déjà dans {jour}.")
                    continue

                default_scheme = inv[exo].get("default_scheme", "3x8-12")
                scheme = input(
                    f"Scheme (Entrée = {default_scheme}) → "
                ).strip() or default_scheme

                self.program[jour][exo] = scheme
                save_program(self.program)
                print(f"✅ '{exo}' ajouté à {jour} avec scheme {scheme} !")

            # ── SUPPRIMER ─────────────────────────────────
            elif action == "Supprimer un exercice":
                exo = selectionner_exercice_programme(
                    "Quel exercice supprimer ?",
                    self.program[jour]
                )
                if not exo:
                    continue

                confirm = selectionner(
                    f"Confirmer la suppression de '{exo}' ?",
                    ["Oui, supprimer", "Non, annuler"]
                )
                if confirm == "Oui, supprimer":
                    del self.program[jour][exo]
                    save_program(self.program)
                    print(f"✅ '{exo}' supprimé de {jour}.")
                else:
                    print("Annulé.")

            # ── REMPLACER ─────────────────────────────────
            elif action == "Remplacer un exercice":
                exo_old = selectionner_exercice_programme(
                    "Quel exercice remplacer ?",
                    self.program[jour]
                )
                if not exo_old:
                    continue

                exo_new = selectionner_exercice_inventaire(
                    f"Remplacer '{exo_old}' par quel exercice ?",
                    inv
                )
                if not exo_new:
                    continue

                if exo_new == exo_old:
                    print("C'est le même exercice, rien changé.")
                    continue

                # Garde le scheme existant ou prend celui de l'inventaire
                ancien_scheme = self.program[jour].pop(exo_old)
                nouveau_scheme = inv[exo_new].get("default_scheme", ancien_scheme)

                scheme = input(
                    f"Scheme (Entrée = {nouveau_scheme}) → "
                ).strip() or nouveau_scheme

                self.program[jour][exo_new] = scheme
                save_program(self.program)
                print(f"✅ '{exo_old}' remplacé par '{exo_new}' (scheme: {scheme}) !")

            # ── CHANGER SCHEME ────────────────────────────
            elif action == "Changer le scheme":
                exo = selectionner_exercice_programme(
                    "Pour quel exercice changer le scheme ?",
                    self.program[jour]
                )
                if not exo:
                    continue

                actuel = self.program[jour][exo]
                print(f"   Scheme actuel : {actuel}")
                new_scheme = input("Nouveau scheme → ").strip()

                if not new_scheme:
                    print("Rien changé.")
                    continue

                self.program[jour][exo] = new_scheme
                save_program(self.program)
                print(f"✅ Scheme de '{exo}' changé : {actuel} → {new_scheme}")

    def setup_or_edit_profile(self):
        from user_profile import setup_user_profile
        setup_user_profile()
        self.user_profile = load_user_profile()

    def show_recap_intelligent(self):
        print("\n" + "═" * 60)
        print("   RÉCAP PERSONNALISÉ")
        print("═" * 60)

        profile = load_user_profile()
        print(f"Profil : {profile['name'] or 'Vince'}, {profile['age'] or '?'} ans, "
              f"{profile['level']} – Objectif : {profile['goal']}")
        print(f"Unités : {profile['units']}  |  Semaine du programme : {get_current_week()}")

        big_lifts = ["Bench Press", "Back Squat", "Romanian Deadlift", "Overhead Press"]
        print("\nProgression 1RM (estimée) – derniers logs :")
        for lift in big_lifts:
            if lift in self.weights and self.weights[lift].get("history"):
                latest = self.weights[lift]["history"][0]
                print(f"  {lift:<20} {latest['1rm']:.1f} lbs ({latest['date']})")
            else:
                print(f"  {lift:<20} pas encore logué")

        print("\nExos stagnants (même poids ≥ 3 séances) :")
        stagnants = []
        for ex, data in self.weights.items():
            if ex == "sessions":
                continue
            hist = data.get("history", [])
            if len(hist) >= 3:
                last3_weights = [e["weight"] for e in hist[:3]]
                if len(set(last3_weights)) == 1:
                    stagnants.append(f"{ex} ({last3_weights[0]} lbs ×3)")
        if stagnants:
            print("  " + "\n  ".join(stagnants))
            print("   → Suggestion : deload 10-15% ou changer scheme")
        else:
            print("  Aucun exo stagné récemment – continue le grind ! 🔥")

        print("\nRécap global :")
        sessions = self.weights.get("sessions", {})
        if sessions:
            last_date = max(sessions.keys())
            last_rpe = sessions[last_date].get("rpe", "—")
            print(f"  Dernière séance : {last_date} (RPE {last_rpe})")
        else:
            print("  Pas encore de séances loguées.")

        print("═" * 60)

    def voir_catalogue_exercices(self):
        print("\n" + "═" * 70)
        print("   CATALOGUE DES EXERCICES (Inventaire complet)")
        print("═" * 70)

        inv = load_inventory()
        if not inv:
            print("Aucun exercice dans l'inventaire pour l'instant.")
            return

        for ex, info in sorted(inv.items()):
            muscles = ", ".join(info.get("muscles", [])) or "non spécifié"
            bar = f" (barre {info.get('bar_weight', 45)} lbs)" if info["type"] == "barbell" else ""
            print(f"  • {ex:<25}")
            print(f"    Type: {info['type']:<12} Incrément: +{info['increment']} lbs{bar}")
            print(f"    Scheme défaut: {info.get('default_scheme', '—')}")
            print(f"    Muscles ciblés: {muscles}")
            print("─" * 70)
    def voir_catalogue_exercices(self):
        print("\n" + "═" * 70)
        print("   CATALOGUE DES EXERCICES (Inventaire complet)")
        print("═" * 70)

        inv = load_inventory()
        if not inv:
            print("Aucun exercice dans l'inventaire pour l'instant.")
            return

        for ex, info in sorted(inv.items()):
            muscles = ", ".join(info.get("muscles", [])) or "non spécifié"
            bar = f" (barre {info.get('bar_weight', 45)} lbs)" if info["type"] == "barbell" else ""
            print(f"  • {ex:<25}")
            print(f"    Type: {info['type']:<12} Incrément: +{info['increment']} lbs{bar}")
            print(f"    Scheme défaut: {info.get('default_scheme', '—')}")
            print(f"    Muscles ciblés: {muscles}")
            print("─" * 70)

    def voir_dashboard_stats(self):
        generate_dashboard()

    def voir_historique_hiit(self):
        from log_workout import show_hiit_history
        show_hiit_history()

    def voir_programme_complet(self):
        from menu_select import selectionner, selectionner_exercice_inventaire, selectionner_exercice_programme

        while True:
            jour = selectionner(
                "Quel programme ?",
                list(self.program.keys())
            )

            if not jour or jour == "↩ Annuler":
                break

            while True:
                inv = load_inventory()

                # Affiche le programme
                print(f"\n{'═' * 65}")
                print(f"   PROGRAMME {jour.upper()}")
                print(f"{'═' * 65}")
                print(f"{'Exercice':<25} {'Scheme':<12} {'Type':<10} {'Muscles'}")
                print("─" * 65)

                for ex, scheme in self.program[jour].items():
                    info = inv.get(ex, {})
                    ex_type = info.get("type", "—")
                    muscles = ", ".join(info.get("muscles", [])) or "—"
                    print(f"{ex:<25} {scheme:<12} {ex_type:<10} {muscles}")

                print("─" * 65)
                print(f"  Total : {len(self.program[jour])} exercices")
                print(f"{'═' * 65}\n")

                action = selectionner(
                    f"Que veux-tu faire avec {jour} ?",
                    [
                        "➕  Ajouter un exercice du catalogue",
                        "🗑️   Supprimer un exercice",
                        "🔄  Remplacer un exercice",
                        "✏️   Changer le scheme d'un exercice",
                        "↩  Choisir un autre programme"
                    ]
                )

                if not action or action == "↩ Annuler" or action.startswith("↩"):
                    break

                # ── AJOUTER ──────────────────────────────────
                if action.startswith("➕"):

                    # Filtre les exercices déjà dans le programme
                    deja_dans = set(self.program[jour].keys())
                    catalogue_dispo = {
                        nom: info for nom, info in inv.items()
                        if nom not in deja_dans
                    }

                    if not catalogue_dispo:
                        print("⚠️  Tous les exercices du catalogue sont déjà dans ce programme.")
                        continue

                    exo = selectionner_exercice_inventaire(
                        f"Quel exercice ajouter à {jour} ?",
                        catalogue_dispo
                    )
                    if not exo or exo == "↩ Annuler":
                        continue

                    default_scheme = inv[exo].get("default_scheme", "3x8-12")
                    scheme = input(
                        f"Scheme (Entrée = {default_scheme}) → "
                    ).strip() or default_scheme

                    self.program[jour][exo] = scheme
                    save_program(self.program)
                    print(f"✅ '{exo}' ajouté à {jour} ({scheme}) !")

                # ── SUPPRIMER ─────────────────────────────────
                elif action.startswith("🗑️"):
                    exo = selectionner_exercice_programme(
                        f"Quel exercice supprimer de {jour} ?",
                        self.program[jour]
                    )
                    if not exo or exo == "↩ Annuler":
                        continue

                    confirmer = selectionner(
                        f"Supprimer '{exo}' de {jour} ?",
                        ["Oui, supprimer", "Non, annuler"]
                    )
                    if confirmer == "Oui, supprimer":
                        del self.program[jour][exo]
                        save_program(self.program)
                        print(f"✅ '{exo}' supprimé de {jour}.")
                    else:
                        print("Annulé.")

                # ── REMPLACER ─────────────────────────────────
                elif action.startswith("🔄"):
                    exo_old = selectionner_exercice_programme(
                        "Quel exercice remplacer ?",
                        self.program[jour]
                    )
                    if not exo_old or exo_old == "↩ Annuler":
                        continue

                    deja_dans = set(self.program[jour].keys()) - {exo_old}
                    catalogue_dispo = {
                        nom: info for nom, info in inv.items()
                        if nom not in deja_dans
                    }

                    exo_new = selectionner_exercice_inventaire(
                        f"Remplacer '{exo_old}' par quel exercice ?",
                        catalogue_dispo
                    )
                    if not exo_new or exo_new == "↩ Annuler":
                        continue

                    ancien_scheme = self.program[jour].pop(exo_old)
                    nouveau_scheme = inv[exo_new].get("default_scheme", ancien_scheme)

                    scheme = input(
                        f"Scheme (Entrée = {nouveau_scheme}) → "
                    ).strip() or nouveau_scheme

                    self.program[jour][exo_new] = scheme
                    save_program(self.program)
                    print(f"✅ '{exo_old}' → '{exo_new}' ({scheme}) !")

                # ── CHANGER SCHEME ────────────────────────────
                elif action.startswith("✏️"):
                    exo = selectionner_exercice_programme(
                        "Pour quel exercice changer le scheme ?",
                        self.program[jour]
                    )
                    if not exo or exo == "↩ Annuler":
                        continue

                    actuel = self.program[jour][exo]
                    new_scheme = input(
                        f"Nouveau scheme (actuel: {actuel}) → "
                    ).strip()

                    if not new_scheme:
                        print("Rien changé.")
                        continue

                    self.program[jour][exo] = new_scheme
                    save_program(self.program)
                    print(f"✅ {exo} : {actuel} → {new_scheme}")

    def voir_analyse_deload(self):
        afficher_rapport_deload(self.weights)