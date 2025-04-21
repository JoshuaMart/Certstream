require 'sqlite3'

class Database
  def initialize(db_path, logger)
    @logger = logger
    @db_path = db_path
    setup_database
  end

  def setup_database
    @logger.info("Setting up database at #{@db_path}")

    @db = SQLite3::Database.new(@db_path)
    @db.results_as_hash = true

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

    @logger.info('Database setup complete')
  end

  # Wildcard methods
  def clear_wildcards
    @db.execute('DELETE FROM wildcards;')
    @logger.info('Cleared all wildcards from database')
  end

  def add_wildcard(pattern, program = nil)
    @db.execute('INSERT OR IGNORE INTO wildcards (pattern, program) VALUES (?, ?);', [pattern, program])
    @logger.debug("Added wildcard: #{pattern} for program: #{program || 'unknown'}")
  end

  def get_wildcards
    @db.execute('SELECT * FROM wildcards;')
  end

  def domain_matches_wildcards?(domain)
    wildcards = get_wildcards

    wildcards.each do |wildcard|
      pattern = wildcard['pattern']
      # Convert the wildcard pattern to a regex pattern
      regex_pattern = pattern.gsub('.', '\\.').gsub('*', '.*')

      return wildcard if /^#{regex_pattern}$/i.match?(domain)
    end

    nil
  end

  # Discovered domains methods
  def domain_already_discovered?(domain)
    result = @db.get_first_row('SELECT COUNT(*) as count FROM discovered_domains WHERE domain = ?;', [domain])
    result['count'] > 0
  end

  def add_discovered_domain(domain, ip, program = nil)
    @db.execute(
      'INSERT OR IGNORE INTO discovered_domains (domain, ip, program) VALUES (?, ?, ?);',
      [domain, ip, program]
    )
    @logger.info("Added discovered domain: #{domain} with IP: #{ip}")
  end

  # Unresolvable domains methods
  def add_unresolvable_domain(domain, wildcard_id = nil)
    @db.execute(
      'INSERT OR IGNORE INTO unresolvable_domains (domain, wildcard_id) VALUES (?, ?);',
      [domain, wildcard_id]
    )
    @logger.debug("Added unresolvable domain: #{domain}")
  end

  def remove_unresolvable_domain(domain)
    @db.execute('DELETE FROM unresolvable_domains WHERE domain = ?;', [domain])
    @logger.debug("Removed unresolvable domain: #{domain}")
  end

  def get_unresolvable_domains
    @db.execute('SELECT * FROM unresolvable_domains;')
  end

  def increment_retry_count(domain)
    @db.execute(
      'UPDATE unresolvable_domains SET retry_count = retry_count + 1, last_retry = CURRENT_TIMESTAMP WHERE domain = ?;',
      [domain]
    )
    @logger.debug("Incremented retry count for domain: #{domain}")
  end

  def get_program_for_domain(domain)
    wildcard = domain_matches_wildcards?(domain)
    wildcard if wildcard
  end
end
