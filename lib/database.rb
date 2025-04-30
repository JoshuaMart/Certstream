# frozen_string_literal: true

require 'sqlite3'
require 'public_suffix'

class Database
  def initialize(db_path, logger)
    @logger = logger
    @db_path = db_path
    @wildcards_cache = nil
    @domain_cache_expiry = Time.now + 3600 # Cache expires after 1 hour
    setup_database
  end

  def setup_database
    @logger.info("Setting up database at #{@db_path}")

    @db = SQLite3::Database.new(@db_path)
    @db.results_as_hash = true
    
    # Enable optimizations for better performance
    @db.execute("PRAGMA journal_mode = WAL")     # Write-Ahead Logging for better concurrency
    @db.execute("PRAGMA synchronous = NORMAL")   # Reduce disk writes while keeping reasonable safety
    @db.execute("PRAGMA cache_size = 10000")     # Increase cache size to 10MB
    @db.execute("PRAGMA temp_store = MEMORY")    # Store temp tables in memory
    
    # Create wildcards table
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS wildcards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pattern TEXT NOT NULL UNIQUE,
        program TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
    SQL

    # Create discovered_domains table
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS discovered_domains (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        domain TEXT NOT NULL UNIQUE,
        ip TEXT,
        program TEXT,
        discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
    SQL

    # Create unresolvable_domains table
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS unresolvable_domains (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        domain TEXT NOT NULL UNIQUE,
        wildcard_id INTEGER,
        retry_count INTEGER DEFAULT 0,
        last_retry DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (wildcard_id) REFERENCES wildcards(id)
      );
    SQL
    
    # Add indexes for better query performance
    @db.execute("CREATE INDEX IF NOT EXISTS idx_wildcards_pattern ON wildcards(pattern)")
    @db.execute("CREATE INDEX IF NOT EXISTS idx_discovered_domains_domain ON discovered_domains(domain)")
    @db.execute("CREATE INDEX IF NOT EXISTS idx_unresolvable_domains_domain ON unresolvable_domains(domain)")
    @db.execute("CREATE INDEX IF NOT EXISTS idx_unresolvable_domains_retry_count ON unresolvable_domains(retry_count)")

    @logger.info('Database setup complete')
  end

  # Wildcard methods
  def clear_wildcards
    @db.execute('DELETE FROM wildcards;')
    @logger.info('Cleared all wildcards from database')
    invalidate_wildcards_cache
  end

  def add_wildcard(pattern, program = nil)
    @db.execute('INSERT OR IGNORE INTO wildcards (pattern, program) VALUES (?, ?);', [pattern, program])
    @logger.debug("Added wildcard: #{pattern} for program: #{program || 'unknown'}")
    invalidate_wildcards_cache
  end

  def all_wildcards
    return @wildcards_cache if @wildcards_cache

    @wildcards_cache = @db.execute('SELECT * FROM wildcards;')
    @logger.debug("Wildcards cache refreshed: #{@wildcards_cache.length} entries")
    @wildcards_cache
  end

  def invalidate_wildcards_cache
    @logger.debug("Invalidating wildcards cache")
    @wildcards_cache = nil
  end

  def domain_matches_wildcards(domain)
    begin
      wildcards = all_wildcards
      
      # Extract effective domain part for matching
      effective_domain = PublicSuffix.domain(domain)
      return nil unless effective_domain
      
      # Find first matching wildcard
      wildcards.find { |wildcard| effective_domain == wildcard['pattern'][2..] }
    rescue PublicSuffix::DomainInvalid => e
      @logger.debug("Invalid domain format for #{domain}: #{e.message}")
      nil
    rescue StandardError => e
      @logger.error("Error in domain_matches_wildcards for #{domain}: #{e.message}")
      nil
    end
  end

  # Discovered domains methods
  def domain_already_discovered?(domain)
    # Use a prepared statement for better performance with frequent queries
    @domain_check_stmt ||= @db.prepare('SELECT COUNT(*) as count FROM discovered_domains WHERE domain = ?;')
    result = @domain_check_stmt.execute(domain).next
    result['count'].to_i.positive?
  end

  def add_discovered_domain(domain, ip, program = nil)
    @db.execute(
      'INSERT OR IGNORE INTO discovered_domains (domain, ip, program) VALUES (?, ?, ?);',
      [domain, ip, program]
    )
    @logger.info("Added discovered domain: #{domain} with IP: #{ip}")
  end
  
  # Batch insert discovered domains for better performance
  def add_discovered_domains_batch(domains_batch)
    return if domains_batch.nil? || domains_batch.empty?
    
    @db.transaction do
      stmt = @db.prepare('INSERT OR IGNORE INTO discovered_domains (domain, ip, program) VALUES (?, ?, ?);')
      
      domains_batch.each do |domain, ip, program|
        stmt.execute(domain, ip, program)
      end
      
      stmt.close
    end
    
    @logger.info("Added #{domains_batch.size} discovered domains in batch")
  end

  # Unresolvable domains methods
  def add_unresolvable_domain(domain, wildcard_id = nil)
    @db.execute(
      'INSERT OR IGNORE INTO unresolvable_domains (domain, wildcard_id) VALUES (?, ?);',
      [domain, wildcard_id]
    )
    @logger.debug("Added unresolvable domain: #{domain}")
  end
  
  # Batch insert unresolvable domains
  def add_unresolvable_domains_batch(domains_batch)
    return if domains_batch.nil? || domains_batch.empty?
    
    # Use a SQLite transaction for bulk insertions
    @db.transaction do
      stmt = @db.prepare('INSERT OR IGNORE INTO unresolvable_domains (domain, wildcard_id) VALUES (?, ?);')
      
      domains_batch.each do |domain, wildcard_id|
        stmt.execute(domain, wildcard_id)
      end
      
      stmt.close
    end
    
    @logger.debug("Added #{domains_batch.size} unresolvable domains in batch")
  end

  def remove_unresolvable_domain(domain)
    @db.execute('DELETE FROM unresolvable_domains WHERE domain = ?;', [domain])
    @logger.debug("Removed unresolvable domain: #{domain}")
  end

  def unresolvable_domains
    # Add LIMIT to avoid pulling too many records at once
    @db.execute('SELECT * FROM unresolvable_domains ORDER BY retry_count ASC LIMIT 1000;')
  end

  def increment_retry_count(domain)
    @db.execute(
      'UPDATE unresolvable_domains SET retry_count = retry_count + 1, last_retry = CURRENT_TIMESTAMP WHERE domain = ?;',
      [domain]
    )
    @logger.debug("Incremented retry count for domain: #{domain}")
  end

  def get_program_for_domain(domain)
    domain_matches_wildcards(domain)
  end
  
  # Preload cache of discovered domains to avoid repeated DB lookups
  def preload_discovered_domains_cache
    # Reset cache if it's expired
    if @domain_cache && @domain_cache_expiry < Time.now
      @domain_cache = nil
      @logger.info("Domain cache expired, resetting")
    end
    
    # Return existing cache if available
    return @domain_cache if @domain_cache
    
    @logger.info("Preloading discovered domains cache")
    discovered = {}
    
    # Limit to a reasonable number of recent domains to avoid memory overload
    @db.execute('SELECT domain FROM discovered_domains ORDER BY discovered_at DESC LIMIT 100000;').each do |row|
      discovered[row['domain']] = true
    end
    
    @domain_cache = discovered
    @domain_cache_expiry = Time.now + 3600 # Cache for 1 hour
    @logger.info("Preloaded #{discovered.size} domains into cache")
    
    discovered
  end
  
  # Method to cleanup database (can be run periodically)
  def cleanup_database
    # Remove old unresolvable domains that have exceeded max retries
    count = @db.execute('DELETE FROM unresolvable_domains WHERE retry_count > 10 AND last_retry < datetime("now", "-7 days");')
    @logger.info("Cleaned up #{count} old unresolvable domains")
    
    # Optimize database
    @db.execute('VACUUM;')
    @logger.info("Database optimized")
  end
end