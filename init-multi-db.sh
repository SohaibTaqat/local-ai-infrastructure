#!/bin/bash
# Creates additional databases listed in POSTGRES_MULTIPLE_DATABASES
# on first Postgres startup. The default DB (POSTGRES_DB) is already
# created by the official entrypoint; this script handles the extras.

set -eu

if [ -n "${POSTGRES_MULTIPLE_DATABASES:-}" ]; then
  for db in $(echo "$POSTGRES_MULTIPLE_DATABASES" | tr ',' ' '); do
    echo "Creating database: $db"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
      SELECT 'CREATE DATABASE $db'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
EOSQL
  done
fi
