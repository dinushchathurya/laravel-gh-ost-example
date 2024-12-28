#!/bin/bash

# Set database credentials (or use environment variables)
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-3306}
DB_DATABASE=${DB_DATABASE:-test_database}
DB_USERNAME=${DB_USERNAME:-root}
DB_PASSWORD=${DB_PASSWORD:-root_password}

# Function to execute gh-ost
execute_gh_ost() {
  TABLE_NAME="$1"
  ALTER_SQL="$2"

  echo "Executing gh-ost for table: $TABLE_NAME"
  echo "SQL: $ALTER_SQL"

  gh-ost \
    --host="$DB_HOST" \
    --port="$DB_PORT" \
    --database="$DB_DATABASE" \
    --user="$DB_USERNAME" \
    --password="$DB_PASSWORD" \
    --table="$TABLE_NAME" \
    --alter="$ALTER_SQL" \
    --execute

  if [[ $? -ne 0 ]]; then
    echo "gh-ost failed!"
    exit 1
  fi
}

extract_sql_from_migration() {
    MIGRATION_FILE="$1"
    TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$MIGRATION_FILE")
        if [[ -z "$TABLE_NAME" ]]; then
        TABLE_NAME=$(grep -oP "(?<=Schema::create\(')[^']+" "$MIGRATION_FILE")
    fi
    # Execute the migration using --pretend and grep for ALTER TABLE statements
    SQL=$(php artisan migrate --path="database/migrations/$(basename "$MIGRATION_FILE")" --pretend --force --no-interaction | grep "ALTER TABLE")
    echo "$SQL"
}

for migration_file in database/migrations/gh-ost_*.php; do
    echo "Processing $migration_file"

        TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file")
        if [[ -z "$TABLE_NAME" ]]; then
        TABLE_NAME=$(grep -oP "(?<=Schema::create\(')[^']+" "$migration_file")
    fi
    if [[ -z "$TABLE_NAME" ]]; then
        echo "Could not extract table name from $migration_file. Skipping."
        continue
    fi

    ALTER_SQL=$(extract_sql_from_migration "$migration_file")

    if [[ -n "$ALTER_SQL" ]]; then
        execute_gh_ost "$TABLE_NAME" "$ALTER_SQL"
    else
        echo "Could not extract SQL from $migration_file. Skipping gh-ost execution."
    fi

    php artisan migrate:rollback --path="database/migrations/$(basename "$migration_file")" --force --no-interaction

done

echo "gh-ost migrations complete."