require 'websocket-eventmachine-client'
require 'json'

class CertstreamMonitor
  attr_reader :ws_url, :db, :resolver, :notifier, :fingerprinter, :logger, :exclusions, :executor

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
    EM.threadpool_size = @concurrency * 2
    EM.run do
      start_workers

      ws = WebSocket::EventMachine::Client.connect(uri: ws_url)

      ws.onopen  { logger.info('WS open') }
      ws.onerror { |e| logger.error("WS error: #{e.message}") }
      ws.onping  do
        logger.info('PING received')
        ws.pong
      end
      ws.onpong  { logger.info('PONG received') }
      ws.onclose { |c, r| shutdown(c, r) }

      ws.onmessage do |msg, _|
        domains = JSON.parse(msg)['data'] || []
        domains.each { |d| @queue.push(d) }
      rescue StandardError => e
        logger.error("Erreur parse message: #{e.message}")
      end
    end
  end

  private

  # Lance N workers qui tournent tant que la queue a des messages
  def start_workers
    @concurrency.times { process_next }
  end

  # Dès qu'un domaine arrive, EM.defer traite et rappelle process_next à la fin
  def process_next
    @queue.pop do |domain|
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
      notifier.send_alert(domain, ip, match)
      fingerprinter.send(domain)
      db.add_discovered_domain(domain, ip, match['program'])
    elsif ip.nil?
      db.add_unresolvable_domain(domain, match['id'])
    end
  rescue StandardError => e
    logger.error("Error with #{domain} : #{e.class} #{e.message}")
  end

  def shutdown(code, reason)
    logger.warn("WS closed (#{code}): #{reason}")
    EM.stop
  end
end
