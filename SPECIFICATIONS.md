# Spécifications du Moniteur Certstream

Ce document détaille les spécifications fonctionnelles et techniques pour la recréation du projet de surveillance Certstream.

## 1. Vue d'ensemble du projet

Le projet est un service de surveillance en temps réel des journaux de transparence des certificats (Certificate Transparency logs) via Certstream. Il filtre les domaines en fonction d'une liste de domaines "wildcard" récupérée depuis une API externe, effectue des analyses sur les domaines correspondants et notifie les résultats.

## 2. Fonctionnalités Clés

### 2.1. Connexion à Certstream
- Le service doit se connecter à un flux WebSocket Certstream pour recevoir les nouveaux certificats en temps réel.
- L'URL du serveur Certstream doit être configurable.
- La connexion doit être résiliente, avec des tentatives de reconnexion en cas d'échec ou de déconnexion.

```Dockerfile
services:
  certstream-server:
    image: 0rickyy0/certstream-server-go:latest
    restart: unless-stopped
    logging:
      driver: none
```

### 2.2. Gestion des Wildcards
- Le service doit récupérer une liste de domaines wildcard (ex: `*.example.com`) depuis une API HTTP.
- L'URL de l'API, les en-têtes (pour l'authentification) et l'intervalle de mise à jour doivent être configurables.
- Les wildcards doivent être stockées en mémoire de manière efficace pour une correspondance rapide. Une structure de données de type **Trie** est recommandée.
- La liste des wildcards doit être mise à jour périodiquement en arrière-plan sans interrompre le traitement principal.

```yaml
# API configuration for wildcard fetching
api:
  url: "https://<url>"
  headers:
    X-API-Key: "<value>"
    Content-Type: "application/json"
    Accept: "application/json"
  update_interval: 86400 # 24 hours in seconds
```

### 2.3. Filtrage des Domaines
- Pour chaque domaine reçu de Certstream, le service doit vérifier s'il correspond à l'un des wildcards.
- La correspondance doit être performante pour gérer un volume élevé de domaines.
- Les domaines commençant eux-mêmes par `*.` (wildcards) doivent être ignorés.
- Une liste d'exclusions de domaines (pour ignorer certains TLDs ou domaines spécifiques) doit être configurable.

```yaml
# Certstream configuration
certstream:
  url: "ws://certstream-server:8080/domains-only"
  exclusions:
    - .ui.com
    - .imperva.com
    - .nflxvideo.net
```

### 2.4. Traitement des Domaines Correspondants
- Lorsqu'un domaine correspond à un wildcard, il doit être soumis à un traitement plus approfondi.
- Ce traitement doit être effectué de manière asynchrone (par exemple, dans un pool de threads) pour ne pas bloquer la réception des messages de Certstream.

#### 2.4.1. Résolution DNS
- Le service doit tenter de résoudre les adresses IP (A et AAAA) du domaine correspondant.
- Les adresses IP privées (RFC 1918, localhost, etc.) doivent être filtrées et ignorées.

#### 2.4.2. Sondage HTTP/HTTPS
- Si un domaine a des adresses IP publiques, le service doit sonder une liste configurable de ports (ex: 80, 443, 8080) avec les protocoles correspondants (http/https).
- Le but est de détecter les serveurs web actifs.
- Les requêtes HTTP doivent avoir un timeout configurable.

```yaml
# HTTP probing configuration
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
  timeout: 5 # seconds
```

### 2.5. Intégration avec "Fingerprinter"
- Si un serveur web est détecté, son URL doit être envoyée à un service externe de "fingerprinting" via une requête POST.
- L'URL du service de fingerprinting et une clé d'API doivent être configurables.

```yaml
# Fingerprinter configuration
fingerprinter:
  url: "https://fingerprinter.jomar.ovh/fingerprint"
  api_key: "<value>"
  callback_urls:
    - "https://recon.jomar.ovh/api/fingerprinter?token=<value>"
```

### 2.6. Notifications Discord
- **Notifications de correspondance** : Chaque fois qu'un domaine correspond à un wildcard, une notification simple doit être envoyée à un webhook Discord configurable.
- **Rapports de statistiques** : Le service doit envoyer un rapport de statistiques agrégées à un autre webhook Discord à intervalles réguliers (par exemple, toutes les 3 heures).

```yaml
# Discord notifications
discord:
  messages_webhook: "https://discord.com/api/webhooks/<value>/<value>"
  logs_webhook: "https://discord.com/api/webhooks/<value>/<value>"
  update_interval: 10800 # 3 hours in seconds
```

### 2.7. Statistiques et Surveillance
- Le service doit collecter et maintenir des statistiques détaillées sur son fonctionnement, notamment :
    - Nombre total de domaines traités.
    - Nombre de domaines correspondants.
    - Taux de correspondance (%).
    - Nombre de résolutions DNS réussies/échouées.
    - Nombre de réponses HTTP.
    - Nombre de timeouts HTTP.
    - Nombre d'URLs envoyées au fingerprinter.
    - Taux de traitement (domaines/seconde).
    - État du pool de threads (threads actifs, file d'attente).
- Ces statistiques doivent être affichées dans la console à intervalles réguliers (par exemple, toutes les 10 minutes).
