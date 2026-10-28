# Projets d'exemple fictifs

Tous ces projets sont **inventés** : noms génériques, aucune donnée, aucun identifiant ni chaîne
de connexion réels. Ils sont gardés octet pour octet (`.gitattributes`) : CRLF et BOM font partie des tests.

| Dossier | Contenu | Attendu |
|---|---|---|
| `Ventes` | PBIR + TMDL (CRLF). 3 tables, 5 mesures, 2 relations, 2 pages, 6 visuels, 1 paramètre M, 1 colonne calculée, 1 hiérarchie, 1 rôle, 1 culture, 1 signet, 2 fonctions DAX (niveau de compatibilité 1702) | aucun diagnostic d'erreur ; `Total HT N-1` inutilisée |
| `VentesLegacy` | même contenu en `report.json` + `model.bim` | même `Report` et même `SemanticModel` que `Ventes` |
| `Publie` | rapport `byConnection`, sans modèle local, avec une mesure de rapport | rapport lu seul, modèle publié nommé |
| `Conflit` | `report.json` **et** `definition/` ; `model.bim` **et** `definition/` | deux erreurs de formats en conflit |
| `RefCassee` | mesure, table et colonne absentes ; relation vers une table absente ; mot-clé TMDL inconnu ; version de schéma inconnue ; `ref table` sans fichier | erreurs de références, avertissements |
| `JsonInvalide` | un `page.json` invalide, un `page.json` avec BOM | erreur JSON, avertissement BOM, lecture du reste |
