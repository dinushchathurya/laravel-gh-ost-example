#!/bin/bash

ENVIRONMENT="$1"

# Database connection settings (local or from secrets)
if [[ "$ENVIRONMENT" == "local" ]]; then
    DB_HOST="127.0.0.1"
    DB_PORT="3306"
    DB_USER="root"
    DB_PASSWORD=""
    DB_NAME="laravel_gh_ost" # Replace with your local database name
    GH_OST_BIN="./gh-ost" # Path to gh-ost binary for local
else
    DB_HOST="${DB_HOST}"
    DB_PORT="${DB_PORT}"
    DB_USER="${DB_USER}"
    DB_PASSWORD="${DB_PASSWORD}"
    DB_NAME="${DB_NAME}"
    GH_OST_BIN="gh-ost" # gh-ost in PATH for CI
fi

MIGRATIONS_PATH="database/migrations"

# Check if there are any migration files changed (duplicate check for safety - only for non-local)
if [[ "$ENVIRONMENT" != "local" ]] && [[ -z "$(git diff --name-only HEAD^ HEAD -- database/migrations)" ]]; then
    echo "No migration files changed. Skipping gh-ost process."
    exit 0
fi

find "$MIGRATIONS_PATH" -name "*.php" -print0 | while IFS= read -r -d $'\0' file; do
    echo "Processing migration file: $file"

    php artisan migrate:refresh --path="$file" --database=mysql --pretend | grep "ALTER" | while IFS= read -r sql_statement; do
        TABLE_NAME=$(echo "$sql_statement" | sed -E 's/ALTER TABLE `(.*?)`.*$/\1/')
        if [[ -z "$TABLE_NAME" ]]; then
            echo "Could not extract table name from: $sql_statement"
            continue
        fi

        echo "Executing gh-ost for table: $TABLE_NAME with statement: $sql_statement"
        $GH_OST_BIN \ # Use the variable for gh-ost execution
            --host="$DB_HOST" \
            --port="$DB_PORT" \
            --user="$DB_USER" \
            --password="$DB_PASSWORD" \
            --database="$DB_NAME" \
            --table="$TABLE_NAME" \
            --alter="$sql_statement" \
            --execute || { echo "ERROR: gh-ost execution failed for: $sql_statement"; exit 1; }
    done
done