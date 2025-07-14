# frozen_string_literal: true

require 'websocket-eventmachine-client'
require 'json'
require 'yaml'
require 'concurrent-ruby'
require 'resolv'
require 'ipaddr'
require_relative 'wildcard_manager'

module Certstream
  class Monitor
    def initialize(config_path = 'src/config.yml')
      config = YAML.load_file(config_path)

      @ws_url = config.dig('certstream', 'url')
      @wildcard_manager = WildcardManager.new(config)
      @http_config = config['http']
      @fingerprinter_config = config['fingerprinter']
      @processing_pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: 2,
        max_threads: 10,
        max_queue: 100,
        fallback_policy: :caller_runs
      )
      @resolver = Resolv::DNS.new
      @resolver.timeouts = [2, 4] # 2s first try, 4s retry
      @stats = {
        total_processed: 0,
        matched_domains: 0,
        dns_resolved: 0,
        dns_failed: 0,
        private_ips: 0,
        http_responses: 0,
        http_timeouts: 0,
        fingerprinter_sent: 0,
        fingerprinter_failed: 0,
        start_time: Time.now
      }
    end

    def run
      # Start wildcard updater in background
      @wildcard_manager.start_updater
      puts "[Monitor] Wildcard manager started"

      # Start stats reporter
      start_stats_reporter

      EM.run do
        ws = WebSocket::EventMachine::Client.connect(uri: @ws_url)

        ws.onerror { |e| puts "WS error: #{e.message}" }
        ws.onping  { ws.pong }
        ws.onclose { shutdown }

        ws.onopen do
          puts '[Monitor] WebSocket connected'
        end

        ws.onmessage do |msg, _|
          domains = JSON.parse(msg)['data'] || []
          process_domains(domains)
        end
      end
    end

    private

    def process_domains(domains)
      domains.each do |domain|
        @stats[:total_processed] += 1

        next if domain.start_with?('*.')

        # Fast wildcard matching - this should be very quick
        next unless @wildcard_manager.match_domain?(domain)

        @stats[:matched_domains] += 1
        handle_matched_domain(domain)
      end
    end

    def handle_matched_domain(domain)
      # Submit DNS resolution to thread pool (non-blocking)
      @processing_pool.post do
        resolve_and_process_domain(domain)
      end
    end

    def resolve_and_process_domain(domain)
      begin
        # Resolve domain to IP addresses
        ips = @resolver.getaddresses(domain)

        if ips.empty?
          @stats[:dns_failed] += 1
          return
        end

        # Filter out private IPs
        public_ips = ips.reject { |ip| private_ip?(ip.to_s) }

        if public_ips.empty?
          @stats[:private_ips] += 1
          return
        end

        @stats[:dns_resolved] += 1

        # Domain resolves to public IP(s) - process it
        process_resolved_domain(domain, public_ips)

      rescue Resolv::ResolvError, Resolv::ResolvTimeout => e
        @stats[:dns_failed] += 1
        # Silent fail - DNS resolution failed
      rescue => e
        @stats[:dns_failed] += 1
        puts "[ERROR] DNS resolution error for #{domain}: #{e.message}"
      end
    end

    def private_ip?(ip_string)
      ip = IPAddr.new(ip_string)

      # RFC 1918 private ranges + localhost + link-local
      private_ranges = [
        IPAddr.new('10.0.0.0/8'),
        IPAddr.new('172.16.0.0/12'),
        IPAddr.new('192.168.0.0/16'),
        IPAddr.new('127.0.0.0/8'),
        IPAddr.new('169.254.0.0/16')
      ]

      private_ranges.any? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true # Consider invalid IPs as private
    end

    def process_resolved_domain(domain, ips)
      puts "[RESOLVED] #{domain} -> #{ips.join(', ')}"

      # Probe HTTP/HTTPS on different ports
      probe_http_services(domain)
    end

    def probe_http_services(domain)
      return unless @http_config && @http_config['ports']

      # Generate URLs to test
      urls = generate_probe_urls(domain)
      return if urls.empty?

      # Collect valid URLs that respond
      valid_urls = []

      # Use Hydra for parallel requests
      hydra = Typhoeus::Hydra.new(max_concurrency: 4)
      requests = []

      urls.each do |url|
        request = Typhoeus::Request.new(
          url,
          timeout: @http_config['timeout'] || 10,
          ssl_verifypeer: false,
          ssl_verifyhost: 0
        )

        request.on_complete do |response|
          if handle_http_response(domain, url, response)
            valid_urls << url
          end
        end

        hydra.queue(request)
        requests << request
      end

      # Execute all requests in parallel
      hydra.run

      # Send valid URLs to fingerprinter if any
      send_to_fingerprinter(valid_urls) unless valid_urls.empty?
    end

    def generate_probe_urls(domain)
      urls = []

      @http_config['ports'].each do |port_config|
        protocol = port_config['protocol']
        port = port_config['port']

        # Build URL
        url = "#{protocol}://#{domain}"

        # Add port if not default
        if port && !default_port?(protocol, port)
          url += ":#{port}"
        end

        urls << url
      end

      urls
    end

    def default_port?(protocol, port)
      (protocol == 'http' && port == 80) || (protocol == 'https' && port == 443)
    end

    def handle_http_response(domain, url, response)
      if response.timed_out?
        @stats[:http_timeouts] += 1
        return false
      end

      # Any response (regardless of status code) is considered a hit
      if response.response_code > 0
        @stats[:http_responses] += 1
        puts "[HTTP] #{url} -> #{response.response_code} (#{response.total_time.round(2)}s)"
        return true
      end

      false
    end

    def send_to_fingerprinter(urls)
      return unless @fingerprinter_config && !urls.empty?

      payload = {
        "urls" => urls,
        "callback_urls" => @fingerprinter_config['callback_urls'] || []
      }

      headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }

      # Add API key to headers if configured
      if @fingerprinter_config['api_key']
        headers['Authorization'] = "Bearer #{@fingerprinter_config['api_key']}"
      end

      begin
        response = Typhoeus.post(
          @fingerprinter_config['url'],
          body: payload.to_json,
          headers: headers,
          timeout: 30
        )

        if response.success?
          @stats[:fingerprinter_sent] += urls.length
          puts "[FINGERPRINTER] Sent #{urls.length} URLs -> #{response.response_code}"
        else
          @stats[:fingerprinter_failed] += urls.length
          puts "[FINGERPRINTER] Failed to send URLs -> #{response.response_code}: #{response.response_body}"
        end

      rescue => e
        @stats[:fingerprinter_failed] += urls.length
        puts "[FINGERPRINTER] Error sending URLs: #{e.message}"
      end
    end

    def start_stats_reporter
      Thread.new do
        loop do
          sleep(60) # Report every minute
          print_stats
        end
      end
    end

    def print_stats
      uptime = Time.now - @stats[:start_time]
      rate = @stats[:total_processed] / uptime
      match_rate = (@stats[:matched_domains].to_f / @stats[:total_processed] * 100).round(2) if @stats[:total_processed] > 0
      resolve_rate = (@stats[:dns_resolved].to_f / @stats[:matched_domains] * 100).round(2) if @stats[:matched_domains] > 0
      http_rate = (@stats[:http_responses].to_f / @stats[:dns_resolved] * 100).round(2) if @stats[:dns_resolved] > 0
      fingerprint_rate = (@stats[:fingerprinter_sent].to_f / @stats[:http_responses] * 100).round(2) if @stats[:http_responses] > 0

      queue_size = @processing_pool.queue_length
      active_threads = @processing_pool.length

      puts "[STATS] Processed: #{@stats[:total_processed]} | Matched: #{@stats[:matched_domains]} (#{match_rate || 0}%)"
      puts "        DNS: #{@stats[:dns_resolved]} resolved (#{resolve_rate || 0}%) | #{@stats[:dns_failed]} failed | #{@stats[:private_ips]} private"
      puts "        HTTP: #{@stats[:http_responses]} responses (#{http_rate || 0}%) | #{@stats[:http_timeouts]} timeouts"
      puts "        Fingerprinter: #{@stats[:fingerprinter_sent]} sent (#{fingerprint_rate || 0}%) | #{@stats[:fingerprinter_failed]} failed"
      puts "        Pool: #{active_threads} active threads | #{queue_size} queued | Rate: #{rate.round(1)}/s"
    end

    def shutdown
      puts '[Monitor] Shutting down...'

      # Gracefully shutdown the thread pool
      @processing_pool.shutdown
      unless @processing_pool.wait_for_termination(10)
        puts '[Monitor] Thread pool shutdown timeout, forcing...'
        @processing_pool.kill
      end

      puts '[Monitor] WebSocket closed'
      EM.stop
    end
  end
end
