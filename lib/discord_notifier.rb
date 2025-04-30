# frozen_string_literal: true

require 'httparty'
require 'json'

class DiscordNotifier
  SUCCESS_COLOR = 5_763_719  # Green
  ERROR_COLOR   = 14_549_051 # Red
  INFO_COLOR = 3_447_003     # Blue

  def initialize(messages_webhook, logs_webhook, username, logger)
    @messages_webhook = messages_webhook
    @logs_webhook     = logs_webhook
    @username         = username
    @logger           = logger
  end

  def send_message(domain, ip, wildcard_info = nil)
    @logger.info("Sending Discord alert for domain: #{domain}")

    program_name     = wildcard_info&.dig('program') || 'Unknown Program'
    wildcard_pattern = wildcard_info&.dig('pattern') || 'Unknown Pattern'

    fields = [
      { name: 'Domain',            value: domain,           inline: true  },
      { name: 'IP Address',        value: ip,               inline: true  },
      { name: 'Program',           value: program_name,     inline: true  },
      { name: 'Matching Wildcard', value: wildcard_pattern, inline: false }
    ]

    send(
      @messages_webhook,
      title: 'New Domain Detected',
      description: 'A new domain matching a monitored wildcard has been detected',
      fields: fields,
      color: INFO_COLOR
    )
  end

  def send_log(title, description, type)
    @logger.error("Sending Discord log: #{title} - #{description}")
    color = type == :error ? ERROR_COLOR : SUCCESS_COLOR

    send(
      @logs_webhook,
      title: title,
      description: description,
      fields: [],
      color: color
    )
  end

  private

  def send(webhook_url, title:, description:, fields:, color:)
    embed = build_embed(title, description, fields, color)
    payload = { username: @username, embeds: [embed] }

    response = HTTParty.post(
      webhook_url,
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
