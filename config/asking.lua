--------------------------------------------------------------------------------
-- config/asking.lua
--
-- Which model neuron hands a sentence to when its own vocabulary does not
-- recognise it.
--
-- Separate from config/deployment.lua on purpose. That file says which world
-- this copy of neuron reaches into, and nothing else; a model is neuron's own
-- business and has nothing to do with the deployment. Two concerns, two files,
-- and neither grows a section belonging to the other.
--
-- The API KEY is not here. It lives in secrets.conf, which is untracked, beside
-- the SOAP password.
--------------------------------------------------------------------------------

return {
    -- The endpoint. Written out rather than assembled from parts, so that
    -- pointing this at a proxy or a local gateway is one edit to one string.
    url = "https://api.anthropic.com/v1/messages",

    -- Which model. A configuration value rather than a constant because it
    -- changes far more often than any code that uses it.
    model = "claude-opus-5",

    -- The API version header. Required, and versioned separately from the model.
    version = "2023-06-01",

    -- How this server's wire format differs from the shape the conversation
    -- loop uses. See src/056-dialects.lua.
    dialect = "anthropic",

    -- WHICH MODEL TO ASK, and it is a choice rather than a failure path.
    --
    --   "configured"  the model named above -- production
    --   "bench"       the local one below -- development
    --
    -- The local model is not here as a spare tyre. It is the bench you build
    -- against: writing the conversation loop, the tool schemas and the routing
    -- needs a hundred round trips of a model calling tools badly, and every one
    -- of those against a paid endpoint is money spent proving that JSON is
    -- shaped right. The bench answers instantly, offline, for nothing.
    --
    -- What it cannot do is the actual work. A seven-billion-parameter model on
    -- a desktop will not hold a world's worth of context or compose twenty
    -- coherent encounters. So: build on the bench, run on the configured one,
    -- and never confuse which answered -- every reply says.
    use = "configured",

    -- What happens when the chosen one cannot be reached.
    --
    --   "bench"   try the local model, saying so loudly
    --   "refuse"  stop, and say why
    --
    -- "bench" is right when there is no API key at all, which makes neuron
    -- usable by somebody who has not signed up for anything. It is wrong in
    -- production, where quietly answering with a much smaller model is worse
    -- than not answering -- so this is the knob that says which situation you
    -- are in.
    when_unavailable = "bench",

    -- The local model. Requires `ollama serve`, and the model pulled:
    --     ollama pull llama3.1
    --
    -- Tool calling needs a model that supports it. llama3.1, qwen2.5 and
    -- mistral-nemo do; many small ones do not, and one that does not answers in
    -- prose ABOUT the tools instead of calling them -- which looks like the
    -- loop being broken and is not.
    bench = {
        -- NOT the default 127.0.0.1:11434. This machine's Ollama is a CUDA
        -- build under /mnt/mtwo/programs/ollama/ started with
        -- OLLAMA_HOST=192.168.1.100:10265, and neuron probing the default port
        -- reported "not running" for days while it was running the whole time.
        url             = "http://192.168.1.100:10265/api/chat",
        -- The only tool-capable model pulled here. llama3.2 is 3B and its tool
        -- calling is shaky; qwen2.5 or mistral-nemo would be better if pulled.
        model           = "llama3.2:latest",
        dialect         = "ollama",
        timeout_seconds = 300,
        max_tokens      = 8192,
    },

    -- How long one request may take before it is abandoned.
    --
    -- A tool-calling turn is not read as it arrives, so this is the time for a
    -- whole answer rather than for a first token. Long enough that a real answer
    -- with twenty tool calls in it arrives; short enough that a hung request
    -- does not hold a chat window open until somebody notices.
    timeout_seconds = 120,

    -- How many times the model may call tools before neuron stops it.
    --
    -- A model that loops -- reading, getting a refusal, reading again -- has to
    -- stop somewhere, and stopping silently on the last partial answer is how
    -- somebody believes a thing finished.
    max_turns = 12,

    -- The ceiling on one response. Twenty spawn calls plus their reasoning is a
    -- lot of tokens and cutting it off mid-plan produces a plan that cannot be
    -- run.
    max_tokens = 8192,
}
