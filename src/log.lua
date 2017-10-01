local restystring = require("resty.string")
local redis = require("resty.redis")
local random = require("resty.random")
local cjson = require("cjson")

local function new_id()
  local bytes = random.bytes(8)
  local hexbytes = restystring.to_hex(bytes)
  return hexbytes
end

local function get_summary(item)
  local req_details = {}
  for i = 1, #item, 2 do
	  req_details[item[i]] = item[i+1]
  end
	return req_details
end

local function scan_logs(red)
  local ptr = "0"
	local first_ids = {}
	local uris = {}
  local req_block = red:xrange("reqs", ptr, "+", "count", 100)
  for i = 1, #req_block do
    ptr = req_block[i][1]
    local this_req = req_block[i][2]
		local req_details = get_summary(this_req)
		local id, uri = req_details.id, req_details.uri
		if not first_ids[id] then
		  first_ids[id] = ptr
			uris[uri] = uris[uri] or {}
			table.insert(uris[uri], id)
	  end
  end
	for k, v in pairs(uris) do
	  print(k)
	end
	for i = 1, #uris["/api"] do
	  local req = uris["/api"][i]
		return first_ids[req]
	end
end

local function fetch_request (red, stream_id, req_id)
  local ptr = stream_id
	local uri, req
	local res = ""
  local req_block = red:xrange("reqs", ptr, "+", "count", 4)
  for i = 1, #req_block do
    ptr = req_block[i][1]
    local this_req = req_block[i][2]
		local item = get_summary(this_req)
		print(item.id, stream_id)
    if item.id == req_id then
		  print(cjson.encode(item))
		  uri = uri or item.uri
			req = req or item.req
			res = res .. item.res
      if item.done == "true" then
			  return uri, req, res
			end
		end
  end
  
end

local function is_blacklisted(red, uri)
  local blocked_urls = red:lrange("urlblacklist", 0, -1)
  if blocked_urls then
    for i = 1, #blocked_urls do
      if uri == blocked_urls[i] then
        return true
     end
    end
  end
  return false
end

local function push_logs(premature, req_id, uri, req_body, res_body, res_done)
  local red = redis:new()
  red:set_timeout(1000) -- 1 sec
  red:connect("127.0.0.1", 6379)
  if is_blacklisted(red, uri) then
    return
  end
  
  local a, b = red:xadd("reqs", "maxlen", 9000, "*",
	         "id", req_id,
           "uri", uri,
           "req", req_body,
           "res", res_body,
           "done", res_done)
end

local bleh = [[
local red = redis:new()
red:set_timeout(1000) -- 1 sec
red:connect("127.0.0.1", 6379)
red:del("reqs")
local id = new_id()
push_logs(false, id, "/api", "reqreq", "resres1 ", false)
push_logs(false, id, "/api", "reqreq", "resres2", true)
--push_logs(false, new_id(), "/api", "reqreq", "resres", true)
push_logs(false, new_id(), "/poop", "reqreq", "resres", true)
local first_id = scan_logs(red)
print("first_id is ", first_id)
print(fetch_request(red, first_id, id))
]]
local _M = {}


-- ngx.timer.at(0, push_logs, ngx.var.uri, ngx.var.request_body, ngx.arg[1], ngx.arg[2])

_M.push_logs = push_logs
_M.new_id = new_id

return _M
