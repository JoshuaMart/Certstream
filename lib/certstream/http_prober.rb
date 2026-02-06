# frozen_string_literal: true

require 'async'

module Certstream
  class HttpProber
    PROBE_TIMEOUT = 15 # seconds

    def initialize(config, logger)
      @ports = config.http['ports']
      @timeout = config.http['timeout']
      @logger = logger
      @http = HttpClient.new(connect_timeout: @timeout, read_timeout: @timeout, verify_ssl: false)
    end

    def probe(domain)
      urls = build_urls(domain)
      return [] if urls.empty?

      active_urls = probe_urls(urls, domain)

      @logger.debug('HTTP', "#{domain} -> #{active_urls.size} active URLs") if active_urls.any?

      active_urls
    rescue StandardError => e
      @logger.error('HTTP', "Error probing #{domain}: #{e.class} - #{e.message}")
      []
    end

    private

    def build_urls(domain)
      @ports.map do |port_config|
        protocol = port_config['protocol']
        port = port_config['port']

        if default_port?(protocol, port)
          "#{protocol}://#{domain}"
        else
          "#{protocol}://#{domain}:#{port}"
        end
      end
    end

    def default_port?(protocol, port)
      (protocol == 'http' && port == 80) || (protocol == 'https' && port == 443)
    end

    def probe_urls(urls, domain)
      Async do |task|
        task.with_timeout(PROBE_TIMEOUT) do
          urls.filter_map { |url| probe_single(url) }
        end
      rescue Async::TimeoutError
        @logger.error('HTTP', "Probe timeout for #{domain} (#{PROBE_TIMEOUT}s)")
        []
      end.wait
    end

    def probe_single(url)
      @http.head(url)
      url
    rescue HttpClient::RequestError
      nil
    end
  end
end
