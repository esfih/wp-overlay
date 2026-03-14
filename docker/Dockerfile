################################################################################
# WebmasterOS local dev image
# Extends the official WordPress image and adds WP-CLI + useful dev tools.
################################################################################

FROM wordpress:php8.1-apache

# ── Install WP-CLI ────────────────────────────────────────────────────────────
RUN curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# ── Install useful PHP extensions / tools available on shared hosts ───────────
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        less \
        unzip \
        mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# ── Enable mod_rewrite (WordPress permalinks — standard on cPanel/Apache) ─────
RUN a2enmod rewrite

# ── Ensure .htaccess is honored in docroot and add REST fallback for local stacks
# where pretty /wp-json routes can fail while /index.php/wp-json works.
RUN set -eux; \
        printf '%s\n' \
            '<Directory /var/www/html>' \
            '    AllowOverride All' \
            '    Require all granted' \
            '</Directory>' \
            > /etc/apache2/conf-available/wmos-docroot-override.conf; \
        a2enconf wmos-docroot-override; \
        printf '%s\n' \
            'RewriteEngine On' \
        'RewriteRule ^wp-json/?$ /index.php/wp-json/ [L,QSA]' \
        'RewriteRule ^wp-json/(.*)$ /index.php/wp-json/$1 [L,QSA]' \
        'RewriteRule ^/wp-json/?$ /index.php/wp-json/ [L,QSA]' \
        'RewriteRule ^/wp-json/(.*)$ /index.php/wp-json/$1 [L,QSA]' \
            > /etc/apache2/conf-available/wmos-rest-fallback.conf; \
        a2enconf wmos-rest-fallback

# ── Label ─────────────────────────────────────────────────────────────────────
LABEL org.opencontainers.image.title="WebmasterOS Dev WordPress" \
      org.opencontainers.image.description="WordPress + WP-CLI mimicking shared hosting"
