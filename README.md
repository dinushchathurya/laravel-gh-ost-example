# Laravel Database Migration with gh-ost Integration

This script automates Laravel database migrations with support for **gh-ost**. It validates, executes, and tracks migrations, ensuring smooth schema changes in production environments.

## Features

- Validates `gh-ost` migrations for correctness.
- Runs normal Laravel migrations using `php artisan migrate`.
- Tracks migration status to prevent re-running already applied migrations.
- Handles rollback in case of migration failure.
- Supports extracting and processing `gh-ost` migrations for schema changes.

## Required Scripts

You need to add the following `gh-ost-with-tracking.sh` scripts to your Laravel project's root directory.

## Setup Environment Variables

In GitHub, navigate to your repository and go to `Settings` > `Secrets`. Add the following environment variables:

- `DB_HOST`: Database host (e.g., Database IP address or endpoint URL).
- `DB_PORT`: Database port (e.g., `3306`).
- `DB_DATABASE`: Database name.
- `DB_USERNAME`: Database username.
- `DB_PASSWORD`: Database password.

## Usage

You can create new migration files as usual using `php artisan make:migration`. Then you need to add the raw SQL query to the migration file. The script will extract the SQL query and execute it using `gh-ost` using first time. If the migration is already applied, it will run the normal Laravel migration.

### Example Migration File

Imagine if we need to add a new column callled `testfour` to the `users` table. We can create a new migration file using the following command:

```bash
php artisan make:migration add_testfour_column_to_users_table --table=users
```

Then we can add the raw SQL query to the migration file:

```php
/**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {   
        // gh-ost: ALTER TABLE users ADD COLUMN testfour VARCHAR(255) NULL AFTER email;
        Schema::table('users', function (Blueprint $table) {
            $table->string('testfour')->nullable()->after('email');
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {   
        // gh-ost: ALTER TABLE users DROP COLUMN testfour; 
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('testfour');
        });
    }
```

## To Do List

- Adding New Columns [x] // Implemented and tested
- Change Dta Type of Existing Columns [] 
- Renaming Columns []
- Dropping Columns []
- Adding or Modifying Indexes []






#