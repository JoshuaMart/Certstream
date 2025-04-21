require 'httparty'
require 'json'

class DiscordNotifier
  def initialize(webhook_url, username = nil, avatar_url = nil, logger)
    @webhook_url = webhook_url
    @username = username || "Certstream Monitor"
    @avatar_url = avatar_url
    @logger = logger
  end

  def send_alert(domain, ip, wildcard_info = nil)
    return if @webhook_url.nil? || @webhook_url.empty? || @webhook_url.include?('your-webhook-url-here')
    
    @logger.info("Sending Discord alert for domain: #{domain}")
    
    begin
      program_name = wildcard_info ? wildcard_info['program'] : "Unknown Program"
      wildcard_pattern = wildcard_info ? wildcard_info['pattern'] : "Unknown Pattern"
      
      embed = {
        title: "New Domain Detected",
        description: "A new domain matching a monitored wildcard has been detected",
        color: 3447003,  # Blue color
        fields: [
          {
            name: "Domain",
            value: domain,
            inline: true
          },
          {
            name: "IP Address",
            value: ip,
            inline: true
          },
          {
            name: "Program",
            value: program_name || "Unknown",
            inline: true
          },
          {
            name: "Matching Wildcard",
            value: wildcard_pattern || "Unknown",
            inline: false
          }
        ],
        footer: {
          text: "Certstream Monitor • #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
        }
      }
      
      payload = {
        username: @username,
        embeds: [embed]
      }
      
      # Add avatar URL if provided
      payload[:avatar_url] = @avatar_url if @avatar_url && !@avatar_url.empty?
      
      response = HTTParty.post(
        @webhook_url,
        body: payload.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      
      if response.code >= 200 && response.code < 300
        @logger.info("Discord notification sent successfully")
      else
        @logger.error("Failed to send Discord notification. Status code: #{response.code}, Response: #{response.body}")
      end
    rescue StandardError => e
      @logger.error("Error sending Discord notification: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
    end
  end
end
