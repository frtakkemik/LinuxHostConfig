{% set kartaca_password = salt['pillar.get']('kartaca:password', 'kartaca2023') %}
{% set mysql_db_user = salt.pillar.get('mysql:db_user') %}
{% set mysql_db_password = salt.pillar.get('mysql:db_password') %}
{% set mysql_db_name = salt.pillar.get('mysql:db_name') %}
{% set mysql_root_password = salt.pillar.get('mysql:root_password') %}

create-kartaca-user:
  user.present:
    - name: kartaca
    - uid: 2023
    - gid: 2023
    - home: /home/krt
    - shell: /bin/bash
    - password: {{ kartaca_password }}

configure-sudo:
  file.append:
    - name: /etc/sudoers
    - text: 'kartaca ALL=(ALL) NOPASSWD: ALL'

set-timezone:
  timezone.system:
    - name: Europe/Istanbul

enable-ip-forwarding:
  sysctl.present:
    - name: net.ipv4.ip_forward
    - value: 1

install-required-packages:
  pkg.installed:
    - names:
      - htop
      - tcptraceroute
      - iputils
      - dnsutils
      - sysstat
      - mtr
      - curl

add-hashicorp-repo:
  cmd.run:
    - name: "curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg"
    - unless: "test -f /usr/share/keyrings/hashicorp-archive-keyring.gpg"
  pkgrepo.managed:
    - name: "hashicorp"
    - file: /etc/apt/sources.list.d/hashicorp.list
    - key_url: "https://apt.releases.hashicorp.com/gpg"
    - clean_file: True

install-terraform:
  pkg.installed:
    - name: terraform
    - version: 1.6.4

configure-host-entries:
  file.blockreplace:
    - name: /etc/hosts
    - marker_start: 
    - marker_end: 
    - content: |
        {% for i in range(128, 144) %}
        192.168.168.{{ i }}/kartaca.local
        {% endfor %}

install_mysql:
  {% if grains['os_family'] == 'RedHat' %}
  pkg.installed:
    - name: mariadb-server
  {% elif grains['os_family'] == 'Debian' %}
  pkg.installed:
    - name: mysql-server
  {% endif %}

mysql_autostart:
  service.running:
    - name: mysql
    - enable: True
    
create_mysql_db_and_user:
  cmd.run:
    - name: |
        mysql -u root -e "CREATE DATABASE {{ mysql_db_name }};"
        mysql -u root -e "CREATE USER '{{ mysql_db_user }}'@'localhost' IDENTIFIED BY '{{ mysql_db_password }}';"
        mysql -u root -e "GRANT ALL PRIVILEGES ON {{ mysql_db_name }}.* TO '{{ mysql_db_user }}'@'localhost';"
        mysql -u root -e "FLUSH PRIVILEGES;"

mysql_backup_cron:
  cron.present:
    - name: "mysql_backup"
    - user: root
    - hour: 2
    - minute: 0
    - job: "/usr/bin/mysqldump -u root -p{{ mysql_root_password }} {{ mysql_db_name }} > /backup/mysql_backup.sql
    
install_nginx:
  pkg.installed:
    - name: nginx

nginx_autostart:
  service.running:
    - name: nginx
    - enable: True

install_php_and_dependencies:
  pkg.installed:
    - names:
      - php
      - php-fpm
      - php-mysql
      - php-cli
      - php-mbstring
      - php-json
      - php-common
      - php-gd

download_and_extract_wordpress:
  cmd.run:
    - name: |
        wget https://wordpress.org/latest.tar.gz -O /tmp/wordpress.tar.gz
        tar -zxvf /tmp/wordpress.tar.gz -C /var/www/
        mv /var/www/wordpress /var/www/wordpress2023
    - unless: test -e /var/www/wordpress2023/wp-config.php

update_nginx_conf:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://files/nginx.conf
    - template: jinja
    - require:
      - cmd: download_and_extract_wordpress

create_wp_config:
  cmd.run:
    - name: |
        cp /var/www/wordpress2023/wp-config-sample.php /var/www/wordpress2023/wp-config.php
        sed -i "s/database_name_here/{{ mysql_db_name }}/g" /var/www/wordpress2023/wp-config.php
        sed -i "s/username_here/{{ mysql_db_user }}/g" /var/www/wordpress2023/wp-config.php
        sed -i "s/password_here/{{ mysql_db_password }}/g" /var/www/wordpress2023/wp-config.php
        curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> /var/www/wordpress2023/wp-config.php
    - require:
      - cmd: create_mysql_db_and_user
      
create_ssl_certificate:
  cmd.run:
    - name: |
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx-selfsigned.key -out /etc/nginx/ssl/nginx-selfsigned.crt -subj "/C=US/ST=California/L=San Francisco/O=My Organization/OU=My Unit/CN=mydomain.com"
        cat /etc/nginx/ssl/nginx-selfsigned.crt /etc/nginx/ssl/nginx-selfsigned.key > /etc/nginx/ssl/nginx-selfsigned.pem
    - require:
      - pkg: install_nginx
     
manage_nginx_with_salt:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://files/nginx.conf
    - template: jinja
    - require:
      - cmd: download_and_extract_wordpress

reload_nginx_on_config_change:
  cmd.run:
    - name: service nginx reload
    - watch:
      - file: update_nginx_conf

nginx_restart_cron:
  cron.present:
    - name: "nginx_restart"
    - user: root
    - month: 1
    - job: "/usr/sbin/service nginx restart"

rotate_nginx_logs:
  file.managed:
    - name: /etc/logrotate.d/nginx
    - source: salt://files/nginx_logrotate
    - template: jinja
