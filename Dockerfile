FROM ruby:4.0.5-slim-bookworm@sha256:707ef4cbfc3d990664996e5ef154abd6a41539aa774b8467f55126697e03d58f

ARG TARGETARCH

ENV BUNDLE_DEPLOYMENT=true \
    BUNDLE_PATH=/usr/local/bundle

WORKDIR /acceptance

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       default-mysql-client \
       postgresql-client \
       unzip \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY support/stage_duckdb_cli.sh /tmp/stage_duckdb_cli.sh
RUN /tmp/stage_duckdb_cli.sh "$TARGETARCH" /usr/local/bin /opt/duckdb/extensions \
    && rm /tmp/stage_duckdb_cli.sh

COPY . ./

CMD ["bundle", "exec", "bin/test"]
