# Certstream Monitor

This tool monitors SSL/TLS certificate issuance via Certstream and alerts on new domains matching specific wildcards.

## Features

- Monitors Certstream for new domain registrations
- Filters domains based on configured wildcards
- Resolves domain IPs and filters out private IPs
- Retries unresolvable domains periodically
- Sends Discord alerts for new matching domains
- Avoids duplicate alerts

## Setup

1. Configure the Discord webhook URL in `config/config.yml`
2. Run using Docker Compose: `docker-compose up -d`

## License

MIT