#!/bin/bash

function renewcert() {
    if [ "$#" -ne 4 ] && [ "$#" -ne 5 ]; then
        echo "wrong arg count"
        return 1
    fi

    wwwroot=$1
    certfilebasename=$2
    domains=$3
    contact=$4
    dnschallangescript=$5

    # Download acme_tiny.py or abort
    if [ ! -f /etc/ssl/private/acme_tiny.py ]; then
        #wget -q -O /tmp/acme_tiny.py https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py
        # allanrbo's version supports dns-01 challange
        wget -q -O /tmp/acme_tiny.py https://raw.githubusercontent.com/allanrbo/acme-tiny/master/acme_tiny.py
        if [ $? -ne 0 ]; then
            echo "failed to download acme_tiny.py"
            return 1
        fi
        mv /tmp/acme_tiny.py /etc/ssl/private/acme_tiny.py
        chmod +x /etc/ssl/private/acme_tiny.py
        echo "downloaded acme_tiny.py to /etc/ssl/private/acme_tiny.py"
    fi

    # Create a Let's Encrypt account key if not already created
    if [ ! -f /etc/ssl/private/letsencryptaccount.key ]; then
        openssl genrsa 4096 > /etc/ssl/private/letsencryptaccount.key
        if [ $? -ne 0 ]; then
            echo "failed to generate letsencryptaccount.key"
            return 1
        fi
        echo "created /etc/ssl/private/letsencryptaccount.key"
    fi

    # Create a private key for this cert if not already created
    if [ ! -f /etc/ssl/private/$certfilebasename.key ]; then
        openssl genrsa -out /etc/ssl/private/$certfilebasename.key 4096
        if [ $? -ne 0 ]; then
            echo "failed to generate $certfilebasename.key"
            return 1
        fi
        echo "created /etc/ssl/private/$certfilebasename.key"
    fi

    # Create a certificate request file (a .csr file)
    IFS=', ' read -r -a domainsArray <<< "$domains"
    maindomain="${domainsArray[0]}"
    echo maindomain is $maindomain
    if [[ "${#domainsArray[@]}" == "1" ]]; then
        # Create a simple certificate request for just a single domain
        openssl req -new -key /etc/ssl/private/$certfilebasename.key -subj "/CN=$maindomain" -out /etc/ssl/private/$certfilebasename.csr 2> /tmp/opensslstderr.txt
        if [ $? -ne 0 ]; then
            >&2 cat /tmp/opensslstderr.txt
            echo "failed to generate $certfilebasename.csr"
            rm /tmp/opensslstderr.txt
            return 1
        fi
        rm /tmp/opensslstderr.txt
    else
        # Create a special certificate request for multiple domains
        cat /etc/ssl/openssl.cnf > /tmp/csrconfig
        echo "[SAN]" >> /tmp/csrconfig
        subjectAltNameLine="subjectAltName=DNS:$maindomain"
        for domain in "${domainsArray[@]:1}"; do
            subjectAltNameLine="$subjectAltNameLine,DNS:$domain"
        done
        echo $subjectAltNameLine >> /tmp/csrconfig

        openssl req -new -sha256 -key /etc/ssl/private/$certfilebasename.key -subj "/CN=$maindomain" -reqexts SAN -config /tmp/csrconfig -out /etc/ssl/private/$certfilebasename.csr 2> /tmp/opensslstderr.txt
        if [ $? -ne 0 ]; then
            >&2 cat /tmp/opensslstderr.txt
            echo "failed to generate $certfilebasename.csr"
            rm /tmp/opensslstderr.txt
            rm /tmp/csrconfig
            return 1
        fi
        rm /tmp/opensslstderr.txt
        rm /tmp/csrconfig
    fi
    echo "created /etc/ssl/private/$certfilebasename.csr"

    # Create a temporary self signed certificate if there doesn't already exist a certificate
    if [ ! -f /etc/ssl/certs/$certfilebasename.crt ] || [ ! -s /etc/ssl/certs/$certfilebasename.crt ]; then
        openssl req -new -key /etc/ssl/private/$certfilebasename.key -subj "/CN=$maindomain" -x509 -days 3650 -out  /etc/ssl/certs/$certfilebasename.crt 2> /tmp/opensslstderr.txt
        if [ $? -ne 0 ]; then
            >&2 cat /tmp/opensslstderr.txt
            echo "failed to generate temporary self signed $certfilebasename.crt"
            rm /tmp/opensslstderr.txt
            return 1
        fi
        echo "created a temporary self signed /etc/ssl/certs/$certfilebasename.crt"
    fi

    mkdir -p $wwwroot/.well-known/acme-challenge/

    # Use acme_tiny.py to request the cert from Let's Encrypt
    python /etc/ssl/private/acme_tiny.py \
        --account-key /etc/ssl/private/letsencryptaccount.key \
        --contact $contact \
        --csr /etc/ssl/private/$certfilebasename.csr \
        --acme-dir $wwwroot/.well-known/acme-challenge/ \
        --dns-01-script "$dnschallangescript" \
        > /tmp/$certfilebasename.crt
        #--directory-url "https://acme-staging-v02.api.letsencrypt.org/directory" \
    if [ $? -ne 0 ]; then
        echo "acme_tiny.py failed for $certfilebasename"
        echo "did not touch existing /etc/ssl/certs/$certfilebasename.crt (if it exists)"
        rm /tmp/$certfilebasename.crt
        return 1
    fi

    # For reasons I cannot explain, letsencrypt sometimes apppends some extra expired CA certs. Remove these.
    csplit -s -z -f /tmp/$certfilebasename.crt- /tmp/$certfilebasename.crt '/-----BEGIN CERTIFICATE-----/' '{*}'
    if [ -f /tmp/$certfilebasename.crt-00 ]; then
        mv /tmp/$certfilebasename.crt-00 /tmp/$certfilebasename.crt
        rm /tmp/$certfilebasename.crt-*
    fi

    mv /tmp/$certfilebasename.crt /etc/ssl/certs/$certfilebasename.crt
    rm -fr $wwwroot/.well-known/
    echo "created /etc/ssl/certs/$certfilebasename.crt"
}
