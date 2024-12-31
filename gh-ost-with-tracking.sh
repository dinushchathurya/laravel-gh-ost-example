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

# Function to run normal migrations
run_normal_migrations() {
  echo "Running normal migrations"
  find database/migrations -maxdepth 1 -name "*.php" | while read -r migration_file; do
    migration_name=$(basename "$migration_file" .php)

    # Check if the migration is already applied
    is_migrated=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
      -e "SELECT COUNT(*) FROM migrations WHERE migration = '$migration_name';" | tail -n 1)

    if [[ "$is_migrated" -eq 0 ]]; then
      echo "Running normal migration: $migration_name"
      php artisan migrate --path="database/migrations/$(basename "$migration_file")" --force --no-interaction || {
        echo "Error: Failed to run normal migration: $migration_name" >&2
        exit 1
      }
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

  echo "gh-ost failed for $TABLE_NAME after $GHOST_RETRY_COUNT retries. Executing rollback."
  mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "$ROLLBACK_SQL" || {
      echo "Error: Failed to execute rollback SQL: $ROLLBACK_SQL" >&2
      exit 1
    }

  return 1
}

# Step 1: Run normal migrations
run_normal_migrations

# Step 2: Process gh-ost migrations
echo "Processing unapplied gh-ost migrations"
find database/migrations -maxdepth 1 -name "*.php" | while read -r migration_file; do
  migration_name=$(basename "$migration_file" .php)

  # Check if migration has // gh-ost: comment and is not yet applied
  is_migrated=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
    -e "SELECT COUNT(*) FROM migrations WHERE migration = '$migration_name';" | tail -n 1)

  if grep -q "// gh-ost:" "$migration_file" && [[ "$is_migrated" -eq 0 ]]; then
    echo "Running gh-ost migration: $migration_name"

    TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file" | head -n 1 | tr -d '\n' | tr -d '\r')
    ALTER_SQL=$(grep -oP "// gh-ost: ALTER TABLE .* ADD COLUMN .*" "$migration_file" | sed 's/.*gh-ost: //')
    ROLLBACK_SQL=$(grep -oP "// gh-ost: ALTER TABLE .* DROP COLUMN .*" "$migration_file" | sed 's/.*gh-ost: //')

    if [[ -n "$ALTER_SQL" && "$ALTER_SQL" == *"ALTER TABLE"* ]]; then
      echo "Executing gh-ost for ALTER SQL: $ALTER_SQL"
      if ! execute_gh_ost "$TABLE_NAME" "$ALTER_SQL" "$ROLLBACK_SQL"; then
        echo "Error: gh-ost migration failed. Rollback executed." >&2
        exit 1
      fi

      # Mark migration as applied
      BATCH=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
        -e "SELECT IFNULL(MAX(batch), 0) + 1 AS next_batch FROM migrations;" | tail -n 1)
      mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
        -e "INSERT INTO migrations (migration, batch) VALUES ('$migration_name', $BATCH);" || {
        echo "Error: Failed to insert migration record for $migration_name" >&2
        exit 1
      }
    else
      echo "Warning: Skipping invalid or empty ALTER SQL for migration: $migration_name"
    fi
  fi
done

echo "Migration process complete."
