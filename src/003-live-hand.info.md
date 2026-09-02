# 003-live-hand.lua

One GM command to a **running** worldserver, over the SOAP console the
deployment binds to loopback. Returns what the console printed.

## Functions

### `LiveHand.execute(handle, command, timeout) -> output | nil, why`
Runs one GM command. `command` is the text a GM would type **after** the dot —
`"tele name Grast ratchet"`, never `".tele name ..."`.

Note the failure shape: a GM command the server rejects usually returns HTTP 200
with an error sentence in the body, not an HTTP error code. A caller checking
only the status will believe everything succeeded, so this function reads the
body and returns nil plus the fault text.

### `LiveHand.probe(handle) -> up, reason, detail`
`reason` is one of `up`, `no_credentials`, `connection_refused`,
`soap_unauthorized`, `unreachable`. The probe command is `server info`, which
reads and changes nothing — a probe with a side effect would make merely asking
"is it up?" an action.

### `LiveHand.addressing_of(command) -> "name" | "selection" | "none" | nil`
How a command is addressed, by longest matching prefix. nil means the command is
not in the table and must not be used as a live step until somebody writes down
how it is addressed.

### `LiveHand.COMMANDS`
Table of the GM commands neuron uses. Each entry has `addressing` and `summary`.

## The constraint that shapes the project

Much of the GM vocabulary acts on the **currently selected unit**. A SOAP caller
has no selection and cannot get one. Commands taking an explicit character name
work through this hand; selection-addressed commands do not work through it at
all.

That is why the cold hand exists. A worked example: `gobject add` is
selection-addressed, so phase 6 cannot spawn props over SOAP and must write
`gameobject` rows through the database instead.
