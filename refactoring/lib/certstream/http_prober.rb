# frozen_string_literal: true

require 'httpx'

module Certstream
  class HttpProber
    def initialize(config, logger)
      @ports = config.http['ports']
      @timeout = config.http['timeout']
      @logger = logger
    end

    def probe(domain)
      urls = build_urls(domain)
      return [] if urls.empty?

      responses = send_requests(urls)
      active_urls = extract_active_urls(responses)

      @logger.debug('HTTP', "#{domain} -> #{active_urls.size} active URLs") if active_urls.any?

      active_urls
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

    def send_requests(urls)
      http = HTTPX.plugin(:follow_redirects)
                  .with(timeout: { connect_timeout: @timeout, request_timeout: @timeout })
                  .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

      http.head(*urls)
    end

    def extract_active_urls(responses)
      responses = [responses] unless responses.is_a?(Array)

      responses.filter_map do |response|
        next if response.is_a?(HTTPX::ErrorResponse)

        response.uri.to_s
      end
    end
  end
end
