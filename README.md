# clickhouseRUN

Репозиторий создан для быстрого развертывания clickhouse стенда.

Запуск:

    sudo docker compose up

После запуска в папке values создается директория var куда сохраняются базы.


Запросы к базе которые могут помочь в расследовании и изучении ее работы:

* Partitions info.
~~~~sql
    SELECT database, table, partition, formatReadableSize(sum (data_compressed_bytes)) AS compressed, formatReadableSize(sum (data_uncompressed_bytes)) AS uncompressed, trunc((sum (data_uncompressed_bytes) / sum (data_compressed_bytes)), 4) as ratio
    FROM system.parts
    GROUP BY
    database,
    table,
    partition
    ORDER BY sum (data_compressed_bytes) DESC;
~~~~

* Compression by columns.
~~~~sql
    SELECT
    database,
    table,
    column,
    type,
    sum(rows) AS rows,
    sum(column_data_compressed_bytes) AS compressed_bytes,
    formatReadableSize(compressed_bytes) AS compressed,
    formatReadableSize(sum(column_data_uncompressed_bytes)) AS uncompressed,
    sum(column_data_uncompressed_bytes) / compressed_bytes AS ratio,
    any(compression_codec) AS codec
    FROM system.parts_columns AS pc
    LEFT JOIN system.columns AS c
    ON (pc.database = c.database) AND (c.table = pc.table) AND (c.name = pc.column)
    WHERE (database LIKE '%') AND (table LIKE '%') AND active
    GROUP BY
    database,
    table,
    column,
    type
    ORDER BY database, table, sum(column_data_compressed_bytes) DESC
~~~~

* Compression by tables.
~~~~sql
    SELECT
    database,
    table,
    count() AS parts,
    uniqExact(partition_id) AS partition_cnt,
    sum(rows),
    formatReadableSize(sum(data_compressed_bytes) AS comp_bytes) AS comp,
    formatReadableSize(sum(data_uncompressed_bytes) AS uncomp_bytes) AS uncomp,
    uncomp_bytes / comp_bytes AS ratio
    FROM system.parts
    WHERE active
    GROUP BY
    database,
    table
    ORDER BY comp_bytes DESC
~~~~

* Longest query.
~~~~sql
    SELECT
    normalized_query_hash,
    any(query),
    count(),
    sum(query_duration_ms) / 1000 AS QueriesDuration,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'RealTimeMicroseconds')]) / 1000000 AS RealTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'UserTimeMicroseconds')]) / 1000000 AS UserTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'SystemTimeMicroseconds')]) / 1000000 AS SystemTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'DiskReadElapsedMicroseconds')]) / 1000000 AS DiskReadTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'DiskWriteElapsedMicroseconds')]) / 1000000 AS DiskWriteTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'NetworkSendElapsedMicroseconds')]) / 1000000 AS NetworkSendTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'NetworkReceiveElapsedMicroseconds')]) / 1000000 AS NetworkReceiveTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'ZooKeeperWaitMicroseconds')]) / 1000000 AS ZooKeeperWaitTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'OSIOWaitMicroseconds')]) / 1000000 AS OSIOWaitTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'OSCPUWaitMicroseconds')]) / 1000000 AS OSCPUWaitTime,
    sum(ProfileEvents.Values[indexOf(ProfileEvents.Names, 'OSCPUVirtualTimeMicroseconds')]) / 1000000 AS OSCPUVirtualTime,
    sum(read_rows) AS ReadRows,
    formatReadableSize(sum(read_bytes)) AS ReadBytes,
    sum(written_rows) AS WrittenTows,
    formatReadableSize(sum(written_bytes)) AS WrittenBytes,
    sum(result_rows) AS ResultRows,
    formatReadableSize(sum(result_bytes)) AS ResultBytes
    FROM system.query_log
    WHERE (event_date >= today()) AND (event_time > (now() - 3600)) AND type in (2,4) -- QueryFinish, ExceptionWhileProcessing
    GROUP BY normalized_query_hash
    WITH TOTALS
    ORDER BY UserTime DESC
    LIMIT 30
    FORMAT Vertical
~~~~

* Disk space.
~~~~sql
    SELECT name,
    path,
    formatReadableSize(free_space)      AS free,
    formatReadableSize(total_space)     AS total,
    formatReadableSize(keep_free_space) AS reserved
    FROM system.disks;
~~~~

* Size table.
~~~~sql
    SELECT concat(database, '.', table) AS table,
    formatReadableSize(sum(bytes)) AS size,
    sum(bytes) AS bytes_size,
    sum(rows) AS rows,
    max(modification_time) AS latest_modification,
    any(engine) AS engine
    FROM system.parts
    WHERE active
    GROUP BY
    database,
    table
    ORDER BY bytes_size DESC;
~~~~

* Columns info.
~~~~sql
    SELECT name,
    type,
    formatReadableSize(data_compressed_bytes)       AS compressed,
    formatReadableSize(data_uncompressed_bytes)     AS uncompressed,
    data_uncompressed_bytes / data_compressed_bytes AS ratio,
    compression_codec
    FROM system.columns
    WHERE (database = 'sgol')
    AND (table = 'gol')
    ORDER BY data_compressed_bytes DESC;
~~~~

* Table info.
~~~~sql
    select parts.*,
    columns.compressed_size,
    columns.uncompressed_size,
    columns.ratio
    from (select database, table, formatReadableSize(sum (data_uncompressed_bytes)) AS uncompressed_size, formatReadableSize(sum (data_compressed_bytes)) AS compressed_size, sum (data_compressed_bytes) / sum (data_uncompressed_bytes) AS ratio
    from system.columns
    group by database, table) columns
    right join (select database, table, sum (rows) as rows, max (modification_time) as latest_modification, formatReadableSize(sum (bytes)) as disk_size, formatReadableSize(sum (primary_key_bytes_in_memory)) as primary_keys_size, any (engine) as engine, sum (bytes) as bytes_size
    from system.parts
    where active
    group by database, table) parts on (columns.database = parts.database and columns.table = parts.table)
    order by parts.bytes_size desc;
~~~~

* Find detach partition.
~~~~sql
    SELECT database, table, partition_id
    FROM system.detached_parts
    WHERE table ='gol'
~~~~

* Delete detach partition.
~~~~sql
    ALTER TABLE gol DROP DETACHED PARTITION '20230617' SETTINGS allow_drop_detached = 1;
~~~~

* Show metric.
~~~~sql
    SELECT * FROM system.metrics LIMIT 5
~~~~

* Count cpu per query.
~~~~sql
    SELECT
    any (query), sum (`ProfileEvents.Values`[indexOf(`ProfileEvents.Names`, 'UserTimeMicroseconds')]) AS userCPU
    FROM system.query_log
    WHERE (type = 2) AND (event_date >= today())
    GROUP BY normalizedQueryHash(query)
    ORDER BY userCPU DESC
    LIMIT 10
    FORMAT Vertical
~~~~

* Show executed query
~~~~sql
    SELECT substring(query, position(query, 'interesting query part'), 20)
    FROM system.processes
    WHERE (query LIKE '%INSERT%')
    AND (user = 'production')
~~~~

* Cluster CH nodes.
~~~~sql
    SELECT cluster,
    shard_num,
    replica_num,
    host_address,
    port
    FROM system.clusters
~~~~

* Remote query.
~~~~sql
    SELECT logid  FROM remote('000.000.000.000', sgol.gol) LIMIT 3
~~~~

* Show readonly replica.
~~~~sql
    SELECT database, table, replica_name, replica_path
    FROM system.replicas
    WHERE is_readonly FORMAT Vertical
~~~~

* Active mutations.
~~~~sql
    SELECT *
    FROM system.mutations
    WHERE is_done = 0 AND table ='log_stydurunner';
~~~~
