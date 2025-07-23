# frozen_string_literal: true

# Load all application files
require_relative 'src/websocket'
require_relative 'src/wildcard_manager'

# Start the application
app = Certstream::Monitor.new
app.run
