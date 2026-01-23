FROM ruby:4.0.1-alpine

RUN apk add --no-cache build-base

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

COPY . .

CMD ["ruby", "main.rb", "start"]
