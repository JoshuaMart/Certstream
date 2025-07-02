# Certstream Monitor with Wildcard Filtering

Monitor Certificate Transparency logs and filter domains based on wildcards fetched from an API.

## 🚀 Quick Start

### 1. Configure your API endpoint
```yaml
# src/config.yml
api:
  url: "https://your-api.com/wildcards"
  update_interval: 3600  # Update every hour
  headers:
    X-API-Key: "your-api-key"
```

### 2. Run the monitor
```bash
# Start with Docker Compose
docker-compose up

# Or run locally
ruby main.rb
```

## 📊 Performance Features

- **High throughput**: Handles ~90k domains/minute
- **Optimized matching**: Uses `end_with?` for fast wildcard matching  
- **Real-time stats**: Monitor processing rates and match ratios
- **Background updates**: Wildcards refresh automatically
- **Thread-safe**: Safe concurrent access to wildcard list

## 🔧 Testing

### Test wildcard matching performance:
```bash
ruby test_performance.rb
```

### Start test API server:
```bash
ruby test_api_server.rb
# Then use config.test.yml
```

## 📈 Expected Output

```
[Monitor] Wildcard manager started
[Monitor] WebSocket connected
[WildcardManager] Updated 25 wildcards
[MATCH] app.example.com
[MATCH] api.github.com
[STATS] Processed: 45000 | Matched: 123 (0.27%) | Rate: 1502.3/s
```

## 🎛️ Configuration

The system expects wildcards from your API in JSON format:
```json
["example.com", "test.org", "github.com"]
```

Or nested format:
```json
{"wildcards": ["example.com", "test.org"]}
```

## 🚨 Performance Notes

- Synchronous processing is usually sufficient for most workloads
- The system includes built-in performance monitoring
- For extreme loads (>100k/minute), consider the thread pool optimization
- Monitor memory usage with large wildcard lists

## 🔍 Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Certstream    │───▶│  Wildcard Filter │───▶│  Match Handler  │
│   WebSocket     │    │  (end_with?)     │    │  (Discord/etc)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                       ┌──────────────────┐
                       │  Wildcard API    │
                       │  (Auto-refresh)  │
                       └──────────────────┘
```
