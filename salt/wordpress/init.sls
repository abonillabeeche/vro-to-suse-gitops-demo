# WordPress (Apache + PHP + MariaDB) on one VM, as in the classic Aria "WordPress" blueprint.
# Plain Salt: the same file runs from an Aria Automation Config / Salt master (state file "wordpress"),
# from `salt-call --local`, or from a SUSE Multi-Linux Manager configuration (state) channel.
# Secrets are generated on the VM at first run (never stored in Git or pillar) and reused afterwards.
{% from tpldir ~ "/map.jinja" import os_map, wp with context %}
{# WP-CLI extracts the WordPress archive in memory; the 128M CLI default is not enough. #}
{% set wpcli = "php -d memory_limit=512M /usr/local/bin/wp --allow-root --path=" ~ os_map.docroot %}

wordpress-packages:
  pkg.installed:
    - pkgs: {{ os_map.pkgs | json }}

wordpress-db-service:
  service.running:
    - name: {{ os_map.db_service }}
    - enable: True
    - require:
      - pkg: wordpress-packages

wordpress-secrets:
  cmd.run:
    - name: |
        umask 077; mkdir -p /etc/wordpress
        [ -s /etc/wordpress/db.pass ] || openssl rand -hex 16 > /etc/wordpress/db.pass
        [ -s /etc/wordpress/admin.pass ] || openssl rand -hex 12 > /etc/wordpress/admin.pass
    - creates:
      - /etc/wordpress/db.pass
      - /etc/wordpress/admin.pass
    - require:
      - pkg: wordpress-packages

wordpress-database:
  cmd.run:
    - name: |
        mysql -e "CREATE DATABASE IF NOT EXISTS \`{{ wp.db_name }}\`;
                  CREATE USER IF NOT EXISTS '{{ wp.db_user }}'@'localhost' IDENTIFIED BY '$(cat /etc/wordpress/db.pass)';
                  GRANT ALL PRIVILEGES ON \`{{ wp.db_name }}\`.* TO '{{ wp.db_user }}'@'localhost'; FLUSH PRIVILEGES;"
    - unless: mysql -N -e "SELECT 1 FROM mysql.user WHERE user='{{ wp.db_user }}'" | grep -q 1
    - require:
      - service: wordpress-db-service
      - cmd: wordpress-secrets

wp-cli:
  file.managed:
    - name: /usr/local/bin/wp
    - source: https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    - source_hash: https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar.sha512
    - mode: '0755'
    - require:
      - pkg: wordpress-packages

wordpress-core:
  cmd.run:
    - name: mkdir -p {{ os_map.docroot }} && {{ wpcli }} core download
    - creates: {{ os_map.docroot }}/wp-load.php
    - require:
      - file: wp-cli

wordpress-config:
  cmd.run:
    - name: {{ wpcli }} config create --dbname={{ wp.db_name }} --dbuser={{ wp.db_user }} --dbpass="$(cat /etc/wordpress/db.pass)" --dbhost=localhost
    - creates: {{ os_map.docroot }}/wp-config.php
    - require:
      - cmd: wordpress-core
      - cmd: wordpress-database

wordpress-install:
  cmd.run:
    - name: >-
        {{ wpcli }} core install --url="{{ wp.url }}" --title="{{ wp.site_title }}"
        --admin_user="{{ wp.admin_user }}" --admin_password="$(cat /etc/wordpress/admin.pass)"
        --admin_email="{{ wp.admin_email }}" --skip-email
    - unless: {{ wpcli }} core is-installed
    - require:
      - cmd: wordpress-config

# Day-2 settings: kept equal to the values above on every highstate (drift is corrected).
wordpress-site-identity:
  cmd.run:
    - name: >-
        {{ wpcli }} option update blogname "{{ wp.site_title }}" &&
        {{ wpcli }} option update blogdescription "{{ wp.tagline }}"
    - unless: >-
        test "$({{ wpcli }} option get blogname)" = "{{ wp.site_title }}" &&
        test "$({{ wpcli }} option get blogdescription)" = "{{ wp.tagline }}"
    - require:
      - cmd: wordpress-install

wordpress-ownership:
  file.directory:
    - name: {{ os_map.docroot }}
    - user: {{ os_map.web_user }}
    - group: {{ os_map.web_user }}
    - recurse: [user, group]
    - require:
      - cmd: wordpress-install

{% if os_map.php_module %}
wordpress-php-module:
  cmd.run:
    - name: a2enmod {{ os_map.php_module }}
    - unless: a2enmod -q {{ os_map.php_module }}
    - require:
      - pkg: wordpress-packages
    - watch_in:
      - service: wordpress-web-service
{% endif %}

wordpress-vhost:
  file.managed:
    - name: {{ os_map.vhost_dir }}/wordpress.conf
    - contents: |
        # Managed by Salt (state: wordpress)
        <VirtualHost *:80>
            DocumentRoot {{ os_map.docroot }}
            <Directory {{ os_map.docroot }}>
                Options FollowSymLinks
                AllowOverride All
                Require all granted
                DirectoryIndex index.php
            </Directory>
        </VirtualHost>
    - require:
      - pkg: wordpress-packages

wordpress-web-service:
  service.running:
    - name: {{ os_map.web_service }}
    - enable: True
    - watch:
      - file: wordpress-vhost
    - require:
      - file: wordpress-ownership

{% if salt['cmd.which']('firewall-cmd') %}
wordpress-firewall:
  firewalld.present:
    - name: public
    - services: [http]
    - prune_services: False
{% endif %}
