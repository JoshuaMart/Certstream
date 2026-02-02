# frozen_string_literal: true

require 'async'

module Certstream
  class Stats
    COUNTERS = %i[
      total_processed
      matched_domains
      dns_resolved
      dns_failed
      http_responses
      http_timeout
      fingerprinter_sent
      fingerprinter_failed
    ].freeze

    def initialize(config, logger, discord_notifier)
      @logger = logger
      @discord_notifier = discord_notifier
      @stats_interval = config.discord['stats_interval']
      @console_interval = 600 # 10 minutes
      @start_time = Time.now
      @mutex = Mutex.new
      @counters = COUNTERS.to_h { |key| [key, 0] }
    end

    def increment(key, value = 1)
      @mutex.synchronize { @counters[key] += value }
    end

    def get(key)
      @mutex.synchronize { @counters[key] }
    end

    def start_reporting
      start_console_reporting
      start_discord_reporting
    end

    def to_h
      @mutex.synchronize do
        data = @counters.dup
        data[:uptime] = (Time.now - @start_time).to_i
        data[:match_rate] = calculate_rate(:matched_domains, :total_processed)
        data[:rate] = calculate_processing_rate(data[:uptime])
        data
      end
    end

    def log_to_console
      data = to_h
      @logger.info('Stats', format_console_stats(data))
    end

    private

    def start_console_reporting
      Async do
        loop do
          sleep @console_interval
          log_to_console
        end
      rescue StandardError => e
        @logger.error('Stats', "Console reporting loop crashed: #{e.class} - #{e.message}")
      end
    end

    def start_discord_reporting
      return unless @stats_interval&.positive?

      Async do
        loop do
          sleep @stats_interval
          @discord_notifier.notify_stats(to_h)
        end
      rescue StandardError => e
        @logger.error('Stats', "Discord reporting loop crashed: #{e.class} - #{e.message}")
      end
    end

    def calculate_rate(numerator, denominator)
      total = @counters[denominator]
      return 0.0 if total.zero?

      ((@counters[numerator].to_f / total) * 100).round(2)
    end

    def calculate_processing_rate(uptime)
      return 0.0 if uptime.zero?

      (@counters[:total_processed].to_f / uptime).round(2)
    end

    def format_console_stats(data)
      parts = [
        "Uptime: #{format_duration(data[:uptime])}",
        "Processed: #{data[:total_processed]}",
        "Matched: #{data[:matched_domains]} (#{data[:match_rate]}%)",
        "DNS: #{data[:dns_resolved]}/#{data[:dns_failed]}",
        "HTTP: #{data[:http_responses]}/#{data[:http_timeout]}",
        "Fingerprinter: #{data[:fingerprinter_sent]}",
        "Rate: #{data[:rate]}/s"
      ]
      parts.join(' | ')
    end

    def format_duration(seconds)
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      secs = seconds % 60
      format('%<hours>02d:%<minutes>02d:%<secs>02d', hours: hours, minutes: minutes, secs: secs)
    end
  end
end
