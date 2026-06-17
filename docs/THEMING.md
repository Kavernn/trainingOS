# TrainingOS — Système de thèmes

> État au 2026-06-16. Source canonique : `Utilities/AppTheme.swift`.

---

## Thèmes disponibles

`AppTheme.swift:6-17` — enum `AppThemeOption` — **10 cas** :

| Clé | Nom affiché |
|---|---|
| `.monochrome` | Monochrome |
| `.sinCity` | Sin City |
| `.blood` | Blood |
| `.electric` | Electric |
| `.matrix` | Matrix |
| `.tokyo` | Tokyo |
| `.arctic` | Arctic |
| `.goldNoir` | Gold Noir |
| `.desert` | Desert |
| `.electricLight` | Electric Light |

---

## Structure AppThemeColors

`AppTheme.swift:80-142` — champs de `AppThemeColors` :

**Couleurs sémantiques :**
`accent`, `accentLight`, `accentMuted`, `onAccent`, `background`, `surfaceCard`,
`surfaceElevated`, `surfaceInset`, `textPrimary`, `onBackground`, `onSurface`,
`textSecondary`, `textMuted`, `separator`, `separatorSubtle`, `separatorStrong`,
`danger`, `success`, `warning`, `info`

**Tokens visuels :**
`cardCornerRadius`, `cardBorderWidth`, `cardBorderColor`, `cardShadowColor`, `cardShadowRadius`,
`cardShadowOffset`, `cardGlowColor`, `cardGlowRadius`, `chartPalette`, `glassOpacity`,
`accentGradientColors`, `identityLayer`, `heroFontDesign`, `titleFontDesign`, `displayWeight`,
`cardAccentFillOpacity`, `cardAccentStrokeOpacity`, `cardStyle`, `accentDistribution`,
`heroNumberSize`, `sectionTitleTracking`, `sectionTitleUppercased`

---

## Tokens sémantiques : onBackground vs onSurface

`AppTheme.swift:90` — commentaire : *"onBackground: texte sur le fond (diverge d'onSurface
uniquement en Electric Light)"*

Exposés via `Utilities/Extensions.swift:64-65` :
- `Color.appOnSurface` — texte sur les cards (`surfaceCard`)
- `Color.appOnBackground` — texte directement sur le fond de l'écran (`background`)

**Règle générale :** Pour 9 thèmes sur 10, `onBackground == onSurface`. Utiliser
`Color.appOnSurface` par défaut pour le texte dans les cards.

**Seule exception — Electric Light** (`AppTheme.swift:544-545`) :
- `onBackground`: `#0A0A00` — noir sur fond jaune
- `onSurface`: `#F5FFB0` — clair sur cards sombres

**Principe "fond = couleur dominante" :** Le champ `background` est la couleur identitaire
du thème. Les cards (`surfaceCard`) s'en détachent par contraste. Ne jamais appliquer
`background` comme couleur de fond d'une card.

**État d'adoption (2026-06-16) :**
- `Color.appOnSurface` — largement adopté dans les vues.
- `Color.appOnBackground` — seulement 3 sites, tous dans `Utilities/DesignSystem.swift:225,
  230, 423`. Pas encore adopté dans les View files. Le chantier Electric Light (adoption de
  `appOnBackground` dans les vues pour gérer le fond jaune) est en cours mais non terminé.

---

## Types de layout

**CardStyle** (`AppTheme.swift:51-56`) :
`flat`, `outlined`, `floating`, `raised`

**AccentDistribution** (`AppTheme.swift:60-63`) :
- `pervasive` — accent présent sur la majorité des éléments
- `surgical` — accent réservé aux éléments clés uniquement

**IdentityLayerStyle** (`AppTheme.swift:67-76`) :
`none`, `scanlines(opacity:)`, `neonHalo(color:intensity:)`, `filmGrain(opacity:)`,
`goldFiligree(opacity:)`, `cyberGrid(opacity:)`, `arcticFrost(opacity:)`, `bloodVein(opacity:)`

---

## Fonds fixes — carve-outs hors thème

Ces fonds ne suivent **pas** le thème actif. Couleur fixe intentionnelle pour préserver
l'ambiance de la vue indépendamment des préférences utilisateur.

`Utilities/Extensions.swift:78-80` :
```swift
static let voidBg          = Color(red: 0.020, green: 0.031, blue: 0.063)
static let pssBg           = Color(hex: "0C0C18")
static let ritualEveningBg = Color(hex: "0D0906")
```
Commentaire en code : "Fond de mood fixe — NE suit pas le thème, intentionnel"

**Usages :**
- `Views/PSS/PSSView.swift:472` — `Color.pssBg.ignoresSafeArea()`
- `Views/Intelligence/RitualEveningView.swift:23` — `Color.ritualEveningBg.ignoresSafeArea()`

Ne pas convertir ces fonds en tokens thémés. Contrat : ces vues ont toujours ce fond, quel que
soit le thème de l'utilisateur.
