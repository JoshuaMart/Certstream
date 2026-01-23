# frozen_string_literal: true

require 'resolv'
require 'ipaddr'

module Certstream
  class DnsResolver
    PRIVATE_RANGES = [
      IPAddr.new('10.0.0.0/8'),
      IPAddr.new('172.16.0.0/12'),
      IPAddr.new('192.168.0.0/16'),
      IPAddr.new('127.0.0.0/8'),
      IPAddr.new('169.254.0.0/16'),
      IPAddr.new('::1/128'),
      IPAddr.new('fc00::/7'),
      IPAddr.new('fe80::/10')
    ].freeze

    def initialize(logger)
      @logger = logger
      @resolver = Resolv::DNS.new
    end

    def resolve(domain)
      ips = resolve_all(domain)
      public_ips = filter_private(ips)

      @logger.debug('DNS', "#{domain} -> #{public_ips.join(', ')}") if public_ips.any?

      public_ips
    rescue Resolv::ResolvError, Resolv::ResolvTimeout => e
      @logger.debug('DNS', "Failed to resolve #{domain}: #{e.message}")
      []
    end

    private

    def resolve_all(domain)
      ips = []
      ips.concat(resolve_a(domain))
      ips.concat(resolve_aaaa(domain))
      ips.uniq
    end

    def resolve_a(domain)
      @resolver.getresources(domain, Resolv::DNS::Resource::IN::A).map { |r| r.address.to_s }
    rescue Resolv::ResolvError
      []
    end

    def resolve_aaaa(domain)
      @resolver.getresources(domain, Resolv::DNS::Resource::IN::AAAA).map { |r| r.address.to_s }
    rescue Resolv::ResolvError
      []
    end

    def filter_private(ips)
      ips.reject { |ip| private_ip?(ip) }
    end

    def private_ip?(ip)
      addr = IPAddr.new(ip)
      PRIVATE_RANGES.any? { |range| range.include?(addr) }
    rescue IPAddr::InvalidAddressError
      true
    end
  end
end
