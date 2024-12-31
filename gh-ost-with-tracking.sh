#!/bin/bash

# Database credentials
DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE}"
DB_USERNAME="${DB_USERNAME}"
DB_PASSWORD="${DB_PASSWORD}"

# Temp folder for gh-ost migrations
TEMP_FOLDER="temp_gh_ost_migrations"

# gh-ost related settings
GHOST_RETRY_COUNT="${GHOST_RETRY_COUNT:-3}"
GHOST_RETRY_DELAY="${GHOST_RETRY_DELAY:-5}"

# Ensure environment variables are set
if [[ -z "$DB_HOST" || -z "$DB_DATABASE" || -z "$DB_USERNAME" || -z "$DB_PASSWORD" ]]; then
  echo "Error: Missing database credentials. Please set DB_HOST, DB_DATABASE, DB_USERNAME, and DB_PASSWORD." >&2
  exit 1
fi

# Create temp folder for gh-ost migrations
mkdir -p "$TEMP_FOLDER"

# Move gh-ost migrations to temp folder
echo "Moving gh-ost migrations to temp folder: $TEMP_FOLDER"
find database/migrations -maxdepth 1 -name "*.php" -exec grep -l "// gh-ost:" {} \; -exec mv {} "$TEMP_FOLDER/" \;

# Function to execute gh-ost with retry logic and capture output
execute_gh_ost() {
  local TABLE_NAME="$1"
  local ALTER_SQL="$2"
  local RETRIES="$GHOST_RETRY_COUNT"

  echo "Executing gh-ost for table: $TABLE_NAME"
  echo "SQL: $ALTER_SQL"

  # Ensure no leftover ghost or old table exists
  echo "Dropping existing ghost or old tables (if any): _${TABLE_NAME}_gho and _${TABLE_NAME}_del"
  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "DROP TABLE IF EXISTS \`_${TABLE_NAME}_gho\`, \`_${TABLE_NAME}_del\`;" || {
      echo "Error: Failed to drop existing ghost or old tables." >&2
      return 1
    }

  while [[ $RETRIES -gt 0 ]]; do
    GHOST_OUTPUT=$(gh-ost \
      --host="$DB_HOST" \
      --port="$DB_PORT" \
      --database="$DB_DATABASE" \
      --user="$DB_USERNAME" \
      --password="$DB_PASSWORD" \
      --table="$TABLE_NAME" \
      --alter="$ALTER_SQL" \
      --execute \
      --switch-to-rbr \
      --allow-on-master \
      --approve-renamed-columns \
      --allow-master-master \
      --initially-drop-ghost-table \
      --initially-drop-old-table \
      2>&1)

    if [[ $? -eq 0 ]]; then
      echo "gh-ost executed successfully for $TABLE_NAME."
      return 0
    fi

    echo "gh-ost failed for $TABLE_NAME. Retrying in $GHOST_RETRY_DELAY seconds..."
    echo "$GHOST_OUTPUT"  # Output gh-ost output on failure
    sleep "$GHOST_RETRY_DELAY"
    RETRIES=$((RETRIES - 1))
  done

  echo "gh-ost failed for $TABLE_NAME after $GHOST_RETRY_COUNT retries." >&2
  echo "$GHOST_OUTPUT"  # Output final gh-ost output on failure
  return 1
}

# Step 1: Run normal migrations first
echo "Running normal migrations (without // gh-ost: comments)"

find database/migrations -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
  migration_name=$(basename "$migration_file" .php)
  echo "Running normal migration: $migration_name"
  php artisan migrate --path="database/migrations/$(basename "$migration_file")" --force --no-interaction || {
    echo "Error: Failed to run normal migration: $migration_name" >&2
    exit 1
  }
done

# Step 2: Process gh-ost migrations from temp folder
echo "Processing gh-ost migrations from temp folder"

while true; do
  remaining_files=$(find "$TEMP_FOLDER" -maxdepth 1 -name "*.php" | wc -l)
  if [[ "$remaining_files" -eq 0 ]]; then
    echo "All gh-ost migrations processed."
    break
  fi

  find "$TEMP_FOLDER" -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    migration_name=$(basename "$migration_file" .php)

    # Check if migration is already applied
    is_migrated=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
      -e "SELECT COUNT(*) FROM migrations WHERE migration = '$migration_name';" | tail -n 1)

    if [[ "$is_migrated" -eq 1 ]]; then
      echo "Migration $migration_name already applied. Running as normal migration for record-keeping."
      php artisan migrate --path="$TEMP_FOLDER/$(basename "$migration_file")" --force --no-interaction || {
        echo "Error: Failed to run normal migration for $migration_name" >&2
        exit 1
      }
    else
      echo "Running gh-ost migration for $migration_name"

      TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file" | head -n 1 | tr -d '\n' | tr -d '\r')
      ALTER_TABLE_STATEMENTS=$(grep -oP "// gh-ost: .+" "$migration_file" | sed 's/.*gh-ost: //' | tr ';' '\n' | tr -d '\r')

      # Process each ALTER TABLE statement
      while IFS= read -r ALTER_TABLE_SQL; do
        if [[ -n "$ALTER_TABLE_SQL" && "$ALTER_TABLE_SQL" == *"ALTER TABLE"* ]]; then
          echo "Executing gh-ost for SQL: $ALTER_TABLE_SQL"
          if ! execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL"; then
            echo "Error: gh-ost failed for SQL: $ALTER_TABLE_SQL" >&2
            exit 1
          fi
        else
          echo "Warning: Skipping invalid or empty SQL: $ALTER_TABLE_SQL"
        fi
      done <<< "$ALTER_TABLE_STATEMENTS"

      # Mark migration as applied
      mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
        -e "INSERT INTO migrations (migration) VALUES ('$migration_name');"
    fi

    # Move processed file back to the main folder
    mv "$migration_file" database/migrations/
  done
done

echo "Migration process complete."
