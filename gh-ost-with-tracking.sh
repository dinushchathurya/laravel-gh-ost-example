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

# Move only unapplied gh-ost migrations to temp folder
echo "Identifying unapplied gh-ost migrations for processing"
find database/migrations -maxdepth 1 -name "*.php" | while read -r migration_file; do
  migration_name=$(basename "$migration_file" .php)

  # Check if migration is already applied
  is_migrated=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "SELECT COUNT(*) FROM migrations WHERE migration = '$migration_name';" | tail -n 1)

  if grep -q "// gh-ost:" "$migration_file" && [[ "$is_migrated" -eq 0 ]]; then
    echo "Moving unapplied migration $migration_name to temp folder for gh-ost processing."
    mv "$migration_file" "$TEMP_FOLDER/"
  fi
done

# Function to get the next batch value
get_next_batch() {
  local CURRENT_BATCH
  CURRENT_BATCH=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "SELECT MAX(batch) FROM migrations;" | tail -n 1)

  if [[ -z "$CURRENT_BATCH" || "$CURRENT_BATCH" == "NULL" ]]; then
    echo 1
  else
    echo $((CURRENT_BATCH + 1))
  fi
}

# Function to execute gh-ost with retry logic
execute_gh_ost() {
  local TABLE_NAME="$1"
  local ALTER_SQL="$2"
  local FAILURE_SQL="$3"
  local RETRIES="$GHOST_RETRY_COUNT"

  echo "Executing gh-ost for table: $TABLE_NAME"
  echo "SQL: $ALTER_SQL"

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
    echo "$GHOST_OUTPUT"
    sleep "$GHOST_RETRY_DELAY"
    RETRIES=$((RETRIES - 1))
  done

  echo "gh-ost failed for $TABLE_NAME after $GHOST_RETRY_COUNT retries. Executing failure SQL."
  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "$FAILURE_SQL" || {
      echo "Error: Failed to execute failure SQL: $FAILURE_SQL" >&2
      exit 1
    }

  return 1
}

# Step 1: Run normal migrations (including those with gh-ost already applied)
echo "Running normal migrations"
find database/migrations -maxdepth 1 -name "*.php" | while read -r migration_file; do
  migration_name=$(basename "$migration_file" .php)
  echo "Running normal migration: $migration_name"
  php artisan migrate --path="database/migrations/$(basename "$migration_file")" --force --no-interaction || {
    echo "Error: Failed to run normal migration: $migration_name" >&2
    exit 1
  }
done

# Step 2: Process unapplied gh-ost migrations
echo "Processing unapplied gh-ost migrations from temp folder"
find "$TEMP_FOLDER" -maxdepth 1 -name "*.php" | while read -r migration_file; do
  migration_name=$(basename "$migration_file" .php)

  echo "Running gh-ost migration for $migration_name"

  TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file" | head -n 1 | tr -d '\n' | tr -d '\r')
  ALTER_TABLE_STATEMENTS=$(grep -oP "// gh-ost: .+" "$migration_file" | sed 's/.*gh-ost: //' | tr ';' '\n' | tr -d '\r')

  # Process each ALTER TABLE statement
  while IFS= read -r ALTER_TABLE_SQL; do
    if [[ -n "$ALTER_TABLE_SQL" && "$ALTER_TABLE_SQL" == *"ALTER TABLE"* ]]; then
      # Define rollback SQL in case of failure
      ROLLBACK_SQL="ALTER TABLE $TABLE_NAME DROP COLUMN country"

      echo "Executing gh-ost for SQL: $ALTER_TABLE_SQL"
      if ! execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL" "$ROLLBACK_SQL"; then
        echo "Error: gh-ost failed for SQL: $ALTER_TABLE_SQL. Rolling back migration." >&2
        exit 1
      fi
    else
      echo "Warning: Skipping invalid or empty SQL: $ALTER_TABLE_SQL"
    fi
  done <<< "$ALTER_TABLE_STATEMENTS"

  # Determine the next batch value
  BATCH=$(get_next_batch)
  echo "Inserting migration record with batch $BATCH for $migration_name"

  # Mark migration as applied
  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "INSERT INTO migrations (migration, batch) VALUES ('$migration_name', $BATCH);" || {
    echo "Error: Failed to insert migration record for $migration_name" >&2
    exit 1
  }

  # Move processed file back to the main folder
  mv "$migration_file" database/migrations/
done

echo "Migration process complete."
