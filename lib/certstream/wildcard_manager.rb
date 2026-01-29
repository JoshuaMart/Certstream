# frozen_string_literal: true

require 'async'
require 'httpx'
require 'json'

module Certstream
  class WildcardManager
    TRIE_END_MARKER = :_end_

    def initialize(config, logger)
      @apis = config.apis
      @update_interval = config.wildcards_update_interval
      @exclusions = config.certstream['exclusions'] || []
      @logger = logger
      @trie = {}
      @mutex = Mutex.new
    end

    def start
      fetch_all_wildcards
      start_periodic_update
    end

    def match?(domain)
      !find_match(domain).nil?
    end

    def find_match(domain)
      return nil if excluded?(domain)

      parts = domain.downcase.split('.').reverse
      @mutex.synchronize { traverse_trie(parts) }
    end

    def count
      @mutex.synchronize { count_wildcards(@trie) }
    end

    private

    def excluded?(domain)
      @exclusions.any? { |exclusion| domain.end_with?(exclusion) }
    end

    def traverse_trie(parts)
      node = @trie
      matched_parts = []

      parts.each_with_index do |part, index|
        return nil unless node.key?(part)

        matched_parts << part
        node = node[part]

        remaining_parts = parts.size - index - 1
        return "*.#{matched_parts.reverse.join('.')}" if node[TRIE_END_MARKER] && remaining_parts >= 1
      end
      nil
    end

    def count_wildcards(node, total = 0)
      node.each do |key, value|
        if key == TRIE_END_MARKER
          total += 1
        elsif value.is_a?(Hash)
          total = count_wildcards(value, total)
        end
      end
      total
    end

    def fetch_all_wildcards
      new_trie = {}

      @apis.each do |api|
        wildcards = fetch_from_api(api)
        wildcards.each { |wildcard| insert_into_trie(new_trie, wildcard) }
        @logger.info('WildcardManager', "Fetched #{wildcards.size} wildcards from #{api['name']}")
      rescue StandardError => e
        @logger.error('WildcardManager', "Failed to fetch from #{api['name']}: #{e.message}")
      end

      old_count = count
      @mutex.synchronize { @trie = new_trie }
      new_count = count
      @logger.info('WildcardManager', "Total wildcards loaded: #{new_count} (was: #{old_count})")
      @logger.warn('WildcardManager', 'Trie is now EMPTY after refresh!') if new_count.zero?
    end

    def fetch_from_api(api)
      response = HTTPX.with(timeout: { request_timeout: 30 })
                      .with(headers: api['headers'] || {})
                      .get(api['url'])

      raise "HTTP #{response.status}" unless response.status == 200

      parse_wildcards(response.body.to_s)
    end

    def parse_wildcards(body)
      data = JSON.parse(body)
      wildcards = data['wildcards'] || []
      wildcards.filter_map { |w| normalize_wildcard(w) }
    end

    def normalize_wildcard(entry)
      return nil unless entry.is_a?(Hash)

      value = entry['value']
      return nil unless value.is_a?(String)

      wildcard = value.strip.downcase.sub(/^\*\./, '')
      wildcard.empty? ? nil : wildcard
    end

    def insert_into_trie(trie, wildcard)
      parts = wildcard.split('.').reverse
      node = trie
      parts.each do |part|
        node[part] ||= {}
        node = node[part]
      end
      node[TRIE_END_MARKER] = true
    end

    def start_periodic_update
      Async do
        loop do
          sleep @update_interval
          @logger.info('WildcardManager', 'Refreshing wildcards...')
          fetch_all_wildcards
        end
      rescue StandardError => e
        @logger.error('WildcardManager', "Periodic update crashed: #{e.class} - #{e.message}")
      end
    end
  end
end
