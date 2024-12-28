#!/bin/bash

# Database credentials
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE:-test_database}"
DB_USERNAME="${DB_USERNAME:-root}"
DB_PASSWORD="${DB_PASSWORD:-root_password}"

execute_gh_ost() {
    TABLE_NAME="$1"
    ALTER_SQL="$2"

    echo "Executing gh-ost for table: $TABLE_NAME"
    echo "SQL: $ALTER_SQL"

    GHOST_OUTPUT=$(gh-ost \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --database="$DB_DATABASE" \
        --user="$DB_USERNAME" \
        --password="$DB_PASSWORD" \
        --table="$TABLE_NAME" \
        --alter="$ALTER_SQL" \
        --execute 2>&1)

    echo "gh-ost Output:"
    echo "$GHOST_OUTPUT"

    if [[ $? -ne 0 ]]; then
        echo "gh-ost failed!"
        exit 1
    fi
}

find database/migrations/gh-ost -maxdepth 1 -name "gh-ost_*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    migration_name=$(basename "$migration_file" .php)
    if [[ $(php artisan db:table migrations --show | grep "$migration_name") ]]; then
        echo "Migration $migration_name already applied. Skipping."
        continue
    fi

    echo "Processing $migration_file"

    php artisan migrate --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
    
    TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file")
    if [[ -z "$TABLE_NAME" ]]; then
        TABLE_NAME=$(grep -oP "(?<=Schema::create\(')[^']+" "$migration_file")
    fi

    if [[ -z "$TABLE_NAME" ]]; then
        echo "Could not extract table name from $migration_file. Skipping."
        php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
        continue
    fi

    ALTER_SQL=$(php artisan migrate --path="database/migrations/gh-ost/$(basename "$migration_file")" --pretend --force --no-interaction | grep "ALTER TABLE")

    if [[ -n "$ALTER_SQL" ]]; then
        execute_gh_ost "$TABLE_NAME" "$ALTER_SQL"
        if [[ $? -eq 0 ]]; then
            batch=$(php artisan db:table migrations --show | grep -oP '^[0-9]+' | tail -1)
            if [[ -z "$batch" ]]; then
                batch=1
            else
                batch=$((batch+1))
            fi
            php artisan migrate --path="database/migrations/gh-ost/$(basename "$migration_file")" --database=mysql --force --no-interaction
        fi
    else
        echo "Could not extract SQL from $migration_file. Skipping gh-ost execution."
        php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
        continue
    fi
    php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
done

echo "gh-ost migrations complete."