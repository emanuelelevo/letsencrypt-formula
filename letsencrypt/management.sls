{%- from "letsencrypt/map.jinja" import letsencrypt with context %}

include:
  - letsencrypt.packages

# Create custom configs in directory just for saltstack
letsencrypt_management_config_saltstack-directory:
  file.directory:
    - name: /etc/letsencrypt/saltstack/changes
    - user: root
    - group: {{ letsencrypt.group }}
    - mode: 750
    - makedirs: True


{% if letsencrypt['webroot_path'] is defined %}

# Create the webroot for the webserver to use
letsencrypt_management_webroot-directory_{{ letsencrypt['webroot_path'] }}/.well-known:
  file.directory:
    - name: {{ letsencrypt['webroot_path'] }}/.well-known
    - user: root
    - group: {{ letsencrypt.group }}
    - mode: 755
    - makedirs: True

{% endif %}


# Iterate over the "packs" with domains to request certificates for
{% for pack in letsencrypt['certificates'] %}

# Create a custom config file with the list of all domains and SANs plus some default options for certbot
letsencrypt_management_config_/etc/letsencrypt/saltstack/{{ pack['domains'][0] }}.conf:
  file.managed:
    - name: /etc/letsencrypt/saltstack/{{ pack['domains'][0] }}.conf
    - user: root
    - group: {{ letsencrypt.group }}
    - mode: 400
    - contents: |
        # This file is managed by Saltstack, DO NOT EDIT IT!
        domains = {{ pack['domains'] | join(', ') }}
        {%- for conf_key in letsencrypt['config'] %}
        {{ conf_key }} = {{ letsencrypt['config'][conf_key] }}
        {%- endfor -%}

{# Create a list of all domains in a file, so we can watch if the domains were updated compared to the previous run #}
letsencrypt_management_change-file_/etc/letsencrypt/saltstack/changes/{{ pack['domains'][0] }}:
  file.managed:
    - name: /etc/letsencrypt/saltstack/changes/{{ pack['domains'][0] }}
    - user: root
    - group: {{ letsencrypt.group }}
    - mode: 400
    - contents: |
        # This file is managed by Saltstack, DO NOT EDIT IT!
        {%- for domain in pack['domains'] %}
        {{ domain }}
        {%- endfor -%}


{#
# Check if there are already certs for this domain - if not, start initial creation
# There is no comfortable way in salt to check for multiple files as requirement for a cmd.run statement
# Also we dont want to renew all domains when we add one additional domain (as we can only request a specific
# domain for five times within a week or so
#}

{# Solve the chicken - egg problem: if there is nothing running on port 80, using webroot can not work
# lsof -i :{ letsencrypt['check_port'] } will return exit status 0 if sth is listening and != zero if not
#}
{% if salt['grains.get']('os_family') == 'FreeBSD' %}
{% set check_port_status = salt['cmd.retcode']('sockstat -l4 -p ' + letsencrypt['check_port']|string + ' | grep -q ' + letsencrypt['check_port']|string, python_shell=True) %}
{% elif salt['grains.get']('os_family') == 'Debian' %}
{% set check_port_status = salt['cmd.retcode']('lsof -i :' + letsencrypt['check_port']|string) %}
{% endif %}

{# Is the certificate already present? #}
{% set check_file_state = salt['cmd.retcode']('test -L /etc/letsencrypt/live/' + pack['domains'][0] + '/privkey.pem') %}

{% if check_file_state == '0' %}
    {% set req_action = 'wait' %}
{% else %}
    {% set req_action = 'run' %}
{% endif %}


letsencrypt_management_request-or-renew_{{ pack['domains'][0] }}:
  cmd.{{ req_action }}:
    - user: root
    - group: {{ letsencrypt.group }}
    - shell: /bin/sh

    # Check the exit status of check_port_status if its not 0, there is no service listening on {{ letsencrypt['check_port'] }}
    # If the port is not used, we can always just use standalone to initial request / refresh on updates of domains.
    # If the port is in use, we can either use --webroot or standalone + hooks (To stop / start service)
    # If anything goes wrong, update the list of domains file so this state would run again on the next salt run.
    - name: |
        exec 2>&1
        set -x
        set -e

        {%- set webroot = pack.get('webroot', False) -%}
        {%- set pre_hook = pack.get('pre_hook', 'echo no pre_hook defined') -%}
        {%- set post_hook = pack.get('post_hook', 'echo no post_hook defined') -%}

        {%- if check_port_status == 0 and webroot == True %}
        # Something runs on port {{ letsencrypt['check_port'] }} and webroot=True, use --webroot plugin
        # Just place files in webroot and server should take care of it, no need for hooks
        date | tee -a /var/log/letsencrypt.log && \
        /opt/letsencrypt/bin/letsencrypt certonly --webroot -w {{ letsencrypt['webroot_path'] }} -c /etc/letsencrypt/saltstack/{{ pack['domains'][0] }}.conf | tee -a /var/log/letsencrypt.log || {
            echo '# previous request unsuccessful' | tee -a /etc/letsencrypt/saltstack/changes/{{ pack['domains'][0] }} && exit 1
        };

        {%- elif check_port_status == 0 and webroot == False %}
        # Something runs on port {{ letsencrypt['check_port'] }} and webroot=False, use --standalone plugin with hooks
        {{ pre_hook }} | tee -a /var/log/letsencrypt.log && \
        /opt/letsencrypt/bin/letsencrypt certonly --standalone -c /etc/letsencrypt/saltstack/{{ pack['domains'][0] }}.conf | tee -a /var/log/letsencrypt.log || {
            echo '# previous request unsuccessful' | tee -a /etc/letsencrypt/saltstack/changes/{{ pack['domains'][0] }} && exit 1
        };
        {{ post_hook }};

        {%- else %}
        # Nothing runs on port {{ letsencrypt['check_port'] }} use --standalone plugin
        /opt/letsencrypt/bin/letsencrypt certonly --standalone -c /etc/letsencrypt/saltstack/{{ pack['domains'][0] }}.conf | tee -a /var/log/letsencrypt.log || {
            echo '# previous request unsuccessful' | tee -a /etc/letsencrypt/saltstack/changes/{{ pack['domains'][0] }} && exit 1
        };

        {% endif %}

    # We want this command to run, if
    #   - The certfificate has never been requested before (/etc/letsencrypt/saltstack/{ pack['domains'][0] } would not exist)
    #   - The SANs are updated (/etc/letsencrypt/saltstack/{ pack['domains'][0] }.conf would be updated too)
    #   - The previous request failed (echo '# previous request unsuccessful' | tee -a .conf would be executed)
    - watch:
      - file: letsencrypt_management_change-file_/etc/letsencrypt/saltstack/changes/{{ pack['domains'][0] }}

    - require:
      - pip: letsencrypt_packages_pip-package


{% endfor %}
