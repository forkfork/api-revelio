local random = require("resty.random")
local restystring = require("resty.string")
local redis = require("resty.redis")

local function new_id()
  local bytes = random.bytes(8)
  local hexbytes = restystring.to_hex(bytes)
  return hexbytes
end

print(new_id())

local function push_logs(premature, req_id, uri, req_body, res_body, res_done)
  local red = redis:new()

  red:set_timeout(1000) -- 1 sec
  red:connect("127.0.0.1", 6379)
  if red:xlen("reqs") > 9000 then
    red:del("reqs")
  end
  red:xadd("reqs", "*", "id", req_id, "uri", tostring(uri), 
           "req_body", tostring(req_body), "res_body", res_body,
	   "res_done", tostring(res_done))
    
end

push_logs(false, new_id(), "/api", "reqreq", "resres", true)

-- ngx.timer.at(0, push_logs, ngx.var.uri, ngx.var.request_body, ngx.arg[1], ngx.arg[2])
local notes = [[
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
