#!/bin/sh
# docker/postgres/init-test-db.sh
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" <<-SQL
    CREATE DATABASE booking_test OWNER $POSTGRES_USER;
SQL
