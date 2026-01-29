# frozen_string_literal: true

require 'httpx'
require 'json'

module Certstream
  class DiscordNotifier
    STATS_FIELDS = [
      ['Uptime', :uptime, ''],
      ['Total Processed', :total_processed, ''],
      ['Matched Domains', :matched_domains, ''],
      ['Match Rate', :match_rate, '%'],
      ['DNS Resolved', :dns_resolved, ''],
      ['DNS Failed', :dns_failed, ''],
      ['HTTP Responses', :http_responses, ''],
      ['HTTP Timeouts', :http_timeout, ''],
      ['Fingerprinter Sent', :fingerprinter_sent, ''],
      ['Rate', :rate, '/s']
    ].freeze

    def initialize(config, logger)
      @messages_webhook = config.discord['messages_webhook']
      @logs_webhook = config.discord['logs_webhook']
      @logger = logger
    end

    def notify_match(domain:, wildcard:, ips:, urls:)
      return unless @messages_webhook

      send_webhook(@messages_webhook, build_match_embed(domain, wildcard, ips, urls))
    end

    def notify_error(message)
      return unless @logs_webhook

      send_webhook(@logs_webhook, build_error_message(message))
    end

    def notify_stats(stats_data)
      return unless @logs_webhook

      send_webhook(@logs_webhook, build_stats_embed(stats_data))
    end

    private

    def send_webhook(url, payload)
      @logger.debug('Discord', "Send message to Discord: #{payload}")
      HTTPX.post(url, json: payload)
    rescue StandardError => e
      @logger.error('Discord', "Failed to send webhook: #{e.message}")
    end

    def build_match_embed(domain, wildcard, ips, urls)
      {
        embeds: [
          {
            title: 'New Domain Match',
            color: 5_025_616,
            fields: [
              { name: 'Domain', value: "`#{domain}`", inline: false },
              { name: 'Matched Wildcard', value: "`#{wildcard}`", inline: true },
              { name: 'IPs', value: ips.join(', '), inline: true },
              { name: 'Active URLs', value: urls.size.to_s, inline: true },
              { name: 'URLs', value: urls.map { |u| "<#{u}>" }.join("\n").slice(0, 1024), inline: false }
            ],
            timestamp: Time.now.utc.iso8601
          }
        ]
      }
    end

    def build_error_message(message)
      {
        embeds: [
          {
            title: 'Error',
            description: message,
            color: 15_158_332,
            timestamp: Time.now.utc.iso8601
          }
        ]
      }
    end

    def build_stats_embed(stats_data)
      {
        embeds: [
          {
            title: 'Certstream Monitor - Statistics',
            color: 3_447_003,
            fields: build_stats_fields(stats_data),
            timestamp: Time.now.utc.iso8601
          }
        ]
      }
    end

    def build_stats_fields(stats_data)
      STATS_FIELDS.map do |name, key, suffix|
        value = format_stat_value(stats_data, key, suffix)
        { name: name, value: value, inline: true }
      end
    end

    def format_stat_value(stats_data, key, suffix)
      return format_duration(stats_data[key]) if key == :uptime

      "#{stats_data[key]}#{suffix}"
    end

    def format_duration(seconds)
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      secs = seconds % 60
      format('%<hours>02d:%<minutes>02d:%<secs>02d', hours: hours, minutes: minutes, secs: secs)
    end
  end
end
