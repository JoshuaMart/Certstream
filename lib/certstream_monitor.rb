# frozen_string_literal: true

require 'websocket-eventmachine-client'
require 'json'
require 'set'

class CertstreamMonitor
  attr_reader :ws_url, :db, :resolver, :notifier, :fingerprinter, :logger, :exclusions, :queue, :concurrency

  # Increased default concurrency
  def initialize(ws_url, db, resolver, notifier, fingerprinter, logger, exclusions, concurrency: 20)
    @ws_url        = ws_url
    @db            = db
    @resolver      = resolver
    @notifier      = notifier
    @fingerprinter = fingerprinter
    @logger        = logger
    @exclusions    = exclusions
    @queue         = EM::Queue.new
    @concurrency   = concurrency

    # In-memory cache to avoid repeated database lookups
    @domain_cache = {}
    @exclusions_set = Set.new(exclusions)

    # Batch optimization for unresolvable domains
    @unresolvable_domains_batch = []
    @unresolvable_batch_size = 100
    @unresolvable_mutex = Mutex.new

    # Performance monitoring statistics
    @processed_domains_count = 0
    @queue_max_size = 0
    @last_stats_time = Time.now

    # Pre-load discovered domains cache if available
    preload_discovered_domains_cache
  end

  def connect_websocket
    # Increase threadpool size to handle more concurrent DNS requests
    EM.threadpool_size = concurrency * 3
    EM.run do
      setup_websocket_connection(true)

      # Add periodic timer to flush unresolvable domains batch and log performance stats
      EM.add_periodic_timer(10) do
        flush_unresolvable_domains_batch
        log_performance_stats
      end

      # Add health check timer to monitor queue growth and adjust concurrency if needed
      EM.add_periodic_timer(60) do
        perform_health_check
      end
    end
  end

  private

  def preload_discovered_domains_cache
    # Attempt to preload discovered domains if the database has such method
    return unless @db.respond_to?(:preload_discovered_domains_cache)

    cache = @db.preload_discovered_domains_cache
    cache.each { |domain, _| @domain_cache[domain] = :discovered }
    @logger.info("Preloaded #{cache.size} discovered domains into memory cache")
  end

  def perform_health_check
    current_queue_size = begin
      @queue.size
    rescue StandardError
      0
    end

    # If queue is growing too large, dynamically increase concurrency
    return unless current_queue_size > 50_000 && @concurrency < 50

    old_concurrency = @concurrency
    @concurrency = [(@concurrency * 1.5).to_i, 50].min

    # Start additional workers
    (@concurrency - old_concurrency).times { process_next }

    @logger.warn("Queue size is #{current_queue_size} - increased concurrency from #{old_concurrency} to #{@concurrency}")
    notifier.send_log('Performance Adjustment',
                      "Queue size has reached #{current_queue_size} domains\n" +
                      "Increased concurrency from #{old_concurrency} to #{@concurrency}",
                      :info)
  end

  def log_performance_stats
    now = Time.now
    elapsed = now - @last_stats_time

    return unless elapsed >= 60 # Log stats every minute

    current_queue_size = begin
      @queue.size
    rescue StandardError
      'unknown'
    end
    domains_per_second = @processed_domains_count / elapsed

    @logger.info('Performance stats: ' +
                "Processed #{@processed_domains_count} domains in last #{elapsed.to_i} seconds " +
                "(#{domains_per_second.round(2)}/sec). " +
                "Current queue size: #{current_queue_size}, " +
                "Max queue size: #{@queue_max_size}, " +
                "Domain cache size: #{@domain_cache.size}")

    # Reset counters
    @processed_domains_count = 0
    @queue_max_size = current_queue_size.is_a?(Integer) ? current_queue_size : 0
    @last_stats_time = now

    # Send warning to Discord if queue size is too large
    return unless current_queue_size.is_a?(Integer) && current_queue_size > 10_000

    notifier.send_log('Performance Warning',
                      "Queue size has reached #{current_queue_size} domains!\n" +
                      "Currently processing at #{domains_per_second.round(2)} domains/sec",
                      :error)
  end

  def setup_websocket_connection(init)
    start_workers if init

    ws = WebSocket::EventMachine::Client.connect(uri: ws_url)

    ws.onerror { |e| logger.error("WS error: #{e.message}") }
    ws.onping  { ws.pong }
    ws.onpong  { logger.info('PONG received') }
    ws.onclose { shutdown }

    ws.onopen do
      logger.info('WS open')
      notifier.send_log('WebSocket', "WebSocket connection open\nQueue size: #{@queue.size}", :success)
    end

    ws.onmessage do |msg, _|
      parsed = JSON.parse(msg)
      # Extract domains efficiently from the message structure
      domains = parsed.dig('data', 'leaf_cert', 'all_domains') || []

      # Update statistics
      current_size = begin
        @queue.size
      rescue StandardError
        0
      end
      @queue_max_size = current_size if current_size > @queue_max_size

      # Pre-filter domains before adding to queue
      filtered_domains = domains.reject do |domain|
        domain.nil? || domain.empty? ||
          @exclusions_set.any? { |ex| domain.end_with?(ex) } ||
          @domain_cache[domain]
      end

      # Mark domains as queued in memory cache
      filtered_domains.each { |d| @domain_cache[d] = :queued }

      # Add only filtered domains to the queue
      filtered_domains.each { |d| queue.push(d) }
    rescue StandardError => e
      logger.error("Error parsing message: #{e.message}")
    end
  end

  # Start multiple workers
  def start_workers
    concurrency.times { process_next }
  end

  def process_next
    queue.pop do |domain|
      EM.defer(
        proc { process_domain(domain) },
        proc { process_next }
      )
    end
  end

  def process_domain(domain)
    # Increment counter for stats
    @processed_domains_count += 1

    # Skip if already processed (double check)
    return if @domain_cache[domain] != :queued

    # Clean the domain by removing wildcard prefix
    clean_domain = domain.sub(/\A\*\./, '')

    # Mark as processed in local cache to avoid reprocessing
    @domain_cache[domain] = :processed

    # Check for exclusions (safety backup)
    return if @exclusions_set.any? { |ex| clean_domain.end_with?(ex) }

    # Check if domain matches any wildcards
    match = db.domain_matches_wildcards(clean_domain)
    return unless match

    # Skip if already discovered in database
    return if @domain_cache[clean_domain] == :discovered || db.domain_already_discovered?(clean_domain)

    # Resolve domain to IP
    ip = resolver.resolve(clean_domain)

    if ip && !resolver.private_ip?(ip)
      # Domain resolved to public IP
      notifier.send_message(clean_domain, ip, match)
      fingerprinter.send(clean_domain)
      db.add_discovered_domain(clean_domain, ip, match['program'])
      # Update cache
      @domain_cache[clean_domain] = :discovered
    elsif ip.nil?
      # Domain not resolvable - add to batch for bulk processing
      add_to_unresolvable_batch(clean_domain, match['id'])
    end
  rescue StandardError => e
    logger.error("Error processing domain #{domain}: #{e.class} #{e.message}")
  end

  # Add domain to unresolvable batch
  def add_to_unresolvable_batch(domain, wildcard_id)
    @unresolvable_mutex.synchronize do
      @unresolvable_domains_batch << [domain, wildcard_id]

      # Process batch immediately if size threshold reached
      flush_unresolvable_domains_batch if @unresolvable_domains_batch.size >= @unresolvable_batch_size
    end
  end

  # Save unresolvable domains in batch
  def flush_unresolvable_domains_batch
    domains_to_save = nil

    @unresolvable_mutex.synchronize do
      return if @unresolvable_domains_batch.empty?

      domains_to_save = @unresolvable_domains_batch.dup
      @unresolvable_domains_batch.clear
    end

    # Use batch database operation if available
    if db.respond_to?(:add_unresolvable_domains_batch) && domains_to_save && !domains_to_save.empty?
      db.add_unresolvable_domains_batch(domains_to_save)
    elsif domains_to_save && !domains_to_save.empty?
      # Fallback to individual inserts if batch method not available
      domains_to_save.each do |domain, wildcard_id|
        db.add_unresolvable_domain(domain, wildcard_id)
      end
    end
  end

  def shutdown
    # Save any remaining unresolvable domains before closing
    flush_unresolvable_domains_batch

    logger.warn('WebSocket connection closed')
    notifier.send_log('WebSocket',
                      "WebSocket connection closed\nQueue size: #{@queue.size}\n\nAttempting to reconnect...", :error)

    # Wait before reconnecting to avoid rapid reconnection loops
    EM.add_timer(5) do
      logger.info('Attempting to reconnect WebSocket...')
      setup_websocket_connection(false)
    end
  end
end
