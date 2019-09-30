local fbase = require("filter_base")

local function filter()
    -- body
    local request_method = ngx.var.request_method
    if "PUT" == request_method then
        -- body
        local headers = ngx.req.get_headers()
        local authorization = nil
        for k, v in pairs(headers) do
            -- get sign
            if string.lower(k) == "authorization" then
                authorization = v
                ngx.log(ngx.DEBUG, "origin-sign:" .. v)
            end
        end
        local uri = ngx.var.uri
        local ks = fbase.get_ks(headers, authorization, uri)
        local objectName = string.sub(uri, 2, -1)
        -- local bucket = filter_base.get_bucket(ngx.var.host)
        local bucket = os.getenv('DATAGATE_BUCKET')
        local sign = fbase.make_signature(headers, objectName, bucket,
                                                ks['secret'])
        ngx.req.set_header("authorization", "OSS " .. ks['key'] .. ":" .. sign)

        ngx.log(ngx.DEBUG, "new-sign:" .. sign)

    end
end

return filter()
