#!/bin/sh

ufw limit ssh
ufw allow 80/tcp
ufw allow 443/tcp

ufw --force enable
ufw status
