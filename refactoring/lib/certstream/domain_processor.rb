# frozen_string_literal: true

require 'async'

module Certstream
  class DomainProcessor
    def initialize(context)
      @config = context.config
      @logger = context.logger
      @stats = context.stats
      @wildcard_manager = context.wildcard_manager
      @dns_resolver = context.dns_resolver
      @http_prober = context.http_prober
      @fingerprinter = context.fingerprinter
      @discord_notifier = context.discord_notifier
      @exclusions = @config.certstream['exclusions'] || []
    end

    def process(domains)
      domains.each do |domain|
        @stats.increment(:total_processed)
        process_domain(domain)
      end
    end

    private

    def process_domain(domain)
      return if skip_domain?(domain)
      return unless @wildcard_manager.match?(domain)

      @stats.increment(:matched_domains)
      @logger.info('Processor', "Match: #{domain}")

      Async { process_matched_domain(domain) }
    end

    def skip_domain?(domain)
      return true if domain.start_with?('*.')
      return true if excluded?(domain)

      false
    end

    def excluded?(domain)
      @exclusions.any? { |exclusion| domain.end_with?(exclusion) }
    end

    def process_matched_domain(domain)
      @discord_notifier.notify_match(domain)

      ips = @dns_resolver.resolve(domain)
      if ips.empty?
        @stats.increment(:dns_failed)
        return
      end
      @stats.increment(:dns_resolved)

      urls = @http_prober.probe(domain)
      if urls.empty?
        @stats.increment(:http_timeout)
        return
      end
      @stats.increment(:http_responses)

      @fingerprinter.send(domain, urls)
    end
  end
end
