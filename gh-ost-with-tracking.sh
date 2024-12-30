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
    MIGRATION_FILE="$3"
    
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

    # If successful, move the migration file to the default folder
    mv "$MIGRATION_FILE" "database/migrations/"
    echo "Successfully moved $MIGRATION_FILE to database/migrations/"

    return 0
}

# Get a list of all gh-ost migrations in the gh-ost folder
find database/migrations/gh-ost -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    migration_name=$(basename "$migration_file" .php)

    # Extract table name and ALTER SQL from the migration file
    TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file")
    ALTER_TABLE_SQL=$(grep -oP "// gh-ost: .+" "$migration_file" | sed 's/.*gh-ost: //')

    if [[ -n "$TABLE_NAME" && -n "$ALTER_TABLE_SQL" ]]; then
        echo "Running gh-ost migration: $migration_name"
        
        # Execute the gh-ost migration
        if execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL" "$migration_file"; then
            echo "Migration $migration_name completed successfully."
        else
            echo "Migration $migration_name failed. Skipping."
        fi
    fi
done

echo "Migration process complete."
