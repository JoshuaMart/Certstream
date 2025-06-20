# frozen_string_literal: true

require 'httparty'
require 'json'

module Certstream
  module Services
    module Wildcard
      class Fetcher
        def initialize(api_url, headers)
          @api_url = api_url
          @headers = headers
        end

        def fetch_wildcards
          Core.container.logger.info("Fetching wildcards from API: #{@api_url}")

          begin
            response = HTTParty.get(
              @api_url,
              headers: @headers
            )

            if response.code != 200
              Core.container.logger.error("Failed to fetch wildcards. Status code: #{response.code}")
              Core.container.logger.error("Response: #{response.body}")
              return
            end

            json_data = JSON.parse(response.body)

            Core.container.logger.info('Successfully fetched wildcards data')

            # Clear existing wildcards from database
            Core.container.database.clear_wildcards

            # Extract wildcards from JSON response
            extract_wildcards(json_data)

            Core.container.logger.info('Wildcards updated successfully')
          rescue JSON::ParserError => e
            Core.container.logger.error("Error parsing wildcards JSON: #{e.message}")
          rescue StandardError => e
            Core.container.logger.error("Error fetching wildcards: #{e.message}")
            Core.container.logger.error(e.backtrace.join("\n"))
          end
        end

        private

        def extract_wildcards(json_data)
          # Process through the entire JSON structure to find wildcards
          wildcards_count = 0

          # The JSON format from the provided example has a structure where programs are keys
          json_data.each_value do |programs|
            programs.each do |name, infos|
              wildcards_count += 1
              scopes = infos.dig('scopes', 'in', 'web')
              next unless scopes

              process_scope(scopes, name)
            end
          end

          Core.container.logger.info("Extracted wildcards for #{wildcards_count} programs")
        end

        def process_scope(scopes, program_name)
          scopes.each do |scope|
            # Check if the scope contains a wildcard
            if scope.start_with?('*.')
              Core.container.logger.debug("Found wildcard: #{scope} in program: #{program_name}")
              Core.container.database.add_wildcard(scope, program_name)
            end
          end
        end
      end
    end
  end
end
