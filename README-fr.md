# Déploiement Auto-hébergé Grist

Une configuration Docker Compose pour déployer [Grist](https://www.getgrist.com/) (tableur collaboratif open-source) derrière un reverse proxy OpenResty avec une authentification personnalisée basée sur Lua.

## Démarrage Rapide

0. **Installer Docker, Docker Compose, et htpasswd**

- Docker / Docker Compose : cf. [documentation Docker](https://docs.docker.com/engine/install/debian/)
- htpasswd : `apt install apache2-utils`
 
1. **Copier et éditer le fichier d'environnement :**
   ```sh
   cp .env.sample .env
   # Éditez .env avec votre domaine, email, paramètres SSL, etc.
   ```
   **N.B. :** Assurez-vous que votre nom de domaine (défini dans `.env`) pointe bien vers l'adresse IP publique de votre serveur (enregistrements A/AAAA).

2. **Créer le fichier des utilisateurs** (ou copier l'exemple) :
   ```sh
   cp users.sample users
   # Ajoutez des utilisateurs avec htpasswd. Doit contenir au moins l'email défini dans .env :
   htpasswd users user@example.com
   htpasswd -D users you@example.com  # supprime l'utilisateur défini comme exemple
   ```

3. **Créer le fichier de sessions** (ou copier l'exemple) :
   ```sh
   cp sessions.sample sessions
   ```

4. **Exposer le service** (choisissez une option) :

   - **4a. Mapping de port direct** (Le plus rapide, mappe 80/443 directement au conteneur) :
     ```sh
     cp compose.override.yaml.sample compose.override.yaml
     ```

   - **4b. Reverse Proxy Hôte** (Reverse Proxy Hôte (Recommandé si vous avez déjà Nginx sur l'hôte) :
     Voir [nginx_grist.sample](nginx_grist.sample). C'est un exemple pour Debian (`/etc/nginx/sites-enabled/`).
     **À modifier :**
     - Remplacez `db.MON.DOMAINE` par votre propre domaine.
     - Assurez-vous que les chemins des certificats SSL pointent vers vos certificats (ex: Let's Encrypt).
     - Notez qu'il redirige vers `172.63.63.20` (l'IP fixe du conteneur `nginx`).

5. **Construire l'image OpenResty personnalisée :**
   Si vous rencontrez des erreurs réseau lors du build (problèmes DNS/MTU), utilisez `--network=host` :
   ```sh
   docker build --network=host -t grist-nginx openresty
   ```

6. **Démarrer les services :**
   ```sh
   docker compose up -d
   ```

## Architecture

```
┌──────────────┐          ┌──────────────────────┐          ┌──────────────┐
│   Clients    │──HTTP/S─▶│  OpenResty (nginx)   │──proxy──▶│   Grist OSS  │
│              │          │  172.63.63.20        │  :8484   │  172.63.63.10│
└──────────────┘          └──────────────────────┘          └──────┬───────┘
                          │ sert /_static/                 ┌─────▼──────┐
                          │ gère /login, /logout           │  persist/  │
                          │ gère /credentials              │  (SQLite)  │
                          │ ACME/Let's Encrypt             └────────────┘
```

| Service   | Image                              | Rôle                                            |
|-----------|------------------------------------|-------------------------------------------------|
| **nginx** | `openresty/openresty:alpine` (build) | Terminaison HTTPS, authentification, fichiers statiques |
| **grist** | `gristlabs/grist-oss:latest`       | Application Grist (port 8484)                   |

## Configuration

### Variables d'Environnement (`.env`)

| Variable      | Description                                      | Exemple                        |
|---------------|--------------------------------------------------|--------------------------------|
| `DOMAIN`      | Nom de domaine public                            | `grist.exemple.com`            |
| `URL`         | URL publique complète                            | `https://grist.exemple.com`    |
| `ORG`         | Nom de l'organisation Grist                      | `monorg`                       |
| `EMAIL`       | Email de contact (utilisé pour Let's Encrypt)    | `admin@exemple.com`            |
| `TELEMETRY`   | Niveau de télémétrie                             | `limited`                      |
| `DEBUG`       | Mode debug                                       | `1`                            |
| `HTTPS`       | `auto` (Let's Encrypt) ou `manual` (propres certs)| `auto`                         |
| `STAGING`     | Utiliser le staging Let's Encrypt (`true`/`false`)| `true`                         |
| `SSL_CERT`    | Chemin du cert SSL (si `HTTPS=manual`)           | `/opt/ssl/fullchain.cer`       |
| `SSL_KEY`     | Chemin de la clé SSL (si `HTTPS=manual`)         | `/opt/ssl/domain.key`          |

### Modes HTTPS

- **`auto`** : Les certificats sont obtenus et renouvelés automatiquement via ACME (utilise `lua-resty-acme`).
- **`manual`** : Fournissez vos propres certificat et clé via `SSL_CERT` et `SSL_KEY`.

### Fournisseurs ACME

Lorsque `HTTPS=auto`, vous pouvez choisir entre plusieurs fournisseurs via la variable `ACME_PROVIDER` :

- **`letsencrypt`** (Défaut) : Les limites de fréquence standard s'appliquent.
- **`actalis`** : Certificats SSL gratuits d'Actalis. Nécessite des identifiants **EAB**.
  - [Documentation ACME Actalis](https://www.actalis.com/en/acme-service)
- **`zerossl`** : Nécessite des identifiants **External Account Binding (EAB)**.
  - [Documentation EAB ZeroSSL](https://zerossl.com/documentation/acme/)
- **`google`** : Google Trust Services. Nécessite des identifiants **EAB** de Google Cloud.
  - [Documentation EAB GTS](https://cloud.google.com/public-certificate-authority/docs/how-to/request-eab-key)

Pour Actalis, ZeroSSL et Google, vous devez définir `EAB_KID` et `EAB_HMAC_KEY` dans votre `.env`.

## Authentification

L'authentification est gérée entièrement par le Lua embarqué d'OpenResty, **pas** par l'authentification intégrée de Grist. Elle utilise le header `x-forwarded-user`.

### Fonctionnement

1. Les utilisateurs visitent `/login` et soumettent leur email et mot de passe.
2. Les identifiants sont vérifiés par rapport au fichier `users` (format htpasswd).
3. En cas de succès, un jeton est généré, stocké dans un fichier `sessions` persistant (pour que les sessions survivent aux redémarrages), et défini comme cookie `gristauth`.
4. Pour les requêtes suivantes, le jeton est recherché pour résoudre l'email de l'utilisateur, qui est ensuite transmis à Grist via le header `x-forwarded-user`.

### Gestion des Comptes

Le point d'accès `/credentials` permet de gérer les comptes et les mots de passe :

- **Création d'un nouveau compte** : Tout le monde peut créer un compte tant que l'email n'existe pas déjà.
- **Changement de mot de passe** : Tout utilisateur connecté peut changer son propre mot de passe.
- **Accès Admin** : Les utilisateurs listés comme "owners" (propriétaires) dans la base de données interne de Grist (`home.sqlite3`) peuvent changer le mot de passe de n'importe quel utilisateur.
- **Configuration Initiale** : Si aucun propriétaire Grist n'a encore configuré de mot de passe, `/credentials` est ouvert pour permettre au premier propriétaire de s'enregistrer.

### Points d'accès (Endpoints)

| Chemin         | Méthode  | Description                              |
|----------------|----------|------------------------------------------|
| `/login`       | GET/POST | Formulaire de connexion et authentification |
| `/logout`      | GET      | Efface la session persistante et redirige |
| `/credentials` | GET/POST | Création de compte ou changement de mot de passe |

## Maintenance

Exécutez `grist-maintenance.sh` pour :

1. Supprimer les fichiers de sauvegarde (`*-backup.grist`)
2. Élaguer l'historique des documents (garde les 10 dernières versions)
3. Télécharger les dernières images Docker
4. Redémarrer les services
5. Nettoyer les ressources Docker inutilisées

```sh
./grist-maintenance.sh
```

## Structure du Répertoire

```
.
├── compose.yaml            # Configuration Docker Compose
├── nginx.conf              # Config OpenResty/Nginx avec logique Lua
├── .env                    # Variables d'env (non committé)
├── .env.sample             # Modèle d'environnement
├── users                   # Base utilisateurs htpasswd (non committé)
├── users.sample            # Modèle htpasswd
├── sessions                # Stockage des sessions (non committé)
├── ssl/                    # Certificats auto-signés de secours
├── grist-maintenance.sh    # Script de maintenance
├── openresty/
│   └── Dockerfile          # Image OpenResty (avec ACME, htpasswd, sqlite)
├── persist/                # Données Grist (SQLite, docs .grist)
└── _static/                # Fichiers statiques
```

## Licence

Cette configuration de déploiement est fournie en l'état. Grist lui-même est sous [Licence Apache 2.0](https://github.com/gristlabs/grist-core/blob/main/LICENSE).
