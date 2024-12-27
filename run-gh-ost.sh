#!/bin/bash

MIGRATIONS_DIR="./database/migrations"
DB_HOST="127.0.0.1"
DB_USER="root"
DB_PASSWORD=""
DB_NAME="laravel_gh_ost"

# Loop through migration files and detect `// gh-ost:`
for file in $MIGRATIONS_DIR/*.php; do
  if grep -q "// gh-ost:" "$file"; then
    echo "Detected gh-ost migration: $file"
    
    # Extract table name and alter statement (you can customize this part)
    TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$file")
    ALTER_STATEMENT="ADD INDEX your_index_name (column_name)" # Customize based on your schema

    # Run gh-ost
    gh-ost --host="$DB_HOST" \
           --user="$DB_USER" \
           --password="$DB_PASSWORD" \
           --database="$DB_NAME" \
           --table="$TABLE_NAME" \
           --alter="$ALTER_STATEMENT" \
           --allow-on-master \
           --execute
  fi
done
