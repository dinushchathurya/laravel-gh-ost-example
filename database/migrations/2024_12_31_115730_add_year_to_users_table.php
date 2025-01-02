<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddYearToUsersTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {   
        // gh-ost: ALTER TABLE users ADD year VARCHAR(255) NULL AFTER email;
        // gh-ost: ALTER TABLE users DROP COLUMN year; 
        Schema::table('users', function (Blueprint $table) {
            $table->string('year')->nullable()->after('email');
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
            $table->dropColumn('year');
        });
    }
}
