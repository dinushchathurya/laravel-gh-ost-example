#!/bin/bash

# Database credentials (using environment variables is recommended)
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE:-test_database}"
DB_USERNAME="${DB_USERNAME:-root}"
DB_PASSWORD="${DB_PASSWORD:-root_password}"

# Ensure environment variables are set
if [[ -z "$DB_HOST" || -z "$DB_DATABASE" || -z "$DB_USERNAME" || -z "$DB_PASSWORD" ]]; then
  echo "Database credentials are missing. Exiting."
  exit 1
fi

# Function to execute gh-ost for a table and ALTER SQL
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
        return 1
    fi
    return 0
}

# Function to check if a migration is already applied in the migrations table
is_migration_applied() {
    migration_name="$1"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT COUNT(1) FROM migrations WHERE migration='$migration_name';" | grep -q "1"
}

# Function to check if the gh-ost migration has been applied by checking table existence
is_gh_ost_migration_applied() {
    TABLE_NAME="$1"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SHOW TABLES LIKE '${TABLE_NAME}_gho%';" | grep -q "${TABLE_NAME}_gho"
}

# Get a list of all migrations that have already been applied in Laravel
applied_migrations=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT migration FROM migrations" | tail -n +2)

# Step 1: Run normal Laravel migrations first (those without //gh-ost: comment)
echo "Running normal migrations (without //gh-ost:)"
find database/migrations -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    migration_name=$(basename "$migration_file" .php)

    # Skip migrations already applied by Laravel
    if echo "$applied_migrations" | grep -q "$migration_name"; then
        echo "Migration $migration_name already applied by Laravel. Skipping."
        continue
    fi

    # If migration doesn't have the //gh-ost: comment, run it as a normal migration
    if ! grep -q "// gh-ost:" "$migration_file"; then
        echo "Running regular Laravel migration: $migration_name"
        php artisan migrate --path="database/migrations/$(basename "$migration_file")" --force --no-interaction
    fi
done

# Step 2: Run gh-ost migrations that have already been applied (via gh-ost)
echo "Running previously applied gh-ost migrations"
find database/migrations -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    migration_name=$(basename "$migration_file" .php)

    # Skip migrations already applied by Laravel
    if echo "$applied_migrations" | grep -q "$migration_name"; then
        echo "Migration $migration_name already applied by Laravel. Skipping."
        continue
    fi

    # Check if the migration has the //gh-ost: comment
    if grep -q "// gh-ost:" "$migration_file"; then
        TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file")
        ALTER_TABLE_SQL=$(grep -oP "// gh-ost: .+" "$migration_file" | sed 's/.*gh-ost: //')

        if [[ -n "$TABLE_NAME" && -n "$ALTER_TABLE_SQL" ]]; then
            # Check if the migration has already been applied via gh-ost (i.e., if the table modification exists)
            if is_gh_ost_migration_applied "$TABLE_NAME"; then
                echo "gh-ost migration $migration_name already applied (via gh-ost). Running as normal migration."
                # Mark the migration as applied in the migrations table (without re-running ALTER TABLE)
                mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "INSERT INTO migrations (migration) VALUES ('$migration_name');"
                continue
            fi
        fi
    fi
done

# Step 3: Run new gh-ost migrations that haven't been applied yet
echo "Running new gh-ost migrations"
find database/migrations -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    migration_name=$(basename "$migration_file" .php)

    # Skip migrations already applied by Laravel
    if echo "$applied_migrations" | grep -q "$migration_name"; then
        echo "Migration $migration_name already applied by Laravel. Skipping."
        continue
    fi

    # Check if the migration has the //gh-ost: comment
    if grep -q "// gh-ost:" "$migration_file"; then
        TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file")
        ALTER_TABLE_SQL=$(grep -oP "// gh-ost: .+" "$migration_file" | sed 's/.*gh-ost: //')

        if [[ -n "$TABLE_NAME" && -n "$ALTER_TABLE_SQL" ]]; then
            # Run the gh-ost migration (it hasn't been applied yet)
            if execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL"; then
                # After gh-ost is successful, mark the migration as applied in the migrations table
                mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "INSERT INTO migrations (migration) VALUES ('$migration_name');"
            else
                echo "gh-ost execution failed. Rolling back migration."
                php artisan migrate:rollback --path="database/migrations/$(basename "$migration_file")" --force --no-interaction
            fi
        fi
    fi
done

echo "Migration process complete."
