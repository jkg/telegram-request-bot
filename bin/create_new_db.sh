#!/bin/bash

DATABASE=requestbot.db

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

