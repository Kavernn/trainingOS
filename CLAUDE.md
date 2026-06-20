# TrainingOS — Instructions Claude Code

App iOS de transformation physique/mentale. **Vince est seul dev ET seul utilisateur.**
Stack : Swift (iOS natif) + Python API (Vercel) + Supabase.

---

## RÈGLES ABSOLUES (non négociables)

1. **Diagnostic AVANT fix.** Détective d'abord, chirurgien ensuite. Théorie → preuve (fichier:ligne) → fix. Jamais de fix sur une belle théorie non prouvée.
2. **Vince valide AVANT que le code soit touché.** Tu proposes, Vince approuve, puis tu implémentes. Jamais l'inverse.
3. **Tu ne lances JAMAIS le build toi-même.** Tu demandes à Vince de builder et de rapporter le résultat.
4. **Zéro modification aux données historiques.** Absolu, sans exception.
5. **Fix chirurgical** — touche uniquement ce qui est nécessaire.
6. **Soumets chaque diff avant merge.**
7. **Un changement à la fois = un build.** Jamais N modifications en un diff indiagnosticable.
8. **Soft-delete uniquement** (`is_deleted`) — jamais de hard delete sur `exercise_logs`.

## PRINCIPES ARCHITECTURAUX

- Une seule source de vérité par type de donnée. Voir `docs/CONVENTIONS.md`.
- Pas de fallback silencieux. Pas de double mécanisme. Échouer fort (throw) si une précondition manque.
- Preuve (fichier + ligne) exigée avant toute décision.
- Débrancher les consommateurs AVANT de supprimer ce qu'ils consomment.
- Vérifier qu'un nouveau retour (None/erreur) est géré en aval.
- Anti-over-engineering : distinguer le PROBABLE du THÉORIQUE. Ne pas sur-investir dans l'improbable.
- Distinguer une ERREUR (bug à corriger) d'un CHOIX DE MODÉLISATION (Vince juge).

## FORMAT DE TRAVAIL

Deux phases distinctes, jamais combinées :
1. **Audit/diagnostic** (read-only) : lire les fichiers pertinents, identifier le problème avec fichier:ligne comme preuve, rapport écrit pour approbation.
2. **Implémentation** : uniquement après validation explicite de Vince.

Langue : français. Terminologie domaine en français (séance, programme, exercice, poids, reps).

---

## COMMANDES

- Build : (Vince builde dans Xcode — tu ne builds jamais)
- API base : `https://training-os-rho.vercel.app`

---

## DOC DE RÉFÉRENCE (lire à la demande, pas chargée par défaut)

- **Conventions de données** (sources de vérité, unités lbs, e1RM, soft-delete) → `docs/CONVENTIONS.md`
- **Système de thèmes** (thèmes, tokens, fonds de mood fixes) → `docs/THEMING.md`
- **Architecture** (coach briefing, dashboard, couches) → `docs/ARCHITECTURE.md`
- **Pièges connus** (AlarmKit inventé, withTaskGroup iOS 26, timezone MTL) → `tasks/lessons.md`
- **Décisions** (ADRs) → `docs/DECISIONS.md`

Pour toute question sur une convention de données, un calcul (e1RM, ACWR, streak, readiness), une unité, ou un thème : **consulter la doc de référence ci-dessus AVANT d'agir**, ne pas deviner.

---

## SOUS-AGENTS

Pour toute EXPLORATION large (cartographier des références, auditer du code mort, tracer des dépendances) : déléguer à un sous-agent pour garder le contexte principal propre. Voir l'agent `detective` (read-only).
L'implémentation reste TOUJOURS dans la session principale, sous validation de Vince — jamais déléguée à un agent autonome.

## COMPACTION

Lors de la compaction, préserver toujours : la liste complète des fichiers modifiés, les décisions validées par Vince non encore implémentées, et les diagnostics en attente d'approbation.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
