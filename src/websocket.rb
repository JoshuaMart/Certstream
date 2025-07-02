# frozen_string_literal: true

require 'websocket-eventmachine-client'
require 'json'
require_relative 'wildcard_manager'

module Certstream
  class Monitor
    def initialize(config_path = 'src/config.yml')
      config = YAML.load_file(config_path)

      @ws_url = config.dig('certstream', 'url')
      @wildcard_manager = WildcardManager.new(config)
      @stats = {
        total_processed: 0,
        matched_domains: 0,
        start_time: Time.now
      }
    end

    def run
      # Start wildcard updater in background
      @wildcard_manager.start_updater
      puts "[Monitor] Wildcard manager started"

      # Start stats reporter
      start_stats_reporter

      EM.run do
        ws = WebSocket::EventMachine::Client.connect(uri: @ws_url)

        ws.onerror { |e| puts "WS error: #{e.message}" }
        ws.onping  { ws.pong }
        ws.onclose { shutdown }

        ws.onopen do
          puts '[Monitor] WebSocket connected'
        end

        ws.onmessage do |msg, _|
          domains = JSON.parse(msg)['data'] || []
          process_domains(domains)
        end
      end
    end

    private

    def process_domains(domains)
      domains.each do |domain|
        @stats[:total_processed] += 1

        # Fast wildcard matching - this should be very quick
        next unless @wildcard_manager.match_domain?(domain)

        @stats[:matched_domains] += 1
        handle_matched_domain(domain)
      end
    end

    def handle_matched_domain(domain)
      # puts "[MATCH] #{domain}"
      # TODO
    end

    def start_stats_reporter
      Thread.new do
        loop do
          sleep(60) # Report every minute
          print_stats
        end
      end
    end

    def print_stats
      uptime = Time.now - @stats[:start_time]
      rate = @stats[:total_processed] / uptime
      match_rate = (@stats[:matched_domains].to_f / @stats[:total_processed] * 100).round(2)

      puts "[STATS] Processed: #{@stats[:total_processed]} | Matched: #{@stats[:matched_domains]} (#{match_rate}%) | Rate: #{rate.round(1)}/s"
    end

    def shutdown
      puts '[Monitor] WebSocket closed'
      EM.stop
    end
  end
end
