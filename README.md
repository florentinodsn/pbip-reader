# pbip-reader

Lecteur en ligne de commande, pour macOS, des projets au format **PBIP**. Il affiche la structure
d'un projet : modèle de données, mesures DAX, relations, requêtes M, pages, visuels et lignage
entre les visuels et le modèle.

> Ce projet n'est ni affilié à Microsoft ni approuvé par Microsoft. Power BI est une marque de Microsoft Corporation.

## Principes

- **Lecture seule** : aucun fichier lu n'est jamais modifié.
- **Aucun composant Microsoft** : le parseur TMDL et les lecteurs JSON sont écrits ici, à partir de
  la documentation publique (voir [`docs/NOTES.md`](docs/NOTES.md)).
- **Tolérant** : une propriété ou un mot-clé inconnus produisent un avertissement, pas un échec.

## Formats pris en charge

| Élément | Formats |
|---|---|
| Rapport | PBIR (`definition/`) et PBIR-Legacy (`report.json`) |
| Modèle sémantique | TMDL (`definition/`) et TMSL (`model.bim`) |
| Référence au modèle | `byPath` (modèle local) et `byConnection` (modèle publié, rapport seul) |

## Installation

Prérequis : macOS 13 ou plus, Swift 5.9 ou plus (Xcode 15+).

```bash
swift build -c release
cp .build/release/pbip /usr/local/bin/
```

## Utilisation

```
pbip info     <chemin.pbip|dossier>   résumé : formats, pages, visuels, tables, mesures, relations
pbip model    <chemin> [--table X]    tables, colonnes, mesures (avec DAX), relations, requêtes M
pbip report   <chemin> [--page X]     pages et visuels, avec les champs utilisés
pbip lineage  <chemin> [--measure X]  qui utilise quoi, dans les deux sens
pbip validate <chemin>                diagnostics ; code de sortie ≠ 0 en cas d'erreur

Options communes : --format text|json|markdown, --no-color
```

Le chemin peut être un fichier `.pbip`, un dossier contenant un `.pbip`, un dossier `.Report`
ou un dossier `.SemanticModel`.

`pbip validate` est conçu pour la CI :

```yaml
- run: pbip validate MonRapport.pbip --format markdown >> "$GITHUB_STEP_SUMMARY"
```

## Bibliothèque

`PBIPKit` est utilisable seule, sans dépendance d'interface :

```swift
import PBIPKit

let project = try ProjectLoader().load(URL(fileURLWithPath: "MonRapport.pbip"))
for table in project.semanticModel?.tables ?? [] {
    print(table.name, table.measures.count)
}
```

## Développement

```bash
swift build
swift test
```

Les fichiers d'exemple de `Tests/Fixtures/` sont des projets **fictifs** écrits à la main.
Pour régénérer les snapshots JSON : `PBIP_RECORD_SNAPSHOTS=1 swift test`.

## Licence

MIT — voir [LICENSE](LICENSE).
