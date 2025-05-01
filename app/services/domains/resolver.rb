# frozen_string_literal: true

require 'resolv'
require 'ipaddress'
require 'lru_redux'
require 'timeout'

module Certstream
  module Services
    module Domain
      class Resolver
        # Common private network CIDR ranges
        PRIVATE_NETWORKS = [
          IPAddress.parse('10.0.0.0/8'),
          IPAddress.parse('172.16.0.0/12'),
          IPAddress.parse('192.168.0.0/16'),
          IPAddress.parse('127.0.0.0/8'),
          IPAddress.parse('0.0.0.0/8'),
          IPAddress.parse('169.254.0.0/16')
        ].freeze

        def initialize(cache_size: 10_000, timeout: 2)
          @timeout = timeout
          @last_stats_time = Time.now

          # Create a resolver with custom options for better performance
          @resolver = Resolv::DNS.new(
            nameserver_port: [
              ['1.1.1.1', 53],  # Cloudflare primary
              ['1.0.0.1', 53],  # Cloudflare secondary
              ['8.8.8.8', 53],  # Google primary
              ['8.8.4.4', 53]   # Google secondary
            ],
            search: [],
            ndots: 1
          )

          # Configure timeout to avoid hanging on unresolvable domains
          Resolv::DNS.open do |dns|
            dns.timeouts = @timeout
          end

          # Create LRU cache for DNS results
          @dns_cache = LruRedux::Cache.new(cache_size)
          @ip_check_cache = LruRedux::Cache.new(cache_size)

          @cache_hits = 0
          @cache_misses = 0
        end

        # Resolve a domain name to an IP address
        def resolve(domain)
          return nil if domain.nil? || domain.empty?

          begin
            # Try to get from cache first
            if @dns_cache.key?(domain)
              @cache_hits += 1
              check_stats_logging_time
              return @dns_cache[domain]
            end

            @cache_misses += 1
            Core.container.logger.debug("Resolving domain: #{domain}")

            # Set timeout for DNS resolution
            result = nil
            Timeout.timeout(@timeout) do
              # Try to resolve as IPv4 first
              result = @resolver.getaddress(domain).to_s
            end

            Core.container.logger.debug("Domain #{domain} resolved to IP: #{result}")

            # Cache the result (including nil for failures)
            @dns_cache[domain] = result

            # Check if it's time to log stats
            check_stats_logging_time

            result
          rescue Resolv::ResolvError => e
            Core.container.logger.debug("Resolution error for domain #{domain}: #{e.message}")
            @dns_cache[domain] = nil
            nil
          rescue Timeout::Error => e
            Core.container.logger.debug("Timeout resolving domain #{domain}: #{e.message}")
            @dns_cache[domain] = nil
            nil
          rescue StandardError => e
            Core.container.logger.error("Error resolving domain #{domain}: #{e.message}")
            nil
          end
        end

        # Check if an IP address is private/internal
        def private_ip?(ip)
          return true if ip.nil? || ip.empty?

          begin
            # Check cache first
            return @ip_check_cache[ip] if @ip_check_cache.key?(ip)

            # Parse IP address
            ip_addr = IPAddress.parse(ip)
            result = false

            # Check if it's a private IP address
            if ip_addr.ipv4?
              result = PRIVATE_NETWORKS.any? { |network| network.include?(ip_addr) }
              result ||= ip_addr.private? || ip_addr.loopback?
            elsif ip_addr.ipv6?
              result = ip_addr.loopback? || ip_addr.mapped? || ip_addr.link_local?
            end

            # Cache the result
            @ip_check_cache[ip] = result
            result
          rescue ArgumentError => e
            Core.container.logger.error("Error parsing IP address #{ip}: #{e.message}")
            true # Default to true (private) for safety
          end
        end

        private

        # Check if it's time to log cache stats based on time interval
        def check_stats_logging_time
          now = Time.now
          # Log stats every 5 minutes or after 10,000 operations, whichever comes first
          return unless (now - @last_stats_time) >= 300 || (@cache_hits + @cache_misses) % 10_000 == 0

          log_cache_stats
          @last_stats_time = now
        end

        def log_cache_stats
          total = @cache_hits + @cache_misses
          return if total.zero?

          hit_rate = (@cache_hits.to_f / total) * 100

          # Utiliser count au lieu de size pour LruRedux::Cache
          dns_cache_count = begin
            @dns_cache.count
          rescue StandardError
            0
          end

          ip_cache_count = begin
            @ip_check_cache.count
          rescue StandardError
            0
          end

          Core.container.logger.info(
            "DNS Cache stats: #{@cache_hits} hits, #{@cache_misses} misses, " \
            "#{hit_rate.round(2)}% hit rate, #{dns_cache_count} cached DNS entries, " \
            "#{ip_cache_count} cached IP entries"
          )
          Core.container.discord_notifier.send_log(
            'DNS Cache',
            "#{@cache_hits} hits, #{@cache_misses} misses\n#{hit_rate.round(2)}% hit rate, " \
            "#{dns_cache_count} cached DNS entries, #{ip_cache_count} cached IP entries",
            :info
          )
        end
      end
    end
  end
end
