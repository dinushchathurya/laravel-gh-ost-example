<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class ChangeProfilePictureToVarcharInUsersTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::table('users', function (Blueprint $table) {
            // gh-ost: ALTER TABLE users CHANGE COLUMN profile_picture profile_picture VARCHAR(255) NULL;
            $table->string('profile_picture', 255)->nullable()->change();
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
            // gh-ost: ALTER TABLE users CHANGE COLUMN profile_picture profile_picture DATE NULL;
            $table->date('profile_picture')->nullable()->change();
        });
    }
}
