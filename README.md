# Formula: Letsencrypt

This formula:
  - installs Letsencrypt's Certbot as python pip package
  - uses a webservers webroot instead of the temporary webserver (nginx default vhost example included)
  - takes care of initial creation of certificates if they have never been requested before
  - creates a cronjob that renews the certificates every two month
  - adds the ability to execute hook scripts (BASH commands) after renewal


# Usage

First prepare your webserver for letsencrypt. Modify your default vhost like follows:

```
root@example.com ~ # cat /etc/nginx/sites-enabled/default 
server {
    listen 80 default_server;
    server_name _;
 
    root /var/www/letsencrypt;
    index index.html;

    # Redirect everything to our default domain
    location / {
        return 301 https://www.blunix.org$request_uri;
    }

    # Letsencrypts location, refer to:
    # https://www.digitalocean.com/community/tutorials/how-to-secure-nginx-with-let-s-encrypt-on-ubuntu-14-04
    location ~ /.well-known {
        allow all;
    }
}
```

If you feel like nobody should see this, or you dont want to server an error in that location,
you can create `/var/www/letsencrypt/.well-known/index.html` with the following content:

```
<meta http-equiv="refresh" content="0; url=https://www.blunix.org/" />
```

When this is done, just run:

```
salt 'webserver' state.sls letsencrypt
```

It will take care of the magic for you. Dont forget to add hooks in the pillar files if you need any.

Hint: If you have 10 domains on your webserver and you only want to reload nginx once, specify pillars like so:

```
letsencrypt:
  domains:
    - name: example.com
    - name: web.example.com
    - name: mail.example.com
    [...]
    - name: foobar.exmaple.com
      hook: service nginx restart
```

It will then process the domains in order and execute the hook at last.


# Chicken egg problem

Currently, you cant run your nginx formula as the certificates are not present yet.
You can also not run your letsencrypt formula, as there is no nginx to service files with.

=> Create some fancyness in the formula that detects if there is a webserver running like

```
{% set lsof = salt['cmd.run']('lsof -i :80') %}
{% if not lsof %}
letsencrypt_get-certificate_temporary_webserver:
  cmd.run:
    - name: and so on..
```
