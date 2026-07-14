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
8. **Suppression : hard sur `exercise_logs`, soft (`deleted_at`) sur `exercises`.** Pas de colonne `is_deleted` (n'existe pas). Détail complet : `docs/CONVENTIONS.md` §4.

## PRINCIPES ARCHITECTURAUX

- Une seule source de vérité par type de donnée. Voir `docs/CONVENTIONS.md`.
- Pas de fallback silencieux. Pas de double mécanisme. Échouer fort (throw) si une précondition manque.
- Preuve (fichier + ligne) exigée avant toute décision.
- Débrancher les consommateurs AVANT de supprimer ce qu'ils consomment.
- Vérifier qu'un nouveau retour (None/erreur) est géré en aval.
- Anti-over-engineering : distinguer le PROBABLE du THÉORIQUE. Ne pas sur-investir dans l'improbable.
- Distinguer une ERREUR (bug à corriger) d'un CHOIX DE MODÉLISATION (Vince juge).
- **RLS Supabase** : toute nouvelle table doit inclure `ENABLE ROW LEVEL SECURITY` + policies `anon_all` et `service_role_all` dans la migration. Sans policies, PostgREST retourne `[]` silencieusement (pas d'erreur). Vérifier après création : `SELECT tablename, policyname FROM pg_policies WHERE tablename = '<t>';`
- **Structure vs terrain (iOS mutations)** : mutations de STRUCTURE (programme, schedules matin/soir, création programme, budget) = **POST direct + throw**, jamais `offlinePost`. Un replay silencieux de structure = fantômes (précédent budget, précédent `create_seance` qui a nécessité l'idempotence backend `954fcd3`). Logs de TERRAIN (exercice, séance, recovery) = `offlinePost` toléré (gym hors-ligne légitime, replay idempotent via garde-fous serveur). Helper de référence : `postProgrammeDirect` dans `Services/APIService+Workout.swift`.

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

- **Conventions de données** (sources de vérité, unités lbs, e1RM, delete strategy hard/soft) → `docs/CONVENTIONS.md`
- **Système de thèmes** (thèmes, tokens, fonds de mood fixes) → `docs/THEMING.md`
- **Architecture** (coach briefing, dashboard, couches) → `docs/ARCHITECTURE.md`
- **Pièges connus** (AlarmKit inventé, withTaskGroup iOS 26, timezone MTL) → `tasks/lessons.md`
- **Décisions** (ADRs) → `docs/DECISIONS.md`

Pour toute question sur une convention de données, un calcul (e1RM, ACWR, streak, readiness), une unité, ou un thème : **consulter la doc de référence ci-dessus AVANT d'agir**, ne pas deviner.

---

## COMPOSANTS UI — RÈGLES FORWARD

- Nouveau row label/valeur → `StatRow` (`Views/Components/StatRow.swift`)
- Nouveau CTA (bouton plein) → `PrimaryButton`
- Patterns inline existants (StatRow dispersés, 3 boutons SessionSupportViews×2 + HistoriqueView) : **NE PAS refactorer de façon proactive**. Migration opportuniste UNIQUEMENT si on touche déjà le fichier pour une autre raison — jamais un commit dédié "migrer vers le composant".

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
- **Hiérarchie d'exploration (RÈGLE)** : Pour toute question de STRUCTURE — qui appelle quoi, dépendances, définitions, navigation, "où vit X", "qui consomme Y" — consulter le graphe EN PREMIER (`graphify query` pour une question ciblée, `GRAPH_REPORT.md` pour la vue large). NE PAS lancer grep/glob pour ces questions structurelles. Grep est réservé au CONTENU TEXTUEL que le graphe n'indexe pas : strings littérales, valeurs hardcodées (ex : 1.0324), commentaires, SQL, texte dans les données. Si une exploration structurelle commence par grep alors que le graphe pouvait répondre, c'est une erreur de méthode.
