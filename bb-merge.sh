#!/usr/bin/env bash

WORKSPACE=jtache
REPO=.vim
PR_ID=5

source .env
if [ -z "$BB_APP_PW" ]; then
	echo "No Bitbucket app password set"
	echo "App password (saved to .env file in current directory):"
	read -p "> " BB_APP_PW
	echo "export BB_APP_PW=$BB_APP_PW" > .env
fi

set -euo pipefail

echo
echo "Getting PR"
echo
# Care about:
# obj.id
# obj.title
# obj.participants[...].state === 'approved'
# obj.participants[...].user.display_name
pr=$(curl --request GET \
	-u jtache:$BB_APP_PW \
	--url "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$REPO/pullrequests/$PR_ID" \
	--header 'Accept: application/json')
echo

echo "Getting commits"
echo
# # Care about:
# # obj.values[...].message (order is increasing age or decreasing recency)
commits=$(curl --request GET \
	-u jtache:$BB_APP_PW \
	--url "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$REPO/pullrequests/$PR_ID/commits")
echo

title=$(echo "$pr" | ./bb-obj.js pr title)
body=$(echo "$commits" | ./bb-obj.js commits all)
footer=$(echo "$pr" | ./bb-obj.js pr approvers)

commit_message=$(echo "$title\n\n$body\n\n$footer" | sed 's/"/\\\"/g' | awk -vRS=\0 '{gsub(/\n/,"\\n")}1')

echo "Merging"
echo

set +e
ret=$(curl --request POST \
	-u jtache:$BB_APP_PW \
	--url "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$REPO/pullrequests/$PR_ID/merge" \
	--header 'Content-Type: application/json' \
	-d "{
		\"type\":\"squash\",
		\"merge_strategy\":\"squash\",
		\"close_source_branch\":true,
		\"message\":\"$commit_message\"
	}")

status=$?
if [ $status -ne 0 ]; then
	echo
	echo $ret
	echo
	exit $status
fi

echo
echo "Success"
echo
