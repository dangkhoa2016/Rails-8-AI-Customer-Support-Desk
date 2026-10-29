# Development-only synthetic Rails app (no production credentials or data).
FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev postgresql-client && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile ./
RUN bundle install
COPY . .
EXPOSE 3000
ENV RAILS_ENV=development
CMD ["sh", "-c", "bin/rails db:create db:migrate && M1_SYNTHETIC_DEMO=YES bin/rails db:seed && bin/rails server -b 0.0.0.0"]
