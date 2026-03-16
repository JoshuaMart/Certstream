# frozen_string_literal: true

require 'json'

module Certstream
  class ReconApi
    def initialize(config, logger, stats)
      @url = config.recon_api&.fetch('url', nil)
      @api_key = config.recon_api&.fetch('api_key', nil)
      @logger = logger
      @stats = stats
      @http = HttpClient.new(connect_timeout: 5, read_timeout: 30, headers: build_headers)
    end

    def send(urls)
      return if @url.nil? || @url.empty?

      urls.each do |url|
        @logger.debug('ReconApi', "Sending URL to Recon API: #{url}")
        response = @http.post(@url, json: { 'url' => url })
        handle_response(response, url)
      rescue HttpClient::RequestError => e
        handle_error(e, url)
      end
    end

    private

    def handle_response(response, url)
      if response.code.to_i.between?(200, 299)
        @stats.increment(:recon_api_sent)
        @logger.debug('ReconApi', "Sent #{url} -> #{response.code}")
      else
        @stats.increment(:recon_api_failed)
        @logger.warn('ReconApi', "Failed for #{url} -> #{response.code}")
      end
    end

    def handle_error(error, url)
      @stats.increment(:recon_api_failed)
      @logger.error('ReconApi', "Error for #{url}: #{error.message}")
    end

    def build_headers
      headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
      headers['X-API-Key'] = @api_key if @api_key
      headers
    end
  end
end
