local random = require("resty.random")
local restystring = require("resty.string")
local redis = require("resty.redis")

local function new_req()
  local bytes = random.bytes(8)
  local hexbytes = restystring.to_hex(bytes)
  return hexbytes
end

local function push_logs(premature, req_id, uri, req_body, res_body, res_done)
  local red = redis:new()

  red:set_timeout(1000) -- 1 sec
  red:connect("127.0.0.1", 6379)
  red:xadd("reqs", "*", "id", req_id, "uri", tostring(uri), "req_body", tostring(req_body), "res_body", res_body, "res_done", tostring(res_done))
    
end
if ngx.var.uri == "/api/public-offers" then
  ngx.log(ngx.ERR, ngx.arg[1])
end
ngx.timer.at(0, push_logs, ngx.var.uri, ngx.var.request_body, ngx.arg[1], ngx.arg[2])
notes = [[
  on req
    gen id
    stream callbacks stitched with id
  reading from stuff
    list reqs for url prefix
  kill a req
    post to /poison
      get /api/foo
  access_by_lua
    lpop verb url
]]