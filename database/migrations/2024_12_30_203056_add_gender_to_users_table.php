<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddGenderToUsersTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        // gh-ost: ALTER TABLE users ADD gender VARCHAR(255) NULL 
        Schema::table('users', function (Blueprint $table) {
            $table->string('gender')->nullable();
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {   
        // gh-ost: ALTER TABLE users drop COLUMN gender
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('gender');
        });
    }
}