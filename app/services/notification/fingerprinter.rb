# frozen_string_literal: true

require 'httparty'
require 'net/http'
require 'uri'
require 'timeout'
require 'concurrent-ruby'

module Certstream
  module Services
    module Notification
      class Fingerprinter
        attr_reader :fingerprinter_url, :callback_urls, :api_key

        # Ports and protocols to test
        CONNECTIVITY_TESTS = [
          { protocol: 'http', port: 80 },
          { protocol: 'https', port: 443 },
          { protocol: 'http', port: 8080 },
          { protocol: 'https', port: 8443 },
          { protocol: 'https', port: 9090 },
          { protocol: 'http', port: 3000 },
          { protocol: 'https', port: 8000 },
          { protocol: 'https', port: 8888 },
          { protocol: 'http', port: 9000 },
          { protocol: 'https', port: 10443 }
        ].freeze

        def initialize(fingerprinter_url, callback_urls, api_key)
          @fingerprinter_url = fingerprinter_url
          @api_key = api_key
          @callback_urls = callback_urls
        end

        def send(domain)
          Core.container.logger.info("Checking connectivity for #{domain} before fingerprinting")

          # Test connectivity on various ports
          reachable_urls = test_connectivity(domain)

          if reachable_urls.empty?
            Core.container.logger.info("#{domain} is not reachable on any tested ports, skipping fingerprinter")
            return
          end

          Core.container.logger.info("#{domain} is reachable on #{reachable_urls.size} endpoint(s), sending to fingerprinter")

          # Send all reachable URLs to fingerprinter
          send_to_fingerprinter(reachable_urls)
        end

        private

        def test_connectivity(domain)
          reachable_urls = []
          
          # Use concurrent execution to test multiple ports simultaneously
          futures = CONNECTIVITY_TESTS.map do |test|
            Concurrent::Future.execute do
              url = "#{test[:protocol]}://#{domain}:#{test[:port]}"
              if test_url_connectivity(url)
                Core.container.logger.debug("✓ #{url} is reachable")
                url
              else
                Core.container.logger.debug("✗ #{url} is not reachable")
                nil
              end
            end
          end

          # Collect results from all futures
          futures.each do |future|
            begin
              result = future.value(5) # 5 seconds timeout for each future
              reachable_urls << result if result
            rescue Concurrent::TimeoutError
              Core.container.logger.debug("Timeout testing connectivity")
            rescue StandardError => e
              Core.container.logger.debug("Error in connectivity test: #{e.message}")
            end
          end

          reachable_urls
        end

        def test_url_connectivity(url)
          begin
            uri = URI.parse(url)
            
            # Create HTTP connection with timeout
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == 'https')
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE if uri.scheme == 'https' # Skip SSL verification for connectivity test
            http.open_timeout = 3
            http.read_timeout = 3
            
            # Make a simple HEAD request to test connectivity
            Timeout.timeout(5) do
              response = http.request_head('/')
              # Any response (even error codes) means the service is reachable
              return true
            end
          rescue Timeout::Error
            Core.container.logger.debug("Timeout connecting to #{url}")
            false
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH
            Core.container.logger.debug("Connection refused/unreachable for #{url}")
            false
          rescue SocketError
            Core.container.logger.debug("DNS resolution failed for #{url}")
            false
          rescue OpenSSL::SSL::SSLError
            # SSL error means the port is open but SSL handshake failed
            # This still counts as "reachable" for our purposes
            Core.container.logger.debug("SSL error for #{url}, but port is open")
            true
          rescue StandardError => e
            Core.container.logger.debug("Unexpected error testing #{url}: #{e.class} - #{e.message}")
            false
          end
        end

        def send_to_fingerprinter(urls)
          Core.container.logger.info("Sending #{urls.size} reachable URLs to fingerprinter")

          payload = {
            urls: urls,
            callback_urls: callback_urls
          }

          headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{api_key}" }

          response = HTTParty.post(
            fingerprinter_url,
            body: payload.to_json,
            headers: headers
          )

          if response.code.between?(200, 299)
            Core.container.logger.info("Successfully sent #{urls.size} URLs to fingerprinter")
          else
            Core.container.logger.error("Failed to send URLs to fingerprinter: #{response.code} - #{response.body}")
          end
        rescue StandardError => e
          Core.container.logger.error("Error sending to fingerprinter: #{e.message}")
        end
      end
    end
  end
end
