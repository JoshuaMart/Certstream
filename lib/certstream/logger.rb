# frozen_string_literal: true

require 'logger'
require 'colorize'

module Certstream
  class Logger
    LEVELS = {
      'DEBUG' => ::Logger::DEBUG,
      'INFO' => ::Logger::INFO,
      'WARN' => ::Logger::WARN,
      'ERROR' => ::Logger::ERROR,
      'FATAL' => ::Logger::FATAL
    }.freeze

    LEVEL_COLORS = {
      'DEBUG' => :light_black,
      'INFO' => :green,
      'WARN' => :yellow,
      'ERROR' => :red,
      'FATAL' => :light_red
    }.freeze

    def initialize(config)
      @colors_enabled = config['console_colors']
      @logger = ::Logger.new($stdout)
      @logger.level = LEVELS.fetch(config['level'].upcase, ::Logger::INFO)
      @logger.formatter = method(:format_message)
    end

    def debug(component, message)
      log(:debug, component, message)
    end

    def info(component, message)
      log(:info, component, message)
    end

    def warn(component, message)
      log(:warn, component, message)
    end

    def error(component, message)
      log(:error, component, message)
    end

    def fatal(component, message)
      log(:fatal, component, message)
    end

    private

    def log(level, component, message)
      @logger.send(level) { { component: component, message: message } }
    end

    def format_message(severity, datetime, _progname, msg)
      timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S')
      component = msg[:component]
      message = msg[:message]

      if @colors_enabled
        format_colored(timestamp, severity, component, message)
      else
        format_plain(timestamp, severity, component, message)
      end
    end

    def format_colored(timestamp, severity, component, message)
      color = LEVEL_COLORS.fetch(severity, :white)

      "[#{timestamp}] ".light_black +
        "[#{severity}]".colorize(color) +
        " [#{component}] ".cyan +
        "#{message}\n"
    end

    def format_plain(timestamp, severity, component, message)
      "[#{timestamp}] [#{severity}] [#{component}] #{message}\n"
    end
  end
end
