local _M = {}

local redis = require("resty.redis")

local ALGORITHMS = {
    ['token-bucket'] = 'redis.token_bucket',
    ['sliding-window'] = 'redis.sliding_window',
    ['leaky-bucket'] = 'redis.leaky_bucket',
    ['fixed-window'] = 'redis.fixed_window'
}

function _M.get_cached_script(red, ngx, script_name, script)
    local redis_scripts_cache = ngx.shared.redis_scripts_cache
    local script_sha = redis_scripts_cache:get(script_name)

    if not script_sha then
        local sha, err = red:script("load", script)
        if not sha then
            ngx.log(ngx.ERR, "Failed to load script into Redis: ", err)
            return false
        end
        redis_scripts_cache:set(script_name, sha)
        script_sha = sha
    end

    return script_sha
end

function _M.connect(ngx, host, port)
    local red = redis:new()
    red:set_timeout(50)

    local ok, err = red:connect(host, port)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect to Redis: ", err)
        return nil
    end

    return red
end


function _M.throttle(ngx, cache_key, rule)
    local red = _M.connect(ngx, os.getenv('CACHE_HOST'), tonumber(os.getenv('CACHE_PORT')))
    if not red then return false end

    local algorithm = os.getenv('CACHE_ALGO') or 'sliding-window'

    if not ALGORITHMS[algorithm] then
        ngx.log(ngx.ERR, "Rate-limiting algorithm not found: " .. algorithm)
        return false
    end

    local module = require(ALGORITHMS[algorithm])

    return module.throttle(red, ngx, cache_key, rule)
end

return _M
