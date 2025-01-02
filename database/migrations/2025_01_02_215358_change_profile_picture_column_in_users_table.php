<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class ChangeProfilePictureColumnInUsersTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        // gh-ost: ALTER TABLE users CHANGE COLUMN profile_picture user_photo DATE NULL;
        Schema::table('users', function (Blueprint $table) {
            $table->renameColumn('profile_picture', 'user_photo');
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        // gh-ost: ALTER TABLE users CHANGE COLUMN user_photo profile_picture DATE NULL;
        Schema::table('users', function (Blueprint $table) {
            $table->renameColumn('user_photo', 'profile_picture');
        });
    }
}
