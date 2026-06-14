local LICENSE={board="{{BOARD_CID}}",eeprom="{{EEPROM_CID}}",filesystem="{{FS_CID}}",fingerprint="{{FINGERPRINT}}",lockId="{{LOCK_ID}}",serverEnabled=false,serverAddress="",attempts=3,state="OK"}
local DRM={locked=false,reason="",attempts=LICENSE.attempts}
local function getFP()local t={}local function add(k,a)for addr in component.list(a)do table.insert(t,k..":"..addr)break end end
table.insert(t,"board:"..computer.address())
add("eeprom","eeprom")add("filesystem","filesystem")add("gpu","gpu")add("screen","screen")add("modem","modem")add("robot","robot")add("redstone","redstone")
table.sort(t)return table.concat(t,"|")end
local function validate()return getFP()==LICENSE.fingerprint,"Hardware mismatch"end
local function cls()local g=component.list("gpu")()local s=component.list("screen")()if g and s then component.invoke(g,"bind",s)component.invoke(g,"fill",1,1,160,50," ")end end
local function lock(r)DRM.locked=true DRM.reason=r local g=component.list("gpu")()local s=component.list("screen")()if g and s then component.invoke(g,"bind",s)component.invoke(g,"setForeground",0xFF0000)component.invoke(g,"setCursor",50,10)component.invoke(g,"write","SYSTEM LOCKED")component.invoke(g,"setForeground",0xFFFFFF)component.invoke(g,"setCursor",40,20)component.invoke(g,"write","Reason: "..r)component.invoke(g,"setForeground",0xFFFF00)component.invoke(g,"setCursor",30,28)component.invoke(g,"write","Enter Unlock ID (or ENTER for server)")component.invoke(g,"setForeground",0xFFFFFF)component.invoke(g,"setCursor",50,35)component.invoke(g,"write","Attempts: "..DRM.attempts)end end
local init
do
local function bi(a,m,...)local r=table.pack(pcall(component.invoke,a,m,...))if not r[1]then return nil,r[2]else return table.unpack(r,2,r.n)end end
local e=component.list("eeprom")()computer.getBootAddress=function()return bi(e,"getData")end
computer.setBootAddress=function(a)return bi(e,"setData",a)end
local s=component.list("screen")()local g=component.list("gpu")()if g and s then bi(g,"bind",s)end
local function tlf(a)local h,r=bi(a,"open","/init.lua")if not h then return nil,r end
local b=""repeat local d,r=bi(a,"read",h,math.maxinteger or math.huge)if not d and r then return nil,r end
b=b..(d or "")until not d
bi(a,"close",h)return load(b,"=init")end
local r
if computer.getBootAddress()then init,r=tlf(computer.getBootAddress())end
if not init then computer.setBootAddress()for a in component.list("filesystem")do init,r=tlf(a)if init then computer.setBootAddress(a)break end end end
if not init then error("no bootable medium found",0)end
local v,m=validate()if not v then lock(m)end
LICENSE.state="OK"
computer.beep(1000,0.2)end
return init()