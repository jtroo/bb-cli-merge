# Bitbucket merge CLI tool

This tool exists due to frustration with the default squash merge message that the Bitbucket UI makes upon merging. Especially recently, it no longer includes the entire commit text and truncates it with an ellipsis `...`.

I want a commit from a pull request to look like this in my commit history:

```
<PR title> (PR #<PR number>)

<commits text>

Approved by: <Approver 1>
Approved by: <Approver 2>
...
```

Since this isn't built into Bitbucket, I decided to make a CLI tool to do this for me.
