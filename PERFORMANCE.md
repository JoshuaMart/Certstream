# Performance Optimizations

This document outlines the performance improvements made to the Certstream application to address issues with queue growth and high server load.

## Problem Statement

The original implementation had performance issues, particularly:
- Large queue growth (over 100,000 domains in queue)
- High server load average (around 5)
- Slow processing of domains in the `process_domain` method
- Inefficient database operations

## Optimizations Implemented

### CertstreamMonitor Class

1. **Memory Caching**
   - Added in-memory domain cache to avoid repeated processing of the same domains
   - Converted exclusions to a Set for faster lookups

2. **Pre-filtering**
   - Filter domains before adding to the queue to reduce queue pressure
   - Skip already processed domains early

3. **Concurrency Improvements**
   - Increased default concurrency from 10 to 20 workers
   - Expanded EventMachine threadpool size
   - Added dynamic concurrency adjustment based on queue size

4. **Batch Processing**
   - Implemented batch processing for unresolvable domains
   - Added mutex protection for thread safety

5. **Performance Monitoring**
   - Added metrics collection and logging
   - Tracking of processing rate (domains/second)
   - Monitoring of queue size and memory cache size

6. **Health Checks**
   - Added periodic health checks to monitor system performance
   - Automatic adjustment of concurrency based on queue growth
   - Discord notifications for performance issues

### Database Class

1. **SQLite Optimizations**
   - Enabled Write-Ahead Logging (WAL) for better concurrency
   - Adjusted synchronous settings to balance performance and durability
   - Increased cache size and used memory for temporary tables

2. **Batch Operations**
   - Added methods for batch inserts of domains
   - Used transactions for better performance with multiple inserts

3. **Prepared Statements**
   - Used prepared statements for frequently executed queries
   - Reused statement objects to avoid parsing overhead

4. **Indexing**
   - Added indexes for commonly queried columns
   - Optimized index usage in query patterns

5. **Domain Caching**
   - Added preloading of recently discovered domains
   - Implemented cache expiry mechanism
   - Added domain cache to reduce database lookups

6. **Database Maintenance**
   - Added cleanup method to remove old records
   - Implemented database optimization through VACUUM

### DomainResolver Class

1. **DNS Caching**
   - Added LRU cache for DNS resolution results
   - Cached both successful and failed lookups
   - Added cache performance monitoring (hit rate tracking)

2. **Resolver Configuration**
   - Configured multiple DNS servers for reliability
   - Added timeout for DNS resolutions
   - Used optimized resolver settings

3. **Network Optimizations**
   - Precomputed private network CIDR ranges
   - Cached IP classification results

## New Dependencies

- Added `lru_redux` gem for efficient caching

## Expected Benefits

These optimizations should:
1. Significantly reduce the queue size
2. Lower server load average
3. Speed up domain processing
4. Reduce database contention
5. Improve overall application stability

## Deployment Instructions

1. Install the new dependencies:
   ```
   bundle install
   ```

2. Restart the application

3. Monitor performance:
   - Watch the server load average
   - Check queue size logs
   - Review domain processing rate
   - Verify database performance

## Monitoring

The application now logs performance metrics every minute, including:
- Domains processed per second
- Current queue size
- Maximum queue size
- Cache hit rates
- Memory cache sizes

Discord notifications will be sent if performance issues are detected, such as a large queue size.
