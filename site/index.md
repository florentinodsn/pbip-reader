---
title: PBIP Reader
lang: fr
---

**Français** · [English](en.html)

<img src="assets/icon.png" alt="" width="128" height="128">

## Lisez vos projets PBIP sur votre Mac

Modèle de données, mesures DAX, relations, pages et visuels : tout un projet PBIP en un coup
d'œil, **sans rien modifier**. Une application native et une ligne de commande, gratuites et open
source.

**[⬇ Télécharger pour macOS](https://github.com/florentinodsn/pbip-reader/releases/latest/download/PBIP-Reader.dmg)**
· [Installer depuis les sources](#installer-depuis-les-sources)
· [Code source](https://github.com/florentinodsn/pbip-reader)

macOS 13 ou plus · Apple Silicon et Intel · licence MIT

![Diagramme du modèle, avec le détail d'une relation au survol](assets/diagram.png)

## Fonctionnalités

On ouvre un fichier `.pbip` ou un dossier `.Report` / `.SemanticModel` : PBIR et PBIR-Legacy,
TMDL et `model.bim`.

- **Diagramme du modèle** : tables de faits en haut et dimensions à gauche, ou disposition en
  étoile / flocon. Le survol d'un lien affiche la relation.
- **Mesures et dossiers** : toutes les mesures par dossier d'affichage, DAX coloré, recherche, et
  où chacune est utilisée dans le rapport.
- **Fonctions DAX** définies par l'utilisateur : paramètres, types, valeurs par défaut, corps et
  appelants.
- **Relations** filtrables par table ou par colonne, avec cardinalité et sens du filtrage.
- **Pages et visuels** : un aperçu de chaque page d'après la position des visuels, et les champs
  de chaque visuel.
- **Lecture seule et diagnostics** : aucun fichier n'est jamais modifié ; références cassées,
  champs inconnus et mesures inutilisées sont signalés.

| | |
|---|---|
| ![Disposition « Étoile / flocon »](assets/star.png) | ![Mesures par dossier d'affichage](assets/measures.png) |
| Disposition « Étoile / flocon » | Mesures par dossier d'affichage |
| ![Pages et visuels](assets/pages.png) | ![Fonctions DAX](assets/functions.png) |
| Pages et visuels | Fonctions DAX définies par l'utilisateur |

## Installation

L'application ne demande aucun compte et ne se connecte à rien.

### Télécharger l'application (le plus simple)

1. **Télécharger** [PBIP-Reader.dmg](https://github.com/florentinodsn/pbip-reader/releases/latest/download/PBIP-Reader.dmg).
2. **L'ouvrir** et glisser « PBIP Reader » sur le dossier Applications.
3. **La lancer** depuis le Launchpad ou Spotlight, puis `⌘O` pour ouvrir un projet.

L'application est signée et notarisée par Apple. Toutes les versions sont sur la page des
[releases](https://github.com/florentinodsn/pbip-reader/releases).

### Installer depuis les sources

Une fois, si les outils de développement d'Apple ne sont pas installés :

```bash
xcode-select --install
```

Puis, pour que l'application arrive dans le dossier Applications :

```bash
git clone https://github.com/florentinodsn/pbip-reader.git
cd pbip-reader
Scripts/make-app.sh /Applications
```

Pour la mettre à jour : `git pull`, puis la même dernière commande.

## Ligne de commande

Les mêmes informations en texte, JSON ou Markdown, et une commande `validate` pensée pour la CI.
Installation, depuis le dossier `pbip-reader` :

```bash
swift build -c release
sudo mkdir -p /usr/local/bin
sudo cp .build/release/pbip /usr/local/bin/
```

```bash
pbip info     MonRapport.pbip    # formats, pages, visuels, tables, mesures
pbip model    MonRapport.pbip    # tables, colonnes, DAX, relations, M, fonctions
pbip report   MonRapport.pbip    # pages et visuels avec leurs champs
pbip lineage  MonRapport.pbip    # qui utilise quoi, dans les deux sens
pbip validate MonRapport.pbip    # diagnostics, code de sortie 1 en cas d'erreur
```

---

Licence MIT · [code source](https://github.com/florentinodsn/pbip-reader)

Ce projet n'est ni affilié à Microsoft ni approuvé par Microsoft. Power BI est une marque de
Microsoft Corporation.
