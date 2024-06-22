#!/bin/bash
set -e
clickhouse-client --port 9000 -n <<-EOSQL
SELECT 1;
EOSQL
