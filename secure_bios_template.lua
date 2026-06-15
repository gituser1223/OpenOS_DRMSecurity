local component=component local computer=computer
local function boot_invoke(a,m,...)local r={pcall(component.invoke,a,m,...)}if not r[1]then return nil,r[2]else return table.unpack(r,2,r.n)end end
local eeprom=component.list("eeprom")()
computer.getBootAddress=function()return boot_invoke(eeprom,"getData")end
computer.setBootAddress=function(a)return boot_invoke(eeprom,"setData",a)end
do local s,g for a in component.list("screen")do s=a break end for a in component.list("gpu")do g=a break end if g and s then pcall(boot_invoke,g,"bind",s)end end
local function fnv1a(s)local h=2166136261 for i=1,#s do h=h~s:byte(i)h=(h*16777619)%4294967296 end return string.format("%08x",h)end
local function findSystemFS()for a in component.list("filesystem")do local fs=component.proxy(a)if fs and fs.exists("/init.lua")then return a end end return nil end
local function findGPU()for a in component.list("gpu")do return a end return nil end
local EF="{{FINGERPRINT}}"
local EH="{{FINGERPRINT_HASH}}"
local LK="{{LOCK_ID}}"
do local g,s for a in component.list("gpu")do g=a break end for a in component.list("screen")do s=a break end if g and s then pcall(component.invoke,g,"bind",s)pcall(component.invoke,g,"setBackground",0)pcall(component.invoke,g,"setForeground",65280)pcall(component.invoke,g,"fill",1,1,80,25," ")pcall(component.invoke,g,"set",1,1,"SecureBoot BIOS v3")pcall(component.invoke,g,"set",1,2,"Validating APU+TPM...")end
computer.pullSignal(0.05)
local board=computer.address()
local eepromAddr=nil for a in component.list("eeprom")do eepromAddr=a break end
local fsAddr=findSystemFS()
local gpuAddr=findGPU()
if not gpuAddr then
  if g then pcall(component.invoke,g,"setForeground",16711680)pcall(component.invoke,g,"set",1,4,"ERROR: No GPU/APU found")end
  while true do computer.beep(880,0.2)computer.beep(440,0.2)computer.pullSignal(1)end
end
local p={}
p[#p+1]="b:"..board
p[#p+1]="e:"..eepromAddr
p[#p+1]="f:"..(fsAddr or "none")
p[#p+1]="g:"..gpuAddr
local f=table.concat(p,"|")
local h=fnv1a(f)
if g then pcall(component.invoke,g,"set",1,3,"Board: "..string.sub(board,1,8))pcall(component.invoke,g,"set",1,4,"GPU/APU: "..string.sub(gpuAddr,1,8))pcall(component.invoke,g,"set",1,5,"FS: "..string.sub(fsAddr or "none",1,8))end
if f~=EF or h~=EH then
  if g then pcall(component.invoke,g,"setForeground",16711680)pcall(component.invoke,g,"set",1,7,"LOCKED: "..(f~=EF and"FP"or"HASH"))pcall(component.invoke,g,"set",1,8,"Exp: "..EH)pcall(component.invoke,g,"set",1,9,"Got: "..h)end
  while true do computer.beep(880,0.2)computer.beep(440,0.2)computer.pullSignal(1)end
end
if g then pcall(component.invoke,g,"setForeground",65280)pcall(component.invoke,g,"set",1,7,"LICENSE OK")pcall(component.invoke,g,"set",1,8,"Booting...")end
computer.beep(1000,0.15)computer.beep(1200,0.15)end
local init
do
  local function tryLoad(a)local h,r=boot_invoke(a,"open","/init.lua")if not h then return nil,r end local b=""repeat local d,r=boot_invoke(a,"read",h,math.maxinteger or 2147483647)if not d and r then return nil,r end b=b..(d or"")until not d boot_invoke(a,"close",h)return load(b,"=init")end
  local r
  if computer.getBootAddress()then init,r=tryLoad(computer.getBootAddress())end
  if not init then computer.setBootAddress()for a in component.list("filesystem")do init,r=tryLoad(a)if init then computer.setBootAddress(a)break end end end
  if not init then error("no bootable medium",0)end
  computer.beep(1000,0.2)
end
return init()
