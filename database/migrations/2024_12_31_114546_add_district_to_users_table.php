<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddDistrictToUsersTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {   
        // gh-ost: ALTER TABLE users ADD district VARCHAR(255) NULL AFTER email;
        // gh-ost: ALTER TABLE users DROP COLUMN district; 
        Schema::table('users', function (Blueprint $table) {
            $table->string('district')->nullable()->after('email');
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
            $table->dropColumn('district');
        });
    }
}
