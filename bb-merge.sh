#!/usr/bin/env bash

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

WORKSPACE=
REPO=
PR_ID=
BB_USER=
COMMITS=all
ACTION=dry-run

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
fields="fields=participants.state,participants.user.display_name,id,title"
pr=$(curl --request GET \
	-u $BB_USER:$BB_APP_PW \
	--url "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$REPO/pullrequests/$PR_ID?$fields" \
	--header 'Accept: application/json')
title=$(echo "$pr" | ./bb-obj.js pr title)
footer=$(echo "$pr" | ./bb-obj.js pr approvers)

echo "Getting commits"
echo
# Care about:
# obj.values[...].message (order is increasing age or decreasing recency)
# obj.next (for pagination)
fields="fields=values.message,next"
commits=$(curl --request GET \
	-u $BB_USER:$BB_APP_PW \
	--url "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$REPO/pullrequests/$PR_ID/commits?$fields")
body=$(echo "$commits" | ./bb-obj.js commits $COMMITS)

# note: "next" can **only** match the JSON key; any "next" in a JSON value
# (e.g. in a comment) will have the double-quotes escaped.
while [ $(echo $commits | grep -c '"next"') -eq 1 ]; do
	next_url=$(echo $commits | sed 's/.*"next": "\([^"]\+\).*/\1/')
	commits=$(curl --request GET \
			-u $BB_USER:$BB_APP_PW \
			--url "$next_url")
	if [ $COMMITS == all ]; then
		body=$(printf "%s\n\n$body" "$(echo "$commits" | ./bb-obj.js commits $COMMITS)")
	else
		body=$(echo "$commits" | ./bb-obj.js commits $COMMITS)
	fi
done

if [ -z "$body" ]; then
	# body can be empty if $COMMITS is "first" and no body in commit; only header
	#
	# Format commit as:
	#
	#     title
	#     footer # footer includes a newline at the beginning if it exists
	msg=$(printf "$title\n$footer")
else
	# Format commit as:
	#
	#     title
	#     # blank line
	#     body
	#     footer # footer includes a newline at the beginning if it exists
	msg=$(printf "$title\n\n$body\n$footer")
fi
echo
echo "Squashed commit message:"
echo
echo ------------------------------------------------------------------------
echo "$msg"
echo ------------------------------------------------------------------------
echo

# Exit early if doing a dry run.
if [ "$ACTION" == dry-run ]; then
	exit 0
fi

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

# Merge the PR
set +e
fields="fields=state,title"
ret=$(curl --request POST \
	-u $BB_USER:$BB_APP_PW \
	--url "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$REPO/pullrequests/$PR_ID/merge?$fields" \
	--header 'Content-Type: application/json' \
	-d "{
		\"type\":\"squash\",
		\"merge_strategy\":\"squash\",
		\"close_source_branch\":true,
		\"message\":\"$commit_message\"
	}"
)

echo
echo Merge request returned:
echo $ret
echo
