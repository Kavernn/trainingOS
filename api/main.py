# main.py

from api.index import TrainingOSApp

if __name__ == "__main__":
    app = TrainingOSApp()
    try:
        app.run()
    except KeyboardInterrupt:
        print("\nArrêt propre. À bientôt ! 💪")