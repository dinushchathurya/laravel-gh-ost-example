### Workflow

```yaml
name: Deploy gh-ost Migrations

on:
  push:
    branches: # Trigger on push to these branches
      - dev
      - staging
      - prod
  pull_request:
    types:
      - closed  # Trigger when a PR is closed
    branches:
      - dev
      - staging
      - prod

jobs:
  deploy:
    runs-on: ubuntu-latest
    if: github.event.pull_request.merged == true  # Only run if the PR is merged, not just closed.

    steps:
      - uses: actions/checkout@v3

      - name: Set up PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.1'
          extensions: pdo, mysql

      - name: Install Composer dependencies
        run: composer install --no-dev --optimize-autoloader

      - name: Create .env file for the target environment
        run: |
          # Define the target environment based on the branch
          case "$GITHUB_REF" in
            "refs/heads/dev")
              ENV_PREFIX="DEV"
            ;;
            "refs/heads/staging")
              ENV_PREFIX="STAGING"
              ;;
            "refs/heads/prod")
              ENV_PREFIX="PROD"
              ;;
            *)
              echo "Unknown branch: $GITHUB_REF"
              exit 1
              ;;
          esac

          # Set the environment variables dynamically
          echo "APP_KEY=base64:$(php artisan key:generate --show)" >> .env
          echo "DB_CONNECTION=mysql" >> .env
          echo "DB_HOST=${{ secrets[ENV_PREFIX + '_DB_HOST'] }}" >> .env
          echo "DB_USERNAME=${{ secrets[ENV_PREFIX + '_DB_USERNAME'] }}" >> .env
          echo "DB_PASSWORD=${{ secrets[ENV_PREFIX + '_DB_PASSWORD'] }}" >> .env
          echo "DB_DATABASE=${{ secrets[ENV_PREFIX + '_DB_DATABASE'] }}" >> .env

      - name: Run gh-ost migrations
        run: bash gh-ost-migrate.sh
        env:
          DB_HOST: ${{ secrets.DB_HOST }}
          DB_PORT: 3306
          DB_DATABASE: ${{ secrets.DB_DATABASE }}
          DB_USERNAME: ${{ secrets.DB_USERNAME }}
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}

```

### Script

```bash
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

execute_gh_ost() {
    TABLE_NAME="$1"
    ALTER_SQL="$2"

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
        return 1
    fi
    return 0
}

find database/migrations/gh-ost -maxdepth 1 -name "*.php" -print0 | while IFS= read -r -d $'\0' migration_file; do
    migration_name=$(basename "$migration_file" .php)

    # Check if the migration has already been applied via gh-ost
    if [[ $(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT * FROM gh_ost_migrations WHERE migration='$migration_name';") ]]; then
        echo "gh-ost Migration $migration_name already applied. Skipping."
        continue
    fi

    echo "Processing $migration_file"

    # Run the migration FIRST to generate the SQL
    php artisan migrate --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction

    # Extract the table name from the migration
    TABLE_NAME=$(grep -oP "(?<=Schema::table\(')[^']+" "$migration_file")
    if [[ -z "$TABLE_NAME" ]]; then
        TABLE_NAME=$(grep -oP "(?<=Schema::create\(')[^']+" "$migration_file")
    fi

    if [[ -z "$TABLE_NAME" ]]; then
        echo "Could not extract table name from $migration_file. Skipping."
        php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
        continue
    fi

    # Extract the ALTER TABLE SQL from the comment in the migration
    ALTER_TABLE_SQL=$(grep -oP "// gh-ost: .+" "$migration_file" | sed 's/.*gh-ost: //')

    echo "Extracted ALTER TABLE SQL: $ALTER_TABLE_SQL"

    if [[ -n "$ALTER_TABLE_SQL" ]]; then
        if execute_gh_ost "$TABLE_NAME" "$ALTER_TABLE_SQL"; then
            # After gh-ost is successful, mark the migration as applied in the gh_ost_migrations table
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "INSERT INTO gh_ost_migrations (migration) VALUES ('$migration_name');"
        else
            echo "gh-ost execution failed. Rolling back migration."
            php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
        fi
    else
        echo "Could not extract SQL from $migration_file. Skipping gh-ost execution."
        php artisan migrate:rollback --path="database/migrations/gh-ost/$(basename "$migration_file")" --force --no-interaction
        continue
    fi
done

echo "gh-ost migrations complete."
```

### Secrets

```yaml

# Secrets for the database connections
DEV_DB_HOST, DEV_DB_USERNAME, DEV_DB_PASSWORD, DEV_DB_DATABASE
STAGING_DB_HOST, STAGING_DB_USERNAME, STAGING_DB_PASSWORD, STAGING_DB_DATABASE
PROD_DB_HOST, PROD_DB_USERNAME, PROD_DB_PASSWORD, PROD_DB_DATABASE
```


public function up()
    {
        // gh-ost: ALTER TABLE users ADD city VARCHAR(255) NULL 
        Schema::table('users', function (Blueprint $table) {
            $table->string('city')->nullable();
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {   
        // gh-ost: ALTER TABLE users DROP COLUMN city
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('city');
        });
    }