# Spécifications du Moniteur Certstream

Ce document détaille les spécifications fonctionnelles et techniques pour la recréation du projet de surveillance Certstream.

## 1. Vue d'ensemble du projet

Le projet est un service de surveillance en temps réel des journaux de transparence des certificats (Certificate Transparency logs) via Certstream. Il filtre les domaines en fonction d'une liste de domaines "wildcard" récupérée depuis des APIs externes, effectue des analyses sur les domaines correspondants et notifie les résultats.

## 2. Stack Technique

### 2.1. Environnement

| Composant | Version / Choix |
|-----------|-----------------|
| Ruby | 4.0.1 |
| Image Docker | `ruby:4.0.1-alpine` |

### 2.2. Dépendances (Gems)

| Gem | Rôle |
|-----|------|
| `httpx` | Client HTTP moderne (HTTP/2, requêtes concurrentes) |
| `async-websocket` | Client WebSocket (écosystème Socketry/Fibers) |
| `async` | Concurrence basée sur les Fibers Ruby 3+ |
| `thor` | Interface CLI |
| `logger` | Logging (bundled gem Ruby 4) |
| `colorize` | Couleurs pour la sortie console |
| `rubocop` | Linting et style de code |

### 2.3. Contraintes de qualité

- Le code doit être **Rubocop clean** (configuration standard).
- Utilisation des fonctionnalités modernes de Ruby 4.0 quand pertinent.

## 3. Fonctionnalités Clés

### 3.1. Connexion à Certstream

- Le service doit se connecter à un flux WebSocket Certstream pour recevoir les nouveaux certificats en temps réel.
- L'URL du serveur Certstream doit être configurable.
- La connexion doit être résiliente, avec des tentatives de reconnexion en cas d'échec ou de déconnexion.

```yaml
# docker-compose.yml
services:
  certstream-server:
    image: 0rickyy0/certstream-server-go:latest
    restart: unless-stopped
    logging:
      driver: none
```

### 3.2. Gestion des Wildcards

- Le service doit récupérer une liste de domaines wildcard (ex: `*.example.com`) depuis **plusieurs APIs HTTP**.
- Chaque API peut avoir sa propre URL et ses propres en-têtes d'authentification.
- Les wildcards de toutes les APIs activées sont **fusionnés** dans la même structure.
- Si une API échoue, les autres continuent de fonctionner (résilience).
- Les wildcards doivent être stockés en mémoire de manière efficace pour une correspondance rapide. Une structure de données de type **Trie** est recommandée.
- La liste des wildcards doit être mise à jour périodiquement en arrière-plan sans interrompre le traitement principal.

```yaml
# Configuration des APIs pour la récupération des wildcards
apis:
  - name: "primary-scopes"
    url: "https://scopes.jomar.ovh"
    headers:
      X-API-Key: "<value>"
      Content-Type: "application/json"
    enabled: true

  - name: "secondary-source"
    url: "https://other-api.example.com/wildcards"
    headers:
      Authorization: "Bearer <token>"
    enabled: false

wildcards_update_interval: 86400 # 24 heures en secondes
```

### 3.3. Filtrage des Domaines

- Pour chaque domaine reçu de Certstream, le service doit vérifier s'il correspond à l'un des wildcards.
- La correspondance doit être performante pour gérer un volume élevé de domaines.
- Les domaines commençant eux-mêmes par `*.` (wildcards) doivent être ignorés.
- Une liste d'exclusions de domaines (pour ignorer certains TLDs ou domaines spécifiques) doit être configurable.

```yaml
# Configuration Certstream
certstream:
  url: "ws://certstream-server:8080/domains-only"
  exclusions:
    - .ui.com
    - .imperva.com
    - .nflxvideo.net
```

### 3.4. Traitement des Domaines Correspondants

- Lorsqu'un domaine correspond à un wildcard, il doit être soumis à un traitement plus approfondi.
- Ce traitement doit être effectué de manière asynchrone (Fibers via `async`) pour ne pas bloquer la réception des messages de Certstream.

#### 3.4.1. Résolution DNS

- Le service doit tenter de résoudre les adresses IP (A et AAAA) du domaine correspondant.
- Les adresses IP privées (RFC 1918, localhost, etc.) doivent être filtrées et ignorées :
  - `10.0.0.0/8`
  - `172.16.0.0/12`
  - `192.168.0.0/16`
  - `127.0.0.0/8`
  - `169.254.0.0/16`

#### 3.4.2. Sondage HTTP/HTTPS

- Si un domaine a des adresses IP publiques, le service doit sonder une liste configurable de ports avec les protocoles correspondants (http/https).
- Le but est de détecter les serveurs web actifs.
- Les requêtes HTTP doivent avoir un timeout configurable.
- Les requêtes doivent être effectuées en parallèle via `httpx`.

```yaml
# Configuration du sondage HTTP
http:
  ports:
    - protocol: "http"
      port: 80
    - protocol: "https"
      port: 443
    - protocol: "http"
      port: 8080
    - protocol: "https"
      port: 8443
  timeout: 5 # secondes
```

### 3.5. Intégration avec "Fingerprinter"

- Si un serveur web est détecté, son URL doit être envoyée à un service externe de "fingerprinting" via une requête POST.
- L'URL du service de fingerprinting et une clé d'API doivent être configurables.

```yaml
# Configuration Fingerprinter
fingerprinter:
  url: "https://fingerprinter.jomar.ovh/fingerprint"
  api_key: "<value>"
  callback_urls:
    - "https://recon.jomar.ovh/api/fingerprinter?token=<value>"
```

### 3.6. Notifications Discord

- **Notifications de correspondance** : Chaque fois qu'un domaine correspond à un wildcard, une notification simple doit être envoyée à un webhook Discord configurable.
- **Rapports de statistiques** : Le service doit envoyer un rapport de statistiques agrégées à un autre webhook Discord à intervalles réguliers (par exemple, toutes les 3 heures).
- **Logs d'erreurs** : Les erreurs importantes (échec de connexion WebSocket, API down, etc.) doivent être envoyées au webhook de logs.

```yaml
# Notifications Discord
discord:
  messages_webhook: "https://discord.com/api/webhooks/<value>/<value>"
  logs_webhook: "https://discord.com/api/webhooks/<value>/<value>"
  stats_interval: 10800 # 3 heures en secondes
```

### 3.7. Statistiques et Surveillance

- Le service doit collecter et maintenir des statistiques détaillées sur son fonctionnement :
  - Nombre total de domaines traités
  - Nombre de domaines correspondants
  - Taux de correspondance (%)
  - Nombre de résolutions DNS réussies/échouées
  - Nombre de réponses HTTP
  - Nombre de timeouts HTTP
  - Nombre d'URLs envoyées au fingerprinter
  - Taux de traitement (domaines/seconde)
  - Uptime du service
- Ces statistiques doivent être affichées dans la console à intervalles réguliers (par exemple, toutes les 10 minutes).

### 3.8. Logging

- Utiliser la gem `logger` (bundled dans Ruby 4).
- Les logs console doivent être colorés via `colorize`.
- Niveaux de log : `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`.
- Le niveau de log doit être configurable (défaut : `INFO`).
- Format des logs : `[TIMESTAMP] [LEVEL] [COMPONENT] Message`.

```yaml
# Configuration des logs
logging:
  level: "INFO" # DEBUG, INFO, WARN, ERROR, FATAL
  console_colors: true
```

### 3.9. Graceful Shutdown

Le service doit gérer proprement les signaux d'arrêt (`SIGTERM`, `SIGINT`) :

1. Arrêter de recevoir de nouveaux messages (fermer la connexion WebSocket).
2. Attendre que les tâches en cours terminent (timeout configurable, défaut : 30 secondes).
3. Envoyer un dernier rapport de statistiques sur Discord.
4. Logger l'arrêt et quitter proprement.

```yaml
# Configuration du shutdown
shutdown:
  timeout: 30 # secondes pour terminer les tâches en cours
```

### 3.10. Health Check

- Le service doit exposer un endpoint HTTP simple pour les health checks.
- Utile pour Docker et les orchestrateurs (Kubernetes, etc.).

```yaml
# Configuration du health check
health:
  enabled: true
  port: 8081
  path: "/health"
```

Réponse attendue :
```json
{
  "status": "healthy",
  "uptime": 3600,
  "websocket_connected": true,
  "wildcards_count": 1234,
  "last_wildcard_update": "2026-01-23T10:00:00Z"
}
```

## 4. Interface CLI (Thor)

Le service doit fournir une interface en ligne de commande via `thor` :

```bash
# Commandes principales
certstream start                      # Démarrer le moniteur
certstream start --config ./custom.yml # Avec config personnalisée
certstream start --log-level DEBUG    # Niveau de log spécifique

# Gestion des wildcards
certstream wildcards refresh          # Forcer un rafraîchissement
certstream wildcards list             # Lister les wildcards chargés
certstream wildcards count            # Afficher le nombre de wildcards

# Utilitaires
certstream health                     # Vérifier le health check
certstream version                    # Afficher la version
```

## 5. Configuration Complète

Exemple de fichier de configuration complet (`config.yml`) :

```yaml
# Configuration Certstream
certstream:
  url: "ws://certstream-server:8080/domains-only"
  exclusions:
    - .ui.com
    - .imperva.com
    - .nflxvideo.net

# Configuration des APIs pour les wildcards
apis:
  - name: "primary-scopes"
    url: "https://scopes.jomar.ovh"
    headers:
      X-API-Key: "<value>"
      Content-Type: "application/json"
    enabled: true

  - name: "secondary-source"
    url: "https://other-api.example.com/wildcards"
    headers:
      Authorization: "Bearer <token>"
    enabled: false

wildcards_update_interval: 86400

# Configuration du sondage HTTP
http:
  ports:
    - protocol: "http"
      port: 80
    - protocol: "https"
      port: 443
    - protocol: "http"
      port: 8080
    - protocol: "https"
      port: 8443
  timeout: 5

# Configuration Fingerprinter
fingerprinter:
  url: "https://fingerprinter.jomar.ovh/fingerprint"
  api_key: "<value>"
  callback_urls:
    - "https://recon.jomar.ovh/api/fingerprinter?token=<value>"

# Notifications Discord
discord:
  messages_webhook: "https://discord.com/api/webhooks/<value>/<value>"
  logs_webhook: "https://discord.com/api/webhooks/<value>/<value>"
  stats_interval: 10800

# Configuration des logs
logging:
  level: "INFO"
  console_colors: true

# Configuration du shutdown
shutdown:
  timeout: 30

# Configuration du health check
health:
  enabled: true
  port: 8081
  path: "/health"
```

## 6. Docker

### Dockerfile

```dockerfile
FROM ruby:4.0.1-alpine

RUN apk add --no-cache build-base

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

COPY . .

EXPOSE 8081

CMD ["ruby", "main.rb", "start"]
```

### docker-compose.yml

```yaml
services:
  certstream-server:
    image: 0rickyy0/certstream-server-go:latest
    restart: unless-stopped
    logging:
      driver: none

  certstream-monitor:
    build: .
    restart: unless-stopped
    depends_on:
      - certstream-server
    volumes:
      - ./config.yml:/app/config.yml:ro
    ports:
      - "8081:8081"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```
