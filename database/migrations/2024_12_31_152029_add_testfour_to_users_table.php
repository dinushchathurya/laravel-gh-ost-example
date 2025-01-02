<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddTestfourToUsersTable extends Migration
{
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
}
