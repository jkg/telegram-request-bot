#!/bin/bash
dbicdump \
    -o dump_directory=./lib \
    -o overwrite_modifications=1 \
    RequestBot::Schema \
    dbi:SQLite:./requestbot.db
