# acmetinywrapper

Bash script I use to ease the steps of using `acme_tiny.py`.

Downloads [my fork of `acme_tiny.py`](https://github.com/allanrbo/acme-tiny), which supports dns-01 for wildcard certificates, if `acme_tiny.py` is not already in the current directory.

Uses openssl to creates account key files, certificate key files, and csr files, as necessary.

Writes crt files to `/tmp` first, checking the return code of `acme_tiny.py`, before copying to `/etc/ssl/certs/`.

Hardcoded to put private keys and csr files in `/etc/ssl/private`, and certificates in `/etc/ssl/certs/`.

Example of Apache config pointing to certs generated at these locations:

```
<VirtualHost _default_:443>
    ServerName yoursite3.com
    ServerAlias *.yoursite3.com
    DocumentRoot /var/www/yoursite3.com/

    SSLEngine on
    SSLProtocol all -SSLv2 -SSLv3
    SSLCertificateFile /etc/ssl/certs/yoursite3.com.crt
    SSLCertificateKeyFile /etc/ssl/private/yoursite3.com.key
</VirtualHost>
```

The signature of the `renewcert` bash function is:

```
renewcert WWW_ROOT CRT_FILE_BASENAME DOMAINS YOUR_MAILTO OPTIONAL_DNS01_SCRIPT
```

The optional `OPTIONAL_DNS01_SCRIPT` param is only needed if you want to generate wildcard `*` certificates. In this case, it needs to point to a script that will add/remove TXT records from your DNS server. See the instructions in [my fork of `acme_tiny.py`](https://github.com/allanrbo/acme-tiny#step-4-get-a-signed-certificate) for the call signature of this script.

Use it like this in your `renewcerts.sh` script that you run in cron monthly or so:

```
#!/bin/bash

source acmetinywrapper.sh

renewcert /var/www/yoursite1.com yoursite1.com yoursite1.com,www.yoursite1.com mailto:you@example.com
renewcert /var/www/yoursite2.com yoursite2.com yoursite2.com,www.yoursite2.com mailto:you@example.com
renewcert /var/www/yoursite3.com yoursite3.com *.yoursite3.com,yoursite3.com mailto:you@example.com /etc/ssl/private/dns01script.sh

/etc/init.d/apache2 reload
/etc/init.d/postfix reload
/etc/init.d/dovecot reload
```
