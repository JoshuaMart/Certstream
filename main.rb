# frozen_string_literal: true

# Load all application files
require_relative 'app/core/dependency_container'
require_relative 'app/core/application'

# Start the application
app = Certstream::Core::Application.new
app.start
