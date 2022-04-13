#!/usr/bin/env bash

WORKSPACE=
REPO=
PR_ID=
COMMITS=all

function usage() {
echo "
Usage: $0 -w <workspace> -r <repo> [?-c (all|first)] <pr number>

e.g.

$0 -w my_workspace -r my_repo 64
$0 -w my_workspace -r my_repo -c first 64

Flags:

  -h | --help      : Print this message
  -w | --workspace : Bitbucket workspace
  -r | --repo      : Bitbucket repository
  -c | --commits   : Commits to include in message (all|first) (default: all)
"
}

while [ ! $# -eq 0 ]; do
	case "$1" in
		-h | --help)
			usage
			exit 0
			;;
		-w | --workspace)
			shift
			WORKSPACE=$1
			;;
		-r | --repo)
			shift
			REPO=$1
			;;
		-c | --commits)
			shift
			COMMITS=$1
			;;
		*)
			PR_ID=$1
			break
			;;
	esac
	shift
done

if [ -z "$WORKSPACE" ] || [ -z "$REPO" ] || [ -z "$PR_ID" ]; then
	usage
	exit 1
fi
if [ "$COMMITS" != all ] && [ "$COMMITS" != first ]; then
	usage
	exit 1
fi

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
title=$(echo "$pr" | ./bb-obj.js pr title)
footer=$(echo "$pr" | ./bb-obj.js pr approvers)

echo
echo "Getting commits"
echo
# # Care about:
# # obj.values[...].message (order is increasing age or decreasing recency)
commits=$(curl --request GET \
	-u jtache:$BB_APP_PW \
	--url "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$REPO/pullrequests/$PR_ID/commits")

body=$(echo "$commits" | ./bb-obj.js commits $COMMITS)

echo
echo "Merging"
echo

# Format commit as:
#
#     title
#     # blank line
#     body
#     footer # footer includes a newline at the beginning if it exists
#
# Double-quotes and newlines are escaped by sed and awk because the text is
# sent as JSON. Strips carriage returns.
commit_message=$(
	echo "$title\n\n$body\n$footer" |
		sed 's/"/\\\"/g' |
		awk -vRS=\0 '{gsub(/\n/,"\\n")}1' |
		awk -vRS=\0 '{gsub(/\r/,"")}1'
)

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
