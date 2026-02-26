# Grist Self-Hosted Deployment

A Docker Compose setup for deploying [Grist](https://www.getgrist.com/) (open-source collaborative spreadsheet) behind an OpenResty reverse proxy with custom Lua-based authentication.

## Quick Start

0. **Install Docker, Docker Compose, and htpasswd**

- Docker / Docker Compose: cf. [Docker documentation](https://docs.docker.com/engine/install/debian/)
- htpasswd: `apt install apache2-utils`
 
1. **Copy and edit the environment file:**
   ```sh
   cp .env.sample .env
   # Edit .env with your domain, email, SSL settings, etc.
   ```
   **N.B.:** Ensure your domain name (as set in `.env`) points to your server's public IP address (A/AAAA records).

2. **Create the users file** (or copy the sample):
   ```sh
   cp users.sample users
   # Add users with htpasswd. Must contain at least the email defined in .env:
   htpasswd users user@example.com
   htpasswd -D users you@example.com  # remove the example user
   ```

3. **Create the sessions file** (or copy the sample):
   ```sh
   cp sessions.sample sessions
   ```

4. **Expose the service** (choose one):

   - **4a. Direct port mapping** (Fastest, maps 80/443 directly to the container):
     ```sh
     cp compose.override.yaml.sample compose.override.yaml
     ```

   - **4b. Host Reverse Proxy** (Recommended if you already have Nginx on the host):
     See [nginx_grist.sample](nginx_grist.sample). This is an example for Debian (`/etc/nginx/sites-enabled/`).
     **What to modify:**
     - Replace `db.MY.DOMAIN` with your own domain.
     - Ensure the SSL certificate paths point to your actual certs (e.g., Let's Encrypt).
     - Note that it proxies to `172.63.63.20` (the fixed IP of the `nginx` container).

5. **Build the Custom OpenResty Image:**
   If you encounter network errors during build (DNS/MTU issues), use `--network=host`:
   ```sh
   docker build --network=host -t grist-nginx openresty
   ```

6. **Start the services:**
   ```sh
   # Assuming docker-ce as per https://docs.docker.com/engine/install/debian/: docker from standard repository behaves a little differently from docker-ce.
   docker compose up -d
   ```

## Architecture

```
┌──────────────┐          ┌──────────────────────┐          ┌──────────────┐
│   Clients    │──HTTP/S─▶│  OpenResty (nginx)   │──proxy──▶│   Grist OSS  │
│              │          │  172.63.63.20        │  :8484   │  172.63.63.10│
└──────────────┘          └──────────────────────┘          └──────┬───────┘
                          │ serves /_static/                 ┌─────▼──────┐
                          │ handles /login, /logout          │  persist/  │
                          │ handles /credentials             │  (SQLite)  │
                          │ ACME/Let's Encrypt               └────────────┘
```

| Service   | Image                              | Role                                            |
|-----------|------------------------------------|-------------------------------------------------|
| **nginx** | `openresty/openresty:alpine` (custom build) | HTTPS termination, authentication, static files |
| **grist** | `gristlabs/grist-oss:latest`       | Grist application (port 8484)                   |

## Configuration

### Environment Variables (`.env`)

| Variable      | Description                                      | Example                        |
|---------------|--------------------------------------------------|--------------------------------|
| `DOMAIN`      | Public domain name                               | `grist.example.com`            |
| `URL`         | Full public URL                                  | `https://grist.example.com`    |
| `ORG`         | Grist organization name                          | `myorg`                        |
| `EMAIL`       | Contact email (used for ACME/Let's Encrypt)      | `admin@example.com`            |
| `TELEMETRY`   | Telemetry level                                  | `limited`                      |
| `DEBUG`       | Debug mode                                       | `1`                            |
| `HTTPS`       | `auto` (Let's Encrypt) or `manual` (own certs)   | `auto`                         |
| `STAGING`     | Use Let's Encrypt staging (`true`/`false`)       | `true`                         |
| `SSL_CERT`    | Path to SSL certificate (when `HTTPS=manual`)    | `/opt/ssl/fullchain.cer`       |
| `SSL_KEY`     | Path to SSL private key (when `HTTPS=manual`)    | `/opt/ssl/domain.key`          |
| `WIDGETS_URL` | Optional URL for custom widgets list             | `https://widgets.example.com`  |

### HTTPS Modes

- **`auto`**: Certificates are automatically obtained and renewed via ACME (using `lua-resty-acme`).
- **`manual`**: Provide your own certificate and key via `SSL_CERT` and `SSL_KEY`.

### ACME Providers

When `HTTPS=auto`, you can choose between several providers via the `ACME_PROVIDER` variable:

- **`letsencrypt`** (Default): Standard rate limits apply.
- **`actalis`**: Free SSL certificates from Actalis. Requires **EAB** credentials.
  - [Actalis ACME Documentation](https://guide.actalis.com/ssl/activation/acme)
- **`zerossl`**: Requires **External Account Binding (EAB)** credentials. 
  - [ZeroSSL EAB Documentation](https://zerossl.com/documentation/acme/)
- **`google`**: Google Trust Services. Requires **EAB** credentials from Google Cloud.
  - [GTS EAB Documentation](https://docs.cloud.google.com/certificate-manager/docs/public-ca-tutorial)

For Actalis, ZeroSSL and Google, you must set `EAB_KID` and `EAB_HMAC_KEY` in your `.env`.

## Authentication

Authentication is handled entirely by OpenResty's embedded Lua, **not** by Grist's built-in auth. It uses the `x-forwarded-user` forward auth header.

### How It Works

1. Users visit `/login` and submit their email and password.
2. Credentials are verified against the `users` file (htpasswd format).
3. On success, a token is generated, stored in a persistent `sessions` file (so logins survive service restarts), and set as the `gristauth` cookie.
4. On subsequent requests, the token is looked up to resolve the user email, which is then forwarded to Grist via the `x-forwarded-user` header.

### Account Management

The `/credentials` endpoint allows managing accounts and passwords:

- **Create a new account**: Anyone can create an account as long as the email doesn't already exist.
- **Change own password**: Any logged-in user can change their own password.
- **Admin access**: Users listed as "owners" in Grist's internal database (`home.sqlite3`) can change any user's password.
- **Initial Setup**: If no Grist owner has set up a password yet, the `/credentials` endpoint is open to allow the initial owner to register.

### Endpoints

| Path           | Method   | Description                              |
|----------------|----------|------------------------------------------|
| `/login`       | GET/POST | Login form and authentication            |
| `/logout`      | GET      | Clear persistent session and redirect    |
| `/credentials` | GET/POST | Create account or change passwords       |

## Maintenance

Run `grist-maintenance.sh` to:

1. Remove backup files (`*-backup.grist`)
2. Prune document history (keep last 10 versions)
3. Pull latest Docker images
4. Restart services
5. Clean up unused Docker resources

```sh
./grist-maintenance.sh
```

## Directory Structure

```
.
├── compose.yaml            # Docker Compose configuration
├── nginx.conf              # OpenResty/Nginx config with Lua auth logic
├── .env                    # Environment variables (not committed)
├── .env.sample             # Environment template
├── users                   # htpasswd user database (not committed)
├── users.sample            # htpasswd template
├── sessions                # Persistent session storage (not committed)
├── ssl/                    # Self-signed fallback certificates
├── grist-maintenance.sh    # Maintenance script
├── openresty/
│   └── Dockerfile          # Custom OpenResty image (with ACME, htpasswd, sqlite)
├── persist/                # Grist persistent data (SQLite, .grist docs)
└── _static/                # Static files
```

## License

This deployment configuration is provided as-is. Grist itself is licensed under the [Apache 2.0 License](https://github.com/gristlabs/grist-core/blob/main/LICENSE).
