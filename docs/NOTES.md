# Notes de format — spécification de travail

Ce fichier résume le format PBIP tel que décrit par la **documentation publique** de Microsoft.
Il sert de spécification au code de `PBIPKit` et prouve que le développement s'appuie
uniquement sur des sources publiques. Aucun binaire, DLL ou code source Microsoft n'a été
consulté, décompilé ni copié.

Pages consultées le 2026-10-28 :

| Sujet | Source | Date de la page |
|---|---|---|
| Vue d'ensemble PBIP | https://learn.microsoft.com/power-bi/developer/projects/projects-overview | 2026-09-23 |
| Dossier du rapport (PBIR) | https://learn.microsoft.com/power-bi/developer/projects/projects-report | 2026-09-23 |
| Dossier du modèle sémantique | https://learn.microsoft.com/power-bi/developer/projects/projects-dataset | 2026-09-23 |
| Langage TMDL | https://learn.microsoft.com/analysis-services/tmdl/tmdl-overview | mise à jour 2026-06-11 |
| Schémas JSON | https://github.com/microsoft/json-schemas/tree/main/fabric | branche `main` |

Les schémas JSON ne sont **pas copiés** dans le dépôt : le code ne fait que lire l'URL `$schema`
de chaque fichier pour en extraire le nom et la version.

## 1. Projet (`.pbip`)

- Fichier JSON optionnel, raccourci vers un dossier de rapport. Schéma `fabric/pbip/pbipProperties/1.0.0`.
- Propriétés : `$schema`, `version`, `artifacts[]`, `settings` (`enableAutoRecovery`).
- `artifacts[].report.path` : chemin **relatif**, séparateur `/`.
- Un dossier peut contenir plusieurs rapports et modèles ; chaque rapport peut s'ouvrir par son
  `definition.pbir`, sans `.pbip`.
- `.gitignore` par défaut : `**/.pbi/localSettings.json`, `**/.pbi/cache.abf`.
- Encodage attendu : **UTF-8 sans BOM**. Fins de ligne écrites par Desktop : **CRLF**.

## 2. Dossier du rapport (`<Nom>.Report/`)

| Élément | Rôle |
|---|---|
| `definition.pbir` | **obligatoire** ; `version`, `datasetReference` |
| `report.json` | format **PBIR-Legacy** (schéma non documenté) |
| `definition/` | format **PBIR** (schémas publics) |
| `.platform` | fichier Fabric Git ; on n'y lit que `metadata.displayName` |
| `.pbi/` | paramètres locaux, ignoré |
| `StaticResources/`, `CustomVisuals/`, `mobileState.json`, `semanticModelDiagramLayout.json` | ignorés |

### `definition.pbir`

- Schéma `fabric/item/report/definitionProperties/{1.0.0|2.0.0}`. Requis : `$schema`, `version`, `datasetReference`.
- `version` `1.0` : PBIR-Legacy obligatoire. `4.0` ou plus : PBIR-Legacy **ou** PBIR.
- `datasetReference` contient **un** des deux :
  - `byPath.path` : chemin relatif vers le dossier du modèle (absolu interdit, séparateur `/`).
  - `byConnection.connectionString` : modèle publié. En v1, propriétés supplémentaires
    (`pbiModelDatabaseName`, `connectionType`, …) ignorées ici.
- Le nom du modèle publié est extrait de `initial catalog=` de la chaîne de connexion,
  sinon de `semanticmodelid=`. Ce découpage est une heuristique (voir § Incertitudes).
- Plusieurs `*.pbir` peuvent coexister ; seul `definition.pbir` est lu.

### Format PBIR (`definition/`)

```
definition/
├── version.json            requis — schéma versionMetadata, propriété `version`
├── report.json             requis — schéma report (themeCollection, filterConfig, annotations…)
├── reportExtensions.json   optionnel — mesures de rapport
├── pages/
│   ├── pages.json          optionnel — pageOrder, activePageName, landingPageName
│   └── <page>/
│       ├── page.json       requis — name, displayName, displayOption, width, height, filterConfig…
│       └── visuals/<visuel>/
│           ├── visual.json requis — name, position, visual, visualGroup, filterConfig, isHidden…
│           └── mobile.json optionnel, ignoré
└── bookmarks/
    ├── bookmarks.json      optionnel — ordre et groupes
    └── <nom>.bookmark.json
```

- Noms de dossiers : un ou plusieurs caractères « mot » ou tirets. Sinon Desktop les ignore.
- `visual.json` : `position` = `x`, `y`, `z`, `width`, `height` (+ `tabOrder`).
- Un visuel est soit `visual` (avec `visualType`), soit `visualGroup` (groupe).
- `pages.json` absent : ordre des pages non garanti ; on trie par nom de dossier.

### Format PBIR-Legacy (`report.json`)

Schéma **non documenté** par Microsoft. Ce qui suit a été établi en observant des fichiers
produits par Desktop, sans outil Microsoft :

- Racine : `config` (chaîne JSON), `filters` (chaîne JSON), `sections[]`.
- `sections[]` : `name`, `displayName`, `ordinal`, `width`, `height`, `filters` (chaîne JSON),
  `visualContainers[]`.
- `visualContainers[]` : `x`, `y`, `z`, `width`, `height`, `config` (chaîne JSON), `filters` (chaîne JSON).
- `config` d'un visuel : `name`, `layouts[].position`, `singleVisual` ou `singleVisualGroup`.
- `singleVisual.projections` : `{ rôle: [{ queryRef }] }`. Le champ réel est dans
  `singleVisual.prototypeQuery.Select[]` (même `Name` que le `queryRef`), avec un `SourceRef.Source`
  qui est un **alias** déclaré dans `prototypeQuery.From[]` (`Name` → `Entity`).
- Tri : `prototypeQuery.OrderBy[].Expression`.
- Filtres legacy : clé `expression` (au lieu de `field` en PBIR).
- Signets : `config.bookmarks[]` (`name`, `displayName`, `children[]` pour les groupes).
- Thème : `config.themeCollection.customTheme.name` sinon `baseTheme.name`.

### Champs d'un visuel (requête sémantique)

Présents dans `visual.query.queryState.<rôle>.projections[].field`, `filterConfig.filters[].field`,
`visual.query.sortDefinition.sort[].field`. Formes reconnues :

| Clé | Table | Nom |
|---|---|---|
| `Column` | `Expression.SourceRef.Entity` | `Property` |
| `Measure` | idem | `Property` |
| `Aggregation` | descendre dans `Expression.Column` | `Property` |
| `HierarchyLevel` | `Expression.Hierarchy.Expression.SourceRef.Entity` | `Level` (hiérarchie : `Expression.Hierarchy.Hierarchy`) |
| `HierarchyLevel` sur variation | `…Hierarchy.Expression.PropertyVariationSource.Expression.SourceRef.Entity` | `Level`, colonne `PropertyVariationSource.Property` |

`SourceRef` contient soit `Entity` (PBIR), soit `Source` (alias à résoudre par `From`).

## 3. Dossier du modèle sémantique (`<Nom>.SemanticModel/`)

- `definition.pbism` **obligatoire** ; schéma `fabric/item/semanticModel/definitionProperties/1.0.0`.
  `version` `1.0` : TMSL obligatoire ; `4.0` ou plus : TMSL **ou** TMDL.
- `model.bim` : TMSL, objet `Database` (`compatibilityLevel`, `model.tables`, `model.relationships`,
  `model.expressions`, `model.roles`, `model.culture`…). Les expressions peuvent être une chaîne
  ou un tableau de lignes.
- `definition/` : TMDL.
- `diagramLayout.json`, `.pbi/`, `DAXQueries/`, `TMDLScripts/` : ignorés.

## 4. TMDL

### Dossier

Fichiers racine : `database.tmdl`, `model.tmdl`, `relationships.tmdl`, `expressions.tmdl`,
`dataSources.tmdl`, `functions.tmdl`. Sous-dossiers : `tables/`, `roles/`, `perspectives/`, `cultures/`.
La déclaration peut être **partielle** : un objet peut être réparti sur plusieurs fichiers.

### Syntaxe

- Indentation significative, **une tabulation** par niveau par défaut. Niveaux : déclaration,
  propriétés, expressions multi-lignes. Les enfants directs de `model`/`database` ne sont pas indentés.
- Déclaration : `<type> <nom>` ou `<type> <nom> = <propriété par défaut>`.
- Nom entre apostrophes s'il contient `.`, `=`, `:`, `'` ou un espace ; apostrophe doublée.
- Référence qualifiée : notation pointée, `'Table 1'.'Column 1'`.
- Propriété : `clé: valeur`, sur une seule ligne. Guillemets doubles optionnels, retirés à la
  lecture ; `""` échappe un guillemet. Booléen : mot seul = `true`.
- Expression (`=`) : sur la même ligne, ou sur les lignes suivantes indentées **d'un niveau de
  plus que les propriétés** de l'objet. L'indentation extérieure est retirée ; lignes vides
  conservées ; lignes vides finales supprimées.
- Bloc ` ``` ` : lu tel quel ; la ligne de fermeture fixe la marge gauche.
- Description : lignes `///` juste au-dessus de la déclaration, sans ligne vide.
- `ref <type> <nom>` : ordre des collections. Référence vers un fichier absent : ignorée ;
  objet non référencé : ajouté en fin.
- Mots-clés et valeurs d'énumération : **insensibles à la casse** à la lecture.
- Valeurs par défaut des relations (TOM) : `fromCardinality` = many, `toCardinality` = one,
  `crossFilteringBehavior` = oneDirection, `isActive` = true.

## 5. Choix d'implémentation

- **Diagnostic.file** : chemin relatif à la racine du projet (au lieu d'une URL absolue) pour une
  sortie stable et testable par snapshot.
- **Ordre des visuels** : trié par identifiant, pour que les deux formats de rapport donnent le même `Report`.
- **Ordre des champs d'un visuel** : rôles par ordre alphabétique, ordre d'origine dans un rôle,
  puis filtres, puis tri. Doublons exacts supprimés.
- **Rôle d'un champ** : nom du rôle de projection, `filter` ou `sort`.
- **Tables `LocalDateTable_*` / `DateTableTemplate_*`** : lues comme les autres par la CLI. L'app les
  masque, avec leurs relations (tables de date automatiques de Desktop, reconnues à leur nom : le
  lecteur ne conserve pas les annotations).
- **Langue** : documentation en français, sortie de la CLI et diagnostics en anglais.
- **Mesures inutilisées** : ni dans un visuel/filtre, ni référencées par le DAX d'une autre mesure
  (balayage lexical simple des `[Nom]`).

## 6. Incertitudes et écarts avec le prompt

- **PBIR-Legacy non documenté.** La lecture de `report.json` repose sur l'observation de fichiers.
  Elle est tolérante : propriété absente = valeur vide, jamais une erreur bloquante.
- **Coexistence `report.json` + `definition/`.** La doc dit que `definition/` « remplace »
  `report.json`, sans dire explicitement que la coexistence est une erreur. Le prompt la traite
  comme une erreur ; on suit le prompt.
- **Coexistence `model.bim` + `definition/`** : même raisonnement.
- **Versions de schéma connues** (vérifiées sur GitHub le 2026-10-28) : report ≤ 3.x, page ≤ 2.x,
  pagesMetadata 1.x, visualContainer ≤ 2.x, versionMetadata 1.x, bookmark ≤ 2.x,
  definitionProperties (rapport) ≤ 2.x, definitionProperties (modèle) 1.x, pbipProperties 1.x.
  Une version majeure supérieure produit un avertissement, pas une erreur.
- **JSON tolérant.** `JSONSerialization` (Foundation récente) accepte des écarts comme une virgule
  finale. Le lecteur n'est donc pas un validateur de schéma : un fichier accepté ici peut être
  refusé par Desktop.
- **Forme de `bookmarks.json`** : non vérifiée en détail ; on accepte une chaîne, un objet `name`
  ou un groupe `children`.
- **Dossier `.Dataset`.** Les anciens projets nomment le dossier du modèle `<Nom>.Dataset`. Le
  `byPath` est suivi quel que soit le suffixe.
- **`definition.pbidataset`.** Ces mêmes anciens dossiers `.Dataset` contiennent `definition.pbidataset`
  au lieu de `definition.pbism` (absent de la doc actuelle). Il est accepté, avec un diagnostic `info`.
- **`functions.tmdl` (UDF DAX)** : listé par la doc ; lu comme nœud `function`, non exposé dans
  le modèle objet pour l'instant.
- **Nom du modèle publié** : la doc montre deux formes de chaîne de connexion ; l'extraction de
  `initial catalog` est une heuristique.
- **Écart avec le prompt (contrainte « salle blanche »)** : en plus des fichiers fictifs, la
  robustesse du parseur a été vérifiée **localement** sur des projets internes de l'auteur,
  enregistrés par Desktop. Rien n'en est copié dans ce dépôt (ni noms, ni données, ni structure).

## 7. Application (phase 4)

- Cible `PBIPReaderApp` séparée ; `PBIPKit` reste sans dépendance d'interface (la coloration DAX/M
  est un découpage en jetons dans `PBIPKit`, les couleurs sont dans l'application).
- Exécutable SwiftPM sans bundle : la politique d'activation `.regular` est posée dans
  `applicationWillFinishLaunching`.
- Le projet à ouvrir au lancement se passe avec `-project <chemin>` (lu dans `UserDefaults`). Un
  chemin passé seul est interprété par AppKit comme un document à ouvrir, et SwiftUI ne crée alors
  pas la fenêtre initiale (constaté à l'usage).
