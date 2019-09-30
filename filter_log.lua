local cjson = require "cjson.safe"
local logger = require "lib.resty.logger.socket"

if not logger.initted() then
    local ok, err = logger.init{
        host = "127.0.0.1", -- 部署时,需要填写logserver服务器ip
        port = 4000, -- 部署时,需要填写logserver服务器port
        sock_type = "tcp", -- 采用udp传输
        flush_limit = 1, -- 1就是时实传输,
        -- drop_limit = 5678, --默认1mb 超过会自动删除
        timeout = 10000, -- 超时设置
        pool_size = 100 -- 连接池大小
    }
    if not ok then
        ngx.log(ngx.ERR, "failed to initialize the logger: ", err)
        return
    end
end

local resp_headers = ngx.req.get_headers()
ngx.log(ngx.DEBUG, "response------headers" .. resp_headers)

ngx.ctx["contentMD5"] = resp_headers["Content-MD5"]
ngx.ctx["eTag"] = resp_headers["ETag"]
ngx.ctx["xOSSRequestId"] = resp_headers["x-oss-request-id"]

local cjson2 = cjson.new()
local msg = cjosn2.encode(ngx.ctx) .. "\n"

ngx.log(ngx.INFO, msg)

local bytes, err = logger.log(msg)


if err then
    ngx.log(ngx.ERR, "failed to log message: ", err)
    return
end



-- local status, retval = xpcall(logger.log,debug.traceback,msg)

-- ngx.log(ngx.DEBUG,status)
-- ngx.log(ngx.DEBUG,retval)
