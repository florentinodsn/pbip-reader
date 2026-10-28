# Construire et publier l'application

Ce document explique comment on passe du code source à un `PBIP-Reader.dmg` que n'importe qui peut
télécharger et ouvrir sans avertissement de macOS, et comment publier une nouvelle version.

En bref : on pousse un tag `vX.Y.Z`, GitHub Actions fait le reste. Le `.dmg` est attaché à une
Release GitHub sous le nom fixe `PBIP-Reader.dmg`, si bien que le lien du site vers la dernière
version ne change jamais :
`https://github.com/florentinodsn/pbip-reader/releases/latest/download/PBIP-Reader.dmg`.

## Publier une version

1. Changer la version dans `Sources/PBIPKit/PBIPKit.swift` (`PBIPKitVersion.current`), commiter et
   pousser. C'est la seule source de la version : la CLI (`pbip --version`), le `Info.plist` de l'app
   et le nom du volume du `.dmg` la reprennent.
2. Créer et pousser le tag correspondant :

   ```bash
   git tag -a v0.3.0 -m "PBIP Reader 0.3.0"
   git push origin v0.3.0
   ```

3. Suivre le workflow dans l'onglet *Actions* (ou `gh run watch`). Une dizaine de minutes en
   général, davantage si les machines macOS de GitHub sont chargées.

Le workflow refuse un tag différent de la version du code, et échoue si un secret manque : il ne
publie jamais un `.dmg` non signé.

## Comment ça marche

### La chaîne de construction

```
Scripts/make-icon.swift   dessine l'icône (PNG 1024 px, AppKit, sans ressource externe)
        │
Scripts/make-app.sh       compile l'app, assemble « PBIP Reader.app », icône .icns, Info.plist
        │                 et la signe si SIGN_IDENTITY est fourni
Scripts/make-dmg.sh       app universelle + raccourci Applications → PBIP-Reader.dmg,
                          puis signature, notarisation et agrafage si les variables sont fournies
```

**`make-app.sh`** compile la cible SwiftPM `pbip-reader-app` en version optimisée. Avec
`UNIVERSAL=1`, le binaire contient les deux architectures (Apple Silicon `arm64` et Intel `x86_64`),
ce qu'on vérifie avec `lipo -archs`. Le script crée l'arborescence d'une app macOS :

```
PBIP Reader.app/Contents/
├── Info.plist          nom, identifiant io.github.florentinodsn.pbip-reader, version, icône
├── MacOS/pbip-reader-app
└── Resources/AppIcon.icns   tailles 16 à 1024 px, produites par sips et iconutil
```

**`make-dmg.sh`** place l'app et un lien vers `/Applications` dans un dossier, puis en fait une image
disque compressée avec `hdiutil` (outil de macOS). À l'ouverture du `.dmg`, l'utilisateur glisse
l'app sur le raccourci : c'est l'installation.

Aucun de ces outils n'est une dépendance à installer : `swift`, `sips`, `iconutil`, `hdiutil`,
`codesign`, `notarytool`, `stapler` et `spctl` sont fournis avec macOS et les outils de développement
d'Apple.

### Signature, notarisation, Gatekeeper

macOS (Gatekeeper) contrôle toute app téléchargée depuis Internet. Une app ni signée ni notarisée
est bloquée au premier lancement. Pour qu'elle s'ouvre directement, trois étapes :

1. **Signature** (`codesign`) avec un certificat **Developer ID Application**, délivré par Apple
   aux membres du programme Apple Developer. Elle garantit l'auteur et que l'app n'a pas été
   modifiée. L'app est signée avec le **runtime renforcé** (`--options runtime`) et un horodatage
   (`--timestamp`), exigés par la notarisation ; le `.dmg` est signé aussi.
2. **Notarisation** (`xcrun notarytool submit --wait`) : le `.dmg` est envoyé à Apple, qui l'analyse
   automatiquement (logiciel malveillant, signature, runtime renforcé) et répond `Accepted` ou
   `Invalid`, en quelques minutes. L'authentification se fait par une clé d'API App Store Connect,
   pas par l'identifiant Apple.
3. **Agrafage** (`xcrun stapler staple`) : le ticket d'Apple est attaché au `.dmg`, pour que
   Gatekeeper le valide même hors ligne.

Le script termine par `spctl --assess`, qui joue le rôle de Gatekeeper : la sortie attendue est
`accepted` et `source=Notarized Developer ID`.

### Le workflow `release.yml`

Déclenché par un tag `v*`, sur une machine macOS de GitHub :

| Étape | Rôle |
|---|---|
| Tag égal à la version du code | refuse `v0.3.0` si `PBIPKitVersion.current` vaut autre chose |
| Tests | `swift test` |
| Certificat et clé | vérifie les six secrets ; importe le `.p12` dans un trousseau temporaire ; écrit la clé `.p8` dans un fichier temporaire |
| Construire, signer et notariser | `Scripts/make-dmg.sh` avec les variables de signature |
| Release GitHub | `gh release create` avec le `.dmg` et des notes générées depuis les commits |
| Nettoyage | supprime le trousseau temporaire et la clé, même en cas d'échec |

Les secrets ne quittent jamais la machine de build : ils ne sont ni affichés dans les journaux
(GitHub les masque) ni écrits dans le dépôt.

## Essais en local

Sans signature, pour vérifier la construction (à ne pas distribuer) :

```bash
Scripts/make-dmg.sh              # → dist/PBIP-Reader.dmg
```

Avec signature et notarisation, comme la CI, sur un Mac où le certificat est dans le trousseau :

```bash
SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)" \
NOTARY_KEY_PATH=~/chemin/AuthKey_XXXXXXXXXX.p8 NOTARY_KEY_ID=XXXXXXXXXX NOTARY_ISSUER=issuer-id \
Scripts/make-dmg.sh
```

Pour seulement installer l'app sur sa propre machine, sans `.dmg` : `Scripts/make-app.sh /Applications`.
Compilée localement, elle n'est pas mise en quarantaine et s'ouvre sans signature.

## En cas d'échec

| Symptôme | Piste |
|---|---|
| « Le tag … ne correspond pas à la version » | mettre à jour `PBIPKitVersion.current`, ou supprimer le tag (`git push --delete origin vX.Y.Z`, `git tag -d vX.Y.Z`) et le recréer |
| « Secret … manquant » | le renseigner (section suivante) puis relancer le workflow (*Re-run jobs*) |
| `security import` échoue | mauvais mot de passe du `.p12`, ou `.p12` exporté sans sa clé privée |
| `codesign` : « no identity found » | `MACOS_SIGN_IDENTITY` doit reprendre exactement le nom affiché par `security find-identity` |
| notarisation `Invalid` | `xcrun notarytool log <id> --key … --key-id … --issuer …` donne la raison détaillée |
| job annulé sans avoir démarré | machines macOS de GitHub saturées : relancer plus tard |

Le certificat Developer ID est valable cinq ans ; la clé d'API n'expire pas mais peut être révoquée
sur App Store Connect. Après un renouvellement, remettre à jour les secrets concernés.

## Une seule fois : les secrets

Il faut un compte **Apple Developer** (programme payant). Les six secrets se renseignent dans
*Settings → Secrets and variables → Actions* du dépôt, ou avec `gh secret set NOM`.

### Certificat de signature

1. Dans Xcode (*Réglages → Comptes → Gérer les certificats… → + → Developer ID Application*) ou sur
   developer.apple.com, créer un certificat **Developer ID Application**. Seul le titulaire du
   compte (*Account Holder*) peut le faire.
2. Ouvrir *Trousseaux d'accès* : sur les versions récentes de macOS, il n'est plus dans Utilitaires
   mais se lance par Spotlight, ou par
   `open "/System/Library/CoreServices/Applications/Keychain Access.app"`. Dans *session → Mes
   certificats*, exporter le certificat **avec sa clé privée** au format `.p12`, protégé par un mot
   de passe.
3. Renseigner, depuis le dossier du dépôt :

   ```bash
   base64 -i certificat.p12 | gh secret set MACOS_CERTIFICATE_P12
   gh secret set MACOS_CERTIFICATE_PASSWORD     # demande le mot de passe sans l'afficher
   gh secret set MACOS_SIGN_IDENTITY --body "$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"
   ```

### Clé de notarisation

1. Sur App Store Connect, *Utilisateurs et accès → Intégrations → App Store Connect API*, créer une
   clé d'équipe avec le rôle **Developer** (le plus restreint qui suffise) et télécharger le fichier
   `AuthKey_XXXXXXXXXX.p8` : Apple ne le propose qu'une fois.
2. Renseigner :

   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_KEY_P8
   gh secret set NOTARY_KEY_ID --body XXXXXXXXXX          # « ID de clé », 10 caractères
   gh secret set NOTARY_ISSUER_ID --body issuer-id        # « Issuer ID », en haut de la page
   ```

`gh secret list` affiche ensuite les six noms (jamais les valeurs). Une fois les secrets en place,
ranger le `.p12` et le `.p8` en lieu sûr ou les supprimer du disque.
