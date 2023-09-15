--
-- Simple Barco Clickshare control driver
-- Originally written by Jeff Kettell in 2018, rewritten by Jeff Kettell in 2023
-- 
-- Having installed many Clickshare units, i found some would remain usable after months or years of uptime, 
-- while some needed frequent reboots. Additionally, direct control of standby state fixed issues with certain video switches 
-- not seeing a signal on the input when the CS was selected.
--
-- scheduling a weekly reboot and controlling standby made the user experience far more reliable in rooms with video switches.
--
-- The Clickshare API has far more functionality than is included in this driver, but I found no real need to control other features.
-- If you'd like to see a feature added, please bring it to my attention on my github page (github.com/JPKDigital)



C4:AddVariable("Current Uptime", "", "STRING")
C4:AddVariable("Device In Use", "", "BOOL")
C4:AddVariable("Device Currently Sharing", "", "BOOL")

ClickShareIp = ClickShareIp or ""
CsApiPw = CsApiPw or ""
pollInterval = pollInterval or 30
debug = false

function OnDriverInit()
    ClickShareIp = Properties["ClickShare IP Address"]
    CsApiPw = Properties["ClickShare API Password"]
   
end

function OnDriverLateInit()
	local t = C4:SetTimer(20000, function(timer) startPollTimer() end)
	dbg("Polling Timer Started")
end

function OnPropertyChanged(propName)
    propValue = Properties[propName]
    if propName == "ClickShare IP Address" then ClickShareIp = propValue  end
    if propName == "ClickShare API Password" then CsApiPw = propValue  end
	if propName == "Polling Interval Seconds" then 
		pollInterval = propValue 
		startPollTimer()
	end
    if propName == "Debug Mode" then
		if propValue == "ON" then
			debug = true
			print("Debug mode ON")
		elseif propValue == "OFF" then
			debug = false
			print("Debug mode OFF")
		end
	end
end

function ExecuteCommand(command, params)
    dbg("ExecuteCommand: " .. command)
    if command == "LUA_ACTION" then
	   if params.ACTION == "getStatusCS" then getStatusCS() end
	   if params.ACTION == "standbyCS" then standbyCS() end
	   if params.ACTION == "wakeFromStandbyCS" then wakeFromStandbyCS() end
	   if params.ACTION == "rebootCS" then rebootCS() end
    
    elseif params == nil then
	   dbg(command)
	   if command == "Reboot Clickshare" then 
		  rebootCS() 
	   elseif command == "Get ClickShare Uptime" then
		  getStatusCS()
	   end
	   
    elseif (params ~= nil) then
 	   for k,v in pairs(params) do
		  dbg(k,v) 
		  if command == "ClickShare Standby" then
			 if v == "True" then standbyCS() end
			 if v == "False" then wakeFromStandbyCS() end
		  end
	   end
    end
end

--
-- Device Command functions
--

function rebootCS()
    dbg("Rebooting Clickshare unit @ " .. ClickShareIp)
    local cmd = "https://" .. ClickShareIp .. ":4003/v2/operations/reboot"
    --local value = "value=true"
    sendPost(cmd, "")
end

function standbyCS()
    dbg("Setting Clickshare to Standby")
    local cmd = "https://" .. ClickShareIp .. ":4003/v2/operations/standby"
    --local value = "value=true"
    dbg(cmd)
    sendPost(cmd, "")
end

function wakeFromStandbyCS()
    dbg("Waking Clickshare from Standby")
    local cmd = "https://" .. ClickShareIp .. ":4003/v2/operations/wakeup"
    --local value = "value=false"
    sendPost(cmd, "")
end



function getStatusCS()
    dbg("Getting Current ClickShare Uptime")
    local cmd = "https://" ..  ClickShareIp .. ":4003/v2/configuration/system/status"
    sendGet(cmd, "")

end

--
-- Helpers
--
function startPollTimer()
	--dbg(pollTimer)
	pollTimer = C4:AddTimer(pollInterval, "SECONDS", true)
end

function OnTimerExpired(idTimer)
    if (idTimer == pollTimer) then
        --dbg("Timer fired")
		getStatusCS()
              
       end
end

function OnDriverDestroyed()
	C4:KillTimer(pollTimer)
end

function setAuthString()
    authStr = C4:Base64Encode("admin:" .. CsApiPw)
    dbg("Authentication String Updated, is now : " .. authStr)
    return authStr
end

function ReceivedAsync(ticketId, dataRx)
    dbg(ticketId)
	dbg(dataRx)
    local data = C4:JsonDecode(dataRx)
    for k,v in pairs(data) do dbg(k,v) end 
    local upTime = parseUptime(data)

end


function parseGet(data)

    --for k,v in pairs(data) do dbg("DATA : " ..k .. "-" .. tostring(v)) end 

    if data.currentUptime ~= nil then
	   local time = uptimeFormat(data.currentUptime) 
	   C4:UpdateProperty("ClickShare Uptime", time)
	   C4:SetVariable("Current Uptime",time)
    else
	   dbg("parseGet Data Invalid")
    end
    
    if tostring(data.inUse) == "true" then
	   C4:UpdateProperty("ClickShare Currently In Use?", "True")
	   C4:SetVariable("Device In Use", 1)
    elseif tostring(data.inUse) == "false" then
	   C4:UpdateProperty("ClickShare Currently In Use?", "False")
	   C4:SetVariable("Device In Use", 0)
    end
    
    if tostring(data.sharing) == "true" then
	   C4:UpdateProperty("ClickShare Currently Sharing?", "True")
	   C4:SetVariable("Device Currenly Sharing", 1)
    elseif tostring(data.sharing) == "false" then
	   C4:UpdateProperty("ClickShare Currently Sharing?", "False")
	   C4:SetVariable("Device Currently Sharing", 0)
    end
end


function uptimeFormat(time)
  local days = math.floor(time/86400)
  local hours = math.floor(math.mod(time, 86400)/3600)
  local minutes = math.floor(math.mod(time,3600)/60)
  local seconds = math.floor(math.mod(time,60))
  return string.format("%d:%02d:%02d:%02d",days,hours,minutes,seconds)
end



-- 
-- C4 URL functions
--

function sendGet(url)
    local authString = setAuthString()
    local responseTable = {}
    local header = {
	    ["Content-Type"] = "text/plain", 
	    ["Authorization"] = "Basic " .. authString .. "", 
	    ["accept"] = "application/json"}
    
   
    local get = C4:url()
    
    :OnDone(
	 function(transfer, responses, errCode, errMsg)
	  if (errCode == 0) then
	   local lresp = responses[#responses]
	   responseTable = C4:JsonDecode(lresp.body)
	   parseGet(responseTable)
	   --for k,v in pairs(responseTable) do dbg(k,v) end
	   dbg("OnDone: transfer succeeded (" .. #responses .. " responses received), last response code: " .. lresp.code)
	   for hdr,val in pairs(lresp.headers) do
	    dbg("OnDone: " .. hdr .. " = " .. val)
	   end
	   dbg("OnDone: body of last response: " ..tostring(lresp.body))
    
    

	  else
	   if (errCode == -1) then
		  dbg("OnDone: transfer was aborted")
	   else
		  dbg("OnDone: transfer failed with error " .. errCode .. ": " .. errMsg .. " (" .. #responses .. " responses completed)")
	   end
	  end
	 end)
	 
	:SetOptions({
	 ["fail_on_error"] = false,
        ["ssl_verify_host"] = false,
        ["ssl_verify_peer"] = false,
	 ["timeout"] = 10,
	 ["connect_timeout"] = 5
	})

	:Get(url, header)
    dbg("scheduled url transfer with id " .. get:TicketId())
    
    
end


function sendPost(url, data)
    local authString = setAuthString()
    local responseTable = {}
    local header = {
	    ["Content-Type"] = "text/plain", 
	    ["Authorization"] = "Basic " .. authString .. "", 
	    ["accept"] = "application/json"}
    
   
    local post = C4:url()
    
    :OnDone(
	 function(transfer, responses, errCode, errMsg)
	 	if (errCode == 0) then
	  	local lresp = responses[#responses]
	  	responseTable = C4:JsonDecode(lresp.body)
	  	parseGet(responseTable)
	  	--for k,v in pairs(responseTable) do dbg(k,v) end
	  	dbg("OnDone: transfer succeeded (" .. #responses .. " responses received), last response code: " .. lresp.code)
	   	for hdr,val in pairs(lresp.headers) do
		dbg("OnDone: " .. hdr .. " = " .. val)
	  	 end
	   	dbg("OnDone: body of last response: " ..tostring(lresp.body))
    
    

	  else
	   if (errCode == -1) then
		  dbg("OnDone: transfer was aborted")
	   else
		  dbg("OnDone: transfer failed with error " .. errCode .. ": " .. errMsg .. " (" .. #responses .. " responses completed)")
	   end
	  end
	 end)
	 
	:SetOptions({
	   ["fail_on_error"] = false,
        ["ssl_verify_host"] = false,
        ["ssl_verify_peer"] = false,
	   ["timeout"] = 10,
	   ["connect_timeout"] = 5
	})

	:Post(url, data, header)

    dbg("scheduled url transfer with id " .. post:TicketId())
    
    
end




-- Debug

function dbg(msg)
	if debug then
		local timeStamp = os.date("%I:%M:%S %p")
		debugMsg = timeStamp .. " " .. msg
		print(debugMsg)
	end
end
