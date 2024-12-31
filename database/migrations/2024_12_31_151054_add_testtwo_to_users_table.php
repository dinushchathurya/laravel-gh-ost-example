<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddTesttwoToUsersTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
     public function up()
    {   
        // gh-ost: ALTER TABLE users ADD COLUMN testtwo VARCHAR(255) NULL AFTER email;
        // gh-ost: ALTER TABLE users DROP COLUMN testtwo; 
        Schema::table('users', function (Blueprint $table) {
            $table->string('testtwo')->nullable()->after('email');
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
            $table->dropColumn('testtwo');
        });
    }
}
