FROM ruby:4.0.2-alpine

RUN apk add --no-cache build-base openssl-dev

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test' && bundle install

COPY . .

CMD ["ruby", "main.rb", "start"]
