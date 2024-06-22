#!/bin/bash
set -e
clickhouse-client --port 9001 -n <<-EOSQL
SELECT 1;
EOSQL
