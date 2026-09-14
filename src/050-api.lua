--------------------------------------------------------------------------------
-- 050-api.lua
--
-- One HTTPS request to a model, and the answer back.
--
-- WHY CURL: LuaJIT ships no TLS and this project takes no dependencies, so
-- there is no socket route to an HTTPS endpoint. But the project already
-- reaches outside itself twice, and both times by running a program --
-- 002-cold-hand.lua runs the deployment's own mysql binary, 003-live-hand.lua
-- speaks HTTP to the SOAP console. Running curl is the same shape of thing, and
-- it brings TLS, redirects, timeouts and proxy handling that would otherwise
-- have to be written. The alternative is linking a TLS library, which means a
-- build step and a version of this project that stops running on a machine
-- where it currently does.
--
-- WHERE THE KEY IS NOT: not on the command line. Anything in an argument list
-- is visible in `ps` to every user on the machine. It goes in a header file
-- written to the RAM tier with restrictive permissions, handed to curl by path,
-- and deleted afterwards.
--
-- WHERE THE BODY IS NOT: also not on the command line. A tool list plus a
-- conversation is far past any safe argument length. Body in, body out, both
-- through files, both deleted.
--------------------------------------------------------------------------------

local Api = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ FAILURES
-- What can go wrong, what it means, and whether waiting helps.
--
-- Kept as a table rather than a chain of comparisons so that a caller can look
-- one up and so the whole set can be printed. The `retry` column is the one
-- callers act on: three of these are worth trying again and the rest are not,
-- and trying again on a 401 is how a wrong key becomes a rate limit.
Api.FAILURES = {
    no_key      = { retry = false, means = "no API key is configured" },
    no_config   = { retry = false, means = "config/asking.lua is absent" },
    no_curl     = { retry = false, means = "curl is not on this machine" },
    unreachable = { retry = true,  means = "the endpoint could not be reached" },
    timed_out   = { retry = true,  means = "the request took too long" },
    unauthorized= { retry = false, means = "the key is wrong, revoked, or has no credit" },
    rate_limited= { retry = true,  means = "too many requests; the response says how long" },
    overloaded  = { retry = true,  means = "the service is busy" },
    malformed   = { retry = false, means = "the request was wrong; this is our bug" },
    unreadable  = { retry = false, means = "the answer did not parse as JSON" },
    -- The key is valid and the account is empty. Distinct from unauthorized
    -- because the fix is completely different and retrying helps neither.
    no_credit   = { retry = false, means = "the account has no credit left" },
}
-- }}}

-- {{{ shell_quote(text)
local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end
-- }}}

-- {{{ scratch_path(handle, what)
-- Where request and response bodies live for the moment they exist.
--
-- The RAM tier, because a conversation written to a disk is a conversation
-- somebody can read afterwards, and because these files are large and
-- worthless the instant they are consumed.
local function scratch_path(handle, what)
    return string.format("%s/tmp/shared-memory/api-%s-%d-%d",
        handle.neuron_root, what, os.time(), math.random(100000, 999999))
end
-- }}}

-- {{{ write_file(path, contents, private)
local function write_file(path, contents, private)
    local file, why = io.open(path, "w")
    if not file then return nil, why end
    file:write(contents)
    file:close()

    -- The header file holds the key. Readable by anybody is the same mistake as
    -- putting it on the command line, arrived at differently.
    if private then
        os.execute("chmod 600 " .. shell_quote(path))
    end

    return true
end
-- }}}

-- {{{ read_file(path)
local function read_file(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local contents = file:read("*a")
    file:close()
    return contents
end
-- }}}

-- {{{ Api.available(handle)
-- Can neuron ask anything at all? Answered without sending a request.
--
-- Two separate absences with two different fixes, so they are two answers
-- rather than one. No config is somebody who has not set this up; no key is
-- somebody who has, and left the secret out.
function Api.available(handle)
    if not handle.asking then
        return false, "no_config",
            "config/asking.lua is not present, so no model is configured.\n"
         .. "  neuron works entirely without one -- every lever, the command\n"
         .. "  line, and the chat window's own vocabulary. Only free-language\n"
         .. "  asking needs it."
    end

    local Keys = sibling(handle.neuron_root, "052-keys.lua")

    local have, why = Keys.present(handle.api_key_path, "the API key")

    if not have then
        -- A local server wants no credential, so a missing key is only fatal
        -- when there is nowhere else to ask. This is why the fallback is worth
        -- having beyond redundancy: it makes neuron usable by somebody who has
        -- not signed up for anything.
        if handle.asking.bench then
            return true, "bench_only", why
        end
        return false, "no_key", why
    end

    return true
end
-- }}}

-- {{{ send_to(handle, request, target, credential)
-- One request to one server, in that server's dialect.
--
-- `request` is the internal shape -- system, messages, tools. What goes on the
-- wire is whatever the target's dialect makes of it, which is why adding a
-- place to ask does not touch this function.
local function send_to(handle, request, target, credential)
    local Json     = sibling(handle.neuron_root, "001-json.lua")
    local Dialects = sibling(handle.neuron_root, "056-dialects.lua")

    local dialect, dialect_why = Dialects.of(target.dialect or "anthropic")
    if not dialect then
        return nil, "malformed", dialect_why
    end

    local encoded = Json.encode(dialect.encode(request, target))

    local request_path  = scratch_path(handle, "request")
    local response_path = scratch_path(handle, "response")
    local headers_path  = scratch_path(handle, "headers")
    local status_path   = scratch_path(handle, "status")

    -- {{{ clean_up()
    local function clean_up()
        for _, path in ipairs({ request_path, response_path,
                                headers_path, status_path }) do
            os.remove(path)
        end
    end
    -- }}}

    local wrote, write_why = write_file(request_path, encoded)
    if not wrote then
        clean_up()
        return nil, "malformed", string.format(
            "cannot write the request body to %s\n  %s\n"
         .. "  Sent: nothing. The RAM tier may not exist -- it is created by the\n"
         .. "  run scripts and is empty after every reboot.",
            request_path, tostring(write_why))
    end

    -- The credential goes in a file the process owner alone can read, never in
    -- an argument list. A local target supplies none and its header block says
    -- only what the content type is.
    write_file(headers_path, dialect.headers(credential, target), true)

    local command = table.concat({
        "curl", "--silent", "--show-error",
        "--max-time", tostring(target.timeout_seconds or 120),
        "--header", "@" .. shell_quote(headers_path),
        "--data-binary", "@" .. shell_quote(request_path),
        "--output", shell_quote(response_path),
        "--write-out", "'%{http_code}'",
        shell_quote(target.url),
        ">", shell_quote(status_path), "2>&1",
    }, " ")

    os.execute(command)

    local status = (read_file(status_path) or ""):gsub("%s+$", "")
    local answer = read_file(response_path) or ""

    clean_up()

    local code = tonumber(status:match("(%d%d%d)%s*$"))

    -- curl writes 000 when it never got an HTTP response at all -- refused,
    -- unresolvable, or reset. That is a transport failure wearing a status
    -- code, and treating it as one produced "rejected the request (HTTP 0)"
    -- about a server that was simply not running.
    if code == 0 then code = nil end

    -- Whatever curl said, for the messages below. The body file is empty on
    -- every transport failure, so reporting `answer` alone reports nothing --
    -- and "could not reach it, because:" followed by a blank line is the least
    -- useful thing an error can do.
    local complaint = answer ~= "" and answer
        or (status:gsub("%s*%d%d%d%s*$", ""):gsub("%s+$", ""))

    -- {{{ transport failures, before any HTTP status exists
    if not code then
        if status:find("not found") or status:find("command not found") then
            return nil, "no_curl",
                "curl is not on this machine, and it is how neuron speaks\n"
             .. "  HTTP -- LuaJIT ships no TLS and this project takes no\n"
             .. "  dependencies."
        end

        if status:find("timed out") or status:find("Operation timeout") then
            return nil, "timed_out", string.format(
                "%s took longer than %d seconds and was abandoned.\n"
             .. "  Whether it did the work anyway is unknowable from here, which\n"
             .. "  is why nothing in this project applies a change on the\n"
             .. "  strength of a request it did not see answered.",
                target.url, target.timeout_seconds or 120)
        end

        return nil, "unreachable", string.format(
            "could not reach %s\n  %s\n"
         .. "  To debug: is it running, and is the url right? For a local\n"
         .. "  server, `ollama serve` must be up and the port must match.",
            target.url, complaint ~= "" and complaint
                or "curl said nothing at all")
    end
    -- }}}

    -- {{{ HTTP status
    if code == 401 or code == 403 then
        return nil, "unauthorized", string.format(
            "%s refused the key (HTTP %d).\n  %s\n"
         .. "  Retrying will not help.", target.url, code, complaint)
    end

    if code == 429 then
        return nil, "rate_limited", string.format(
            "rate limited by %s (HTTP 429).\n  %s", target.url, complaint)
    end

    if code == 404 then
        -- The local case worth naming: Ollama answers 404 for a model it has
        -- not pulled, which looks like a wrong url and is not.
        return nil, "malformed", string.format(
            "%s returned 404.\n  %s\n"
         .. "  For a local server this usually means the model is not pulled\n"
         .. "  rather than that the url is wrong:  ollama pull %s",
            target.url, complaint, tostring(target.model))
    end

    if code == 529 or code >= 500 then
        return nil, "overloaded", string.format(
            "%s is having trouble (HTTP %d).\n  %s", target.url, code, complaint)
    end

    if code ~= 200 then
        -- A 400 that is really about money.
        --
        -- The account having no credit comes back as invalid_request_error,
        -- which by status alone reads as a malformed body -- so neuron told
        -- somebody their request was wrong when their card was. Matched on the
        -- text because the status cannot distinguish them.
        local lowered = complaint:lower()

        if lowered:find("credit balance", 1, true)
        or lowered:find("quota", 1, true)
        or lowered:find("billing", 1, true) then
            return nil, "no_credit", string.format(
                "%s answered, and the account has nothing to spend.\n\n  %s\n\n"
             .. "  The key works and the request was fine. Nothing here can fix\n"
             .. "  it -- add credit, or set use = \"bench\" in config/asking.lua\n"
             .. "  and run a local model instead.",
                target.url, (complaint:match('"message":"([^"]*)"') or complaint))
        end

        return nil, "malformed", string.format(
            "%s rejected the request (HTTP %d).\n  %s\n"
         .. "  A 4xx that is not 401, 404, 429 or a billing problem means the\n"
         .. "  body was wrong, which is neuron's bug rather than anybody's\n"
         .. "  configuration.", target.url, code, complaint)
    end
    -- }}}

    local decoded, decode_why = Json.decode(answer)

    if not decoded then
        return nil, "unreadable", string.format(
            "%s answered HTTP 200 and it did not parse as JSON.\n  %s\n"
         .. "  The first 200 characters were:\n  %s",
            target.url, tostring(decode_why), answer:sub(1, 200))
    end

    -- A body that parses and carries an error is NOT a success. A caller
    -- checking only the status believes it worked -- the same shape
    -- 003-live-hand.lua documents for the SOAP console.
    if decoded.type == "error" or decoded.error then
        local detail = decoded.error or {}
        return nil, "malformed", string.format(
            "HTTP 200 from %s, and the body is an error: %s\n  %s",
            target.url, tostring(detail.type),
            tostring(detail.message or decoded.error))
    end

    local reply = dialect.decode(decoded, Json)
    reply.via = target.url
    reply.model = target.model
    return reply
end
-- }}}

-- {{{ Api.reachable(target)
-- Is anything actually listening there? Answered in under a second, without
-- asking it to think.
--
-- The distinction this exists for: a bench model that is CONFIGURED and a bench
-- model that is RUNNING are different things, and reporting the first as though
-- it were the second let the menu open a chat window with nothing behind it.
-- Ollama not being started is the normal case, not the exception.
--
-- A HEAD to the base url rather than a chat request: it costs nothing, needs no
-- model loaded, and answers the only question being asked.
-- Answers are kept for a little while.
--
-- The menu asks for state on a timer, and every one of those was a HEAD request
-- at the local model -- a line in its log every few seconds, forever, about a
-- question whose answer changes maybe twice a day. Cached for a minute: long
-- enough to stop the noise, short enough that starting ollama shows up while
-- somebody is still looking at the page.
local recently = {}

-- `force` skips the remembered answer.
--
-- The cache is right for a page drawing itself and wrong for a person pressing
-- a button: somebody who just started ollama and pressed check is asking about
-- NOW, and handing them a minute-old "not answering" makes the button look
-- broken and the fix look ineffective.
local function reachable(url, force)
    local now = os.time()
    local remembered = recently[url]
    if not force and remembered and (now - remembered.at) < 60 then
        return remembered.answer
    end

    -- The URL AS CONFIGURED, not just its host.
    --
    -- Asking the root was asking a different question. https://api.anthropic.com
    -- answers a bare GET intermittently -- sometimes 404, more often nothing at
    -- all -- while https://api.anthropic.com/v1/messages answers 405 every
    -- time, because there is a real handler there that only objects to the
    -- method. The endpoint somebody configured is the endpoint worth asking
    -- about, and a wrong PATH is exactly the misconfiguration this button is
    -- for: a right host with a wrong path would have passed the old check.
    local base = url

    -- A GET whose body is thrown away, NOT a HEAD.
    --
    -- HEAD looked right -- it is the request that asks for nothing -- and it
    -- was wrong: https://api.anthropic.com does not answer HEAD at all, so the
    -- request hung until the timeout and came back 000. The check button
    -- reported "not answering" about an endpoint that answers a GET in under a
    -- second, which is worse than having no button.
    --
    -- The body is discarded and capped, so this stays as cheap as HEAD was
    -- meant to be. It costs no tokens and no money: the root of an inference
    -- endpoint is not the inference endpoint.
    -- Ten seconds, not two. Measured: this machine's link to
    -- api.anthropic.com delivers a 112-byte 405 in about five seconds, and at
    -- two seconds the probe timed out and reported an endpoint that works as
    -- one that does not. A check that is quick and wrong is worse than one that
    -- takes a moment.
    local pipe = io.popen(string.format(
        "curl --silent --max-time 10 --max-filesize 20000 --output /dev/null "
     .. "--write-out '%%{http_code}' %s 2>/dev/null",
        "'" .. base:gsub("'", "'\\''") .. "'"), "r")

    if not pipe then return false end

    local code = tonumber((pipe:read("*a") or ""):match("(%d+)"))
    pipe:close()

    -- Any answer at all means something is there. A 405 from an endpoint that
    -- only accepts POST is still an endpoint, and a 401 from one that wants a
    -- key it was not given is a particularly good answer: it proves the whole
    -- path is real.
    local answer = code ~= nil and code > 0
    recently[url] = { at = now, answer = answer }
    return answer
end

Api.reachable = reachable
-- }}}

-- {{{ Api.warm(handle, target)
-- Ask the local model server to load a model into memory, without generating
-- anything with it.
--
-- Loading is the slow step -- weights off disk into RAM and up to the GPU, five
-- to sixty seconds depending on size -- and it happens on the FIRST request,
-- which is the one somebody is sitting waiting for. Doing it when a window
-- opens means the wait is spent while they are still reading the screen.
--
-- Ollama's /api/generate with a model and no prompt loads and returns. It is
-- fire-and-forget: nothing here waits for it or cares whether it worked, since
-- the only consequence of failing is the first real request being slow, which
-- is what would have happened anyway.
function Api.warm(handle, target)
    target = target or (handle.asking and handle.asking.bench)
    if not target or not target.model then return end

    local base = target.url:match("^(https?://[^/]+)") or target.url

    local body = string.format('{"model":%q,"keep_alive":"10m"}', target.model)

    os.execute(string.format(
        "curl --silent --max-time 120 --output /dev/null "
     .. "--header 'content-type: application/json' "
     .. "--data %s %s/api/generate >/dev/null 2>&1 &",
        "'" .. body:gsub("'", "'\\''") .. "'",
        "'" .. base:gsub("'", "'\\''") .. "'"))
end
-- }}}

-- {{{ Api.chosen(handle)
-- Which model this neuron will ask, and why -- answered WITHOUT asking it.
--
-- The menu needs this before a conversation starts. Finding out which model
-- answered by reading the answer is finding out too late: a plan composed by a
-- seven-billion-parameter model and one composed by a frontier model look
-- alike on the page and are not alike at all.
--
-- Returns: { which, model, url, why, usable }
function Api.chosen(handle)
    local asking = handle.asking

    if not asking then
        return { which = "none", usable = false,
            why = "config/asking.lua is not present, so no model is configured. "
               .. "Everything else works -- every lever, the command line, and "
               .. "the chat window's own vocabulary. Only free language needs one." }
    end

    local Keys = sibling(handle.neuron_root, "052-keys.lua")
    local have_key = Keys.present(handle.api_key_path, "the API key")

    local bench = asking.bench

    if asking.use == "bench" then
        if not bench then
            return { which = "none", usable = false,
                why = "config/asking.lua says to use the bench model and does "
                   .. "not describe one." }
        end
        if not reachable(bench.url) then
            return { which = "bench", model = bench.model, url = bench.url,
                usable = false,
                why = "config/asking.lua says to use the bench model, and "
                   .. "nothing is listening at " .. bench.url .. ".\n\n"
                   .. "Start it:  ollama serve\n"
                   .. "And make sure the model is pulled:  ollama pull "
                   .. bench.model }
        end

        return { which = "bench", model = bench.model, url = bench.url,
            usable = true,
            why = "Deliberately on the bench model -- config/asking.lua says "
               .. "use = \"bench\". This is the development setting: cheap, "
               .. "offline, and much less capable. Set it back to \"configured\" "
               .. "for real work." }
    end

    if have_key then
        return { which = "configured", model = asking.model, url = asking.url,
            usable = true,
            why = "The configured model, with a key present. If it cannot be "
               .. "reached, " .. (asking.when_unavailable == "bench"
                   and "the bench model answers and says so."
                    or "neuron refuses rather than quietly using a smaller model.") }
    end

    if asking.when_unavailable == "bench" and bench then
        if not reachable(bench.url) then
            return { which = "none", model = bench.model, url = bench.url,
                usable = false,
                why = "There is no API key, and the bench model that would "
                   .. "stand in for one is not running -- nothing is listening "
                   .. "at " .. bench.url .. ".\n\n"
                   .. "Either write an API key in the keys section below, or start\n"
                   .. "the bench:\n"
                   .. "    ollama serve\n"
                   .. "    ollama pull " .. bench.model }
        end

        return { which = "bench", model = bench.model, url = bench.url,
            usable = true,
            why = "No API key, so the bench model is the only one available. "
               .. "It is much less capable and every answer will say it came "
               .. "from here." }
    end

    return { which = "none", usable = false,
        why = "No API key, and config/asking.lua does not allow the bench "
           .. "model to stand in. See secrets/README.md." }
end
-- }}}

-- {{{ Api.send(handle, request)
-- Ask, and say which one answered.
--
-- This project's position is that a fallback is a warning and a warning is an
-- error. The position holds: nothing here is silent. Every reply carries which
-- model produced it, the loop puts that in the answer, and the asking log
-- records it.
--
-- The reason is not redundancy. A local model and a frontier one produce very
-- different plans from the same sentence, and a person reading twenty spawn
-- steps needs to know which wrote them.
function Api.send(handle, request)
    local asking = handle.asking

    if not asking then
        return nil, "no_config",
            "config/asking.lua is not present, so no model is configured."
    end

    local Keys = sibling(handle.neuron_root, "052-keys.lua")
    local bench = asking.bench

    -- {{{ a caller may require the bench, and mean it
    -- The configuration window does, and it is not a preference -- it is the
    -- whole point of that window.
    --
    -- It is a life raft. Somebody opens it when nothing works: no key, no
    -- credit, no network, a URL that was wrong for days. A life raft that
    -- phones a remote service to ask how to reach a remote service is not a
    -- life raft. So this does not fall through, ever, and says plainly what to
    -- do instead.
    if request.only == "bench" then
        if not bench then
            return nil, "no_config",
                "config/asking.lua describes no local model, and this window "
             .. "will not use a remote one."
        end

        local reply, kind, why = send_to(handle, request, bench, nil)

        if not reply then
            return nil, kind, string.format(
                "%s\n\n  This window only ever talks to a local model -- it is "
             .. "the one you open when nothing else works, so reaching out to a "
             .. "paid service to ask how to reach a paid service would defeat "
             .. "it.\n\n  Start one:  ollama serve", why)
        end

        reply.answered_by = string.format("%s (local)", bench.model)
        return reply
    end
    -- }}}

    -- {{{ deliberately on the bench
    if asking.use == "bench" then
        if not bench then
            return nil, "no_config",
                "config/asking.lua says use = \"bench\" and describes no bench "
             .. "model."
        end

        local reply, kind, why = send_to(handle, request, bench, nil)
        if not reply then return nil, kind, why end

        reply.answered_by = string.format("%s (local)", bench.model)
        return reply
    end
    -- }}}

    local credential, key_why = Keys.read(handle.api_key_path, "the API key")

    -- {{{ the configured model
    if credential then
        local reply, kind, why = send_to(handle, request, asking, credential)

        if reply then
            reply.answered_by = asking.model
            return reply
        end

        if asking.when_unavailable ~= "bench" or not bench then
            return nil, kind, why
        end

        -- Only failures a different server could plausibly survive. A malformed
        -- request is neuron's bug and will be just as malformed on the bench.
        local worth_retrying = (kind == "unreachable" or kind == "timed_out"
            or kind == "rate_limited" or kind == "overloaded"
            or kind == "unauthorized" or kind == "no_credit")

        if not worth_retrying then return nil, kind, why end

        local bench_reply, bench_kind, bench_why =
            send_to(handle, request, bench, nil)

        if not bench_reply then
            return nil, kind, string.format(
                "%s\n\n  The bench model did not answer either (%s):\n  %s",
                why, bench_kind, bench_why)
        end

        bench_reply.answered_by = string.format(
            "%s (local) -- %s could not be reached (%s)",
            bench.model, asking.model, kind)
        return bench_reply
    end
    -- }}}

    -- {{{ no key at all
    if asking.when_unavailable ~= "bench" or not bench then
        return nil, "no_key", key_why
    end

    local reply, kind, why = send_to(handle, request, bench, nil)

    if not reply then
        return nil, kind, string.format(
            "%s\n\n  There is no API key either:\n  %s", why, key_why)
    end

    reply.answered_by = string.format(
        "%s (local) -- no API key is configured", bench.model)
    return reply
    -- }}}
end
-- }}}

return Api
