# Certstream Monitor

A high-performance, real-time Certificate Transparency log monitor. It filters domains against a list of wildcards fetched from external APIs, performs DNS resolution and HTTP probing, and sends notifications to Discord.

## Features

- **Real-time monitoring** - Connects to Certstream via WebSocket to receive new certificates as they are issued
- **Multi-API wildcard management** - Fetch wildcards from multiple APIs with automatic periodic updates
- **Efficient matching** - Uses a Trie data structure for O(L) domain matching (where L = domain parts)
- **DNS resolution** - Resolves A and AAAA records, filters out private IPs (RFC 1918)
- **HTTP probing** - Concurrent probing on configurable ports (80, 443, 8080, 8443)
- **Discord notifications** - Rich embeds with domain, matched wildcard, IPs, and active URLs
- **Statistics** - Detailed stats reported to console (10 min) and Discord (3 hours)
- **Graceful shutdown** - Handles SIGTERM/SIGINT with final stats report
- **Deduplication** - Prevents duplicate notifications for the same domain

## Requirements

- Ruby 4.0+
- Docker & Docker Compose (recommended)

## Quick Start

### Using Docker Compose (recommended)

1. Clone the repository and navigate to the project directory

2. Copy and edit the configuration file:
```bash
cp config.yml.example config.yml
# Edit config.yml with your settings
```

3. Start the services:
```bash
docker-compose up -d
```

4. View logs:
```bash
docker-compose logs -f certstream-monitor
```

### Manual Installation

1. Install dependencies:
```bash
bundle install
```

2. Configure `config.yml` with your settings

3. Run the monitor:
```bash
ruby main.rb start
```

## CLI Usage

```bash
# Start the monitor
ruby main.rb start

# Start with custom config file
ruby main.rb start --config /path/to/config.yml

# Start with debug logging
ruby main.rb start --log-level DEBUG

# Display version
ruby main.rb version
```

## API Response Format

The wildcard APIs should return JSON in the following format:

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

Only the `value` field is required. The monitor extracts wildcards from `*.domain.com` format.

## Architecture

```
┌─────────────────┐
│   Certstream    │
│   WebSocket     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│  Domain Filter  │────▶│ Wildcard Manager│
│  (exclusions)   │     │     (Trie)      │
└────────┬────────┘     └─────────────────┘
         │
         ▼
┌─────────────────┐
│  DNS Resolver   │
│ (A/AAAA records)│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  HTTP Prober    │
│ (ports 80,443..)│
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│    Discord      │     │  Fingerprinter  │
│  Notification   │     │   (external)    │
└─────────────────┘     └─────────────────┘
```

## Discord Notifications

### Domain Match
When a domain matches a wildcard and has active URLs, a rich embed is sent:
- **Domain** - The matched domain
- **Matched Wildcard** - The wildcard pattern that matched
- **IPs** - Resolved public IP addresses
- **Active URLs** - Number and list of responding URLs

### Statistics Report
Every 3 hours (configurable), a statistics report is sent:
- Uptime
- Total domains processed
- Matched domains and match rate
- DNS resolution success/failure
- HTTP responses/timeouts
- Processing rate (domains/second)

## Performance

- Processes ~90k+ domains per minute
- Trie-based matching: O(L) complexity
- Concurrent HTTP probing with HTTPX
- Async processing with Ruby Fibers
- Deduplication prevents redundant work

## Tech Stack

| Component | Technology |
|-----------|------------|
| Runtime | Ruby 4.0 |
| WebSocket | async-websocket |
| HTTP Client | HTTPX |
| Concurrency | Async (Fibers) |
| CLI | Thor |

## License

MIT
