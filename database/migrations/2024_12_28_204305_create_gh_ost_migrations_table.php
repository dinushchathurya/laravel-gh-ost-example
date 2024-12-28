<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateGhOstMigrationsTable extends Migration
{
    /**
     * Run the migrations.
     *
     * @return void
     */
    public function up()
    {
        Schema::create('gh_ost_migrations', function (Blueprint $table) {
            $table->string('migration')->primary(); // Store migration file name
            $table->timestamps(); // Optional: Track timestamps for when migrations are applied
        });
    }

    /**
     * Reverse the migrations.
     *
     * @return void
     */
    public function down()
    {
        Schema::dropIfExists('gh_ost_migrations');
    }
}
