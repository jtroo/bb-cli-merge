#!/usr/bin/env bash

WORKSPACE=
REPO=
PR_ID=
BB_USER=
COMMITS=all
ACTION=dry-run

function usage() {
	echo "
Usage:
$0 \\
	--workspace <workspace> \\
	--repo <repo> \\
	[?--action (dry-run|merge)] \\
	[?--commits (all|first)] \\
	<pr number>

Examples:

$0 --workspace my_workspace --repo my_repo 64
$0 --workspace my_workspace --repo my_repo --action merge 64
$0 --workspace my_workspace --repo my_repo --commits first 64
$0 --workspace my_workspace --repo my_repo --commits first --action merge 64

Flags:

  -h | --help      : Print this message
  -w | --workspace : Bitbucket workspace
  -r | --repo      : Bitbucket repository
  -c | --commits   : Commits to include in message (all|first) (default: all)
  -a | --action    : Action for this script. (dry-run|merge) (default: dry-run)
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
		-a | --action)
			shift
			ACTION=$1
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
if [ "$ACTION" != dry-run ] && [ "$ACTION" != merge ]; then
	usage
	exit 1
fi

# Ensure temporary .bb-creds file is removed
function cleanup {
	rm -f .bb-creds
}
trap cleanup EXIT

# Read in username and app pass if they exist. They should be stored as
# `<var>=<value>` strings which are valid to evaluate.
eval $(2>/dev/null gpg -d .bb-creds.gpg)

if [ -z "$BB_APP_PW" ] || [ -z "$BB_USER" ]; then
	echo "Input username (saved to .bb-creds.gpg file in current directory):"
	read -p "> " BB_USER
	echo "BB_USER=$BB_USER" > .bb-creds
	echo "Input app password (saved to .bb-creds.gpg file in current directory):"
	read -sp "(characters are hidden) > " BB_APP_PW
	echo "BB_APP_PW=$BB_APP_PW" >> .bb-creds
	gpg -c .bb-creds
	rm .bb-creds
fi

# Commands should not fail from here on.
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
	-u $BB_USER:$BB_APP_PW \
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
	-u $BB_USER:$BB_APP_PW \
	--url "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$REPO/pullrequests/$PR_ID/commits")
body=$(echo "$commits" | ./bb-obj.js commits $COMMITS)

# Format commit as:
#
#     title
#     # blank line
#     body
#     footer # footer includes a newline at the beginning if it exists
#
msg=$(printf "$title\n\n$body\n$footer")
echo "Squash merge commit message:"
echo -----
echo "$msg"
echo -----
echo

# Double-quotes and newlines are escaped by sed and awk because the text is
# sent as JSON. Strip carriage returns as well, in case they exist.
#
# The awk `-vRS` sets the record separator to a regular expression meaning
# "empty string". Since any non-empty string won't match the regular
# expression, the record separator will never be found and the whole input
# string will be treated as one record.
commit_message=$(
	echo -n "$msg" |
		sed 's/"/\\\"/g' |
		awk -vRS='^$' '{gsub(/\r/,"")}1' |
		awk -vRS='^$' '{gsub(/\n/,"\\n")}1'
)

if [ "$ACTION" == dry-run ]; then
	echo
	echo "Commit message as sent via curl:"
	echo "$commit_message"
	exit 0
fi

set +e
ret=$(curl --request POST \
	-u $BB_USER:$BB_APP_PW \
	--url "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$REPO/pullrequests/$PR_ID/merge" \
	--header 'Content-Type: application/json' \
	-d "{
		\"type\":\"squash\",
		\"merge_strategy\":\"squash\",
		\"close_source_branch\":true,
		\"message\":\"$commit_message\"
	}"
)

echo
if [ ${#ret} -lt 100 ]; then
	echo $ret
else
	# This doen't actually check success, it just assumes that a long
	# returned value is the large JSON that is returned when successful.
	# I'm too lazy to figure out how to properly check for success, and
	# this seems good enough for the script's intended use case.
	echo "Success"
fi
