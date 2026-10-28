## Ventes

Lignes de vente fictives.

### Columns

| Name | Type | Source | Format | Hidden |
|---|---|---|---|---|
| Date | dateTime | Date | General Date |  |
| Code Produit | string | Code Produit |  |  |
| Quantité | int64 | Quantité | 0 |  |
| Prix unitaire | decimal | Prix unitaire | 0.00 "€" |  |
| Montant HT | decimal | `Ventes[Quantité] * Ventes[Prix unitaire]` | #,##0.00 € | yes |

### Measures

#### Total HT

Chiffre d'affaires hors taxes.

format `#,##0.00 €`

```dax
SUM(Ventes[Montant HT])
```

#### Quantité vendue

format `0`

```dax
SUM(Ventes[Quantité])
```

#### Panier moyen

format `#,##0.00 €` · folder *Indicateurs*

```dax
VAR nb = DISTINCTCOUNT(Ventes[Date])
RETURN
	DIVIDE([Total HT], nb)
```

#### Total HT N-1

format `#,##0.00 €`

```dax
CALCULATE(
	[Total HT],
	SAMEPERIODLASTYEAR('Calendrier'[Date])
)
```

#### Marge %

Marge estimée, coût fictif à 60 % du prix.
Sert d'exemple de description sur deux lignes.

format `0.0 %` · folder *Indicateurs*

```dax
DIVIDE([Total HT] - SUMX(Ventes, Ventes[Quantité] * Ventes[Prix unitaire] * 0.6), [Total HT])
```

### Partitions

- **Ventes** (m, import)

```powerquery
let
	Source = Csv.Document(File.Contents(#"Dossier source" & "/ventes.csv"), [Delimiter=";", Encoding=65001]),
	Typé = Table.TransformColumnTypes(Source, {{"Quantité", Int64.Type}})
in
	Typé
```

## Produits

### Columns

| Name | Type | Source | Format | Hidden |
|---|---|---|---|---|
| Code Produit | string | Code Produit |  |  |
| Libellé | string | Libellé |  |  |
| Catégorie | string | Catégorie |  |  |

### Hierarchies

- **Gamme**: Catégorie › Libellé

### Partitions

- **Produits** (m, import)

```powerquery
let
	Source = Csv.Document(File.Contents(#"Dossier source" & "/produits.csv"), [Delimiter=";", Encoding=65001])
in
	Source
```

## Calendrier

### Columns

| Name | Type | Source | Format | Hidden |
|---|---|---|---|---|
| Date | dateTime | [Date] | General Date |  |
| Année | int64 | [Année] | 0 |  |

### Partitions

- **Calendrier** (calculated, import)

```dax
ADDCOLUMNS(
	CALENDAR(DATE(2024, 1, 1), DATE(2025, 12, 31)),
	"Année", YEAR([Date])
)
```

## Relationships

| From | To | Cardinality | Cross filter | Active |
|---|---|---|---|---|
| Ventes[Code Produit] | Produits[Code Produit] | many:one | bothDirections | yes |
| Ventes[Date] | Calendrier[Date] | many:one | oneDirection | yes |

## Expressions

### Dossier source (parameter)

```powerquery
"/exemple/donnees" meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true]
```

## Functions

### Fiscalite.AppliquerTVA

Applique un taux de TVA (20 % par défaut) à un montant hors taxes.

```dax
(montant : NUMERIC, taux : NUMERIC = 0.2) =>
	montant * ( 1 + taux )
```

### MontantTTC

```dax
(montantHT : SCALAR NUMERIC VAL) =>
	ROUND ( Fiscalite.AppliquerTVA ( montantHT ), 2 )
```

## Roles

- **Lecteurs France** (read)
  - Produits: `Produits[Catégorie] <> "Interne"`
