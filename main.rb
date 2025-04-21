#!/usr/bin/env ruby
# frozen_string_literal: true

# Add lib directory to load path
$LOAD_PATH.unshift(File.expand_path('lib', __dir__))

require 'yaml'
require 'logger'
require 'fileutils'
require 'rufus-scheduler'

require 'wildcard_fetcher'
require 'certstream_monitor'
require 'database'
require 'domain_resolver'
require 'discord_notifier'

# Create directories if they don't exist
FileUtils.mkdir_p('logs')
FileUtils.mkdir_p('data')

# Load configuration
CONFIG = YAML.load_file(File.expand_path('config/config.yml', __dir__))

# Setup logger
logger = Logger.new(CONFIG['logging']['file'] || STDOUT)
logger.level = Logger.const_get(CONFIG['logging']['level'].upcase || 'INFO')
logger.formatter = proc do |severity, datetime, _progname, msg|
  "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
end

# Initialize components
db = Database.new(CONFIG['database']['path'], logger)
resolver = DomainResolver.new(logger)
notifier = DiscordNotifier.new(CONFIG['discord']['webhook_url'],
                               CONFIG['discord']['username'],
                               CONFIG['discord']['avatar_url'],
                               logger)
fetcher = WildcardFetcher.new(CONFIG['api']['url'],
                              CONFIG['api']['headers'],
                              db,
                              logger)

# Create scheduler
scheduler = Rufus::Scheduler.new

# Setup wildcards fetch schedule
scheduler.every "#{CONFIG['api']['update_interval']}s" do
  logger.info('Scheduled fetch of wildcards')
  fetcher.fetch_wildcards
end

# Setup domain resolution retry schedule
scheduler.every "#{CONFIG['database']['retry_interval']}s" do
  logger.info('Starting scheduled retry of unresolvable domains')

  domains = db.get_unresolvable_domains
  domains.each do |domain|
    logger.debug("Retrying resolution for domain: #{domain['domain']}")

    # Check if we've exceeded max retries
    if domain['retry_count'] >= CONFIG['database']['max_retries']
      logger.info("Max retries exceeded for domain: #{domain['domain']}, removing from database")
      db.remove_unresolvable_domain(domain['domain'])
      next
    end

    # Try to resolve the domain
    ip = resolver.resolve(domain['domain'])

    if ip
      logger.info("Successfully resolved previously unresolvable domain: #{domain['domain']} to IP: #{ip}")

      # Check if IP is private
      if resolver.private_ip?(ip)
        logger.info("Domain #{domain['domain']} resolved to private IP: #{ip}, removing from unresolvable")
        db.remove_unresolvable_domain(domain['domain'])
      else
        logger.info("Domain #{domain['domain']} resolved to public IP: #{ip}, sending notification")
        program_info = db.get_program_for_domain(domain['domain'])
        notifier.send_alert(domain['domain'], ip, program_info)
        db.add_discovered_domain(domain['domain'], ip, program_info ? program_info['program'] : nil)
        db.remove_unresolvable_domain(domain['domain'])
      end
    else
      # Increment retry count
      db.increment_retry_count(domain['domain'])
    end
  end
end

# Initial wildcards fetch
fetcher.fetch_wildcards

# Setup and start the certstream monitor
certstream = CertstreamMonitor.new(CONFIG['certstream']['url'],
                                   db,
                                   resolver,
                                   notifier,
                                   CONFIG['certstream']['reconnect_interval'],
                                   logger)
certstream.start

# Keep the main thread alive
begin
  loop do
    sleep 1
  end
rescue Interrupt
  logger.info('Received interrupt signal, shutting down...')
  scheduler.shutdown
  exit(0)
end
