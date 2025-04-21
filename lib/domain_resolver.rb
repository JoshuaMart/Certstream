# frozen_string_literal: true

require 'resolv'
require 'ipaddress'

class DomainResolver
  def initialize(logger)
    @logger = logger
    @resolver = Resolv::DNS.new
  end

  # Resolve a domain name to an IP address
  def resolve(domain)
    return nil if domain.nil? || domain.empty?

    begin
      @logger.debug("Resolving domain: #{domain}")

      # Try to resolve as IPv4 first
      ip = @resolver.getaddress(domain).to_s

      @logger.debug("Domain #{domain} resolved to IP: #{ip}")

      ip
    rescue Resolv::ResolvError => e
      @logger.debug("Resolution error for domain #{domain}: #{e.message}")
      nil
    rescue StandardError => e
      @logger.error("Error resolving domain #{domain}: #{e.message}")
      nil
    end
  end

  # Check if an IP address is private/internal
  def private_ip?(ip)
    return true if ip.nil? || ip.empty?

    begin
      ip_addr = IPAddress.parse(ip)

      # Check if it's a private IP address
      if ip_addr.ipv4?
        # IPv4 link-local addresses are in the range 169.254.0.0/16
        is_link_local = ip_addr.to_string.start_with?('169.254.')
        return true if ip_addr.private? || ip_addr.loopback? || is_link_local
      elsif ip_addr.ipv6?
        return true if ip_addr.loopback?
      end

      false
    rescue ArgumentError => e
      @logger.error("Error parsing IP address #{ip}: #{e.message}")
      true # Default to true (private) for safety
    end
  end

  # Get all IP addresses for a domain (both IPv4 and IPv6)
  def resolve_all(domain)
    return [] if domain.nil? || domain.empty?

    ips = []

    begin
      # Try IPv4 resolution
      @resolver.each_address(domain) do |addr|
        ips << addr.to_s
      end
    rescue Resolv::ResolvError => e
      @logger.debug("IPv4 resolution error for domain #{domain}: #{e.message}")
    rescue StandardError => e
      @logger.error("Error during IPv4 resolution for domain #{domain}: #{e.message}")
    end

    ips
  end
end
