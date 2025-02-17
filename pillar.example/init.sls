# Letsencrypt Rate Limitations: You can create a maximum of 500 Registrations per IP Address per 3 hours. Hitting this rate limit is very rare.
# https://letsencrypt.org/docs/rate-limits/
# In short:
# - You can have up to 100 names per certificate
# - You can create a maximum of 500 Registrations per IP Address per 3 hours
# - We also have a Duplicate Certificate limit of 5 certificates per week. A certificate is considered a duplicate of an earlier
#   certificate if they contain the exact same set of hostnames, ignoring capitalization and ordering of hostnames. For instance,
#   if you requested a certificate for the names [www.example.com, example.com], you could request four more certificates for
#   [www.example.com, example.com] during the week. If you changed the set of names by adding [blog.example.com], you would be
#   able to request additional certificates.

# letsencrypt formula pillar data
letsencrypt:

  # Root level key for a "pack" of domains - an abstraction for a collection of domains for this formula
  certificates:


    # Each list item will create /etc/letsencrypt/live/{ list_item['names'][0] }
    # If more than one domain is given in the list of domains, the additional domains will be subject alternative names
    - domains:

        # First domain - will determine that the certfificate is to be placed in /etc/letsencrypt/live/mail.example.org
        - mail.example.org
        # Optional additional domains (Subject Alternative Names)
        - www.example.org
        - test.example.org

      # Set webroot: True if you want to use --webroot { pillar:letsencrypt:webroot_path }, default: False
      # If the certificate is not present, the formula will run a lsof -i :80 to see if a webserver is using the HTTP port
      # If so, it will use --webroot, if no webserver is running it will use --standalone automatically
      webroot: True

      # This shell command will be executed before / after the certificate has been requested or renewed
      pre_hook: echo test pre_hook
      post_hook: echo test post_hook

    - domains:
      - www.example.com
      - example.com
      webroot: True
      post_hook: service apache2 reload

{% if 'ftp' in grains['id'] %}
    - domains:
      # Server only running an ftp service, no webserver
      - ftp.example.com
      # Note that the both the initial request and the cronjob will use --standalone
      webroot: False
      post_hook: service vsftpd restart
{% endif %}


  # This formula checks a port before it determines wether to use --webroot or --standalone
  # (If no webserver is running, we cant use --webroot)
  check_port: 80

  # If webroot is set to True, your webserver has to have a location (i.e. for nginx) like described in the README.md file.
  # There are examples for nginx and apache2 webserver in the contrib directory of this repository.
  # The formula will assure the existance of this path
  webroot_path: /var/www/letsencrypt

  # Each "pack" of domains in the list pillar:letsencrypt:certificates will get a config file /etc/letsencrypt/saltstack/
  # --webroot or --standalone will be used depending on the choices in the "pack", so do not define it here! These settings
  # are used for ALL "packs" defined.
  config:
    email: monitoring@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    renew-by-default: 'True'
    agree-tos: 'True'
    no-self-upgrade: 'True'
    non-interactive: 'True'
