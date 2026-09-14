--------------------------------------------------------------------------------
-- 066-srp6.lua
--
-- Checking a password against a game account, without asking the account for it.
--
-- WHY THIS AND NOT THE AUTHSERVER: the authserver's job is exactly this, and it
-- does it over the WoW login protocol -- a multi-step socket dance with
-- challenge, proof and reconnect stages. There is no "is this password right?"
-- endpoint to call. Speaking that protocol correctly is far more work than
-- computing the one value it would have compared.
--
-- WHAT IS STORED: acore_auth.account holds `salt` and `verifier`, both 32 bytes,
-- and no password. The verifier is
--
--     x = SHA1( salt || SHA1(UPPER(user) || ":" || UPPER(pass)) )
--     v = g^x mod N          with g = 7 and N the 256-bit SRP prime
--
-- Recomputing v from a typed password and comparing it to the stored bytes
-- proves the password without the password ever having been stored -- which is
-- the whole point of storing a verifier rather than a hash.
--
-- ENDIANNESS is where this goes wrong silently. The core's BigNumber reads and
-- writes LITTLE-endian, so the SHA1 digest becomes an integer least-significant
-- byte first, and the verifier is written out the same way. Get it backwards
-- and every password is wrong, with nothing to indicate why.
--
-- No new dependency: SHA1 and the bignum arithmetic come from libcrypto, which
-- is already on any machine with curl, reached through LuaJIT's own FFI.
--------------------------------------------------------------------------------

local ffi = require("ffi")

local Srp6 = {}

-- {{{ the libcrypto surface used here
ffi.cdef[[
    unsigned char *SHA1(const unsigned char *d, size_t n, unsigned char *md);

    typedef struct bignum_st BIGNUM;
    typedef struct bignum_ctx BN_CTX;

    BIGNUM *BN_new(void);
    void    BN_free(BIGNUM *a);
    BN_CTX *BN_CTX_new(void);
    void    BN_CTX_free(BN_CTX *c);

    BIGNUM *BN_bin2bn(const unsigned char *s, int len, BIGNUM *ret);
    int     BN_bn2binpad(const BIGNUM *a, unsigned char *to, int tolen);
    int     BN_set_word(BIGNUM *a, unsigned long w);
    int     BN_mod_exp(BIGNUM *r, const BIGNUM *a, const BIGNUM *p,
                       const BIGNUM *m, BN_CTX *ctx);
    int     BN_hex2bn(BIGNUM **a, const char *str);
]]

local crypto = ffi.load("crypto")
-- }}}

-- {{{ N and g
-- The SRP prime and generator AzerothCore uses. Not configurable and not ours
-- to choose -- they are baked into the client.
local N_HEX = "894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7"
local G     = 7
-- }}}

-- {{{ sha1(text)
local function sha1(text)
    local digest = ffi.new("unsigned char[20]")
    crypto.SHA1(ffi.cast("const unsigned char *", text), #text, digest)
    return ffi.string(digest, 20)
end
-- }}}

-- {{{ reversed(bytes)
-- Little-endian to big-endian and back. BN_bin2bn reads big-endian; the core
-- writes little-endian; this is the whole of the translation between them.
local function reversed(bytes)
    local out = {}
    for index = #bytes, 1, -1 do
        table.insert(out, bytes:sub(index, index))
    end
    return table.concat(out)
end
-- }}}

-- {{{ Srp6.verifier(username, password, salt)
-- The 32 bytes acore_auth.account.verifier should hold, little-endian, for this
-- username and password against this salt.
--
-- `salt` is the raw 32 bytes as stored, not hex.
function Srp6.verifier(username, password, salt)
    if type(salt) ~= "string" or #salt ~= 32 then
        return nil, string.format(
            "the salt must be the 32 raw bytes from acore_auth.account, got %s "
         .. "of length %d. Read it with HEX(salt) and unhex it, or the compare "
         .. "silently never matches.",
            type(salt), type(salt) == "string" and #salt or 0)
    end

    -- The core upper-cases both before hashing. A password typed in lower case
    -- and one typed in upper case are the same password to this game.
    local inner = sha1(username:upper() .. ":" .. password:upper())
    local outer = sha1(salt .. inner)

    -- The digest becomes an integer LITTLE-endian, so reverse it for
    -- BN_bin2bn, which reads big-endian.
    local ctx = crypto.BN_CTX_new()
    local x   = crypto.BN_bin2bn(ffi.cast("const unsigned char *", reversed(outer)),
                                 20, nil)
    local g   = crypto.BN_new()
    crypto.BN_set_word(g, G)

    local n = ffi.new("BIGNUM*[1]")
    crypto.BN_hex2bn(n, N_HEX)

    local v = crypto.BN_new()
    crypto.BN_mod_exp(v, g, x, n[0], ctx)

    local out = ffi.new("unsigned char[32]")
    crypto.BN_bn2binpad(v, out, 32)

    local big_endian = ffi.string(out, 32)

    crypto.BN_free(v)
    crypto.BN_free(g)
    crypto.BN_free(x)
    crypto.BN_free(n[0])
    crypto.BN_CTX_free(ctx)

    -- Back to little-endian, which is how the column stores it.
    return reversed(big_endian)
end
-- }}}

-- {{{ Srp6.check(handle, username, password)
-- Is this the password for this game account?
--
-- Reads the salt and verifier, recomputes, and compares. Returns true, or false
-- with a reason that does NOT distinguish "no such account" from "wrong
-- password" in its first line -- telling somebody which of the two they got
-- wrong is telling them which usernames exist.
function Srp6.check(handle, username, password)
    local cold = dofile(handle.neuron_root .. "/src/002-cold-hand.lua")

    local rows, why = cold.read(handle, handle.db_auth,
        "SELECT HEX(salt) AS salt, HEX(verifier) AS verifier "
     .. "FROM account WHERE UPPER(username) = UPPER(?)", { username })

    if not rows then
        return nil, "could not reach the account database: " .. tostring(why)
    end

    if #rows == 0 then
        return false, "that username and password do not match an account."
    end

    -- {{{ unhex(text)
    local function unhex(text)
        return (tostring(text):gsub("%x%x", function(pair)
            return string.char(tonumber(pair, 16))
        end))
    end
    -- }}}

    local salt  = unhex(rows[1].salt)
    local stored = unhex(rows[1].verifier)

    local computed, compute_why = Srp6.verifier(username, password, salt)
    if not computed then
        return nil, compute_why
    end

    if computed == stored then
        return true
    end

    return false, "that username and password do not match an account."
end
-- }}}

return Srp6
