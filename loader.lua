-- Bloxbot Free: Panda keys, GitHub updates.
local factories,cache={},{}
local function import(name) if cache[name]==nil then cache[name]=factories[name]() end;return cache[name] end
factories.ExecutorCompat=function()
local Compat={};local checked=nil
function Compat.get()
 if checked then return checked end
 local crypto=crypt or (syn and syn.crypt)
 assert(type(crypto)=='table'and type(crypto.decrypt)=='function','This executor needs AES-CBC support')
 assert(type(buffer)=='table'and type(buffer.create)=='function'and type(buffer.readf32)=='function','Update your executor to a build with Luau buffer support')
 local function normalize(digest)
  assert(type(digest)=='string','SHA-256 returned invalid data')
  if #digest==32 then digest=(digest:gsub('.',function(c)return string.format('%02x',string.byte(c))end))end
  digest=digest:lower();assert(#digest==64 and digest:match('^[a-f0-9]+$'),'Executor SHA-256 returned invalid data');return digest
 end
 local nativeHash=nil;local hashPath='executor-sha256'
 local nativeOk,candidate=pcall(function()
  local encoding=game:GetService('EncodingService');local algorithm=Enum.HashAlgorithm.Sha256
  local fn=function(raw)return normalize(encoding:ComputeStringHash(raw,algorithm))end
  assert(fn('abc')=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad','Engine SHA-256 differs')
  assert(fn('')=='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855','Engine empty SHA-256 differs')
  return fn
 end)
 if nativeOk then nativeHash=candidate;hashPath='engine-sha256'end
 local function hash(raw)
  if nativeHash then local ok,digest=pcall(nativeHash,raw);if ok then return digest end;nativeHash=nil;hashPath='executor-sha256';if checked then checked.hash_path=hashPath end end
  assert(type(crypto.hash)=='function','This executor needs SHA-256 support');return normalize(crypto.hash(raw,'sha256'))
 end
 assert(hash('abc')=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad','Executor SHA-256 implementation differs')
 -- Verify a public AES-256-CBC known answer before selecting a mode. Some
 -- implementations silently accept an unknown mode and return wrong bytes.
 local mode=nil
 for _,candidate in ipairs({'CBC','cbc'})do
  local ok,value=pcall(crypto.decrypt,'WJP1EnJoVNPaeBik/tKCIsqHDKWb8O9KLGSJYXaHCRU=','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=','AAAAAAAAAAAAAAAAAAAAAA==',candidate)
  if ok and value=='BloxBot AES probe'then mode=candidate;break end
 end
 assert(mode,'Executor AES-CBC implementation differs')
 local function decrypt(raw,key,iv)
  return crypto.decrypt(raw,key,iv,mode)
 end
 local fetch=request or http_request or(http and http.request)or(syn and syn.request)or(fluxus and fluxus.request)
 assert(type(fetch)=='function','This executor needs HTTP request support')
 local function normalizedFetch(options)
  local response=fetch(options);assert(type(response)=='table','Executor HTTP request returned invalid data')
  local status=response.StatusCode or response.Status or response.status_code or response.status
  local body=response.Body or response.body
  assert(type(status)=='number'and type(body)=='string','Executor HTTP response format differs')
  return {StatusCode=status,Body=body,Headers=response.Headers or response.headers}
 end
 checked={hash=hash,hash_path=hashPath,decrypt=decrypt,fetch=normalizedFetch,encrypt=type(crypto.encrypt)=='function'and function(raw,key,iv)return crypto.encrypt(raw,key,iv,mode)end or nil}
 return checked
end
function Compat.mobile()
 local ok,input=pcall(function()return game:GetService('UserInputService')end)
 return ok and input.TouchEnabled==true
end
return Compat

end
factories.ServerSession=function()
-- Short server-verified leases survive a broken executor SDK heartbeat.
-- Every renewal rechecks Panda's key, HWID, expiry, service and blacklist.
local Session={};Session.__index=Session
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
function Session.new(options)
 local self=setmetatable({options=options,clock=options.clock or os.clock,deadline=0,renewAt=0,alive=true,busy=false,epoch=0,failures=0,reason='Checking Panda…'},Session)
 -- The SDK-facing surface uses dot calls, matching Panda's standalone API.
 self.isConnected=function()self:poll();return self.alive and self.clock()<self.deadline end
 self.isExpired=function()return not self.alive or self.clock()>=self.deadline end
 self.getTimeLeft=function()return math.max(0,math.ceil(self.deadline-self.clock()))end
 self.getSessionMessage=function()return self.reason end
 self.disconnect=function()self:close()end
 if options.heartbeat then self.connection=options.heartbeat:Connect(function()self:poll()end)end
 return self
end
function Session:accept(key,grant,started)
 assert(self.alive and type(key)=='string','Session is closed')
 local lease,renew=grant.lease_seconds,grant.renew_after_seconds
 assert(finite(lease)and lease>0 and lease<=90 and finite(renew)and renew>0 and renew<=30 and renew<lease,'Panda lease response differs')
 assert(finite(started)and started<=self.clock()and started+lease>self.clock(),'Panda reply took too long. Retry.')
 self.key=key;self.deadline=started+lease;self.renewAt=started+renew;self.failures=0;self.reason='Panda connected'
end
function Session:poll()
 if not self.alive or not self.key or self.busy or self.clock()<self.renewAt then return end
 self.busy=true;local epoch=self.epoch;local key=self.key
 local spawn=self.options.spawn or task.spawn
 spawn(function()
  local began=self.clock();local ok,status,grant=pcall(self.options.renew,key)
  if not self.alive or epoch~=self.epoch then return end
  self.busy=false
  if ok and status==200 then
   local accepted=pcall(function()self:accept(key,grant,began)end)
   if accepted then return end
  elseif ok and(status==403 or status==409)then
   self.deadline=0;self.key=nil
   self.reason=status==409 and 'Update available. Run the loader again.'or 'Key expired or revoked. Get a new Panda key.'
   if status==403 and self.options.onRejected then pcall(self.options.onRejected)end
   return
  end
  self.failures+=1;self.renewAt=self.clock()+math.min(20,2^math.min(4,self.failures))
  self.reason=self.clock()<self.deadline and 'Panda reconnecting…'or 'Connection interrupted. Reconnecting to Panda…'
 end)
end
function Session:close()
 if not self.alive then return end
 self.alive=false;self.epoch+=1;self.key=nil;self.deadline=0;self.reason='Session closed'
 if self.connection then self.connection:Disconnect();self.connection=nil end
 for _,connection in ipairs(self.owned or {})do connection:Disconnect()end;self.owned={}
end
function Session:own(connection)self.owned=self.owned or {};self.owned[#self.owned+1]=connection end
return Session

end
factories.SavedKey=function()
-- Convenience storage bound to the executor's device ID. Local device access
-- can recover it; the server always checks the saved key again before access.
local Saved={};Saved.__index=Saved
local PATH='BloxBotFreeCache-v1/key-v1.json'
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64(raw)
 local result={}
 for i=1,#raw,3 do
  local a,b,c=string.byte(raw,i,i+2);local n=a*65536+(b or 0)*256+(c or 0)
  result[#result+1]=alphabet:sub(math.floor(n/262144)+1,math.floor(n/262144)+1)..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1)or '=')..(c and alphabet:sub(n%64+1,n%64+1)or '=')
 end
 return table.concat(result)
end
local function valid(key)return type(key)=='string'and key:match('^PANDA%-%w%w%w%w%-%w%w%w%w%-%w%w%w%w%-%w%w%w%w$')~=nil end
local models={['mechanoid']=true,['wolvot-v3']=true,['ripple-v1-0']=true,['ripple-v1-1']=true}
local function resumeState(value)
 if type(value)~='table'or not models[value.id]or(value.game~='Turbo Soccer'and value.game~='Blox League')or value.autoQueue~=true or type(value.skipReplay)~='boolean'then return nil end
 return {id=value.id,game=value.game,autoQueue=true,skipReplay=value.skipReplay}
end
function Saved.new(transport,hwid,api)
 api=api or {read=readfile,write=writefile,folder=makefolder,remove=delfile,http=game:GetService('HttpService')}
 return setmetatable({api=api,transport=transport,key=b64(transport.hash('BloxBot saved key v1:'..hwid):sub(1,32))},Saved)
end
function Saved:read()
 if type(self.api.read)~='function'then return nil end
 local ok,value=pcall(function()
  local text=self.api.read(PATH);assert(type(text)=='string'and #text<=1024)
  local row=self.api.http:JSONDecode(text);assert(row.version==1 and type(row.cipher)=='string'and #row.cipher<=256 and type(row.iv)=='string'and #row.iv==24)
  assert(self.transport.hash(row.iv..row.cipher)==row.sha256)
  local key=self.transport.decrypt(row.cipher,self.key,row.iv);assert(valid(key));return {key=key,resume=resumeState(row.resume)}
 end)
 if ok then return value.key,value.resume end
 return nil
end
function Saved:write(key,resume)
 if not valid(key)or type(self.api.write)~='function'or type(self.transport.encrypt)~='function'then return false end
 return pcall(function()
  if type(self.api.folder)=='function'then pcall(self.api.folder,'BloxBotFreeCache-v1')end
  local guid=self.api.http:GenerateGUID(false):gsub('-','');assert(#guid==32)
  local iv=b64((guid:gsub('..',function(pair)return string.char(tonumber(pair,16))end)))
  local cipher=self.transport.encrypt(key,self.key,iv);assert(type(cipher)=='string'and #cipher<=256 and self.transport.decrypt(cipher,self.key,iv)==key)
  local row={version=1,cipher=cipher,iv=iv,sha256=self.transport.hash(iv..cipher),resume=resumeState(resume)}
  assert(self.api.write(PATH,self.api.http:JSONEncode(row))~=false)
 end)
end
function Saved:prepareTeleport(resume)local key=self:read();if key then return self:write(key,resume)end;return false end
function Saved:clear()if type(self.api.remove)=='function'then pcall(self.api.remove,PATH)end end
return Saved

end
factories.GitHubMain=function()
-- Public bootstrap. Panda handles keys; the catalog stays behind server checks.
local Compat=import("ExecutorCompat")
local ServerSession=import("ServerSession")
local SavedKey=import("SavedKey")
local config=import("ReleaseConfig")
return function()
 local env=type(getgenv)=='function'and getgenv()or _G
 for _,name in ipairs({'BloxBotFreeLuau','BloxBotFreeLogin'})do local previous=env[name];if type(previous)=='table'and type(previous.destroy)=='function'then pcall(previous.destroy,true)end end
 local player=game:GetService('Players').LocalPlayer;assert(player,'Join a game before running Bloxbot')
 local http=game:GetService('HttpService');local input=game:GetService('UserInputService');local guiService=game:GetService('GuiService')
 local transport=Compat.get();local alive,busy,transferred=true,false,false;local sdk,session,saved,hwid=nil,nil,nil,nil;local connections={}
 local function fetch(url,method,body)
  local reply=transport.fetch({Url=url,Method=method or 'GET',Headers={Accept='application/json',['Content-Type']='application/json',['User-Agent']='Bloxbot/1.0',['Cache-Control']='no-cache'},Body=body,Timeout=20})
  assert(reply.StatusCode==200,'Connection interrupted. Please try again.');return reply.Body
 end
 local function create(kind,properties,parent)local n=Instance.new(kind);for k,v in pairs(properties)do n[k]=v end;n.Parent=parent;return n end
 local parent=player:FindFirstChildOfClass('PlayerGui')or player:WaitForChild('PlayerGui',10)
 if type(gethui)=='function'then local ok,node=pcall(gethui);if ok and typeof(node)=='Instance'then parent=node end end
 local gui=create('ScreenGui',{Name='BloxBotFreeLogin',ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=1000,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},parent)
 local panel=create('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(360,292),BackgroundColor3=Color3.fromRGB(18,19,26),BorderSizePixel=0},gui)
 create('UICorner',{CornerRadius=UDim.new(0,12)},panel);create('UIStroke',{Color=Color3.fromRGB(46,48,60)},panel)
 local scale=create('UIScale',{Scale=1},panel)
 local function resize()
  local camera=workspace.CurrentCamera;if not camera then return end
  local top,bottom=guiService:GetGuiInset();local v=camera.ViewportSize
  scale.Scale=math.max(.2,math.min(1,(v.X-top.X-bottom.X-20)/360,(v.Y-top.Y-bottom.Y-20)/292))
  panel.Position=UDim2.fromOffset((top.X+v.X-bottom.X)/2,(top.Y+v.Y-bottom.Y)/2)
 end
 local function connect(signal,fn)local c=signal:Connect(fn);table.insert(connections,c);return c end
 local cameraConnection=nil
 local function bindCamera()if cameraConnection then cameraConnection:Disconnect()end;local c=workspace.CurrentCamera;if c then cameraConnection=c:GetPropertyChangedSignal('ViewportSize'):Connect(resize)end;resize()end
 connect(workspace:GetPropertyChangedSignal('CurrentCamera'),bindCamera);bindCamera()
 local function label(text,y,height,size,color)return create('TextLabel',{Position=UDim2.fromOffset(18,y),Size=UDim2.new(1,-36,0,height),BackgroundTransparency=1,Text=text,Font=Enum.Font.Gotham,TextSize=size,TextColor3=color or Color3.fromRGB(232,232,237),TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true},panel)end
 label('BB   Bloxbot',12,28,17);label('FREE',43,18,10,Color3.fromRGB(72,151,255))
 local close=create('TextButton',{Position=UDim2.new(1,-46,0,2),Size=UDim2.fromOffset(44,44),Text='×',TextSize=23,Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(137,139,152),BackgroundTransparency=1},panel)
 local function button(text,y,color)local b=create('TextButton',{Position=UDim2.fromOffset(18,y),Size=UDim2.new(1,-36,0,44),BackgroundColor3=color or Color3.fromRGB(72,151,255),BorderSizePixel=0,Text=text,TextSize=13,Font=Enum.Font.GothamMedium,TextColor3=Color3.new(1,1,1)},panel);create('UICorner',{CornerRadius=UDim.new(0,8)},b);return b end
 local copy=button('Get key with Panda',72)
 local key=create('TextBox',{Position=UDim2.fromOffset(18,126),Size=UDim2.new(1,-36,0,44),Text='',PlaceholderText='PANDA-XXXX-XXXX-XXXX-XXXX',ClearTextOnFocus=false,TextSize=12,Font=Enum.Font.Code,TextColor3=Color3.fromRGB(232,232,237),PlaceholderColor3=Color3.fromRGB(137,139,152),BackgroundColor3=Color3.fromRGB(35,35,40),BorderSizePixel=0},panel);create('UICorner',{CornerRadius=UDim.new(0,8)},key)
 local enter=button('Unlock',180)
 local status=label('Connecting to Panda…',233,42,11,Color3.fromRGB(137,139,152))
 local public={}
 function public.destroy()
  if not alive then return end;alive=false
  for _,c in ipairs(connections)do c:Disconnect()end;if cameraConnection then cameraConnection:Disconnect()end
  gui:Destroy();if not transferred then
   if session then session:close()end;if sdk and type(sdk.disconnect)=='function'then pcall(sdk.disconnect)end
   local retained=env.BloxBotFreePreparedModel;env.BloxBotFreePreparedModel=nil
   if type(retained)=='table'and type(retained.model)=='table'and type(retained.model.dispose)=='function'then pcall(retained.model.dispose,retained.model)end
  end
  if env.BloxBotFreeLogin==public then env.BloxBotFreeLogin=nil end
 end
 env.BloxBotFreeLogin=public;connect(close.Activated,public.destroy)
 local function message(text)if alive then status.Text=text end end
 local function grant(path,userKey)
  local started=os.clock()
  local reply=transport.fetch({Url=config.gateway..path,Method='POST',Headers={Accept='application/json',['Content-Type']='application/json',['User-Agent']='Bloxbot/1.0',['Cache-Control']='no-cache'},Body=http:JSONEncode({key=userKey,hwid=hwid,release=config.sha256}),Timeout=20})
  local data=http:JSONDecode(reply.Body);return reply.StatusCode,data,started
 end
 local function runtime()
  local path='BloxBotFreeCache-v1/runtime-'..config.sha256..'.enc64'
  if type(readfile)=='function'then local ok,value=pcall(readfile,path);if ok and type(value)=='string'and #value==config.bytes and transport.hash(value)==config.sha256 then return value end end
  message('Downloading update…');local value=fetch(config.url)
  assert(#value==config.bytes and transport.hash(value)==config.sha256,'Update verification failed. Please retry.')
  if type(writefile)=='function'then if type(makefolder)=='function'then pcall(makefolder,'BloxBotFreeCache-v1')end;pcall(writefile,path,value)end
  return value
 end
 connect(copy.Activated,function()
  if not sdk or busy then return end
  local ok,link=pcall(sdk.getKeyUrl);if not ok or type(link)~='string'or not link:match('^https://ads%.pandauth%.com/getkey/')then message('Panda is reconnecting. Please retry.');return end
  local copied=false;if type(setclipboard)=='function'then copied=pcall(setclipboard,link)end
  if copied then message('Link copied. Complete Panda, then paste your key.')else key.Text=link;key:CaptureFocus();message('Copy the link above, then paste your Panda key here.')end
 end)
 local function unlock(userKey,automatic,resume)
  if busy or not sdk then return end;busy=true;enter.Text='Checking…';message(automatic and 'Signing in with your saved key…'or 'Checking Panda key…')
  userKey=userKey:match('^%s*(.-)%s*$')or''
  task.spawn(function()
   local ok,result=pcall(function()
    assert(userKey:match('^PANDA%-%w%w%w%w%-%w%w%w%w%-%w%w%w%w%-%w%w%w%w$'),'Paste your Panda key exactly as shown')
    -- Already-bound keys can use the independent server check immediately.
    -- New keys still pass Panda's SDK handshake to establish their HWID.
    local status,authorization,started=grant('/v1/catalog',userKey)
    if status==403 then
     local result=sdk.validate(userKey)
     if type(result)~='table'or result.success~=true then
      local reason=type(result)=='table'and result.reason
      if reason=='INVALID_KEY'then saved:clear()end
      error(reason=='INVALID_KEY'and'Key expired or bound to another device. Get a key from this menu.'or'Panda is busy. Please retry shortly.',0)
     end
     status,authorization,started=grant('/v1/catalog',userKey)
    end
    if status==403 then saved:clear()end
    assert(status==200,status==409 and 'Update available. Run the loader again.'or status==403 and 'Key expired or bound to another device. Get a key from this menu.'or 'Panda connection interrupted. Please retry.')
    assert(type(authorization)=='table'and type(authorization.catalog)=='table'and type(authorization.code)=='table','Panda verification needs a retry')
    assert(alive,'Closed');session:accept(userKey,authorization,started);saved:write(userKey);userKey='';if alive then key.Text=''end
    -- Runtime access now uses fresh server leases, not the mobile SDK heartbeat.
    pcall(sdk.disconnect)
    local encrypted=runtime();local code=transport.decrypt(encrypted,authorization.code.key,authorization.code.iv)
    assert(type(code)=='string'and #code==config.plain_bytes and transport.hash(code)==config.plain_sha256,'Update decryption failed. Please retry.')
    assert(alive and session.isConnected()==true,'Panda is reconnecting. Please retry.')
    local chunk,problem=loadstring(code,'BloxBotFreeRuntime');assert(chunk,problem)
    local start=chunk();assert(type(start)=='function','Update format differs')
    transferred=true;public.destroy()
    local launchOk,menu=pcall(start,{sdk=session,catalog=authorization.catalog,resume=resume})
    if not launchOk then transferred=false;session:close();error(menu,0)end
    local destroy=menu.destroy;local closed=false
    menu.destroy=function(preserve)if closed then return end;closed=true;destroy(preserve==true);session:close();pcall(sdk.disconnect)end
    local queue=queue_on_teleport or queue_on_tp or queueonteleport or queueontp
    if type(queue)=='function'and player.OnTeleport then
     local queued=false
     session:own(player.OnTeleport:Connect(function(state)
      if queued or state~=Enum.TeleportState.Started or not session.isConnected()then return end
      queued=true
      if type(menu.snapshot)=='function'then
       local ok,state=pcall(menu.snapshot)
       if ok and type(state)=='table'and state.bot and state.bot.wanted and state.preferences and state.preferences.autoQueue then saved:prepareTeleport({id=state.model,game=state.game,autoQueue=true,skipReplay=state.preferences.skipReplay==true})end
      end
      local line='if not game:IsLoaded() then game.Loaded:Wait() end loadstring(game:HttpGet('..string.format('%q',config.loader_url..'?v=')..'..os.time()))()'
      pcall(queue,line)
     end))
    end
    return menu
   end)
   userKey='';busy=false
   if not alive and not transferred and sdk and type(sdk.disconnect)=='function'then pcall(sdk.disconnect)end
   if alive then enter.Text='Unlock';if not ok then message(tostring(result):gsub('^.-:%d+: ',''))end end
   if not ok and not alive and transferred then warn('Bloxbot: '..tostring(result))end
  end)
 end
 connect(enter.Activated,function()unlock(key.Text,false)end)
 task.spawn(function()
  local ok,value=pcall(function()
   local code=fetch('https://secure.pandauth.com/pv4/lib');assert(#code<4*1024*1024,'Panda response differs')
   local fn,problem=loadstring(code,'PandaSDK');assert(fn,problem);local library=fn()
   assert(type(library)=='table'and type(library.configure)=='function'and type(library.validate)=='function'and type(library.hwid)=='function','Panda SDK needs an update')
   library.configure({serviceId='bloxbotfreelootlabs',debug=false,kickOnDetect=false});return library
  end)
  if not alive then if ok and type(value.disconnect)=='function'then pcall(value.disconnect)end;return end
  if ok then
   sdk=value
   local prepared=pcall(function()
    hwid=sdk.hwid();assert(type(hwid)=='string'and #hwid>=8,'Device identity unavailable')
    saved=SavedKey.new(transport,hwid)
    session=ServerSession.new({heartbeat=game:GetService('RunService').Heartbeat,renew=function(userKey)local status,data=grant('/v1/session',userKey);return status,data end,onRejected=function()saved:clear()end})
   end)
   if not prepared then message('Panda device identity is unavailable. Update your executor.');return end
   local remembered,resume=saved:read()
   if remembered then unlock(remembered,true,resume)else message('Get your key with Panda, then paste it above.')end
  else message('Panda connection interrupted. Run the loader again.')end
 end)
 return public
end

end
factories.ReleaseConfig=function()return {["sha256"]="c067d0fc8af0e3a27e8395815dcff017ffd79e383c4207333305bfb6538506b4",["bytes"]=4742188,["plain_bytes"]=3556635,["plain_sha256"]="74c1154468e08c1adf606fa9bd84e95115b1adac2e3e4734d821b7a4d3dc1d1c",["url"]="https://raw.githubusercontent.com/sabex999/bloxbot-free/main/releases/r20-c067d0fc8af0e3a2.enc64",["gateway"]="https://bloxbot-free-catalog.bloxbot.workers.dev",["loader_url"]="https://raw.githubusercontent.com/sabex999/bloxbot-free/refs/heads/main/loader.lua"} end
return import("GitHubMain")()
