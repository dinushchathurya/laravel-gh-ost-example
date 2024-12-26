FROM debian:buster

# Install essential packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    build-essential \
    git \
    libzip-dev \
    zip \
    libpq-dev \
    mysql-client # Add mysql-client

# Install PHP and extensions (separate base and additional packages)
RUN apt-get update && apt-get install -y --no-install-recommends \
    php8.1 \  # Base PHP installation
    php8.1-cli \  # Additional packages (CLI tools)
    php8.1-fpm \  # Web server process manager (if applicable)
    php8.1-mysql \  # MySQL database driver
    php8.1-pgsql \  # PostgreSQL database driver (if needed)
    php8.1-zip \   # ZIP archive support
    php8.1-bcmath \  # Arbitrary precision math library
    php8.1-mbstring \  # Multi-byte string functions
    php8.1-xml \   # XML processing extension

# Download and install gh-ost (specific version)
WORKDIR /tmp
RUN wget https://github.com/github/gh-ost/archive/refs/tags/v1.1.7.tar.gz
RUN tar -xzf v1.1.7.tar.gz
WORKDIR /tmp/gh-ost-1.1.7
RUN make
RUN cp gh-ost /usr/local/bin

# Set working directory for the application
WORKDIR /app

# Copy application files
COPY . /app

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Set permissions (if needed)
# RUN chown -R www-data:www-data /app/storage /app/bootstrap/cache

# Expose port (if needed)
# EXPOSE 80

# Set default command
# CMD ["php-fpm8.1", "-F"]