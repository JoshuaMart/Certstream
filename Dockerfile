FROM ruby:3.4-alpine

WORKDIR /app

# Install system dependencies
RUN apk add --no-cache build-base sqlite-dev

# Copy Gemfile and install dependencies
COPY Gemfile ./
RUN bundle config set --local without 'development test' && \
    bundle install

# Copy application code
COPY . .

# Create directories for persistent data
RUN mkdir -p /app/data /app/logs

# Set execution permissions for the main script
RUN chmod +x /app/main.rb

# Run the application
CMD ["ruby", "main.rb"]
