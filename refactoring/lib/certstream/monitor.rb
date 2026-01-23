# frozen_string_literal: true

module Certstream
  class Monitor
    def initialize(config, logger)
      @config = config
      @logger = logger
    end

    def run
      @logger.info('Monitor', 'Monitor started (stub)')
      # TODO: Phase 8
    end
  end
end
