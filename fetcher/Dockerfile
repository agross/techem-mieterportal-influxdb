FROM ruby:4.0.1-alpine

ENV LANG=C.UTF-8

WORKDIR /app

RUN apk add --no-cache \
            build-base

COPY Gemfile Gemfile.lock ./

RUN bundle config set --global frozen 1 && \
    bundle config set --global without development

RUN bundle install

COPY . ./

CMD ["./main.rb"]
