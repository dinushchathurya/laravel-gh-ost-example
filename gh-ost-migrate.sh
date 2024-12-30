#!/bin/bash

# Database credentials (using environment variables is recommended)
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE:-test_database}"
DB_USERNAME="${DB_USERNAME:-root}"
DB_PASSWORD="${DB_PASSWORD:-root_password}"

# Ensure database is set
if [[ -z "$DB_DATABASE" ]]; then
    echo "Database not specified. Exiting."
    exit 1
fi

# Function to execute gh-ost for a table and ALTER SQL
execute_gh_ost() {
    TABLE_NAME="$1"
    ALTER_SQL="$2"

    # Trim any leading or trailing spaces from the table name
    TABLE_NAME=$(echo "$TABLE_NAME" | xargs)

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
        return 1
    fi
    return 0
}

# Ensure the migration table is available before checking if the migration is applied
check_migration_applied() {
    migration_name="$1"
    # Check if migration exists in the gh_ost_migrations table
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" -e "SELECT 1 FROM gh_ost_migrations WHERE migration='$migration_name'" | grep -q "1"
}

find database/migrations/gh-ost -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    migration_name=$(basename "$migration_file" .php)

    # Check if the migration has already been applied via gh-ost
    if check_migration_applied "$migration_name"; then
        echo "gh-ost Migration $migration_name already applied. Skipping."
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

    # Trim the table name to avoid any leading/trailing spaces
    TABLE_NAME=$(echo "$TABLE_NAME" | xargs)

    if [[ -z "$TABLE_NAME" ]]; then
        echo "Could not extract table name from $migration_file. Skipping."
        php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
        continue
    fi

    # Extract the ALTER TABLE SQL from the comment in the migration
    ALTER_TABLE_SQL=$(grep -oP "// gh-ost: .+" "$migration_file" | sed 's/.*gh-ost: //')

    # Debugging output to verify the SQL extraction
    echo "Extracted ALTER TABLE SQL: $ALTER_TABLE_SQL"

    if [[ -n "$ALTER_TABLE_SQL" ]]; then
        if execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL"; then
            # After gh-ost is successful, mark the migration as applied in the gh_ost_migrations table
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" -e "INSERT INTO gh_ost_migrations (migration) VALUES ('$migration_name');"
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
