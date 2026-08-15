FROM ruby:4.0-alpine

# throw errors if Gemfile has been modified since Gemfile.lock
# RUN bundle config --global frozen 1

WORKDIR /app

RUN apk add --update --no-cache \
    build-base \
    postgresql-dev \
    postgresql-client \
    tzdata \
    file

COPY ./app/Gemfile ./app/Gemfile.lock ./
RUN bundle config set --local without 'development test' \
    && bundle config set --local frozen true \
    && bundle install

COPY ./app .

# exec form so SIGTERM reaches Ruby directly for graceful shutdown
ENTRYPOINT ["bundle", "exec", "./auto_planka.rb"]
