#!/bin/bash

set -e

MARKER_FILE="/root/.btcpay-domain-configured"

if [ -f "$MARKER_FILE" ]; then
    exit 0
fi

echo ""
echo "=================================================="
echo " BTCPay Server - Domain Setup"
echo "=================================================="
echo ""
echo "Before BTCPay can start, it needs a domain name pointed"
echo "at this server. This is required for HTTPS (Let's Encrypt)."
echo ""

DROPLET_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)

if [ -z "$DROPLET_IP" ]; then
    echo "Could not determine this droplet's public IP. Aborting."
    exit 1
fi

echo "This droplet's IP address is: $DROPLET_IP"
echo ""

echo "Which Lightning Network implementation would you like to use?"
echo "  1) Core Lightning / CLN  (default, well-supported, lighter footprint)"
echo "  2) LND                   (popular for wallet compatibility, e.g. Zeus)"
echo "  3) phoenixd              (lightweight, non-custodial)"
echo ""

BTCPAY_LN_IMPL="clightning"
while true; do
    read -p "Enter 1, 2, or 3 [default: 1]: " LN_CHOICE
    case "$LN_CHOICE" in
        ""|1)
            BTCPAY_LN_IMPL="clightning"
            break
            ;;
        2)
            BTCPAY_LN_IMPL="lnd"
            break
            ;;
        3)
            BTCPAY_LN_IMPL="phoenixd"
            break
            ;;
        *)
            echo "Please enter 1, 2, or 3."
            ;;
    esac
done

echo "Using Lightning implementation: $BTCPAY_LN_IMPL"
echo ""

while true; do
    read -p "Enter your domain name (e.g. btcpay.example.com): " BTCPAY_DOMAIN

    if [ -z "$BTCPAY_DOMAIN" ]; then
        echo "Domain cannot be empty."
        continue
    fi

    echo ""
    echo "Checking DNS for $BTCPAY_DOMAIN ..."

    RESOLVED_IP=$(getent hosts "$BTCPAY_DOMAIN" | awk '{ print $1 }' | head -n1)

    if [ "$RESOLVED_IP" == "$DROPLET_IP" ]; then
        echo "DNS check passed: $BTCPAY_DOMAIN resolves to $DROPLET_IP"
        echo ""
        break
    else
        echo ""
        echo "DNS check failed."
        if [ -z "$RESOLVED_IP" ]; then
            echo "$BTCPAY_DOMAIN does not resolve to any IP yet."
        else
            echo "$BTCPAY_DOMAIN currently resolves to $RESOLVED_IP, not $DROPLET_IP."
        fi
        echo "DNS changes can take a few minutes up to a few hours to propagate."
        echo ""
        read -p "Try again now? (y = retry, n = exit and run this again later) [y/n]: " RETRY
        if [ "$RETRY" != "y" ]; then
            echo ""
            echo "No problem. Run this command again once your DNS is ready:"
            echo "  sudo /root/configure-domain.sh"
            exit 0
        fi
        echo ""
    fi
done

echo "Starting BTCPay Server install for $BTCPAY_DOMAIN ..."
echo "This can take several minutes on first run."
echo ""

export BTCPAY_HOST="$BTCPAY_DOMAIN"
export BTCPAY_PROTOCOL="https"
export BTCPAYGEN_REVERSEPROXY="nginx"
export BTCPAYGEN_CRYPTO1="btc"
export BTCPAYGEN_LIGHTNING="$BTCPAY_LN_IMPL"
export BTCPAYGEN_ADDITIONAL_FRAGMENTS="opt-save-storage-xs"

cd /root/btcpayserver-docker
. ./btcpay-setup.sh -i

touch "$MARKER_FILE"

echo ""
echo "=================================================="
echo " Done. BTCPay Server should now be available at:"
echo " https://$BTCPAY_DOMAIN"
echo "=================================================="
echo ""
