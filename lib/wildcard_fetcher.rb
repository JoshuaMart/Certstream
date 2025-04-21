# frozen_string_literal: true

require 'httparty'
require 'json'

class WildcardFetcher
  def initialize(api_url, headers, database, logger)
    @api_url = api_url
    @headers = headers
    @db = database
    @logger = logger
  end

  def fetch_wildcards
    @logger.info("Fetching wildcards from API: #{@api_url}")

    begin
      response = HTTParty.get(
        @api_url,
        headers: @headers
      )

      if response.code != 200
        @logger.error("Failed to fetch wildcards. Status code: #{response.code}")
        @logger.error("Response: #{response.body}")
        return
      end

      json_data = JSON.parse(response.body)

      @logger.info('Successfully fetched wildcards data')

      # Clear existing wildcards from database
      @db.clear_wildcards

      # Extract wildcards from JSON response
      extract_wildcards(json_data)

      @logger.info('Wildcards updated successfully')
    rescue JSON::ParserError => e
      @logger.error("Error parsing wildcards JSON: #{e.message}")
    rescue StandardError => e
      @logger.error("Error fetching wildcards: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
    end
  end

  private

  def extract_wildcards(json_data)
    # Process through the entire JSON structure to find wildcards
    wildcards_count = 0

    # The JSON format from the provided example has a structure where programs are keys
    json_data.each do |program_id, program_data|
      # Skip if not a Hash
      next unless program_data.is_a?(Hash)

      program_name = program_data['slug'] || program_id

      # Process scopes if they exist
      if program_data['scopes'] && program_data['scopes']['in']
        process_scope(program_data['scopes']['in'], program_name)
        wildcards_count += 1
      end
    end

    @logger.info("Extracted wildcards for #{wildcards_count} programs")
  end

  def process_scope(scope, program_name)
    # Check for URL scopes which contain wildcards
    if scope['url'].is_a?(Array)
      scope['url'].each do |url|
        # Check if the URL contains a wildcard
        if url.include?('*.')
          @logger.debug("Found wildcard: #{url} in program: #{program_name}")
          @db.add_wildcard(url, program_name)
        end
      end
    end

    # Also check other fields that might contain wildcards
    %w[other mobile executable].each do |field|
      next unless scope[field].is_a?(Array)

      scope[field].each do |item|
        # Check if the item contains a wildcard
        if item.is_a?(String) && item.include?('*.')
          @logger.debug("Found wildcard in #{field}: #{item} in program: #{program_name}")
          @db.add_wildcard(item, program_name)
        end
      end
    end
  end
end
