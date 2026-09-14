--------------------------------------------------------------------------------
-- 036-live.lua
--
-- The live hand as a mechanism: one game master command to a running
-- worldserver over its SOAP console.
--
-- A doorway onto 003-live-hand.lua, which is unchanged.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")

local Mechanism = Load(here .. "034-mechanism.lua")
local Hands     = Mechanism.Hands
local Refusals  = Mechanism.Refusals

return Mechanism.define {
    hand = Hands.live,

    -- {{{ probe
    probe = function(handle)
        local LiveHand = Load(handle.neuron_root .. "/src/003-live-hand.lua")
        return LiveHand.probe(handle)
    end,
    -- }}}

    -- {{{ describes
    describes = function(step)
        return step.describes or ("." .. tostring(step.command))
    end,
    -- }}}

    -- {{{ perform
    -- The addressing check happens here, once, rather than inside every
    -- operation that might reach for a command.
    --
    -- Much of the GM vocabulary acts on the caller's currently selected unit,
    -- and a SOAP caller has no selection and cannot acquire one. Such a command
    -- does not fail loudly over SOAP -- it acts on nothing, or on whatever the
    -- console considers selected, which is worse. Refusing it before sending is
    -- the only place that can be caught.
    perform = function(handle, step)
        local LiveHand = Load(handle.neuron_root .. "/src/003-live-hand.lua")

        local addressing = LiveHand.addressing_of(step.command)

        if addressing == nil then
            return Mechanism.failed(Refusals.refused, string.format(
                "'%s' is not a command neuron knows how to address.\n"
             .. "  Before a command can be sent as a live step, somebody has to\n"
             .. "  write down whether it acts on a named character, on the\n"
             .. "  caller's selection, or on nothing -- see LiveHand.COMMANDS.\n"
             .. "  To debug: is this command selection-addressed? If so it can\n"
             .. "  never work through SOAP and the operation needs a cold form\n"
             .. "  instead. If it takes a name, adding it to that table is the\n"
             .. "  whole fix.", tostring(step.command)))
        end

        if addressing == "selection" then
            return Mechanism.failed(Refusals.refused, string.format(
                "'%s' acts on the caller's selected unit, and a SOAP caller has\n"
             .. "  no selection and cannot get one.\n"
             .. "  Sending it anyway would not error -- it would act on nothing,\n"
             .. "  or on something arbitrary, and report success.\n"
             .. "  This operation needs a cold-hand form of the same change.",
                tostring(step.command)))
        end

        local output, why = LiveHand.execute(handle, step.command)

        if not output then
            return Mechanism.failed(Refusals.refused, string.format(
                "the worldserver refused this command.\n"
             .. "  %s\n"
             .. "  Sent: .%s\n"
             .. "  Note the shape of this failure: a rejected GM command comes\n"
             .. "  back as HTTP 200 with an error sentence in the body, not as\n"
             .. "  an HTTP error. The text above is the server's own words.\n"
             .. "  To debug: does the named character exist and are they online?\n"
             .. "  A live command cannot reach somebody who is not in the world.",
                tostring(why), tostring(step.command)))
        end

        -- The console reports what it did in prose. There is no affected-row
        -- count to be had, so one command that returned is one thing changed.
        return Mechanism.done(1, output)
    end,
    -- }}}
}
