# frozen_string_literal: true

require 'httparty'
require 'json'

class DiscordNotifier
  DEFAULT_USERNAME = 'Certstream Monitor'.freeze
  SUCCESS_COLOR = 3_447_003  # Blue
  ERROR_COLOR   = 14_549_051 # Red

  def initialize(webhook_url, username, logger)
    @webhook_url = webhook_url
    @username    = username
    @logger      = logger
  end

  def send_alert(domain, ip, wildcard_info = nil)
    return unless valid_webhook?

    @logger.info("Sending Discord alert for domain: #{domain}")

    program_name     = wildcard_info&.dig('program') || 'Unknown Program'
    wildcard_pattern = wildcard_info&.dig('pattern') || 'Unknown Pattern'

    fields = [
      { name: 'Domain',            value: domain,           inline: true  },
      { name: 'IP Address',        value: ip,               inline: true  },
      { name: 'Program',           value: program_name,     inline: true  },
      { name: 'Matching Wildcard', value: wildcard_pattern, inline: false }
    ]

    send_message(
      title: 'New Domain Detected',
      description: 'A new domain matching a monitored wildcard has been detected',
      fields: fields,
      color: SUCCESS_COLOR
    )
  end

  def send_error(title, description)
    return unless valid_webhook?

    @logger.error("Sending Discord error: #{title} - #{description}")

    send_message(
      title: title,
      description: description,
      fields: [],
      color: ERROR_COLOR
    )
  end

  private

  def valid_webhook?
    @webhook_url && !@webhook_url.empty? && !@webhook_url.include?('your-webhook-url-here')
  end

  def send_message(title:, description:, fields:, color:)
    embed = build_embed(title, description, fields, color)
    payload = { username: @username, embeds: [embed] }

    response = HTTParty.post(
      @webhook_url,
      body: payload.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    if response.code.between?(200, 299)
      @logger.info('Discord notification sent successfully')
    else
      @logger.error("Failed to send Discord notification. Status code: #{response.code}, Response: #{response.body}")
    end
  rescue StandardError => e
    @logger.error("Error sending Discord notification: #{e.message}")
    @logger.error(e.backtrace.join("\n"))
  end

  def build_embed(title, description, fields, color)
    {
      title: title,
      description: description,
      color: color,
      fields: fields,
      footer: { text: "Certstream Monitor • #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}" }
    }
  end
end
