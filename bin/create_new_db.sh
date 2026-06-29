#!/bin/bash

# Usage: create_new_db.sh [DB_PATH]
# DB_PATH defaults to requestbot.db if not supplied.
DATABASE=${1:-requestbot.db}

EPOCH=$(date +%s)
if [ -e "$DATABASE" ]
then
    echo "Creating backup of the database."
    mv "$DATABASE" "$DATABASE.$EPOCH"
fi

echo "Rebuilding database..."
for sql_file in sql/*.sql
do
    echo "- $sql_file"
    sqlite3 "$DATABASE" < "$sql_file"
done

