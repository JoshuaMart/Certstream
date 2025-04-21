# frozen_string_literal: true

require 'websocket-client-simple'
require 'json'

class CertstreamMonitor
  def initialize(ws_url, database, resolver, notifier, logger, exclusions, reconnect_interval = 5)
    @ws_url = ws_url
    @db = database
    @resolver = resolver
    @notifier = notifier
    @reconnect_interval = reconnect_interval
    @logger = logger
    @exclusions = exclusions
  end

  def start
    @logger.info('Starting Certstream monitor')

    connect_websocket
  end

  private

  def connect_websocket
    @logger.info("Connecting to Certstream websocket at #{@ws_url}")

    # Capture des références locales aux variables d'instance
    logger = @logger
    db = @db
    resolver = @resolver
    notifier = @notifier
    ws_url = @ws_url
    reconnect_interval = @reconnect_interval
    exclusions = @exclusions

    begin
      ws = WebSocket::Client::Simple.connect(ws_url)

      ws.on :open do
        logger.info("Certstream websocket connection established")
      end

      ws.on :message do |msg|
        begin
          case msg.type
          when :ping
            logger.debug("PING received, sending PONG")
            ws.send('', type: :pong) if ws.open?
          when :pong
            logger.debug("PONG received")
          when :close
            logger.warn("CLOSE message received from the server")
          else
            # Traitement direct du message
            if msg.data && !msg.data.empty?
              begin
                json_data = JSON.parse(msg.data)
                domains = json_data['data'] || []

                domains.each do |domain|
                  next if exclusions.any? { |exclusion| domain.end_with?(exclusion) }

                  domain = domain[2..] if domain.start_with?('*.')
                  matching_wildcard = db.domain_matches_wildcards(domain)
                  next unless matching_wildcard

                  logger.info("Domain #{domain} matched wildcard: #{matching_wildcard['pattern']}")

                  # Ignorer si déjà découvert
                  if db.domain_already_discovered?(domain)
                    logger.debug("Domain #{domain} already discovered, skipping")
                    next
                  end

                  # Résoudre l'IP
                  ip = resolver.resolve(domain)

                  if ip
                    logger.info("Resolved domain: #{domain} to IP: #{ip}")

                    # Ignorer IP privée
                    if resolver.private_ip?(ip)
                      logger.info("Domain #{domain} has private IP: #{ip}, skipping")
                    else
                      # Envoyer notification et enregistrer
                      notifier.send_alert(domain, ip, matching_wildcard)
                      db.add_discovered_domain(domain, ip, matching_wildcard['program'])
                    end
                  else
                    logger.info("Couldn't resolve #{domain}, adding to retry queue")
                    db.add_unresolvable_domain(domain, matching_wildcard['id'])
                  end
                end
              rescue JSON::ParserError => e
                logger.error("JSON parsing error: #{e.message}")
              end
            end
          end
        rescue => e
          logger.error("Error processing message: #{e.message}")
          logger.error(e.backtrace.join("\n"))
        end
      end

      ws.on :error do |e|
        logger.error("Certstream websocket error: #{e.message}")
      end

      ws.on :close do |e|
        logger.warn("Certstream websocket connection closed")

        # Reconnexion après délai
        logger.info("Reconnecting in #{reconnect_interval} seconds")
        sleep reconnect_interval
        connect_websocket
      end

      # Keep the connection alive
      loop do
        sleep 1
        if ws.open? && Time.now.to_i % 30 == 0
          logger.debug("Sending keepalive ping")
          ws.send('', type: :ping)
        end
      end
    rescue => e
      logger.error("Connection error: #{e.message}")
      logger.error(e.backtrace.join("\n"))

      # Reconnexion après délai
      logger.info("Reconnecting in #{reconnect_interval} seconds")
      sleep reconnect_interval
      retry
    end
  end
end
