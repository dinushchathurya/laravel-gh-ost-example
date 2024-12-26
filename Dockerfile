FROM php:8.1-cli

# Install essential packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    build-essential \
    git \
    libzip-dev \
    zip \
    libpq-dev \
    default-mysql-client

# Install additional PHP extensions (if needed)
RUN docker-php-ext-install pdo pdo_mysql pgsql zip bcmath mbstring xml

# Download and install gh-ost (specific version)
WORKDIR /tmp
RUN wget https://github.com/github/gh-ost/archive/refs/tags/v1.1.7.tar.gz
RUN tar -xzf v1.1.7.tar.gz
WORKDIR /tmp/gh-ost-1.1.7
RUN make
RUN cp gh-ost /usr/local/bin

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Set working directory for the application
WORKDIR /app

# Copy application files
COPY . /app

# Set permissions (if needed)
# RUN chown -R www-data:www-data /app/storage /app/bootstrap/cache

# Expose port (if needed)
# EXPOSE 80

# Set default command (if needed)
# CMD ["php-fpm", "-F"]