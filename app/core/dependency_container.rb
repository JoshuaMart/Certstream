# frozen_string_literal: true

module Certstream
  module Core
    # Container for managing application-wide dependencies
    class DependencyContainer
      def initialize
        @services = {}
      end

      # Register a service with the container
      def register(name, service = nil, &block)
        @services[name.to_sym] = if block_given?
                                   # Lazy initialization with a block
                                   { instance: nil, initializer: block }
                                 else
                                   # Direct initialization with an instance
                                   { instance: service, initializer: nil }
                                 end
      end

      # Retrieve a service from the container
      def resolve(name)
        service_entry = @services[name.to_sym]
        raise "Service '#{name}' not registered" unless service_entry

        # Initialize the service if it's not already initialized
        service_entry[:instance] = service_entry[:initializer].call if service_entry[:instance].nil? && service_entry[:initializer]

        service_entry[:instance]
      end

      # Get a service using method_missing for cleaner syntax (e.g., container.logger)
      def method_missing(method_name, *args, &block)
        if @services.key?(method_name)
          resolve(method_name)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @services.key?(method_name) || super
      end
    end

    # Global container instance
    def self.container
      @container ||= DependencyContainer.new
    end
  end
end
