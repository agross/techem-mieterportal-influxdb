FROM ruby:4.0.0-alpine

ENV LANG=C.UTF-8

WORKDIR /app

RUN apk add --no-cache \
            build-base

COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1 && \
    bundle install

COPY . ./

CMD ["./main.rb"]
