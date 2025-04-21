A tool that monitors SSL/TLS certificate issuance via Certstream to detect new domains matching specified wildcards. Perfect for bug bounty hunters, security researchers, and organizations monitoring their digital footprint.

## ✨ Features

- 🚀 **Real-time monitoring** of certificate transparency logs via Certstream
- 🎯 **Automatic detection** of domains matching your configured wildcards
- 🔄 **Periodic wildcard updates** from your API endpoint
- 🧩 **Domain resolution** with intelligent handling of unresolvable domains
- 🚫 **IP filtering** to exclude private/internal IP addresses
- 📊 **Persistent storage** using SQLite
- 🔔 **Discord notifications** for newly discovered domains
- 🐳 **Docker integration** for easy deployment and management

## 📋 Prerequisites

- Docker and Docker Compose
- Access to a Discord webhook URL (for notifications)
- [ScopesExtractor](https://github.com/JoshuaMart/ScopesExtractor/) API access for wildcard retrieval

## 🛠️ Installation

1. **Clone this repository**

```bash
git clone https://github.com/JoshuaMart/Certstream.git
cd Certstream
```

2. **Configure the application**

Edit the `config/config.yml` file with the needed informations

3. **Start the application**

```bash
docker-compose up -d
```

## 🏗️ Architecture

The application consists of several components:

- **Certstream Server**: A Docker container running the [certstream-server-go](https://github.com/d-Rickyy-b/certstream-server-go) service
- **Certstream Monitor**: A Ruby application that:
  - Connects to the Certstream server via WebSocket
  - Fetches wildcards from your API
  - Processes new domain registrations
  - Resolves domains and filters by IP
  - Sends notifications via Discord
  - Maintains a database of discovered domains

## 📊 How It Works

1. **Wildcard collection**: The application fetches wildcards (e.g., `*.example.com`) from ScopesExtractor API endpoint every 24 hours.

2. **Certstream monitoring**: The application connects to the Certstream server to receive real-time updates about new certificate issuances.

3. **Domain matching**: When a new domain is detected in the certificate transparency logs, the application checks if it matches any of your wildcards.

4. **Domain processing**:
   - The domain is resolved to an IP address
   - If the domain resolves to a private IP, it's ignored
   - If the domain cannot be resolved, it's added to a retry queue

5. **Retry queue**: Unresolvable domains are retried every 3 hours for up to 14 days before being discarded.

6. **Notification**: When a valid domain (with public IP) is discovered, a Discord notification is sent with details about the domain and the matching wildcard.

7. **Deduplication**: The application maintains a database of discovered domains to avoid duplicate notifications.

### Logs

Application logs are stored in the `logs` directory. Check these logs for detailed information about any issues:

```bash
docker-compose logs -f certstream-monitor
```
