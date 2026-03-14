# Tâches — TrainingOS

Les agents sélectionnent et implémentent les tâches de cette liste.
Mettre à jour ce fichier et `STATE.md` après chaque tâche complétée.

---

## Haute priorité

- [x] Logger les appels Claude (remplacer les `print` DEBUG par un vrai logger)
- [x] Forcer `SECRET_KEY` en production (lever une erreur si valeur par défaut détectée sur Vercel)
- [x] Ajouter un rate limiting sur les appels à l'API Anthropic (éviter dépassement de coût)
- [x] Tests Flask pour les routes principales (seance_data, historique_data, log, deload_status)

---

## Priorité moyenne

- [x] Indicateur UI de sync offline (endpoint /api/sync_status exposant le nombre de dirty)
- [x] Externaliser le CSS inline volumineux des templates vers `static/` (base.html → main.css)
- [x] Améliorer la page `intelligence.html` : historique des échanges avec le coach IA
- [x] Déload automatique : endpoint `/api/deload_status` exposant stagnation + RPE + recommandation

---

## Priorité basse

- [ ] Partage de programme entre utilisateurs (export/import JSON)
- [ ] Notifications push PWA (rappels séance planifiée)
- [ ] Mode sombre
- [ ] Internationalisation (EN/FR)

---

## Complétées récemment

- [x] Tracker nutritionnel complet (calories, macros, déficit)
- [x] Historique par date avec édition inline
- [x] Coach IA migré vers Claude Sonnet 4.6
- [x] Safe area iOS + PWA manifest amélioré
- [x] Auto-update Service Worker sur déploiement Vercel
- [x] Responsive mobile sur toutes les pages
- [x] Fix calcul 1RM et propagation édition séance
- [x] Fix décalage UTC/heure locale pour le log des séances
- [x] Timer HIIT : beeps, flash, options panel
- [x] Statistiques : KPIs globaux + Personal Records
