kartaca:
  password: "{{ salt['pillar.get']('kartaca:password', 'kartaca2023') }}"
mysql:
  db_user: wordpressuser
  db_password: wordpresspassword
  db_name: wordpressdb
  root_password: rootpassword

