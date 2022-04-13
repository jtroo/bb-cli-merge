# Bitbucket merge CLI tool

This tool exists due to frustration with the default squash merge message that
the Bitbucket (Cloud) UI makes upon merging. Especially recently, it no longer
includes the entire commit text and truncates it with an ellipsis `...`.

I want a commit from a pull request to look like this in my commit history
after doing a squash merge:

```
<PR title> (PR #<PR number>)

<commits text>

Approved by: <Approver 1>
Approved by: <Approver 2>
...
```

Since this isn't built into Bitbucket, I decided to make a CLI tool to do this
for me.

# Dependencies

- node
- bash
- curl
- sed
- awk

# How to use

```shell
# help
./bb-merge.sh -h

# do a merge
./bb-merge.sh -u <user> -w <workspace> -r <repo> [?-c (all|first)] <pr number>
```

# Security

This code relies on a [Bitbucket app password](https://support.atlassian.com/bitbucket-cloud/docs/app-passwords/)
to be able to read from Bitbucket and perform the merge. The app password gets
stored in plaintext into `$PWD/.env`. The app password is not sent anywhere
other than to Bitbucket over https. Feel free to check the code, there's not
that much of it.

# Commit message after merging

This tool always uses the squash merge strategy. There are two ways that the
commit message can be formatted, determed by the `-c | --commit` flag. They are
mostly similar, with the difference being in the commit body.

## Header

A properly formatted git commit has the following format:

```
header

body
```

The header will always be the Pull Request title, as set in the Bitbucket pull
request UI, followed by `(PR #<pr number>)`

Example:

`Fix race condition in db write (PR #99)`

## Body

The body changes depending on if `all` or `first` is configured for the `-c` flag.
The default is `all`.

### Body: `all`

When the flag is set to `all`, the commit will have the following appearance:

```
<header>

* <commit 1>

* <commit 2>

<approvals>
```

Example:

```
Fix bugs in x and y (PR #101)

* Fix bug in x

Bug in x was very confusing. Here is a long description about what the
root cause is and how the code change fixes the bug.

* Fix bug in y

Bug in y was very confusing. Here is a long description about what the
root cause is and how the code change fixes the bug.

Approved by: Me
Approved by: You
```

### Body: `first`

When the flag is set to `first`, the commit will have the following appearance:

```
<header>

<commit 1 body only>

<approvals>
```

Example:

```
Fix bug in x (PR #101)

Bug in x was very confusing. Here is a long description about what the
root cause is and how the code change fixes the bug.

Approved by: Me
Approved by: You
```

Note that the header for the commit is stripped out. This is done because the
assumption is that I put more thought into the PR title in the bitbucket UI as
opposed to the header of the commit message. The original commit header won't
be the actual header after merging, so including the header of the first commit
message is redundant and wasteful.

This option exists because often I will have a meaningful and useful first
commit, but then as part of the review process, add commits after creating the
PR such as:

```
* Improve naming of function
* Improve clarity of doc comment
```

These post-creation commits are useful to see during the review process, but
are useless in the actual git history after merging to main. Using `-c first`,
this code will only use the first, useful commit when merging to main.

# My qualms

If you're curious, below are more of my specific qualms about the default
Bitbucket squash merge message.

- The truncation described above is particularly grievous
- The default header prefix `Merged in <branch>` wastes characters and relies
  on the branch name being a useful title.
- The default header suffix `(pull request #X)` also wastes characters when it
  could be shortened without losing any meaning. The `PR #X` text correctly
  hyperlinks in the Bitbucket UI at the time of writing, so there's no reason
  not to use `PR` instead of `pull request`.
- Redundant header when the PR is only one commit (see [body: first](#body-first))
