#!/bin/bash

# Database credentials (using environment variables is recommended)
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
        return 1 # Return 1 to indicate failure
    fi
    return 0
}

find database/migrations/gh-ost -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    migration_name=$(basename "$migration_file" .php)

    # Check if migration has already been applied
    if [[ $(php artisan migrate:status | grep "$migration_name") ]]; then
        echo "Migration $migration_name already applied. Skipping."
        continue
    fi

    echo "Processing $migration_file"

    # Run the migration FIRST to generate the SQL
    php artisan migrate --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction

    # Extract the table name from the migration
    TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file")
    if [[ -z "$TABLE_NAME" ]]; then
        TABLE_NAME=$(grep -oP "(?<=Schema::create\(')[^']+" "$migration_file")
    fi

    if [[ -z "$TABLE_NAME" ]]; then
        echo "Could not extract table name from $migration_file. Skipping."
        php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
        continue
    fi

    # Extract the ALTER TABLE SQL from the comment in the migration
    ALTER_TABLE_SQL=$(grep "//gh-ost:" "$migration_file" | sed 's/.*gh-ost: //')

    echo "** Actual ALTER TABLE SQL from migration: **"
    echo "$ALTER_TABLE_SQL"

    if [[ -n "$ALTER_TABLE_SQL" ]]; then
        if execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL"; then
            # After gh-ost is successful, mark the migration as applied
            php artisan migrate --path="database/migrations/gh-ost/$(basename "$migration_file")" --database=mysql --force --no-interaction
        else
            echo "gh-ost execution failed. Rolling back migration."
            php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
        fi
    else
        echo "Could not extract SQL from $migration_file. Skipping gh-ost execution."
        php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
        continue
    fi
done

echo "gh-ost migrations complete."
