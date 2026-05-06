#!/bin/bash
# Usage: dump_db.sh [DB_PATH]
# DB_PATH defaults to ./requestbot.db if not supplied.
DB_PATH=${1:-./requestbot.db}
dbicdump \
    -o dump_directory=./lib \
    -o overwrite_modifications=1 \
    RequestBot::Schema \
    "dbi:SQLite:${DB_PATH}"
