#!/bin/bash

ROOT_DIR=$(cd $(dirname $0)/..; pwd)
DB_DIR="$ROOT_DIR/db"
BENCH_DIR="$ROOT_DIR/bench"

export MYSQL_PWD=isucon

mysql -uisucon -h 172.17.147.2 -e "DROP DATABASE IF EXISTS torb; CREATE DATABASE torb;"
mysql -uisucon -h 172.17.147.2 torb < "$DB_DIR/schema.sql"

if [ ! -f "$DB_DIR/dump.sql.gz" ]; then
  echo "Run the following command beforehand." 1>&2
  echo "$ ( cd \"$BENCH_DIR\" && bin/gen-initial-dataset )" 1>&2
  exit 1
fi

mysql -uisucon -h 172.17.147.2 torb -e 'ALTER TABLE reservations DROP KEY event_id_and_sheet_id_idx'
gzip -dc "$DB_DIR/dump.sql.gz" | mysql -uisucon -h 172.17.147.2 torb
mysql -uisucon -h 172.17.147.2 torb -e 'ALTER TABLE reservations ADD KEY event_id_and_sheet_id_idx (event_id, sheet_id)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (11, "S", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (11, "A", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (11, "B", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (11, "C", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (12, "S", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (12, "A", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (12, "B", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (12, "C", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (13, "S", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (13, "A", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (13, "B", 0)'
mysql -uisucon -h 172.17.147.2 torb -e 'INSERT INTO sheetcounts (event_id, `rank`, count) VALUES (13, "C", 0)'
