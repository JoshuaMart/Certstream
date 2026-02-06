# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'

module Certstream
  class HttpClient
    class RequestError < StandardError; end

    DEFAULT_CONNECT_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 10

    def initialize(connect_timeout: DEFAULT_CONNECT_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT, verify_ssl: true,
                   headers: {})
      @connect_timeout = connect_timeout
      @read_timeout = read_timeout
      @verify_ssl = verify_ssl
      @headers = headers
    end

    def get(url)
      perform(:get, url)
    end

    def post(url, json: nil)
      perform(:post, url, json: json)
    end

    def head(url)
      perform(:head, url)
    end

    private

    def perform(method, url, json: nil)
      uri = URI.parse(url)
      Net::HTTP.start(uri.hostname, uri.port, open_timeout: @connect_timeout, read_timeout: @read_timeout,
                                              use_ssl: uri.scheme == 'https', verify_mode: ssl_verify_mode) do |http|
        request = build_request(method, uri, json)
        http.request(request)
      end
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH,
           Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      raise RequestError, e.message
    end

    def build_request(method, uri, json)
      request_class = { get: Net::HTTP::Get, post: Net::HTTP::Post, head: Net::HTTP::Head }[method]
      request = request_class.new(uri.request_uri)

      @headers.each { |key, value| request[key] = value }

      if json
        request.content_type = 'application/json'
        request.body = JSON.generate(json)
      end

      request
    end

    def ssl_verify_mode
      @verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    end
  end
end
