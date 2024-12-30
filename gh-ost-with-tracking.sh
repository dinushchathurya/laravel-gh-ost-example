#!/bin/bash

# Database credentials (ensure these are set in your .env file)
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

# Step 1: Move gh-ost migrations to a temporary folder
echo "Moving gh-ost migrations to temporary folder..."
mkdir -p database/migrations/gh-ost
find database/migrations -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    if grep -q "// gh-ost:" "$migration_file"; then
        mv "$migration_file" database/migrations/gh-ost/
        echo "Moved $migration_file to gh-ost folder."
    fi
done

# Step 2: Run regular Laravel migrations (without gh-ost migrations)
echo "Running regular Laravel migrations (excluding gh-ost migrations)..."
php artisan migrate --force --no-interaction

# Step 3: Move gh-ost migrations back to the main migrations folder
echo "Moving gh-ost migrations back to the main migrations folder..."
find database/migrations/gh-ost -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    mv "$migration_file" database/migrations/
    echo "Moved $migration_file back to migrations folder."
done

# Step 4: Run gh-ost migrations (only if they haven't been applied yet)
echo "Running gh-ost migrations (if not applied already)..."

find database/migrations -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    ALTER_SQL=$(grep -oP "// gh-ost: .+" "$migration_file" | sed 's/.*gh-ost: //')

    if [[ -n "$ALTER_SQL" ]]; then
        MIGRATION_NAME=$(basename "$migration_file" .php)

        # Check if this migration has already been applied
        MIGRATION_APPLIED=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT COUNT(1) FROM migrations WHERE migration='$MIGRATION_NAME';" "$DB_DATABASE" | grep -q "1" && echo "yes" || echo "no")

        if [[ "$MIGRATION_APPLIED" == "yes" ]]; then
            echo "Migration $MIGRATION_NAME already applied. Skipping gh-ost migration."
            continue
        fi

        # Extract table name from the ALTER SQL (simplified)
        TABLE_NAME=$(echo "$ALTER_SQL" | sed -n 's/ALTER TABLE \([a-zA-Z0-9_]*\) .*/\1/p')

        if [[ -z "$TABLE_NAME" ]]; then
            echo "Error: Unable to extract table name from ALTER SQL in $migration_file. Skipping."
            continue
        fi

        # Run the gh-ost migration
        echo "Running gh-ost migration for table: $TABLE_NAME"
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
            --verbose)

        # Check if the gh-ost command was successful
        if [[ $? -ne 0 ]]; then
            echo "gh-ost migration failed for $TABLE_NAME. Exiting."
            echo "$GHOST_OUTPUT"
            exit 1
        fi

        # Mark the migration as applied by Laravel
        echo "Marking migration $MIGRATION_NAME as applied."
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "INSERT INTO migrations (migration) VALUES ('$MIGRATION_NAME');" "$DB_DATABASE"
    fi
done

echo "gh-ost migration process complete."
