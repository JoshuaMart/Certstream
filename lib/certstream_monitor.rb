# frozen_string_literal: true

require 'websocket-eventmachine-client'
require 'json'

class CertstreamMonitor
  attr_reader :ws_url, :db, :resolver, :notifier, :fingerprinter, :logger, :exclusions, :queue, :concurrency

  def initialize(ws_url, db, resolver, notifier, fingerprinter, logger, exclusions, concurrency: 10)
    @ws_url        = ws_url
    @db            = db
    @resolver      = resolver
    @notifier      = notifier
    @fingerprinter = fingerprinter
    @logger        = logger
    @exclusions    = exclusions
    @queue         = EM::Queue.new
    @concurrency   = concurrency
  end

  def connect_websocket
    EM.threadpool_size = concurrency * 2
    EM.run do
      setup_websocket_connection
    end
  end

  private

  def setup_websocket_connection(init = true)
    start_workers if init

    ws = WebSocket::EventMachine::Client.connect(uri: ws_url)

    ws.onerror { |e| logger.error("WS error: #{e.message}") }
    ws.onpong  { logger.info('PONG received') }
    ws.onclose { shutdown }

    ws.onopen do
      logger.info('WS open')
      notifier.send_log("WebSocket", 'WebSocket connection open', :success)
    end

    ws.onping  do
      logger.info('PING received')
      ws.pong
    end

    ws.onmessage do |msg, _|
      domains = JSON.parse(msg)['data'] || []
      domains.each { |d| queue.push(d) }
    rescue StandardError => e
      logger.error("Erreur parse message: #{e.message}")
    end
  end

  # Launches N workers that run as long as the queue has messages
  def start_workers
    concurrency.times { process_next }
  end

  # As soon as a domain arrives, EM.defer processes it and calls back process_next at the end.
  def process_next
    queue.pop do |domain|
      EM.defer(
        proc { process_domain(domain) },
        proc { process_next }
      )
    end
  end

  def process_domain(domain)
    return if exclusions.any? { |ex| domain.end_with?(ex) }

    domain = domain.sub(/\A\*\./, '')

    match = db.domain_matches_wildcards(domain) or return
    return if db.domain_already_discovered?(domain)

    ip = resolver.resolve(domain)
    if ip && !resolver.private_ip?(ip)
      notifier.send_message(domain, ip, match)
      fingerprinter.send(domain)
      db.add_discovered_domain(domain, ip, match['program'])
    elsif ip.nil?
      db.add_unresolvable_domain(domain, match['id'])
    end
  rescue StandardError => e
    logger.error("Error with #{domain} : #{e.class} #{e.message}")
  end

  def shutdown
    logger.warn("WebSocket connection closed")

    notifier.send_log("WebSocket", 'WebSocket connection closed, attempting to reconnect...', :error)

    # Wait a while before reconnecting to avoid rapid reconnection loops.
    EM.add_timer(5) do
      logger.info("Attempting to reconnect WebSocket...")
      setup_websocket_connection(false)
    end
  end
end
