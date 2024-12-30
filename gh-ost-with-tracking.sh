#!/bin/bash

# Database credentials (using environment variables is recommended)
DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE}"
DB_USERNAME="${DB_USERNAME}"
DB_PASSWORD="${DB_PASSWORD}"

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
        return 1 # Return 1 to indicate failure
    fi
    return 0
}

# Function to check if a migration is already applied in the migrations table
is_migration_applied() {
    migration_name="$1"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT COUNT(1) FROM migrations WHERE migration='$migration_name';" "$DB_DATABASE" | grep -q "1"
}

# Get a list of all migrations that have already been applied in Laravel
applied_migrations=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT migration FROM migrations" "$DB_DATABASE" | tail -n +2)

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

        # After running a normal migration, mark it as applied in the migrations table
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" -e "INSERT INTO migrations (migration) VALUES ('$migration_name');"
    fi
done

# Step 2: Check and run already applied gh-ost migrations (if already in the migrations table)
echo "Checking previously applied gh-ost migrations"

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
            if is_migration_applied "$migration_name"; then
                echo "gh-ost migration $migration_name already applied. Skipping."
                continue
            fi

            # Run gh-ost migration that was previously applied manually or by another means
            echo "Running previously applied gh-ost migration: $migration_name"
            if execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL"; then
                mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" -e "INSERT INTO migrations (migration) VALUES ('$migration_name');"
            else
                echo "gh-ost execution failed. Skipping."
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
            echo "Running new gh-ost migration: $migration_name"
            if execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL"; then
                mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" -e "INSERT INTO migrations (migration) VALUES ('$migration_name');"
            else
                echo "gh-ost execution failed. Skipping."
            fi
        fi
    fi
done

echo "Migration process complete."
