# secrets/

One credential per file. Each file holds the credential **alone** — no name, no
equals sign, no quotes, no comment.

```
soap.key    the password of the GM game account named in config/deployment.lua
api.key     the API key for the model named in config/asking.lua
```

Both are optional. Without `soap.key` neuron works cold-hand only; without
`api.key` it works entirely except for free-language asking.

## Making one

```
printf '%s' 'the-credential' > secrets/soap.key
chmod 600 secrets/soap.key
```

`printf '%s'` rather than `echo`, because `echo` appends a newline and a
credential differing by a trailing newline fails in a way nothing shows you.
The reader strips trailing whitespace anyway; the habit is still worth having.

## Why files rather than a conf file

A conf file is a settings file that happens to hold a secret, and the secret
then **travels** — parsed into a table, carried in the handle, received by every
function that receives the handle whether it wanted it or not.

A key is an artifact you point at. `config/deployment.lua` holds the *path*; the
one function that needs the credential opens the file, uses it, and lets it go.
Nothing between the file and the socket ever holds it.

An environment variable is worse than either: inherited by every child process,
and readable from `/proc` by the owner and by root.

## What is refused, not warned about

- a file readable by group or other — a key somebody else can read is a key they
  have
- a file containing `=` — that is a config line, and guessing which half is the
  secret is how a password becomes the string `hunter2\n`
- an empty file — usually a redirect that ran before the value was ready

## This directory is not tracked

`.gitignore` excludes everything here except this file.
