#!/bin/bash

ENVIRONMENT="$1"

# Database connection settings from environment-specific secrets
DB_HOST="${DB_HOST}"
DB_USER="${DB_USER}"
DB_PASSWORD="${DB_PASSWORD}"
DB_NAME="${DB_NAME}"

MIGRATIONS_PATH="database/migrations"

# Check if there are any migration files changed (duplicate check for safety)
if [[ -z "$(git diff --name-only HEAD^ HEAD -- database/migrations)" ]]; then
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
        gh-ost \
            --host="$DB_HOST" \
            --port="$DB_PORT" \
            --user="$DB_USER" \
            --password="$DB_PASSWORD" \
            --database="$DB_NAME" \
            --table="$TABLE_NAME" \
            --alter="$sql_statement" \
            --execute
    done
done