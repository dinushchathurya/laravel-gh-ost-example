FROM mysql:8.0

RUN apt-get update && apt-get install -y wget build-essential git

WORKDIR /tmp

RUN wget https://github.com/github/gh-ost/archive/refs/tags/v1.1.7.tar.gz # Pin to a specific version
RUN tar -xzf v1.1.7.tar.gz
WORKDIR /tmp/gh-ost-1.1.7
RUN make

RUN cp gh-ost /usr/local/bin

WORKDIR /app
COPY . /app

# Install system dependencies for php
RUN apt-get update && apt-get install -y \
    libzip-dev \
    zip \
    libpq-dev # For PostgreSQL support

# Install PHP extensions
RUN docker-php-ext-configure zip --with-libzip \
    && docker-php-ext-install pdo pdo_mysql pgsql