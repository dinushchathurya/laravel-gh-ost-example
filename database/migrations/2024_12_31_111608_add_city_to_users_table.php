<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddCityToUsersTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {   
        // gh-ost: ALTER TABLE users ADD city VARCHAR(255) NULL AFTER email;
        // gh-ost: ALTER TABLE users DROP COLUMN city; 
        Schema::table('users', function (Blueprint $table) {
            $table->string('city')->nullable()->after('email');
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {   
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('city');
        });
    }
}
