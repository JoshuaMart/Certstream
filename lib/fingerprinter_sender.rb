# frozen_string_literal: true

require 'httparty'

class FingerprinterSender
  attr_reader :fingerprinter_url, :callback_url, :api_key, :logger

  def initialize(fingerprinter_url, callback_url, api_key, logger)
    @fingerprinter_url = fingerprinter_url
    @api_key = api_key
    @callback_url = callback_url
    @logger = logger
  end

  def send(domain)
    logger.info("Sending #{domain} to fingerprinter")

    payload = {
      urls: [domain],
      callback_url: callback_url
    }

    headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{api_key}" }

    HTTParty.post(
      fingerprinter_url,
      body: payload.to_json,
      headers: headers
    )
  end
end
