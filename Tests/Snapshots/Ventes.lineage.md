## Model objects → report

| Object | Kind | Used by | Referenced by | References |
|---|---|---|---|---|
| Ventes[Total HT] | measure | Synthèse › card "Chiffre d'affaires HT" (Values)<br>Synthèse › lineChart "Évolution du CA" (Y) | Ventes[Panier moyen]<br>Ventes[Total HT N-1]<br>Ventes[Marge %] | Ventes[Montant HT] |
| Ventes[Quantité vendue] | measure | Synthèse › card c1000000000000000002 (Values) |  | Ventes[Quantité] |
| Ventes[Panier moyen] | measure | Détail produits › tableEx "Ventes par produit" (Values) |  | Ventes[Date]<br>Ventes[Total HT] |
| Ventes[Total HT N-1] | measure |  |  | Ventes[Total HT]<br>Calendrier[Date] |
| Ventes[Marge %] | measure | Détail produits › clusteredBarChart "Marge par catégorie" (Y) |  | Ventes[Total HT]<br>Ventes[Quantité]<br>Ventes[Prix unitaire] |
| Ventes[Date] | column |  | Ventes[Panier moyen] |  |
| Ventes[Quantité] | column | Détail produits › tableEx "Ventes par produit" (Values) | Ventes[Quantité vendue]<br>Ventes[Marge %]<br>Ventes[Montant HT] |  |
| Ventes[Prix unitaire] | column |  | Ventes[Marge %]<br>Ventes[Montant HT] |  |
| Ventes[Montant HT] | column |  | Ventes[Total HT] | Ventes[Quantité]<br>Ventes[Prix unitaire] |
| Produits[Libellé] | column | Détail produits › tableEx "Ventes par produit" (Values) |  |  |
| Produits[Catégorie] | column | Détail produits › page filter (filter)<br>Détail produits › clusteredBarChart "Marge par catégorie" (Category)<br>Détail produits › clusteredBarChart "Marge par catégorie" (filter) |  |  |
| Calendrier[Date] | column |  | Ventes[Total HT N-1] |  |
| Calendrier[Année] | column | report filter (filter)<br>Synthèse › lineChart "Évolution du CA" (Category)<br>Synthèse › lineChart "Évolution du CA" (sort)<br>Synthèse › slicer c1000000000000000004 (Values) |  |  |

## Report → model objects

| Page | Visual | Role | Field | Status |
|---|---|---|---|---|
| Synthèse | card "Chiffre d'affaires HT" | Values | Ventes[Total HT] | ok |
| Synthèse | card | Values | Ventes[Quantité vendue] | ok |
| Synthèse | lineChart "Évolution du CA" | Category | Calendrier[Année] | ok |
| Synthèse | lineChart "Évolution du CA" | Y | Ventes[Total HT] | ok |
| Synthèse | lineChart "Évolution du CA" | sort | Calendrier[Année] | ok |
| Synthèse | slicer | Values | Calendrier[Année] | ok |
| Détail produits | tableEx "Ventes par produit" | Values | Produits[Libellé] | ok |
| Détail produits | tableEx "Ventes par produit" | Values | Ventes[Quantité] | ok |
| Détail produits | tableEx "Ventes par produit" | Values | Ventes[Panier moyen] | ok |
| Détail produits | clusteredBarChart "Marge par catégorie" | Category | Produits[Gamme].[Catégorie] | ok |
| Détail produits | clusteredBarChart "Marge par catégorie" | Y | Ventes[Marge %] | ok |
| Détail produits | clusteredBarChart "Marge par catégorie" | filter | Produits[Catégorie] | ok |
