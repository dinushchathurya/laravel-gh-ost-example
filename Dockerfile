FROM debian:buster

# Install essential packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    build-essential \
    git \
    libzip-dev \
    zip \
    libpq-dev \
    mysql-client

# Install PHP and extensions (using a single apt-get command)
RUN apt-get update && apt-get install -y --no-install-recommends \
    php8.1 \
    php8.1-cli \
    php8.1-fpm \
    php8.1-mysql \
    php8.1-pgsql \
    php8.1-zip \
    php8.1-bcmath \
    php8.1-mbstring \
    php8.1-xml \
    php8.1-gd # Often needed for image processing

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

# Copy application files (AFTER setting the working directory)
COPY . /app

# Set permissions (if needed - adjust for your user/group)
# RUN chown -R www-data:www-data /app/storage /app/bootstrap/cache

# Expose port (if needed)
# EXPOSE 80

# Set default command (if needed)
# CMD ["php-fpm8.1", "-F"]