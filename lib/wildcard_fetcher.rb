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
    json_data.each do |platforms, programs|
      programs.each do |name, infos|
        wildcards_count += 1
        urls = infos.dig('scopes', 'in', 'url')
        next unless urls

        process_scope(urls, name)
      end
    end

    @logger.info("Extracted wildcards for #{wildcards_count} programs")
  end

  def process_scope(urls, program_name)
    urls.each do |url|
      # Check if the URL contains a wildcard
      if url.start_with?('*.')
        @logger.debug("Found wildcard: #{url} in program: #{program_name}")
        @db.add_wildcard(url, program_name)
      end
    end
  end
end
