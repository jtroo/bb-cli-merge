#!/usr/bin/env node

let args = process.argv
console.error('')

if (args.length < 3) {
    console.error('Incorrect usage')
    process.exit(1)
} else if (args[2] === 'pr') {
    handle_pr()
} else if (args[2] === 'commits') {
    handle_commits()
} else {
    console.error('Incorrect usage')
    process.exit(1)
}

function handle_pr() {
    if (args.length < 4) {
        console.error('Incorrect usage')
        process.exit(1)
    } else if (args[3] === 'title') {
        let handler = (pr_obj) => {
            if (pr_obj.state === 'MERGED') {
                console.error('PR already merged')
                process.exit(1)
            }
            console.log(`${pr_obj.title} (PR #${pr_obj.id})`)
        }
        process_stdin(handler)
    } else if (args[3] === 'approvers') {
        let handler = (pr_obj) => {
            if (pr_obj.state === 'MERGED') {
                console.error('PR already merged')
                process.exit(1)
            }
            if (pr_obj.participants.length === 0) {
                return
            }
            console.log('')
            for (let p of pr_obj.participants) {
                if (p.state === 'approved') {
                    console.log(`Approved by: ${p.user.display_name}`)
                }
            }
        }
        process_stdin(handler)
    } else {
        console.error('Incorrect usage')
        process.exit(1)
    }
}

function handle_commits() {
    if (args.length < 4) {
        console.error('Incorrect usage')
        process.exit(1)
    } else if (args[3] === 'first') {
        let handler = (c_obj) => {
            if (c_obj.values.length === 0) {
                console.error('No commits - PR likely already merged')
                process.exit(1)
            }
            let msg = c_obj.values[c_obj.values.length - 1].message
            // If keeping only one commit, then assume the PR title supercedes
            // the commit header and makes it pointless to include. Remove the
            // first two lines (commit header and blank line). Not my problem
            // if you don't follow proper git commit convention and this
            // mangles your commit body.
            //
            // In the case that there is ONLY a header and no body in the first
            // commit, this will output a blank line; this is fine. The PR
            // title is the only useful info in that case.
            console.log(msg.split('\n').slice(2).join('\n'))
        }
        process_stdin(handler)
    } else if (args[3] === 'all') {
        let handler = (c_obj) => {
            if (c_obj.values.length === 0) {
                console.error('No commits - PR likely already merged')
                process.exit(1)
            }
            for (let commit of Object.values(c_obj.values).reverse()) {
                console.log(`* ${commit.message}`)
            }
        }
        process_stdin(handler)
    } else {
        console.error('Incorrect usage')
        process.exit(1)
    }
}

function process_stdin(cb) {
    let all_stdin = ''
    process.stdin.on('data', (dat) => {
        all_stdin += dat
    })

    process.stdin.on('end', () => {
        try {
            cb(JSON.parse(all_stdin))
        } catch (_) {
            console.error('Could not parse; likely PR does not exist\n')
            console.error(`HTTP body:\n${all_stdin}`)
            process.exit(1)
        }
    })
}
