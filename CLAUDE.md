# CLAUDE.md

Contexte pour Claude Code dans ce dépôt.

## Projet

`pbip-reader` : lecteur **en lecture seule**, pour macOS, des projets PBIP (rapport + modèle sémantique).
Open source, MIT, publié sur https://github.com/florentinodsn/pbip-reader.
La spécification de travail (format, sources, incertitudes, écarts) est dans `docs/NOTES.md`.

## Contraintes non négociables

- **Salle blanche** : uniquement la documentation publique de Microsoft et des fichiers d'exemple
  écrits par nous. Ne jamais décompiler, inspecter ni copier un binaire, une DLL ou du code Microsoft.
- **Aucun composant Microsoft** en dépendance. Les schémas JSON sont cités par URL, jamais copiés.
- **Marque** : ne pas utiliser « Power BI » dans le nom du projet, de l'app ou de l'icône. Garder la
  mention de non-affiliation du README.
- **Aucune donnée réelle** dans le dépôt : fixtures fictives seulement (pas de noms internes,
  identifiants ou chaînes de connexion réels).
- **Lecture seule** : le code ne modifie jamais les fichiers lus.
- **Demander avant** : d'ajouter une dépendance (seule `swift-argument-parser` est autorisée),
  ou de changer un choix technique.
- Si la doc Microsoft contredit le code ou le prompt d'origine, la doc a raison : le noter dans `docs/NOTES.md`.

## Commandes

```bash
swift build
swift test                                     # 82 tests XCTest
PBIP_RECORD_SNAPSHOTS=1 swift test             # réécrit Tests/Snapshots après un changement voulu
swift run pbip info Tests/Fixtures/Ventes      # CLI : info | model | report | lineage | validate
swift run pbip-reader-app -project Tests/Fixtures/Ventes/Ventes.pbip   # app SwiftUI
Scripts/make-app.sh                            # construit « PBIP Reader.app » (non signée)
```

CI : `.github/workflows/ci.yml` (`swift build` + `swift test` sur `macos-latest`).

## Architecture

| Cible | Rôle |
|---|---|
| `PBIPKit` | bibliothèque, **sans dépendance d'interface** |
| `pbip` | CLI (`Sources/pbip/Pbip.swift`) |
| `PBIPReaderApp` | app SwiftUI, seule cible qui dépend de l'interface |

Dans `Sources/PBIPKit/` :

- `Model/` : `Project`, `Report`, `SemanticModel`, `Diagnostic` (Codable, Equatable).
- `IO/` : `JSON` (arbre générique tolérant), `FileReader` (UTF-8, BOM signalé, `$schema` contrôlé).
- `Loading/` : `ProjectLoader` (`.pbip` → `definition.pbir` → modèle) et choix du lecteur selon le format.
- `TMDL/` : lexer (indentation), parseur (arbre `TMDLNode`), `TMDLModelBuilder`.
- `BIM/` : lecteur `model.bim`.
- `Report/` : `PBIRReader`, `LegacyReportReader`, `FieldExtractor` (champs des visuels).
- `Analysis/` : `DAXScanner` (balayage lexical), `LineageBuilder`, `Validator`, `ModelDiagram`
  (rôle faits/dimensions, dispositions « Ranger » et « Étoile / flocon », tracé des liens),
  `MeasureFolder` (arbre des dossiers d'affichage).
- `Output/` : rendus text / json / markdown par commande ; JSON à clés triées.
- `Syntax/` : découpage en jetons DAX/M pour la coloration de l'app.

## Invariants testés

- `Ventes` (PBIR + TMDL) et `VentesLegacy` (`report.json` + `model.bim`) donnent **le même**
  `Report`, `SemanticModel` et `Lineage`, au champ `format` près. Toute modification d'un lecteur
  doit garder cette égalité.
- Sorties JSON et Markdown figées par snapshot (`Tests/Snapshots`).
- Codes de sortie de la CLI : `0` succès, `1` erreurs de `validate`, `2` projet illisible, `64` option invalide.
- Fixtures décrites dans `Tests/Fixtures/README.md`, gardées octet pour octet (`.gitattributes`).

## Pièges déjà rencontrés

- Desktop indente l'expression de `source =` d'une partition **deux** niveaux sous la propriété,
  la doc en montre un : le parseur retire la marge réelle (plus petit niveau rencontré).
- Les anciens dossiers `.Dataset` utilisent `definition.pbidataset` au lieu de `definition.pbism`.
- `JSONSerialization` accepte une virgule finale : pour un JSON invalide de test, il faut une vraie faute.
- Ne pas nommer un type `PBIPKit` : il masquerait le module (`PBIPKit.Table` vs `SwiftUI.Table`).
- App SwiftUI lancée sans bundle : la politique d'activation `.regular` se pose dans
  `applicationWillFinishLaunching`, et le chemin se passe avec `-project` (un chemin seul est pris
  par AppKit pour un document à ouvrir, et SwiftUI ne crée alors pas de fenêtre).

## Conventions

- Documentation (README, NOTES, commentaires) en français ; sortie de la CLI et diagnostics en
  anglais ; interface de l'app en français.
- Commits : `type: message` en français (`feat`, `fix`, `test`, `docs`, `chore`), un commit par étape
  cohérente, tests verts avant de commiter.

## Points ouverts

- Titulaire de la licence : `florentinodsn` par défaut, nom complet possible.
- `functions.tmdl` (UDF DAX) lu mais non exposé dans le modèle objet.
- Message `model.unusedMeasure` bruyant sur un modèle partagé par plusieurs rapports (relatif au rapport lu).
