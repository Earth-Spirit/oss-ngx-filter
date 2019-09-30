local _M = {_VERSION = '1.0.0'}

local function split(str, reps)
    local resultStrList = {}
    string.gsub(str, '[^' .. reps .. ']+',
                function(w) table.insert(resultStrList, w) end)
    return resultStrList
end

local function startswith(str, substr)
    if str == nil or substr == nil then return nil end

    if string.find(str, substr) ~= 1 then
        return false
    else
        return true
    end

end

local function redis_get_value(key)
    if key == nil or key == '' then
        ngx.log(ngx.ERR, key .. " is nil or ''")
        return ""
    end

    local redis = require("lib.resty.redis")
    local red = redis:new()

    local host = os.getenv('DATAGATE_REDIS_HOST')
    local port = os.getenv('DATAGATE_REDIS_PORT')
    local pwd = os.getenv('DATAGATE_REDIS_PWD')
    red:set_timeout(1000)

    local ok, err = red:connect(host, tonumber(port))
    if not ok then
        ngx.log(ngx.ERR, "failed to connect: " .. err)
        return ""
    end
    if pwd ~= '' and pwd ~= nil then red:auth(pwd) end

    -- ok, err = red:set("dog", "an animal")
    -- if not ok then
    --     ngx.say("failed to set dog: ", err)
    --     return
    -- end

    local res, err = red:get(key)
    if not res then
        ngx.log(ngx.ERR, "failed to get : " .. key)
        return ""
    end

    if res == ngx.null then
        ngx.log(ngx.ERR, key .. " not found")
        ngx.exit(401)
        return ""
    end

    -- or just close the connection right away:
    local ok, err = red:close()
    if not ok then
        ngx.say("failed to close: ", err)
        return
    end

    return res
end

local function get_username(token)
    return redis_get_value('DataGate:TokenToUser:' .. token)
end

local function get_bucketname(token)
    return redis_get_value('DataGate:TokenToBucket:' .. token)
end

local function get_secret(key)
    return redis_get_value('DataGate:KeyToSecret:' .. key)
end

local function param_to_query(k, v)
    if v then
        return k .. '=' .. v
    else
        return k
    end
end

local function get_resource_string(bucket, objectName)
    if bucket == nil then
        return "/"
    else
        -- '/{0}/{1}{2}'.format(key, bucket_name, "")
        return '/' .. bucket .. '/' .. objectName
    end
end

local function get_headers_string(headers)

    local canon_headers = {}
    for k, v in pairs(headers) do
        local lower_key = string.lower(k)
        if startswith(lower_key, "x-oss-") then
            canon_headers[lower_key] = v
        end
    end

    table.sort(canon_headers)

    if canon_headers == nil then
        return ""
    else

        local params_string = "?"
        for i, v in pairs(canon_headers) do
            if params_string == "?" then
                params_string = params_string .. param_to_query(k, v)
            else
                params_string = params_string .. "&" .. param_to_query(k, v)
            end
        end

        if params_string == "?" then
            return ''
        else
            return params_string
        end
    end
end

local function format_v(v)
    if v == nil then
        return ''
    else
        return v
    end
end

local function get_string_to_sign(headers, objectName, bucket)

    local resource_string = format_v(get_resource_string(bucket, objectName))
    local headers_string = format_v(get_headers_string(headers))

    local content_md5 = format_v(headers['content-md5'])
    local content_type = format_v(headers['content-type'])
    local date = format_v(headers['date'])

    return
        "PUT" .. "\n" .. content_md5 .. "\n" .. content_type .. "\n" .. date ..
            "\n" .. headers_string .. resource_string
end

local function format_log(username, filetype, client, request, host)

    ngx.ctx["username"] = username
    ngx.ctx["filetype"] = filetype
    ngx.ctx["client"] = client
    ngx.ctx["request"] = request
    ngx.ctx["host"] = host

end

function _M.get_ks(headers, authorization, filename)
    -- body get key,secret
    ngx.log(ngx.DEBUG, "authorization:" .. authorization)
    ngx.log(ngx.DEBUG, "filename:" .. filename)
    local result = string.gsub(authorization, "OSS ", "")
    local key = nil
    if string.find(authorization, "@") ~= nil then

        local value = split(split(result, ":")[1], "@")
        key = value[1]
        local token = value[2]
        ngx.log(ngx.DEBUG, "key:" .. key)
        ngx.log(ngx.DEBUG, "token:" .. token)

        local username = get_username(token)
        local token_bucket = get_bucketname(token)
        if username == nil then
            -- body
            ngx.exit(401)
        elseif token_bucket !=  get_bucket(ngx.var.host) then
            -- body
            ngx.exit(403)
        else
            -- log username filename
            ngx.log(ngx.DEBUG, '-- log username filename:' .. filename)
            
            ngx.ctx['date'] = headers['date']
            ngx.ctx['logtime'] = ngx.parse_http_time(headers['date'])
            ngx.ctx["username"] = username
            ngx.ctx["filetype"] = format_v(headers['content-type'])
            ngx.ctx["client"] = ngx.var.remote_addr
            ngx.ctx["request"] = ngx.var.uri
            ngx.ctx["host"] = headers['host']

        end
    else
        -- ngx.say("token error")
        ngx.exit(401)
    end

    local keytable = {}
    keytable["key"] = key
    keytable["secret"] = get_secret(key)

    return keytable
end

function _M.make_signature(headers, objectName, bucket, secret)
    local string_to_sign = get_string_to_sign(headers, objectName, bucket)
    ngx.log(ngx.DEBUG,
            "--------Make signature: string to be signed:" .. string_to_sign)

    -- hmac.new(to_bytes(secret), to_bytes(string_to_sign), hashlib.sha1)
    -- b64encode_as_string(h.digest())

    local digest = ngx.hmac_sha1(secret, string_to_sign)
    return ngx.encode_base64(digest)
end

function _M.get_bucket(host)
    -- body
    local bucket = split(host, '.')[1]
    return bucket
end

return _M