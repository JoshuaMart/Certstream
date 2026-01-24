# frozen_string_literal: true

module Certstream
  class Fingerprinter
    def initialize(config, logger, stats)
      @url = config.fingerprinter['url']
      @api_key = config.fingerprinter['api_key']
      @callback_urls = config.fingerprinter['callback_urls'] || []
      @logger = logger
      @stats = stats
    end

    def send(domain, urls)
      # TODO: Implement fingerprinter integration
      @logger.debug('Fingerprinter', "Would send #{urls.size} URLs for #{domain}")
      @stats.increment(:fingerprinter_sent)
    end
  end
end
