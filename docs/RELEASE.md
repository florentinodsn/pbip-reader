# Publier une version

Le `.dmg` est construit, signé et notarisé par GitHub Actions (`.github/workflows/release.yml`)
quand on pousse un tag `vX.Y.Z`. Il est attaché à une Release GitHub sous le nom fixe
`PBIP-Reader.dmg`, si bien que le lien du site vers la dernière version ne change jamais :
`https://github.com/florentinodsn/pbip-reader/releases/latest/download/PBIP-Reader.dmg`.

## À chaque version

1. Changer la version dans `Sources/PBIPKit/PBIPKit.swift` (`PBIPKitVersion.current`), commiter.
2. Créer et pousser le tag correspondant :

   ```bash
   git tag v0.3.0
   git push origin v0.3.0
   ```

Le workflow refuse un tag différent de la version du code, lance les tests, puis publie.

Pour un essai local (non signé, à ne pas distribuer) : `Scripts/make-dmg.sh` → `dist/PBIP-Reader.dmg`.

## Une seule fois : les secrets

Il faut un compte **Apple Developer** (programme payant). Les six secrets se renseignent dans
*Settings → Secrets and variables → Actions* du dépôt, ou avec `gh secret set NOM`.

### Certificat de signature

1. Dans Xcode (*Settings → Accounts → Manage Certificates*) ou sur developer.apple.com, créer un
   certificat **Developer ID Application**.
2. Dans *Trousseaux d'accès*, exporter ce certificat **avec sa clé privée** au format `.p12`,
   protégé par un mot de passe.
3. Renseigner :

| Secret | Valeur |
|---|---|
| `MACOS_CERTIFICATE_P12` | le fichier `.p12` en base64 : `base64 -i certificat.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | le mot de passe du `.p12` |
| `MACOS_SIGN_IDENTITY` | le nom complet, par exemple `Developer ID Application: Prénom Nom (ABCDE12345)` (`security find-identity -v -p codesigning`) |

### Clé de notarisation

1. Sur App Store Connect, *Users and Access → Integrations → App Store Connect API*, créer une clé
   avec le rôle **Developer** et télécharger le fichier `AuthKey_XXXXXXXXXX.p8` (une seule fois).
2. Renseigner :

| Secret | Valeur |
|---|---|
| `NOTARY_KEY_P8` | le fichier `.p8` en base64 : `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` |
| `NOTARY_KEY_ID` | l'identifiant de la clé (10 caractères) |
| `NOTARY_ISSUER_ID` | l'« Issuer ID » affiché en haut de la page des clés |

Si un secret manque, le workflow échoue au lieu de publier un `.dmg` non signé.
