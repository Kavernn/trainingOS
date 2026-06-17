# Audit UX — Séance · Bonus · Programme
> Point de vue : power user habitué à Strong / Hevy / Fitbod

---

## 🔴 HIGH — cassent le flow de séance

- [ ] **Timer de repos ne se lance pas automatiquement après "Logger"**
  Strong/Hevy démarrent le timer dès que tu loggues. Ici il faut taper manuellement "Lancer la pause". Sur 8 exercices × 3 sets = 24 fois cliquer en plus.

- [x] **Pas d'auto-scroll vers le prochain exercice après logger**
  La card se ferme mais tu restes au même endroit. Tu dois scroller manuellement vers le suivant à chaque fois.

- [x] **Card collapsed ne montre pas le poids/reps de la dernière session**
  Un power user scanne la liste pour savoir "où j'en suis". En l'état, chaque card collapsed ne dit rien — tu dois ouvrir pour voir. Afficher "85kg · 6,6,6" en subtitle suffirait.

- [x] **Pas de bouton "Same as last" depuis la card collapsed**
  Si tu veux refaire exactement la même chose, tu dois : ouvrir la card → taper "Reprendre la dernière séance" → taper "Logger". Ça devrait être 1 tap depuis l'état fermé.

- [x] **"Terminer la séance" accessible même avec 0 exercices loggués**
  Un power user ne devrait pas pouvoir finir une séance vide. Griser le bouton ou montrer une alerte si < 1 exercice loggué.

- [x] **PostSessionEdit : poids pré-rempli = poids total (barre incluse), pas poids par côté**
  Si tu fais Bench Press à 100kg (barre 45 + 27.5/côté), la modification post-session te montre "100" pas "27.5". Impossible de savoir si c'est par côté ou total. Confusion garantie.

- [x] **Récap post-séance : que les noms, pas les poids/reps**
  `AlreadyLoggedSeanceView` affiche "Bench Press", "Squat" etc. Un power user veut "Bench Press — 85kg (6,6,5)". L'info est dans le dashboard, juste pas affichée.

- [x] **Aperçu demain : ordre alphabétique au lieu de l'ordre de séance**
  `tomorrowExercises` = `sorted { $0.0 < $1.0 }`. Le power user veut voir dans l'ordre réel d'entraînement, pas A→Z.

---

## 🟠 MEDIUM — ralentissent sans casser

- [x] **Navigation clavier entre sets : pas de bouton "Suivant"**
  Sur le numpad poids/reps, pas de toolbar avec "Suivant" pour passer de S1 → S2 → S3 sans taper ailleurs. Sur 4 sets × 2 champs = 8 taps de plus que nécessaire.

- [x] **Durée de séance : minutes seulement**
  "45 min" → devrait être "45:32" (avec secondes). TimelineView est déjà là, juste pas les secondes.

- [x] **Notes cachées derrière "Zone douleur · Notes"**
  Le lien est en gris 10pt en bas de la card. Un power user qui veut noter quelque chose rate souvent ce bouton. Mettre une icône note visible dans le header de la card.

- [x] **Mode set-à-set : cocher nécessite un tap précis sur une petite zone**
  Le ✓ en fin de set row est petit. Un swipe right sur la row serait plus naturel (comme dans Todoist/Strong).

- [x] **Séance bonus : même programme que la séance du jour, pas de choix**
  `ExtraSessionSheet` lance `WorkoutSeanceView(data: data)` — exactement le même programme. Un power user voulant faire Pull B après Push A n'a aucun moyen de le choisir.

- [x] **Séance bonus : titre générique "Séance supplémentaire"**
  L'utilisateur ne sait pas quelle séance il va faire. Afficher le nom de la session (ex. "Séance supplémentaire — Pull B").

- [x] **Fermer la séance bonus en cours : double friction**
  Alerte → "Sauvegarder" → ouvre un FinishSessionSheet. Deux étapes pour ce qui devrait être une. Idéalement : "Terminer" directement dans l'alerte avec un slider RPE inline.

- [x] **Modifier séance post-workout : pas de détail par set**
  `PostSessionEditSheet` = un seul champ poids + un seul champ reps. Si tu as fait 85/80/75 sur 3 sets, tu ne peux pas les corriger individuellement.

- [x] **Programme : pas de load indicator sur les mutations (add/delete/reorder)**
  Quand tu ajoutes un exercice, la UI se met à jour localement immédiatement mais aucun feedback si le réseau a échoué. Le cache se vide mais l'utilisateur ne sait pas si c'est sauvegardé.

- [x] **Programme : suppression d'exercice sans undo**
  Tap supprime, c'est définitif. Pas de "Annuler" snackbar comme iOS le recommande. Risque de fat-finger sur un programme soigneusement construit.

- [x] **Programme : impossible de réordonner les séances entre elles**
  Les exercices sont draggables dans une séance, mais l'ordre Push A → Pull A → Legs est figé (trié selon `seanceOrder` hardcodé). Pour un programme custom, c'est bloquant.

- [x] **Programme : le clipboard de copie/colle est invisible**
  `@AppStorage("programme_clipboard")` persiste mais rien ne montre ce qui est dans le clipboard. Tu peux coller sans savoir quoi. Afficher un petit badge "Clipboard: Push A (6 exos)".

- [x] **Historique dans ExerciseCard : poids total affiché, pas poids par côté**
  L'historique montre "85kg · 6,6,5" mais si c'est du barbell, le poids à entrer est 20kg par côté. Le power user doit faire le calcul mental à chaque fois.

---

## 🟡 LOW — polish / nice-to-have

- [x] **Bilan IA : spinner bloquant 2-3 secondes après la séance**
  Le post-workout brief se charge après l'animation de succès. Charger en arrière-plan pendant la séance et avoir le résultat prêt au moment de l'afficher.

- [x] **Partager la séance : format trop basique**
  "4 exercices : Bench, Squat…" sans volume ni PRs. Un power user qui partage veut montrer ses stats.

- [x] **Semaine type (Programme) : blocs jour en 9pt, illisibles sur iPhone SE**
  7 blocs compressés horizontalement avec text 9pt. Sur petit écran c'est inutilisable.

- [x] **Pas de pull-to-refresh dans Programme**
  Pour recharger après une modif backend externe, il faut quitter et revenir.

- [x] **Volume total : affiché seulement après le premier exercice loggué**
  `if !vm.logResults.isEmpty { ... }` — le volume apparaît après le 1er log. Afficher "0 lbs" dès le début pour montrer que le tracker est actif.

- [x] **"Sauter cet exercice" : bouton pas assez signalé comme destructif**
  Petit texte gris 12pt. Risque de fat-finger côté du bouton "Logger". Mettre une couleur distincte ou un swipe action.

- [ ] **Échauffement : affiché uniquement pour barbell/dumbbell, pas pour machine**
  `warmupSets` se base sur `currentWeight > 0` mais le guard `if !isTimeBased && !evm.warmupSets.isEmpty` n'exclut pas machine. À vérifier.

- [x] **Périodisation card : ne modifie pas automatiquement les schemes d'exercices**
  La card dit "Force : 4-5×4-6 reps" mais l'utilisateur doit changer chaque scheme manuellement. Mettre un bouton "Appliquer à tout le programme".

- [x] **Deux schedules matin/soir trop similaires visuellement**
  Même card design, même couleurs. Un utilisateur peut confondre lequel il édite.

- [x] **Pas de feedback haptic sur "Reprendre la dernière séance"**
  Tap → rien. Tous les autres boutons ont `triggerImpact`. Inconsistance.
