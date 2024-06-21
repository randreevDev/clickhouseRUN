#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
SELECT 1;
EOSQL
