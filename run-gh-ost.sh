#!/bin/bash

ENVIRONMENT="$1"

# Database connection settings (local or from secrets)
if [[ "$ENVIRONMENT" == "local" ]]; then
    DB_HOST="127.0.0.1"
    DB_PORT="3306"
    DB_USER="root"
    DB_PASSWORD=""
    DB_NAME="laravel_gh_ost" # Replace with your local database name
    GH_OST_BIN="./gh-ost" # Path to gh-ost binary for local
else
    DB_HOST="${DB_HOST}"
    DB_PORT="${DB_PORT}"
    DB_USER="${DB_USER}"
    DB_PASSWORD="${DB_PASSWORD}"
    DB_NAME="${DB_NAME}"
    GH_OST_BIN="gh-ost" # gh-ost in PATH for CI
fi

MIGRATIONS_PATH="database/migrations"

# Check if there are any migration files changed (duplicate check for safety - only for non-local)
if [[ "$ENVIRONMENT" != "local" ]] && [[ -z "$(git diff --name-only HEAD^ HEAD -- database/migrations)" ]]; then
    echo "No migration files changed. Skipping gh-ost process."
    exit 0
fi

find "$MIGRATIONS_PATH" -name "*.php" -print0 | while IFS= read -r -d $'\0' file; do
    echo "Processing migration file: $file"

    # Extract the 'up' method content
    UP_METHOD_CONTENT=$(grep -oP '(?s)(?<=public function up\(\)\n\s*\{\n)(.*?)(?=\n\s*\})' "$file")

    # Extract Schema::table calls
    SCHEMA_TABLE_CALLS=$(echo "$UP_METHOD_CONTENT" | grep -oE 'Schema::table\(.*?\)[\;]' )
    while IFS= read -r schema_table_call; do
        TABLE_NAME=$(echo "$schema_table_call" | sed -E 's/Schema::table\(\'(.*?)\'.*/\2/')
        if [[ -z "$TABLE_NAME" ]]; then
            echo "Could not extract table name from: $schema_table_call"
            continue
        fi
        CLOSURE_CONTENT=$(echo "$schema_table_call" | sed -E 's/Schema::table\(.*?\)\s*\{([^}]*)\}\;/\1/')
        TABLE_OPERATIONS=$(echo "$CLOSURE_CONTENT" | grep -oE '\$table->(.*?)\;' )
        while IFS= read -r table_operation; do
            # Extract gh-ost comment if it exists
            GHOST_COMMENT=$(echo "$table_operation" | grep -oP '// gh-ost:\s*(.*)')

            if [[ -n "$GHOST_COMMENT" ]]; then
                SQL_STATEMENT=$(echo "$GHOST_COMMENT" | sed 's/\/\/ gh-ost:\s*//')
                GENERATED_SQL=$(php artisan tinker --execute="use Illuminate\Support\Facades\Schema; use Illuminate\Database\Schema\Blueprint; \$blueprint = new Blueprint('$TABLE_NAME'); $table_operation; echo \$blueprint->toSql(null, null)[0];" 2>/dev/null)
                if [[ "$SQL_STATEMENT" != "$GENERATED_SQL" ]]; then
                    echo "WARNING: gh-ost comment SQL does not match generated SQL in $file"
                    echo "Comment SQL: $SQL_STATEMENT"
                    echo "Generated SQL: $GENERATED_SQL"
                fi
                echo "Using gh-ost comment: $SQL_STATEMENT"
            else
                SQL_STATEMENT=$(php artisan tinker --execute="use Illuminate\Support\Facades\Schema; use Illuminate\Database\Schema\Blueprint; \$blueprint = new Blueprint('$TABLE_NAME'); $table_operation; echo \$blueprint->toSql(null, null)[0];" 2>/dev/null)
                if [[ -z "$SQL_STATEMENT" ]]; then
                  echo "ERROR: Could not generate SQL for: $table_operation in $file"
                  continue
                fi
                echo "Generated SQL: $SQL_STATEMENT"
            fi

            if [[ -n "$SQL_STATEMENT" ]]; then
                echo "Executing gh-ost for table: $TABLE_NAME with statement: $SQL_STATEMENT"
                $GH_OST_BIN \
                    --host="$DB_HOST" \
                    --port="$DB_PORT" \
                    --user="$DB_USER" \
                    --password="$DB_PASSWORD" \
                    --database="$DB_NAME" \
                    --table="$TABLE_NAME" \
                    --alter="$SQL_STATEMENT" \
                    --execute || { echo "ERROR: gh-ost execution failed for: $SQL_STATEMENT"; exit 1; }
            fi
        done <<< "$TABLE_OPERATIONS"
    done <<< "$SCHEMA_TABLE_CALLS"

    # Handle Schema::create separately (gh-ost doesn't handle creates directly)
    SCHEMA_CREATE_CALLS=$(echo "$UP_METHOD_CONTENT" | grep -oE 'Schema::create\(.*?\)[\;]' )
    while IFS= read -r schema_create_call; do
      echo "Skipping Schema::create statement: $schema_create_call (gh-ost does not handle this)"
    done <<< "$SCHEMA_CREATE_CALLS"
done