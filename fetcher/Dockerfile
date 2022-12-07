FROM ruby:3.1.2-alpine

ENV LANG C.UTF-8

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1 && \
    bundle install

COPY . ./

CMD ["./main.rb"]
