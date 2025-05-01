# frozen_string_literal: true

require 'httparty'

module Certstream
  module Services
    module Notification
      class Fingerprinter
        attr_reader :fingerprinter_url, :callback_url, :api_key

        def initialize(fingerprinter_url, callback_url, api_key)
          @fingerprinter_url = fingerprinter_url
          @api_key = api_key
          @callback_url = callback_url
        end

        def send(domain)
          Core.container.logger.info("Sending #{domain} to fingerprinter")

          payload = {
            urls: [domain],
            callback_url: callback_url
          }

          headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{api_key}" }

          response = HTTParty.post(
            fingerprinter_url,
            body: payload.to_json,
            headers: headers
          )

          if response.code.between?(200, 299)
            Core.container.logger.info("Successfully sent #{domain} to fingerprinter")
          else
            Core.container.logger.error("Failed to send domain to fingerprinter: #{response.code} - #{response.body}")
          end
        rescue StandardError => e
          Core.container.logger.error("Error sending to fingerprinter: #{e.message}")
        end
      end
    end
  end
end
