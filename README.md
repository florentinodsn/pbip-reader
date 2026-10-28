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

Il faut macOS 13 ou plus et les outils de développement d'Apple (Swift 5.9 ou plus). S'ils ne sont
pas encore installés, une seule commande suffit (une fenêtre s'ouvre, cliquer sur « Installer ») :

```bash
xcode-select --install
```

### L'application

```bash
git clone https://github.com/florentinodsn/pbip-reader.git
cd pbip-reader
Scripts/make-app.sh /Applications
```

« PBIP Reader » est alors dans le dossier Applications : on la lance depuis le Launchpad, Spotlight
ou le Finder, puis `⌘O` pour ouvrir un projet. Compilée sur la machine, elle s'ouvre sans
avertissement de macOS.

Pour la mettre à jour, depuis le dossier `pbip-reader` :

```bash
git pull
Scripts/make-app.sh /Applications
```

Pour la désinstaller, mettre « PBIP Reader » du dossier Applications à la corbeille.

### La ligne de commande (facultatif)

```bash
swift build -c release
sudo mkdir -p /usr/local/bin
sudo cp .build/release/pbip /usr/local/bin/
```

`pbip --help` liste ensuite les commandes.

## Utilisation

```
pbip info     <chemin.pbip|dossier>   résumé : formats, pages, visuels, tables, mesures, relations
pbip model    <chemin> [--table X]    tables, colonnes, mesures (avec DAX), relations, requêtes M, fonctions DAX
pbip report   <chemin> [--page X]     pages et visuels, avec les champs utilisés
pbip lineage  <chemin> [--measure X]  qui utilise quoi, dans les deux sens
pbip validate <chemin>                diagnostics ; code de sortie ≠ 0 en cas d'erreur
              [--no-unused-measures]   sans les mesures inutilisées (modèle partagé avec des rapports publiés)

Options communes : --format text|json|markdown, --no-color
```

Le chemin peut être un fichier `.pbip`, un dossier contenant un `.pbip`, un dossier `.Report`
ou un dossier `.SemanticModel`.

Codes de sortie : `0` succès, `1` erreurs de validation (`pbip validate`), `2` projet illisible,
`64` option invalide.

`pbip validate` est conçu pour la CI :

```yaml
- run: pbip validate MonRapport.pbip --format markdown >> "$GITHUB_STEP_SUMMARY"
```

## Application macOS

Une application SwiftUI en lecture seule accompagne la CLI :

- vue d'ensemble : diagramme du modèle (dispositions « Ranger » et « Étoile / flocon », détail d'une
  relation au survol), toutes les mesures par dossier d'affichage, fonctions DAX, relations
  filtrables par table ou par colonne, pages et visuels ;
- détail des tables et des mesures (DAX coloré, usages dans le rapport), requêtes M ;
- aperçu schématique de chaque page à partir des positions des visuels ;
- diagnostics filtrables par gravité.

Les tables de date automatiques (`LocalDateTable_…`, `DateTableTemplate_…`) y sont masquées.

Pour l'installer, voir [Installation](#lapplication). En développement :

```bash
swift run pbip-reader-app -project chemin/vers/MonRapport.pbip   # lancement direct, sans icône
Scripts/make-app.sh                                              # construit .build/PBIP Reader.app
```

Dans l'application : `⌘O` ouvre un projet (fichier `.pbip` ou dossier), `⌘R` le relit ; on peut
aussi déposer le fichier dans la fenêtre. Le chemin se passe avec `-project` : un chemin seul
serait pris par macOS pour un document à ouvrir.

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
