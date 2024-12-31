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

# Function to check if a migration is already applied
is_migration_applied() {
  local migration_name="$1"
  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "SELECT COUNT(*) FROM migrations WHERE migration = '$migration_name';" | tail -n 1
}

# Function to insert a migration record into the migrations table
record_migration() {
  local migration_name="$1"
  local BATCH

  # Determine the next batch number
  BATCH=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "SELECT IFNULL(MAX(batch), 0) + 1 AS next_batch FROM migrations;" | tail -n 1)

  # Insert the migration record
  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "INSERT INTO migrations (migration, batch) VALUES ('$migration_name', $BATCH);" || {
    echo "Error: Failed to record migration in migrations table: $migration_name" >&2
    exit 1
  }
  echo "Recorded migration: $migration_name in batch: $BATCH"
}

# Function to run normal migrations
run_normal_migrations() {
  echo "Running normal migrations"
  find database/migrations -maxdepth 1 -name "*.php" | while read -r migration_file; do
    migration_name=$(basename "$migration_file" .php)

    if [[ $(is_migration_applied "$migration_name") -eq 0 ]]; then
      echo "Running normal migration: $migration_name"
      php artisan migrate --path="database/migrations/$(basename "$migration_file")" --force --no-interaction || {
        echo "Error: Failed to run normal migration: $migration_name" >&2
        exit 1
      }
      record_migration "$migration_name"
    else
      echo "Skipping already applied migration: $migration_name"
    fi
  done
}

# Function to execute gh-ost with retry logic and rollback handling
execute_gh_ost() {
  local TABLE_NAME="$1"
  local ALTER_SQL="$2"
  local ROLLBACK_SQL="$3"
  local MIGRATION_NAME="$4"
  local RETRIES="$GHOST_RETRY_COUNT"

  echo "Executing gh-ost for table: $TABLE_NAME with SQL: $ALTER_SQL"

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
      echo "gh-ost migration successful for table: $TABLE_NAME"
      record_migration "$MIGRATION_NAME"
      return 0
    fi

    echo "gh-ost failed for $TABLE_NAME. Retrying in $GHOST_RETRY_DELAY seconds..."
    echo "$GHOST_OUTPUT"
    sleep "$GHOST_RETRY_DELAY"
    RETRIES=$((RETRIES - 1))
  done

  echo "gh-ost failed after $RETRIES retries for $TABLE_NAME. Executing rollback."
  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "$ROLLBACK_SQL" || {
      echo "Error: Failed to execute rollback SQL for $TABLE_NAME: $ROLLBACK_SQL" >&2
      exit 1
    }

  return 1
}

# Step 1: Identify and move unapplied gh-ost migrations to temp folder
echo "Identifying unapplied gh-ost migrations for processing"
find database/migrations -maxdepth 1 -name "*.php" | while read -r migration_file; do
  migration_name=$(basename "$migration_file" .php)

  if grep -q "// gh-ost:" "$migration_file" && [[ $(is_migration_applied "$migration_name") -eq 0 ]]; then
    echo "Moving unapplied gh-ost migration $migration_name to temp folder."
    mv "$migration_file" "$TEMP_FOLDER/"
  fi
done

# Step 2: Run normal migrations (including already applied gh-ost migrations)
run_normal_migrations

# Step 3: Process gh-ost migrations from temp folder
echo "Processing unapplied gh-ost migrations from temp folder"
find "$TEMP_FOLDER" -maxdepth 1 -name "*.php" | while read -r migration_file; do
  migration_name=$(basename "$migration_file" .php)

  echo "Running gh-ost migration for $migration_name"

  TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file" | head -n 1 | tr -d '\n' | tr -d '\r')
  ALTER_SQL=$(grep -oP "// gh-ost: ALTER TABLE .* ADD COLUMN .*" "$migration_file" | sed 's/.*gh-ost: //')
  ROLLBACK_SQL=$(grep -oP "// gh-ost: ALTER TABLE .* DROP COLUMN .*" "$migration_file" | sed 's/.*gh-ost: //')

  if [[ -n "$ALTER_SQL" && "$ALTER_SQL" == *"ALTER TABLE"* ]]; then
    echo "Executing gh-ost for ALTER SQL: $ALTER_SQL"
    if ! execute_gh_ost "$TABLE_NAME" "$ALTER_SQL" "$ROLLBACK_SQL" "$migration_name"; then
      echo "Error: gh-ost migration failed. Rollback executed." >&2
      exit 1
    fi
  else
    echo "Warning: Skipping invalid or empty ALTER SQL for migration: $migration_name"
  fi

  # Move processed file back to the main folder
  mv "$migration_file" database/migrations/
done

echo "Migration process complete."
