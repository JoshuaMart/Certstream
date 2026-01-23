# TODO - Refactoring Certstream Monitor

## Architecture du projet

```
refactoring/
├── SPECIFICATIONS.md           # Spécifications détaillées
├── TODO.md                     # Ce fichier
├── main.rb                     # Point d'entrée CLI (Thor)
├── config.yml                  # Configuration par défaut
├── Gemfile                     # Dépendances
├── Dockerfile
├── docker-compose.yml
├── .rubocop.yml                # Configuration Rubocop
└── lib/
    ├── certstream.rb           # Module principal + autoloads
    └── certstream/
        ├── version.rb          # Constante VERSION
        ├── cli.rb              # Interface Thor (start, version)
        ├── config.rb           # Chargement et validation config YAML
        ├── logger.rb           # Logger coloré personnalisé
        ├── monitor.rb          # Orchestrateur principal
        ├── websocket_client.rb # Connexion WebSocket async
        ├── wildcard_manager.rb # Gestion Trie + fetch APIs
        ├── domain_processor.rb # Traitement des domaines matchés
        ├── dns_resolver.rb     # Résolution DNS + filtrage IPs privées
        ├── http_prober.rb      # Sondage HTTP/HTTPS via httpx
        ├── fingerprinter.rb    # Intégration service fingerprinting
        ├── discord_notifier.rb # Notifications webhooks Discord
        └── stats.rb            # Collecte et reporting statistiques
```

## Étapes de mise en œuvre

### Phase 1 : Setup du projet

- [ ] Créer la structure de dossiers `lib/certstream/`
- [ ] Créer le `Gemfile` avec les nouvelles dépendances
  - async
  - async-websocket
  - httpx
  - thor
  - colorize
  - rubocop
- [ ] Configurer `.rubocop.yml`
- [ ] Créer `lib/certstream.rb` (module principal + requires)
- [ ] Créer `lib/certstream/version.rb`

### Phase 2 : Configuration et CLI

- [ ] Créer `lib/certstream/config.rb`
  - Chargement YAML
  - Validation des clés obligatoires
  - Valeurs par défaut
- [ ] Créer `lib/certstream/cli.rb` (Thor)
  - Commande `start` avec options `--config`, `--log-level`
  - Commande `version`
- [ ] Créer `lib/certstream/logger.rb`
  - Logger Ruby standard
  - Formatter coloré (colorize)
  - Format : `[TIMESTAMP] [LEVEL] [COMPONENT] Message`
- [ ] Mettre à jour `main.rb` pour lancer la CLI

### Phase 3 : Gestion des Wildcards

- [ ] Créer `lib/certstream/wildcard_manager.rb`
  - Structure Trie pour stockage
  - Fetch multi-APIs (httpx)
  - Méthode `match?(domain)` performante
  - Update périodique en background (async)
  - Gestion des erreurs par API (résilience)

### Phase 4 : Connexion WebSocket

- [ ] Créer `lib/certstream/websocket_client.rb`
  - Connexion via async-websocket
  - Reconnexion automatique avec backoff
  - Parsing JSON des messages
  - Callback pour traitement des domaines

### Phase 5 : Traitement des domaines

- [ ] Créer `lib/certstream/dns_resolver.rb`
  - Résolution A et AAAA
  - Filtrage IPs privées (RFC 1918)
  - Timeout configurable
- [ ] Créer `lib/certstream/http_prober.rb`
  - Sondage parallèle via httpx
  - Ports configurables (80, 443, 8080, 8443)
  - Détection serveurs actifs
- [ ] Créer `lib/certstream/domain_processor.rb`
  - Pipeline : DNS → filtrage IPs → HTTP probe
  - Traitement async (Fibers)

### Phase 6 : Intégrations externes

- [ ] Créer `lib/certstream/fingerprinter.rb`
  - Envoi POST vers service fingerprinting
  - Gestion API key
  - Callback URLs
- [ ] Créer `lib/certstream/discord_notifier.rb`
  - Webhook messages (domaines matchés)
  - Webhook logs (erreurs, stats)
  - Embeds formatés pour les rapports

### Phase 7 : Statistiques et Monitoring

- [ ] Créer `lib/certstream/stats.rb`
  - Compteurs thread-safe
  - Calcul des taux et ratios
  - Export pour Discord et console
- [ ] Intégrer reporting périodique
  - Console : toutes les 10 minutes
  - Discord : toutes les 3 heures

### Phase 8 : Orchestration

- [ ] Créer `lib/certstream/monitor.rb`
  - Initialisation de tous les composants
  - Boucle principale async
  - Graceful shutdown (SIGTERM, SIGINT)
  - Coordination des tâches

### Phase 9 : Docker et finalisation

- [ ] Mettre à jour `Dockerfile` (Ruby 4.0.1-alpine)
- [ ] Mettre à jour `docker-compose.yml`
- [ ] Créer `config.yml` par défaut
- [ ] Vérifier Rubocop clean
- [ ] Tests manuels end-to-end
- [ ] Mettre à jour `README.md`
