# Tâches — TrainingOS

Les agents sélectionnent et implémentent les tâches de cette liste.
Mettre à jour ce fichier et `STATE.md` après chaque tâche complétée.

---

## Haute priorité

- [ ] Logger les appels Claude (remplacer les `print` DEBUG par un vrai logger)
- [ ] Forcer `SECRET_KEY` en production (lever une erreur si valeur par défaut détectée sur Vercel)
- [ ] Ajouter un rate limiting sur les appels à l'API Anthropic (éviter dépassement de coût)
- [ ] Tests Flask pour les routes principales (index, seance, historique, nutrition)

---

## Priorité moyenne

- [ ] Indicateur UI de sync offline (badge "non synchronisé" quand des entrées sont `dirty`)
- [ ] Externaliser le CSS inline volumineux des templates vers `static/`
- [ ] Améliorer la page `intelligence.html` : historique des échanges avec le coach IA
- [ ] Déload automatique : notification UI quand un déload est détecté

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
