#!/usr/bin/env bash

source .env
if [ -z "$BB_APP_PW" ]; then
	echo "No Bitbucket app password set"
	echo "App password (saved to .env file in current directory):"
	read -p "> " BB_APP_PW
	echo "export BB_APP_PW=$BB_APP_PW" > .env
fi
