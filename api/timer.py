# timer.py
import time
import sys
import threading


def countdown(seconds: int, label: str = "Repos"):
    """
    Compte à rebours dans le terminal.
    Affiche sur la même ligne et se termine proprement.
    """
    print()
    try:
        for remaining in range(seconds, 0, -1):
            mins = remaining // 60
            secs = remaining % 60

            if mins > 0:
                temps = f"{mins}:{secs:02d}"
            else:
                temps = f"{secs}s"

            # Barre de progression
            total_bars = 20
            filled     = int((seconds - remaining) / seconds * total_bars)
            bar        = "█" * filled + "░" * (total_bars - filled)

            sys.stdout.write(
                f"\r  ⏱  {label} : {temps:<6}  [{bar}]  (Entrée pour skip)"
            )
            sys.stdout.flush()
            time.sleep(1)

        sys.stdout.write(f"\r  ✅ {label} terminé !{' ' * 30}\n")
        sys.stdout.flush()

    except KeyboardInterrupt:
        sys.stdout.write(f"\r  ⏭  {label} skippé.{' ' * 30}\n")
        sys.stdout.flush()


def get_rest_time(exercise: str, scheme: str) -> int:
    """
    Retourne le temps de repos recommandé en secondes
    selon l'exercice et le scheme.
    """
    # Gros lifts composés → repos plus long
    big_lifts = [
        "Bench Press", "Back Squat", "Deadlift",
        "Romanian Deadlift", "Overhead Press", "Barbell Row"
    ]

    if exercise in big_lifts:
        return 180  # 3 min

    # Scheme style force (faibles reps)
    if scheme:
        try:
            reps_part = scheme.split("x")[-1]
            max_reps  = int(reps_part.split("-")[-1])
            if max_reps <= 6:
                return 180  # Force → 3 min
            elif max_reps <= 10:
                return 120  # Hypertrophie → 2 min
            else:
                return 90   # Endurance musculaire → 90s
        except:
            pass

    return 90  # Défaut


def demander_timer(exercise: str, scheme: str = "") -> bool:
    """
    Demande à l'utilisateur s'il veut activer le timer.
    Retourne True si oui.
    """
    from menu_select import selectionner
    temps = get_rest_time(exercise, scheme)
    mins  = temps // 60
    secs  = temps % 60
    label = f"{mins}:{secs:02d}" if mins > 0 else f"{secs}s"

    choix = selectionner(
        f"Timer de repos ({label} recommandé) :",
        [
            f"▶  {label} (recommandé)",
            "▶  60s",
            "▶  90s",
            "▶  2:00",
            "▶  3:00",
            "⏭  Pas de timer"
        ]
    )

    if not choix or choix.startswith("⏭"):
        return False

    durees = {
        "60s":  60,
        "90s":  90,
        "2:00": 120,
        "3:00": 180,
    }

    # Timer recommandé
    if choix.startswith(f"▶  {label}"):
        countdown(temps, "Repos")
        return True

    # Autres durées
    for key, val in durees.items():
        if key in choix:
            countdown(val, "Repos")
            return True

    return False