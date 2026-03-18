![Image](https://github.com/user-attachments/assets/89c7112c-43b1-4f5d-aebc-bf4426842025)

<p align="center">
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-green"></a>
  <img src="https://img.shields.io/badge/docker-supported-blue?logo=docker">
  <img src="https://img.shields.io/badge/ruby-4.0.2-blue?logo=ruby">
</p>

Real-time Certificate Transparency log monitor. Filters domains against wildcards, resolves DNS, probes HTTP services, and forwards active URLs to an external Recon API with Discord notifications.

> [!IMPORTANT]
> This project is primarily intended to work with [ScopesExtractor](https://github.com/JoshuaMart/ScopesExtractor) and [Recon](https://github.com/JoshuaMart/Recon).

## Pipeline

```
1. Certstream WebSocket — receive new certificate domains in real time
        |
        v
2. Wildcard matching — filter against Trie built from manual wildcards + API sources
        |
        v
3. Deduplication — skip already-seen domains
        |
        v
4. DNS resolution — resolve A/AAAA records, filter out private IPs (RFC 1918)
        |
        v
5. HTTP probing — concurrent HEAD requests on ports 80, 443, 8080, 8443
        |
        v
6. Recon API — POST each active URL to external API for further processing
        |
        v
7. Discord notification — rich embed with domain, wildcard, IPs, and active URLs
```

## Quick Start

### Docker Compose (recommended)

```bash
cp config.yml.example config.yml
# Edit config.yml with your settings
docker-compose up -d
```

### Manual

```bash
bundle install
ruby main.rb start
```

<details>
<summary>CLI flags</summary>

```bash
ruby main.rb start                          # Start the monitor
ruby main.rb start --config /path/to.yml    # Custom config file
ruby main.rb start --log-level DEBUG        # Debug logging
ruby main.rb version                        # Display version
```

</details>

## Configuration

Copy `config.yml.example` to `config.yml` and edit as needed:

```yaml
certstream:
  url: "ws://certstream-server:8080/domains-only"
  exclusions:
    - .internal.com

wildcards:
  - "*.example.com"
  - "*.target.org"

apis:
  - name: "scopes"
    url: "https://scopes.example.com/wildcards"
    headers:
      X-API-Key: "your-api-key"
    enabled: true

wildcards_update_interval: 86400

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

recon_api:
  url: "https://recon.example.com/api/ingest/certstream"
  api_key: "your-api-key"

discord:
  messages_webhook: "https://discord.com/api/webhooks/..."
  logs_webhook: "https://discord.com/api/webhooks/..."
  stats_interval: 10800

logging:
  level: "INFO"
  console_colors: true

shutdown:
  timeout: 30
```

## Wildcard Sources

### Manual

Define wildcards directly in `config.yml` under the `wildcards` key.

### API-based

APIs should return JSON in the following format:

```json
{
  "wildcards": [
    {
      "value": "*.example.com",
      "program_name": "Example Program",
      "platform": "bugcrowd"
    }
  ]
}
```

Only the `value` field is required. Both sources are merged into the same Trie and refreshed periodically.

## License

[MIT](LICENSE)
