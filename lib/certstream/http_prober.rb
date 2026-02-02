# frozen_string_literal: true

require 'httpx'
require 'async'
require 'async/semaphore'

module Certstream
  class HttpProber
    PROBE_TIMEOUT = 15 # seconds
    MAX_CONCURRENT_PROBES = 5

    def initialize(config, logger)
      @ports = config.http['ports']
      @timeout = config.http['timeout']
      @logger = logger
      @semaphore = Async::Semaphore.new(MAX_CONCURRENT_PROBES)
    end

    def probe(domain)
      urls = build_urls(domain)
      return [] if urls.empty?

      responses = send_requests_with_timeout(urls, domain)
      return [] if responses.nil? || responses.empty?

      active_urls = extract_active_urls(responses)

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

    def send_requests_with_timeout(urls, domain)
      @semaphore.acquire do
        Async do |task|
          task.with_timeout(PROBE_TIMEOUT) do
            send_requests(urls)
          end
        rescue Async::TimeoutError
          @logger.error('HTTP', "Probe timeout for #{domain} (#{PROBE_TIMEOUT}s)")
          []
        end.wait
      end
    end

    def send_requests(urls)
      http = HTTPX.with(timeout: { connect_timeout: @timeout, request_timeout: @timeout })
                  .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

      http.head(*urls)
    rescue HTTPX::Error => e
      @logger.error('HTTP', "HTTPX error during requests: #{e.message}")
      []
    end

    def extract_active_urls(responses)
      responses = [responses] unless responses.is_a?(Array)

      urls = responses.filter_map do |response|
        next if response.is_a?(HTTPX::ErrorResponse)

        response.uri.to_s
      end

      urls.uniq
    end
  end
end
