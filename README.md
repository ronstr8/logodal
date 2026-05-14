# Logodal

Logodal is a fast-paced wordsmith dueling game. It combines Perl, Rust, and Nginx into a seamless, high-performance game universe.

> [!NOTE]
> The latest development version of the game is running at [logodal.com](https://logodal.com). It is sometimes stable, sometimes crashing into the abyss, and often filled with extra annoying bugs. You have been warned.

---

## 🛠 Prerequisites

Before embarking on your descent into the word-void, ensure your host (e.g., Ubuntu) has the following tools installed:

- **Docker**: For building and running containers.
- **Kind**: Our local Kubernetes environment.
- **kubectl**: The command-line interface for our cluster.
- **Helm**: To manage our eldritch charts.
- **hunspell** & **hunspell-tools**: For generating application lexicons with full affix expansion.
- **hunspell-{lang}**: Dictionaries for your desired languages (e.g., `hunspell-en-us`, `hunspell-de-de`, etc.).

### Quick Install (Ubuntu/Debian)

```bash
# Install core tools
sudo apt update
sudo apt install -y docker.io kubectl helm hunspell hunspell-tools hunspell-en-us hunspell-de-de hunspell-es hunspell-fr hunspell-ru

# Install Kind
# See https://kind.sigs.k8s.io/docs/user/quick-start/#installation for latest
go install sigs.k8s.io/kind@latest
# or via binary release:
# curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

---

## 🚀 Getting Started

### 1. Initialize the Universe

Before deploying, ensure you have a running Kubernetes cluster and a local Docker registry.

We manage the local environment in a separate repository: **k8s-homelab**.
You can start the cluster from that repository:

```bash
# In the k8s-homelab directory
make up
```

This single command:
- Starts a local Docker registry on `localhost:5000`
- Creates a Kind cluster (default: `homelab`) with ports 80/443 mapped to your host
- Connects the registry to the Kind network
- Deploys the nginx ingress controller

### 2. Build & Deploy

Build all polyglot services, push them to the local registry, and deploy the umbrella Helm chart:

```bash
make build && make deploy && watch kubectl -n Logodal get pods
```

**Persistent Storage**: PostgreSQL uses Kind's built-in `local-path` provisioner via the `standard` StorageClass. Data survives pod restarts and helm upgrades but is scoped to the Kind cluster — deleting the cluster (`make down` in k8s-homelab) wipes all data.

To reset the database without destroying the cluster:

```bash
kubectl -n Logodal delete pvc --all
make deploy
```

### 3. Access the Game

With Kind's `extraPortMappings`, the ingress controller binds directly to your host's ports 80 and 443. Add a hosts entry on your client machine:

```bash
echo "127.0.0.1 logodal.com" | sudo tee -a /etc/hosts
```

Then navigate to `http://logodal.com` to play.

### 4. Setup SSL Certificates (Optional)

For production or if you want trusted HTTPS locally, apply the Let's Encrypt ClusterIssuer:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.yaml

# Wait for it
kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=180s

# Apply the issuers
kubectl apply -f helm/resources/production/letsencrypt-issuer.yaml
```

*Note: Your domain must be publicly accessible on port 80 for HTTP-01 validation to succeed.*

### 5. External Services Setup

Logodal integrates with several external services for authentication, notifications, and payments. Follow these steps to generate the required credentials:

#### 🔑 Google OAuth

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project or select an existing one.
3. Configure the **OAuth consent screen**.
4. Create **OAuth 2.0 Client IDs** (Web application).
5. Add `https://logodal.com/auth/google/callback` to the **Authorized redirect URIs**.
6. Copy the `Client ID` and `Client Secret` to `helm/secrets.yaml`.

#### 🎮 Discord OAuth & Webhooks

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications).
2. Create a new Application.
3. Under **OAuth2 -> General**, add `https://logodal.com/auth/discord/callback` to the **Redirects**.
4. In the **OAuth2 -> URL Generator**, select the following scopes:
   - `identify`
   - `email`
5. Copy the `Client ID` and `Client Secret` to `helm/secrets.yaml`.
6. To enable **Notifications**:
   - In your Discord server, go to a channel's settings -> **Integrations** -> **Webhooks**.
   - Create a new webhook and copy the **Webhook URL** to `helm/secrets.yaml` under `admin-discord-webhook`.

### 6. PLAYTIME

Navigate to `https://logodal.com` (or `http://` if you skipped SSL setup) to begin.

### 7. Lexicons

Logodal uses high-speed, pre-compiled lexicons for word validation. If you want to update the word lists from the latest Hunspell dictionaries:

```bash
# Standard rebuild of all lexicons
# This requires hunspell and hunspell-tools (unmunch) to be installed.
make lexicons
```

You can customize the source and destination paths if your system stores dictionaries elsewhere:

```bash
make lexicons HUNSPELL_DICTS=/path/to/dicts WORDD_ROOT=srv/wordd/share/words
```

### 8. Teardown

To destroy the Kind cluster and local registry, run this command in the **k8s-homelab** repository:

```bash
# In the k8s-homelab directory
make down
```

---

---

## 🎮 Scoring & Special Mechanics

- **Letter values** are frequency-based (1–9 pts), with two Unicorn letters at 10 pts and one daily bonus letter at 7 pts.
- **Length bonuses**: +5 for words using more than half the rack, doubling for each tile beyond that.
- **Unique word bonus**: +1 pt for playing a word nobody else played.
- **Quick bonus**: +5 pts for playing within the first 5 seconds.
- **Duplicate penalty**: copying another player's word scores you 0 pts — but the original player earns the full raw letter value of that word for each copy made.
- **Mutant Letter**: Each game, tiles associated with a randomly chosen letter mutate, changing their score to 10.

---

## 📐 Architecture

- **frontend**: React-based UI (Vite/Nginx).
- **backend**: Perl (Mojolicious) service handling authentication, API, and WebSocket.
- **wordd**: Rust-based high-speed word validator.

---
*Created by Ron "Quinn" Straight and Antigravity using a variety of models.*

