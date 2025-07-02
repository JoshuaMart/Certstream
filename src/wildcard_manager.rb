# frozen_string_literal: true

require 'typhoeus'
require 'json'
require 'yaml'
require 'set'

module Certstream
  class WildcardManager
    attr_reader :wildcards

    def initialize(config)
      @api_config = config['api']
      @update_interval = @api_config['update_interval'] || 86400
      @wildcards = Set.new
      @exclusions = config.dig('certstream', 'exclusions') || []
      @last_update = nil
      @mutex = Mutex.new
    end

    def start_updater
      # Initial fetch
      fetch_wildcards

      # Start background thread for periodic updates
      Thread.new do
        loop do
          sleep(@update_interval)
          fetch_wildcards
        end
      end
    end

    def match_domain?(domain)
      # Thread-safe read access
      @mutex.synchronize do
        # Check exclusions first (early return)
        return false if excluded_domain?(domain)

        @wildcards.any? { |wildcard| domain.end_with?(wildcard) }
      end
    end

    private

    def excluded_domain?(domain)
      @exclusions.any? { |exclusion| domain.end_with?(exclusion) }
    end

    def fetch_wildcards
      headers = {}
      @api_config['headers']&.each { |key, value| headers[key] = value }

      response = Typhoeus.get(@api_config['url'], headers:)

      if response.code == 200
        new_wildcards = parse_response(response.body)
        update_wildcards(new_wildcards)
        puts "[WildcardManager] Updated #{@wildcards.size} wildcards"
      else
        puts "[WildcardManager] Failed to fetch wildcards: HTTP #{response.code}"
      end
    rescue => e
      puts "[WildcardManager] Error fetching wildcards: #{e.message}"
    end

    def parse_response(body)
      wildcards = Set.new

      data = JSON.parse(body)
      data.each_value do |programs|
        programs.each do |name, infos|
          scopes = infos.dig('scopes', 'in', 'web')
          next unless scopes

          scopes.each do |scope|
            wildcards << scope[1..] if scope.start_with?('*.')
          end
        end
      end

      wildcards
    rescue JSON::ParserError => e
      puts "[WildcardManager] JSON parse error: #{e.message}"
      Set.new
    end

    def update_wildcards(new_wildcards)
      @mutex.synchronize do
        @wildcards = new_wildcards
        @last_update = Time.now
      end
    end
  end
end
