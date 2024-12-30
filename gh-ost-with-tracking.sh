#!/bin/bash

# Database credentials
DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE}"
DB_USERNAME="${DB_USERNAME}"
DB_PASSWORD="${DB_PASSWORD}"

# gh-ost related settings
GHOST_RETRY_COUNT="${GHOST_RETRY_COUNT:-3}"
GHOST_RETRY_DELAY="${GHOST_RETRY_DELAY:-5}"

# Ensure environment variables are set
if [[ -z "$DB_HOST" || -z "$DB_DATABASE" || -z "$DB_USERNAME" || -z "$DB_PASSWORD" ]]; then
  echo "Error: Missing database credentials. Please set DB_HOST, DB_DATABASE, DB_USERNAME, and DB_PASSWORD." >&2
  exit 1
fi

# Function to execute gh-ost with retry logic and capture output
execute_gh_ost() {
  local TABLE_NAME="$1"
  local ALTER_SQL="$2"
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

# Step 1: Run normal Laravel migrations first (those without //gh-ost: comment)
echo "Running normal migrations (without //gh-ost:)"

find database/migrations -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
  migration_name=$(basename "$migration_file" .php)

  # If migration doesn't have the //gh-ost: comment, run it as a normal migration
  if ! grep -q "// gh-ost:" "$migration_file"; then
    echo "Running regular Laravel migration: $migration_name"
    php artisan migrate --path="database/migrations/$(basename "$migration_file")" --force --no-interaction || {
      echo "Error: Failed to run regular migration: $migration_name" >&2
      exit 1
    }
  fi
done

# Step 2: Run gh-ost migrations (those with //gh-ost: comment)
echo "Running gh-ost migrations"

find database/migrations -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
  migration_name=$(basename "$migration_file" .php)

  # Check if the migration has the //gh-ost: comment
  if grep -q "// gh-ost:" "$migration_file"; then
    TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file")
    ALTER_TABLE_SQL=$(grep -oP "// gh-ost: .+" "$migration_file" | sed 's/.*gh-ost: //')

    if [[ -n "$TABLE_NAME" && -n "$ALTER_TABLE_SQL" ]]; then
      # Run the gh-ost migration (it hasn't been applied yet)
      if execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL"; then
        # After gh-ost is successful, mark the migration as applied in the migrations table
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" -e "INSERT INTO migrations (migration) VALUES ('$migration_name');" || {
          echo "Error: Failed to insert migration record into database." >&2
          exit 1
        }
      else
        echo "gh-ost execution failed. Rolling back migration."
        php artisan migrate:rollback --path="database/migrations/$(basename "$migration_file")" --force --no-interaction || {
          echo "Error: Failed to rollback migration." >&2
          exit 1
        }
      fi
    fi
  fi
done

echo "Migration process complete."
