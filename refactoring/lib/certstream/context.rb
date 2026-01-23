# frozen_string_literal: true

module Certstream
  class Context
    attr_reader :config, :logger, :stats, :wildcard_manager, :dns_resolver,
                :http_prober, :fingerprinter, :discord_notifier

    def initialize(config:, logger:, stats:, wildcard_manager:, dns_resolver:,
                   http_prober:, fingerprinter:, discord_notifier:)
      @config = config
      @logger = logger
      @stats = stats
      @wildcard_manager = wildcard_manager
      @dns_resolver = dns_resolver
      @http_prober = http_prober
      @fingerprinter = fingerprinter
      @discord_notifier = discord_notifier
    end
  end
end
