require 'websocket-client-simple'
require 'json'

class CertstreamMonitor
  def initialize(ws_url, database, resolver, notifier, reconnect_interval = 5, logger)
    @ws_url = ws_url
    @db = database
    @resolver = resolver
    @notifier = notifier
    @reconnect_interval = reconnect_interval
    @logger = logger
    @ws = nil
  end

  def start
    @logger.info('Starting Certstream monitor')

    # Start the connection in a separate thread
    @thread = Thread.new do
      connect_websocket
    end
  end

  def stop
    @logger.info('Stopping Certstream monitor')
    @ws.close if @ws && @ws.open?
    @thread.exit if @thread && @thread.alive?
  end

  private

  def connect_websocket
    @logger.info("Connecting to Certstream websocket at #{@ws_url}")

    begin
      @ws = WebSocket::Client::Simple.connect(@ws_url)

      @ws.on :open do
        @logger.info('Certstream websocket connection established')
      end

      @ws.on :message do |msg|
        handle_message(msg)
      end

      @ws.on :error do |e|
        @logger.error("Certstream websocket error: #{e.message}")
      end

      @ws.on :close do |e|
        @logger.warn("Certstream websocket connection closed (code: #{e.code}, reason: #{e.reason})")

        # Attempt to reconnect after a delay
        @logger.info("Attempting to reconnect in #{@reconnect_interval} seconds")
        sleep @reconnect_interval
        connect_websocket
      end

      # Keep the thread running
      loop do
        sleep 1
        # Send ping every 30 seconds to keep the connection alive
        if @ws.open? && Time.now.to_i % 30 == 0
          @logger.debug('Sending PING to maintain connection')
          @ws.send('', type: :ping)
        end
      end
    rescue StandardError => e
      @logger.error("Error in websocket connection: #{e.message}")
      @logger.error(e.backtrace.join("\n"))

      # Attempt to reconnect after a delay
      @logger.info("Attempting to reconnect in #{@reconnect_interval} seconds")
      sleep @reconnect_interval
      retry
    end
  end

  def handle_message(msg)
    case msg.type
    when :ping
      @logger.debug('PING received, sending PONG')
      @ws.send('', type: :pong) if @ws.open?
    when :pong
      @logger.debug('PONG received')
    when :close
      @logger.warn('CLOSE message received from the server')
    else
      process_certstream_data(msg.data)
    end
  end

  def process_certstream_data(data)
    return if data.nil? || data.empty?

    begin
      # Parse the JSON message
      json_data = JSON.parse(data)

      # Extract the domain - certstream-go provides a simple array of domains
      domains = json_data['data'] || []

      domains.each do |domain|
        check_domain(domain)
      end
    rescue JSON::ParserError => e
      @logger.error("Error parsing Certstream JSON data: #{e.message}")
      @logger.debug("Raw message: #{data}")
    rescue StandardError => e
      @logger.error("Error processing Certstream data: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
    end
  end

  def check_domain(domain)
    return if domain.nil? || domain.empty?

    @logger.debug("Checking domain: #{domain}")

    # Check if the domain matches any of our wildcards
    matching_wildcard = @db.domain_matches_wildcards?(domain)

    return unless matching_wildcard

    @logger.info("Domain #{domain} matched wildcard: #{matching_wildcard['pattern']}")

    # Check if this domain has already been discovered
    if @db.domain_already_discovered?(domain)
      @logger.debug("Domain #{domain} already discovered, skipping")
      return
    end

    # Try to resolve the domain
    ip = @resolver.resolve(domain)

    if ip
      @logger.info("Successfully resolved domain: #{domain} to IP: #{ip}")

      # Check if IP is private
      if @resolver.private_ip?(ip)
        @logger.info("Domain #{domain} resolved to private IP: #{ip}, skipping")
        return
      end

      # Send notification
      @logger.info("Sending notification for domain: #{domain}")
      @notifier.send_alert(domain, ip, matching_wildcard)

      # Add to discovered domains
      @db.add_discovered_domain(domain, ip, matching_wildcard['program'])
    else
      @logger.info("Could not resolve domain: #{domain}, adding to unresolvable domains")
      @db.add_unresolvable_domain(domain, matching_wildcard['id'])
    end
  end
end
