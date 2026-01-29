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
      @seen_domains = Set.new
      @seen_mutex = Mutex.new
    end

    def process(domains)
      @logger.debug('Processor', "Processing batch of #{domains.size} domains")
      domains.each do |domain|
        @stats.increment(:total_processed)
        process_domain(domain)
      end
    rescue StandardError => e
      @logger.error('Processor', "Error in process: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end

    private

    def process_domain(domain)
      return if skip_domain?(domain)

      matched_wildcard = @wildcard_manager.find_match(domain)
      return unless matched_wildcard
      return if already_seen?(domain)

      @stats.increment(:matched_domains)
      @logger.info('Processor', "Match: #{domain} (#{matched_wildcard})")

      Async { process_matched_domain(domain, matched_wildcard) }
    rescue StandardError => e
      @logger.error('Processor', "Error in process_domain for #{domain}: #{e.class} - #{e.message}")
    end

    def skip_domain?(domain)
      return true if domain.start_with?('*.')
      return true if excluded?(domain)

      false
    end

    def excluded?(domain)
      @exclusions.any? { |exclusion| domain.end_with?(exclusion) }
    end

    def already_seen?(domain)
      @seen_mutex.synchronize do
        return true if @seen_domains.include?(domain)

        @seen_domains.add(domain)
        false
      end
    end

    def process_matched_domain(domain, matched_wildcard)
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

      @discord_notifier.notify_match(
        domain: domain,
        wildcard: matched_wildcard,
        ips: ips,
        urls: urls
      )

      @fingerprinter.send(domain, urls)
    end
  end
end
