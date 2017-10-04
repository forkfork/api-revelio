local restystring = require("resty.string")
local redis = require("resty.redis")
local random = require("resty.random")
local cjson = require("cjson")

local function chunk(str)
  local chunks = {}
  local ptr = 0
  local chunksize = 4096
  local strlen = string.len(str)
  if strlen == 0 then return {""} end
  while ptr < strlen do
    table.insert(chunks, string.sub(str, ptr, ptr + chunksize))
    ptr = ptr + chunksize
  end
  return chunks
end

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
  local req_block, err = red:xrange("reqs", ptr, "+", "count", 100)
  ngx.log(ngx.ERR, err)
  for i = 1, #req_block do
    ptr = req_block[i][1]
    local this_req = req_block[i][2]
		local req_details = get_summary(this_req)
		local id, uri = req_details.id, req_details.uri
    if tonumber(req_details.counter) == 1 and not first_ids[id] then
		  first_ids[id] = ptr
			uris[uri] = uris[uri] or {}
			table.insert(uris[uri], id)
	  end
  end
  return uris, first_ids
end

local function get_uris()
  local red = redis:new()
  red:set_timeout(1000) -- 1 sec
  red:connect("127.0.0.1", 6379)
  local uris, first_ids = scan_logs(red)
  local uri_names = {}
  for k, v in pairs(uris) do
    table.insert(uri_names, k)
  end
  return uri_names
end

local function reqs_for_route(route)
  local red = redis:new()
  red:set_timeout(1000) -- 1 sec
  red:connect("127.0.0.1", 6379)
  local uris, first_ids = scan_logs(red)
  for i = 1, #uris[route] do
    ngx.say(uris[route][i] .. " " .. first_ids[uris[route][i]])
  end
end

local function fetch_request (red, stream_id)
  local ptr = stream_id
	local uri, req, req_id
	local res = ""
  local req_block = red:xrange("reqs", ptr, "+", "count", 10)
  local chunks = {}
  for i = 1, #req_block do
    ptr = req_block[i][1]
    local this_req = req_block[i][2]
		local item = get_summary(this_req)
    req_id = item.id
    local counter = tonumber(item.counter)
    ngx.log(ngx.ERR, "item.id " .. tostring(item.id) .. " req_id " .. tostring(req_id))
    if item.id == req_id then
		  uri = uri or item.uri
			req = req or item.req
      chunks[counter] = chunks[counter] or ""
      chunks[counter] = chunks[counter] .. item.res
      ngx.log(ngx.ERR, "btw item.res is " .. cjson.encode(item))
      ngx.log(ngx.ERR, "btw chunks is " .. cjson.encode(chunks))
      if item.done == "true" then
        break
			end
		end
  end
  for i = 1, #chunks do
    res = res .. chunks[i]
  end
  ngx.log(ngx.ERR, "shit, res is " .. tostring(res))
  return uri, req, res
end

local function dump_req(stream_id, req_id)
  local red = redis:new()
  red:set_timeout(1000) -- 1 sec
  red:connect("127.0.0.1", 6379)
  local uri, req, res = fetch_request(red, stream_id, req_id)
  ngx.say("uri is " .. tostring(uri))
  ngx.say("req body is " .. tostring(req))
  ngx.say("res body is " .. tostring(res))
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

local function push_logs(premature, req_id, uri, req_body, counter, res_body, res_done)
  ngx.log(ngx.ERR, "EOF2 " .. tostring(res_done) .. " COUNTER " .. tostring(counter))
  local red = redis:new()
  red:set_timeout(1000) -- 1 sec
  red:connect("127.0.0.1", 6379)
  if is_blacklisted(red, uri) then
    return
  end
  
  local chunks = chunk(res_body)
  ngx.log(ngx.ERR, "CHUNKS IS " .. tostring(#chunks))
  for i = 1, #chunks do
    red:xadd("reqs", "maxlen", 9000, "*",
      "id", req_id,
      "uri", uri,
      "req", req_body,
      "res", chunks[i],
      "counter", counter,
      "done", i == #chunks and res_done or false)
  end
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
_M.get_uris = get_uris
_M.reqs_for_route = reqs_for_route
_M.dump_req = dump_req

return _M
