# frozen_string_literal: true

require 'async'

module Certstream
  class Monitor
    def initialize(config, logger)
      @config = config
      @logger = logger
      @shutdown_timeout = config.shutdown['timeout']
      @running = false
    end

    def run
      @running = true
      setup_signal_handlers

      Async do |task|
        @task = task
        initialize_components
        start_services
        wait_for_shutdown
      end
    end

    private

    def initialize_components
      @discord_notifier = DiscordNotifier.new(@config, @logger)
      @stats = Stats.new(@config, @logger, @discord_notifier)
      @wildcard_manager = WildcardManager.new(@config, @logger)
      @dns_resolver = DnsResolver.new(@logger)
      @http_prober = HttpProber.new(@config, @logger)
      @fingerprinter = Fingerprinter.new(@config, @logger, @stats)

      @context = Context.new(
        config: @config,
        logger: @logger,
        stats: @stats,
        wildcard_manager: @wildcard_manager,
        dns_resolver: @dns_resolver,
        http_prober: @http_prober,
        fingerprinter: @fingerprinter,
        discord_notifier: @discord_notifier
      )

      @domain_processor = DomainProcessor.new(@context)
    end

    def start_services
      @logger.info('Monitor', 'Starting services...')

      @wildcard_manager.start
      @stats.start_reporting

      @websocket_client = WebsocketClient.new(@config, @logger) do |domains|
        @domain_processor.process(domains)
      end

      @websocket_client.start
    end

    def setup_signal_handlers
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { initiate_shutdown }
      end
    end

    def initiate_shutdown
      return unless @running

      @running = false
      @logger.info('Monitor', 'Shutdown signal received, stopping...')

      Async do
        graceful_shutdown
      end
    end

    def graceful_shutdown
      @websocket_client&.stop

      @logger.info('Monitor', "Waiting up to #{@shutdown_timeout}s for tasks to complete...")
      sleep 1 # Allow pending tasks to complete

      send_final_stats
      @logger.info('Monitor', 'Shutdown complete')

      @task&.stop
    end

    def send_final_stats
      @logger.info('Monitor', 'Sending final statistics...')
      @stats.log_to_console
      @discord_notifier.notify_stats(@stats.to_h)
    rescue StandardError => e
      @logger.error('Monitor', "Failed to send final stats: #{e.message}")
    end

    def wait_for_shutdown
      sleep 0.1 while @running
    end
  end
end
