# frozen_string_literal: true

require 'json'

module Certstream
  class Fingerprinter
    def initialize(config, logger, stats)
      @url = config.fingerprinter['url']
      @api_key = config.fingerprinter['api_key']
      @callback_urls = config.fingerprinter['callback_urls'] || []
      @logger = logger
      @stats = stats
      @http = HttpClient.new(connect_timeout: 5, read_timeout: 30, headers: build_headers)
    end

    def send(domain, urls)
      return if @url.nil? || @url.empty?

      @logger.debug('Fingerprinter', 'Send URLs to fingerprinter')
      response = perform_request(urls)
      handle_response(response, domain, urls.size)
    rescue HttpClient::RequestError => e
      handle_error(e, domain, urls.size)
    end

    private

    def perform_request(urls)
      @http.post(@url, json: build_payload(urls))
    end

    def handle_response(response, domain, count)
      if response.code.to_i.between?(200, 299)
        @stats.increment(:fingerprinter_sent, count)
        @logger.debug('Fingerprinter', "Sent #{count} URLs for #{domain} -> #{response.code}")
      else
        @stats.increment(:fingerprinter_failed, count)
        @logger.warn('Fingerprinter', "Failed for #{domain} -> #{response.code}")
      end
    end

    def handle_error(error, domain, count)
      @stats.increment(:fingerprinter_failed, count)
      @logger.error('Fingerprinter', "Error for #{domain}: #{error.message}")
    end

    def build_headers
      headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
      headers['Authorization'] = "Bearer #{@api_key}" if @api_key
      headers
    end

    def build_payload(urls)
      {
        'urls' => urls,
        'callback_urls' => @callback_urls
      }
    end
  end
end
