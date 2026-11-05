-- Bloxbot Free: Panda keys, GitHub updates.
local factories,cache={},{}
local function import(name) if cache[name]==nil then cache[name]=factories[name]() end;return cache[name] end
factories.ExecutorCompat=function()
local Compat={};local checked=nil
function Compat.get()
 if checked then return checked end
 local crypto=crypt or (syn and syn.crypt)
 assert(type(crypto)=='table'and type(crypto.decrypt)=='function'and type(crypto.hash)=='function','This executor needs AES-CBC and SHA-256 support')
 assert(type(buffer)=='table'and type(buffer.create)=='function'and type(buffer.readf32)=='function','Update your executor to a build with Luau buffer support')
 local function hash(raw)
  local digest=crypto.hash(raw,'sha256');assert(type(digest)=='string','Executor SHA-256 returned invalid data')
  if #digest==32 then digest=(digest:gsub('.',function(c)return string.format('%02x',string.byte(c))end))end
  digest=digest:lower();assert(#digest==64 and digest:match('^[a-f0-9]+$'),'Executor SHA-256 returned invalid data');return digest
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
 checked={hash=hash,decrypt=decrypt,fetch=normalizedFetch}
 return checked
end
function Compat.mobile()
 local ok,input=pcall(function()return game:GetService('UserInputService')end)
 return ok and input.TouchEnabled==true and input.KeyboardEnabled~=true
end
return Compat

end
factories.GitHubMain=function()
-- Public bootstrap. Panda handles keys; the catalog stays behind server checks.
local Compat=import("ExecutorCompat")
local config=import("ReleaseConfig")
return function()
 local env=type(getgenv)=='function'and getgenv()or _G
 for _,name in ipairs({'BloxBotFreeLuau','BloxBotFreeLogin'})do local previous=env[name];if type(previous)=='table'and type(previous.destroy)=='function'then pcall(previous.destroy)end end
 local player=game:GetService('Players').LocalPlayer;assert(player,'Join a game before running Bloxbot')
 local http=game:GetService('HttpService');local input=game:GetService('UserInputService');local guiService=game:GetService('GuiService')
 local transport=Compat.get();local alive,busy,transferred=true,false,false;local sdk=nil;local connections={}
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
  gui:Destroy();if not transferred and sdk and type(sdk.disconnect)=='function'then pcall(sdk.disconnect)end
  if env.BloxBotFreeLogin==public then env.BloxBotFreeLogin=nil end
 end
 env.BloxBotFreeLogin=public;connect(close.Activated,public.destroy)
 local function message(text)if alive then status.Text=text end end
 local function catalog(userKey)
  local hwid=sdk.hwid();assert(type(hwid)=='string'and #hwid>=8,'Panda device identity is unavailable')
  local data=http:JSONDecode(fetch(config.gateway..'/v1/catalog','POST',http:JSONEncode({key=userKey,hwid=hwid,release=config.sha256})))
  assert(type(data)=='table'and type(data.catalog)=='table'and type(data.code)=='table','Panda verification needs a retry');return data
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
 connect(enter.Activated,function()
  if busy or not sdk then return end;busy=true;enter.Text='Checking…';message('Checking Panda key…')
  local userKey=key.Text:match('^%s*(.-)%s*$')or''
  task.spawn(function()
   local ok,result=pcall(function()
    assert(userKey:match('^PANDA%-%w%w%w%w%-%w%w%w%w%-%w%w%w%w%-%w%w%w%w$'),'Paste your Panda key exactly as shown')
    local result=sdk.validate(userKey)
    if type(result)~='table'or result.success~=true then
     local reason=type(result)=='table'and result.reason
     error(reason=='INVALID_KEY'and'Key expired or bound to another device. Get a key from this menu.'or'Panda is busy. Please retry shortly.',0)
    end
    assert(alive,'Closed');local grant=catalog(userKey);userKey='';if alive then key.Text=''end
    local encrypted=runtime();local code=transport.decrypt(encrypted,grant.code.key,grant.code.iv)
    assert(type(code)=='string'and #code==config.plain_bytes and transport.hash(code)==config.plain_sha256,'Update decryption failed. Please retry.')
    assert(alive and sdk.isConnected()==true,'Panda session ended. Please retry.')
    local chunk,problem=loadstring(code,'BloxBotFreeRuntime');assert(chunk,problem)
    local start=chunk();assert(type(start)=='function','Update format differs')
    transferred=true;public.destroy()
    local launchOk,menu=pcall(start,{sdk=sdk,catalog=grant.catalog})
    if not launchOk then transferred=false;pcall(sdk.disconnect);error(menu,0)end
    local destroy=menu.destroy;local closed=false
    menu.destroy=function()if closed then return end;closed=true;destroy();pcall(sdk.disconnect)end
    return menu
   end)
   userKey='';busy=false
   if not alive and not transferred and sdk and type(sdk.disconnect)=='function'then pcall(sdk.disconnect)end
   if alive then enter.Text='Unlock';if not ok then message(tostring(result):gsub('^.-:%d+: ',''))end end
   if not ok and not alive and transferred then warn('Bloxbot: '..tostring(result))end
  end)
 end)
 task.spawn(function()
  local ok,value=pcall(function()
   local code=fetch('https://secure.pandauth.com/pv4/lib');assert(#code<4*1024*1024,'Panda response differs')
   local fn,problem=loadstring(code,'PandaSDK');assert(fn,problem);local library=fn()
   assert(type(library)=='table'and type(library.configure)=='function'and type(library.validate)=='function'and type(library.hwid)=='function','Panda SDK needs an update')
   library.configure({serviceId='bloxbotfreelootlabs',debug=false,kickOnDetect=false});return library
  end)
  if not alive then if ok and type(value.disconnect)=='function'then pcall(value.disconnect)end;return end
  if ok then sdk=value;message('Get your key with Panda, then paste it above.')else message('Panda connection interrupted. Run the loader again.')end
 end)
 return public
end

end
factories.ReleaseConfig=function()return {["sha256"]="1e7955c292e51602dd2ed4adaabe9ceeaac1e599d7e0c7430417be187724b59b",["bytes"]=4654360,["plain_bytes"]=3490765,["plain_sha256"]="83c3faeb06619e2bf494eeddc788c637e6a83fbd02a53485200707ddc871f921",["url"]="https://raw.githubusercontent.com/sabex999/bloxbot-free/main/releases/r9-1e7955c292e51602.enc64",["gateway"]="https://bloxbot-free-catalog.bloxbot.workers.dev"} end
return import("GitHubMain")()
