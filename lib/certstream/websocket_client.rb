# frozen_string_literal: true

require 'async'
require 'async/websocket/client'
require 'async/http/endpoint'
require 'json'

module Certstream
  class WebsocketClient
    RECONNECT_DELAYS = [1, 2, 5, 10, 30].freeze

    def initialize(config, logger, &on_domains)
      @url = config.certstream['url']
      @logger = logger
      @on_domains = on_domains
      @reconnect_attempt = 0
      @running = false
    end

    def start
      @running = true
      connect
    end

    def stop
      @running = false
    end

    private

    def connect
      endpoint = Async::HTTP::Endpoint.parse(@url)

      Async::WebSocket::Client.connect(endpoint) do |connection|
        @logger.info('WebSocket', "Connected to #{@url}")
        @reconnect_attempt = 0

        while @running && (message = connection.read)
          process_message(message)
        end
      end
    rescue StandardError => e
      handle_disconnect(e)
    end

    def process_message(message)
      data = JSON.parse(message.to_str)
      domains = extract_domains(data)
      @logger.debug('WebSocket', "Received #{domains.size} domains") if domains.any?
      @on_domains.call(domains) if domains.any?
    rescue JSON::ParserError => e
      @logger.debug('WebSocket', "Invalid JSON: #{e.message}")
    rescue StandardError => e
      @logger.error('WebSocket', "Error in process_message: #{e.class} - #{e.message}")
    end

    def extract_domains(data)
      return data['data'] if data['data'].is_a?(Array)

      []
    end

    def handle_disconnect(error)
      return unless @running

      delay = RECONNECT_DELAYS.fetch(@reconnect_attempt, RECONNECT_DELAYS.last)
      @reconnect_attempt += 1

      @logger.warn('WebSocket', "Disconnected: #{error.message}. Reconnecting in #{delay}s...")
      sleep delay
      connect
    end
  end
end
