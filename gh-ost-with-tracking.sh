#!/bin/bash

# Database credentials
DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT:-3306}"
DB_DATABASE="${DB_DATABASE}"
DB_USERNAME="${DB_USERNAME}"
DB_PASSWORD="${DB_PASSWORD}"

# Temp folder for gh-ost migrations
TEMP_FOLDER="temp_gh_ost_migrations"

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

# Function to record a migration in the migrations table
record_migration() {
  local migration_name="$1"
  local BATCH

  # Check if the migration is already recorded
  if [[ $(is_migration_applied "$migration_name") -ne 0 ]]; then
    echo "Skipping already recorded migration: $migration_name"
    return 0
  fi

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

# Function to extract SQL from migration file
extract_sql() {
  local file="$1"
  local pattern="$2"
  local sql=$(grep -oP "$pattern" "$file" | sed 's/.*gh-ost: //')

  if [[ -z "$sql" ]]; then
    echo "Debug: No SQL extracted for pattern: $pattern in file: $file"
  else
    echo "Debug: Extracted SQL: $sql"
  fi

  echo "$sql"
}

# Function to validate gh-ost migration
validate_gh_ost_migration() {
  local file="$1"
  echo "Validating file: $file"

  local alter_sql=$(extract_sql "$file" "// gh-ost: ALTER TABLE .* ADD COLUMN .*")
  local rollback_sql=$(extract_sql "$file" "// gh-ost: ALTER TABLE .* DROP COLUMN .*")

  echo "  Debug: Extracted ADD COLUMN SQL: $alter_sql"
  echo "  Debug: Extracted DROP COLUMN SQL: $rollback_sql"

  if [[ -z "$alter_sql" ]]; then
    echo "Error: Missing or invalid ADD COLUMN SQL in migration file: $file" >&2
    return 1
  fi

  if [[ -z "$rollback_sql" ]]; then
    echo "Error: Missing or invalid DROP COLUMN SQL in migration file: $file" >&2
    return 1
  fi

  echo "Validation passed for migration file: $file"
  return 0
}

# Function to execute gh-ost
execute_gh_ost() {
  local table_name="$1"
  local alter_sql="$2"
  local rollback_sql="$3"
  local migration_name="$4"

  echo "Executing gh-ost for table: $table_name with SQL: $alter_sql"

  GHOST_OUTPUT=$(gh-ost \
    --host="$DB_HOST" \
    --port="$DB_PORT" \
    --database="$DB_DATABASE" \
    --user="$DB_USERNAME" \
    --password="$DB_PASSWORD" \
    --table="$table_name" \
    --alter="$alter_sql" \
    --execute \
    --switch-to-rbr \
    --allow-on-master \
    --approve-renamed-columns \
    --allow-master-master 2>&1)

  if [[ $? -eq 0 ]]; then
    echo "gh-ost executed successfully for table: $table_name"
    record_migration "$migration_name"
    return 0
  else
    echo "Error: gh-ost failed for $table_name with error: $GHOST_OUTPUT"
    echo "Rolling back using SQL: $rollback_sql"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" \
      -e "$rollback_sql" || {
        echo "Error: Failed to execute rollback SQL for $table_name: $rollback_sql" >&2
        exit 1
      }
    return 1
  fi
}

# Step 1: Identify and move unapplied gh-ost migrations to temp folder
echo "Identifying unapplied gh-ost migrations for processing"
find database/migrations -maxdepth 1 -name "*.php" | while read -r migration_file; do
  migration_name=$(basename "$migration_file" .php)

  if grep -q "// gh-ost:" "$migration_file" && [[ $(is_migration_applied "$migration_name") -eq 0 ]]; then
    echo "Validating migration file: $migration_file"
    if validate_gh_ost_migration "$migration_file"; then
      echo "Moving unapplied gh-ost migration $migration_name to temp folder."
      mv "$migration_file" "$TEMP_FOLDER/"
    else
      echo "Skipping invalid gh-ost migration: $migration_name"
    fi
  fi
done

# Step 2: Run normal migrations (including already applied gh-ost migrations)
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

# Step 3: Process gh-ost migrations from temp folder
echo "Processing unapplied gh-ost migrations from temp folder"
find "$TEMP_FOLDER" -maxdepth 1 -name "*.php" | while read -r migration_file; do
  migration_name=$(basename "$migration_file" .php)

  echo "Processing migration: $migration_name"

  table_name=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file" | head -n 1 | tr -d '\n' | tr -d '\r')
  alter_sql=$(extract_sql "$migration_file" "// gh-ost: ALTER TABLE .* ADD COLUMN .*")
  rollback_sql=$(extract_sql "$migration_file" "// gh-ost: ALTER TABLE .* DROP COLUMN .*")

  execute_gh_ost "$table_name" "$alter_sql" "$rollback_sql" "$migration_name"

  # Move processed file back to the main folder
  mv "$migration_file" database/migrations/
done

echo "Migration process complete."
