# frozen_string_literal: true

require 'mysql2'
require 'public_suffix'
require 'connection_pool'

module Certstream
  module Core
    class Database
      attr_reader :pool

      def initialize(config)
        @config = config
        @wildcards_cache = nil
        @domain_cache_expiry = Time.now + 3600 # Cache expires after 1 hour
        @pool_mutex = Mutex.new

        setup_connection_pool
        setup_database
      end

      def setup_connection_pool
        Core.container.logger.info('Setting up MySQL connection pool')

        # Create a pool of connections instead of a single connection
        @pool = ConnectionPool.new(size: 20, timeout: 5) do
          client = Mysql2::Client.new(
            host: @config['host'],
            username: @config['username'],
            password: @config['password'],
            database: @config['database'],
            reconnect: true,
            encoding: 'utf8mb4',
            collation: 'utf8mb4_unicode_ci'
          )

          # Optimizations for every connection
          client.query('SET NAMES utf8mb4')
          client.query('SET CHARACTER SET utf8mb4')
          client.query('SET collation_connection = utf8mb4_unicode_ci')
          client.query("SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO'")

          client
        end

        Core.container.logger.info('MySQL connection pool created successfully')
      end

      def setup_database
        Core.container.logger.info('Setting up database tables')

        with_connection do |client|
          # Create wildcards table
          client.query(<<-SQL)
            CREATE TABLE IF NOT EXISTS wildcards (
              id INT AUTO_INCREMENT PRIMARY KEY,
              pattern VARCHAR(255) NOT NULL UNIQUE,
              program VARCHAR(255),
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              INDEX idx_wildcards_pattern (pattern)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
          SQL

          # Create discovered_domains table
          client.query(<<-SQL)
            CREATE TABLE IF NOT EXISTS discovered_domains (
              id INT AUTO_INCREMENT PRIMARY KEY,
              domain VARCHAR(255) NOT NULL UNIQUE,
              ip VARCHAR(45),
              program VARCHAR(255),
              discovered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              INDEX idx_discovered_domains_domain (domain),
              INDEX idx_discovered_domains_program (program)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
          SQL

          # Create unresolvable_domains table
          client.query(<<-SQL)
            CREATE TABLE IF NOT EXISTS unresolvable_domains (
              id INT AUTO_INCREMENT PRIMARY KEY,
              domain VARCHAR(255) NOT NULL UNIQUE,
              wildcard_id INT,
              retry_count INT DEFAULT 0,
              last_retry TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              INDEX idx_unresolvable_domains_domain (domain),
              INDEX idx_unresolvable_domains_retry_count (retry_count),
              INDEX idx_unresolvable_domains_created_at (created_at),
              FOREIGN KEY (wildcard_id) REFERENCES wildcards(id) ON DELETE SET NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
          SQL
        end

        Core.container.logger.info('Database setup complete')
      end

      # Helper method to execute blocks with a connection from the pool
      def with_connection
        @pool.with do |client|
          yield client
        rescue Mysql2::Error => e
          Core.container.logger.error("MySQL error: #{e.message}")
          raise
        end
      end

      # Wildcard methods
      def clear_wildcards
        with_connection do |client|
          client.query('DELETE FROM wildcards;')
        end
        Core.container.logger.info('Cleared all wildcards from database')
        invalidate_wildcards_cache
      end

      def add_wildcard(pattern, program = nil)
        with_connection do |client|
          safe_pattern = client.escape(pattern.to_s)
          safe_program = program.nil? ? 'NULL' : "'#{client.escape(program.to_s)}'"

          client.query("INSERT IGNORE INTO wildcards (pattern, program) VALUES ('#{safe_pattern}', #{safe_program})")
        end
        Core.container.logger.debug("Added wildcard: #{pattern} for program: #{program || 'unknown'}")
        invalidate_wildcards_cache
      end

      def all_wildcards
        # Use a mutex to avoid simultaneous cache refreshes
        @pool_mutex.synchronize do
          return @wildcards_cache if @wildcards_cache

          result = with_connection { |client| client.query('SELECT * FROM wildcards;') }
          @wildcards_cache = result.to_a
          Core.container.logger.debug("Wildcards cache refreshed: #{@wildcards_cache.length} entries")
          @wildcards_cache
        end
      end

      def invalidate_wildcards_cache
        @pool_mutex.synchronize do
          Core.container.logger.debug('Invalidating wildcards cache')
          @wildcards_cache = nil
        end
      end

      def domain_matches_wildcards(domain)
        wildcards = all_wildcards

        # Extract effective domain part for matching
        effective_domain = PublicSuffix.domain(domain)
        return nil unless effective_domain

        # Find first matching wildcard
        wildcards.find { |wildcard| effective_domain == wildcard['pattern'][2..] }
      rescue PublicSuffix::DomainInvalid => e
        Core.container.logger.debug("Invalid domain format for #{domain}: #{e.message}")
        nil
      rescue StandardError => e
        Core.container.logger.error("Error in domain_matches_wildcards for #{domain}: #{e.message}")
        nil
      end

      # Discovered domains methods
      def domain_already_discovered?(domain)
        with_connection do |client|
          safe_domain = client.escape(domain.to_s)
          result = client.query("SELECT COUNT(*) as count FROM discovered_domains WHERE domain = '#{safe_domain}'").first
          result['count'].to_i.positive?
        end
      end

      def add_discovered_domain(domain, ip, program = nil)
        with_connection do |client|
          safe_domain = client.escape(domain.to_s)
          safe_ip = client.escape(ip.to_s)
          safe_program = program.nil? ? 'NULL' : "'#{client.escape(program.to_s)}'"

          client.query("INSERT IGNORE INTO discovered_domains (domain, ip, program) VALUES ('#{safe_domain}', '#{safe_ip}', #{safe_program})")
        end
        Core.container.logger.info("Added discovered domain: #{domain} with IP: #{ip}")
      end

      # Batch insert discovered domains for better performance
      def add_discovered_domains_batch(domains_batch)
        return if domains_batch.nil? || domains_batch.empty?

        with_connection do |client|
          # MySQL's multiple value insert syntax for better performance
          values = domains_batch.map do |domain, ip, program|
            safe_domain = client.escape(domain.to_s)
            safe_ip = client.escape(ip.to_s)
            safe_program = program.nil? ? 'NULL' : "'#{client.escape(program.to_s)}'"

            "('#{safe_domain}', '#{safe_ip}', #{safe_program})"
          end.join(', ')

          client.query("INSERT IGNORE INTO discovered_domains (domain, ip, program) VALUES #{values}")
        end

        Core.container.logger.info("Added #{domains_batch.size} discovered domains in batch")
      end

      # Unresolvable domains methods
      def add_unresolvable_domain(domain, wildcard_id = nil)
        with_connection do |client|
          safe_domain = client.escape(domain.to_s)
          safe_wildcard_id = wildcard_id.nil? ? 'NULL' : wildcard_id.to_i

          client.query("INSERT IGNORE INTO unresolvable_domains (domain, wildcard_id) VALUES ('#{safe_domain}', #{safe_wildcard_id})")
        end
        Core.container.logger.debug("Added unresolvable domain: #{domain}")
      end

      # Batch insert unresolvable domains
      def add_unresolvable_domains_batch(domains_batch)
        return if domains_batch.nil? || domains_batch.empty?

        with_connection do |client|
          # Construire la requête manuellement pour un meilleur contrôle
          values_array = []

          domains_batch.each do |entry|
            # Vérifier que entry est un tableau à deux éléments
            unless entry.is_a?(Array) && entry.size == 2
              Core.container.logger.error("Invalid entry in domains_batch: #{entry.inspect}")
              next
            end

            domain, wildcard_id = entry

            # Vérifier et valider domain
            unless domain.is_a?(String)
              Core.container.logger.error("Invalid domain type: #{domain.class}, value: #{domain.inspect}")
              next
            end

            # Échapper domain correctement
            safe_domain = "'#{client.escape(domain)}'"

            # Vérifier et valider wildcard_id
            safe_wildcard_id = if wildcard_id.nil?
                                 'NULL'
                               elsif wildcard_id.is_a?(Integer)
                                 wildcard_id.to_s
                               else
                                 Core.container.logger.warn("Non-integer wildcard_id: #{wildcard_id.inspect}, converting")
                                 begin
                                   wildcard_id.to_i.to_s
                                 rescue StandardError
                                   'NULL'
                                 end
                               end

            # Ajouter cette paire au tableau des valeurs
            values_array << "(#{safe_domain}, #{safe_wildcard_id})"
          end

          # Si aucune valeur valide n'a été trouvée, terminer
          if values_array.empty?
            Core.container.logger.warn('No valid domains in batch to insert')
            return
          end

          # Joindre les valeurs en une seule chaîne
          values = values_array.join(', ')

          # Exécuter la requête SQL
          client.query("INSERT IGNORE INTO unresolvable_domains (domain, wildcard_id) VALUES #{values}")
        end

        Core.container.logger.debug("Added #{domains_batch.size} unresolvable domains in batch")
      end

      def remove_unresolvable_domain(domain)
        with_connection do |client|
          safe_domain = client.escape(domain.to_s)
          client.query("DELETE FROM unresolvable_domains WHERE domain = '#{safe_domain}'")
        end
        Core.container.logger.debug("Removed unresolvable domain: #{domain}")
      end

      # Get unresolvable domains older than 1 day
      def unresolvable_domains
        with_connection do |client|
          result = client.query(
            'SELECT * FROM unresolvable_domains ' \
            'WHERE created_at < NOW() - INTERVAL 1 DAY ' \
            'ORDER BY retry_count ASC LIMIT 1000;'
          )
          result.to_a
        end
      end

      # Remove unresolvable domains older than 3 days
      def cleanup_old_unresolvable_domains
        with_connection do |client|
          count = client.query(
            'DELETE FROM unresolvable_domains ' \
            'WHERE created_at < NOW() - INTERVAL 3 DAY'
          ).affected_rows
          Core.container.logger.info("Cleaned up #{count} old unresolvable domains (older than 3 days)")
        end
      end

      def increment_retry_count(domain)
        with_connection do |client|
          safe_domain = client.escape(domain.to_s)
          client.query("UPDATE unresolvable_domains SET retry_count = retry_count + 1, last_retry = CURRENT_TIMESTAMP WHERE domain = '#{safe_domain}'")
        end
        Core.container.logger.debug("Incremented retry count for domain: #{domain}")
      end

      def get_program_for_domain(domain)
        domain_matches_wildcards(domain)
      end

      # Preload cache of discovered domains to avoid repeated DB lookups
      def preload_discovered_domains_cache
        # Utiliser un mutex pour éviter les mises à jour simultanées du cache
        @pool_mutex.synchronize do
          # Reset cache if it's expired
          if @domain_cache && @domain_cache_expiry < Time.now
            @domain_cache = nil
            Core.container.logger.info('Domain cache expired, resetting')
          end

          # Return existing cache if available
          return @domain_cache if @domain_cache

          Core.container.logger.info('Preloading discovered domains cache')
          discovered = {}

          # Limit to a reasonable number of recent domains to avoid memory overload
          with_connection do |client|
            client.query('SELECT domain FROM discovered_domains ORDER BY discovered_at DESC LIMIT 100000;').each do |row|
              discovered[row['domain']] = true
            end
          end

          @domain_cache = discovered
          @domain_cache_expiry = Time.now + 3600 # Cache for 1 hour
          Core.container.logger.info("Preloaded #{discovered.size} domains into cache")

          discovered
        end
      end

      # Method to cleanup database (can be run periodically)
      def cleanup_database
        with_connection do |client|
          # Remove old unresolvable domains that have exceeded max retries
          count = client.query(
            'DELETE FROM unresolvable_domains ' \
            'WHERE retry_count > 10 AND last_retry < NOW() - INTERVAL 7 DAY'
          ).affected_rows

          Core.container.logger.info("Cleaned up #{count} old unresolvable domains")
        end
        Core.container.logger.info('Database cleanup complete')
      end
    end
  end
end
