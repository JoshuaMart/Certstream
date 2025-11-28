# frozen_string_literal: true

require 'typhoeus'
require 'json'
require 'yaml'

module Certstream
  class WildcardManager
    attr_reader :wildcards

    def initialize(config)
      @api_config = config['api']
      @update_interval = @api_config['update_interval'] || 86_400
      @wildcards_trie = {}
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
      # Check exclusions first (early return)
      return false if excluded_domain?(domain)

      # Fast Trie traversal (O(L) where L is number of domain parts)
      # No mutex needed as we read the atomic reference @wildcards_trie
      node = @wildcards_trie
      parts = domain.split('.').reverse

      parts.each do |part|
        return false unless node
        
        # If we hit a terminal node, it means we matched a wildcard
        # e.g. domain: app.example.com -> com -> example (terminal) -> match
        return true if node[:_end_]

        node = node[part]
      end

      # Check if the last node was terminal (exact match)
      # e.g. domain: example.com -> com -> example (terminal)
      node && node[:_end_]
    end

    private

    def excluded_domain?(domain)
      @exclusions.any? { |exclusion| domain.end_with?(exclusion) }
    end

    def fetch_wildcards
      headers = {}
      @api_config['headers']&.each { |key, value| headers[key] = value }

      response = Typhoeus.get(@api_config['url'], headers: headers)

      if response.code == 200
        new_wildcards = parse_response(response.body)
        update_wildcards(new_wildcards)
        puts "[WildcardManager] Updated wildcards (Trie built)"
      else
        puts "[WildcardManager] Failed to fetch wildcards: HTTP #{response.code}"
      end
    rescue StandardError => e
      puts "[WildcardManager] Error fetching wildcards: #{e.message}"
    end

    def parse_response(body)
      wildcards = Set.new

      data = JSON.parse(body)
      data.each_value do |programs|
        programs.each_value do |infos|
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
      trie = {}

      new_wildcards.each do |wildcard|
        # wildcard is like ".example.com"
        # We strip the leading dot and split
        parts = wildcard[1..].split('.').reverse
        
        node = trie
        parts.each do |part|
          node[part] ||= {}
          node = node[part]
        end
        node[:_end_] = true
      end

      # Atomic update
      @wildcards_trie = trie
      @last_update = Time.now
    end
  end
end
