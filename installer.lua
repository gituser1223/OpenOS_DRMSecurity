local component = require("component")
local computer = require("computer")

local INSTALLER_VERSION = "2.3.0-STABLE"

local function log(msg, level)
  level = level or "INFO"
  print(string.format("[%s] %s", level, msg))
end

local function fnv1a(str)
  local hash = 2166136261
  for i = 1, #str do
    hash = hash ~ str:byte(i)
    hash = (hash * 16777619) % 4294967296
  end
  return string.format("%08x", hash)
end

local function findSystemFS()
  for addr in component.list("filesystem") do
    local fs = component.proxy(addr)
    if fs and fs.exists("/init.lua") then
      return addr
    end
  end
  return nil
end

local function findGPU()
  for addr in component.list("gpu") do
    return addr
  end
  return nil
end

local function generateLockId(fp)
  local seed = 0
  for i = 1, #fp do
    seed = (seed * 31 + fp:byte(i)) % 2147483647
  end
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local out = ""
  for i = 1, 16 do
    seed = (seed * 1103515245 + 12345) % 2147483647
    local idx = (seed % #chars) + 1
    out = out .. chars:sub(idx, idx)
  end
  return out
end

local function collectCritical()
  log("Collecting hardware APU fingerprint...")
  
  local board = computer.address()
  if not board then error("No motherboard") end
  
  local eeprom = nil
  for addr in component.list("eeprom") do
    eeprom = addr
    break
  end
  if not eeprom then error("No EEPROM") end
  
  local fs = findSystemFS()
  if not fs then error("No filesystem with /init.lua found") end
  
  local gpu = findGPU()
  if not gpu then error("No GPU/APU found - this system requires APU binding") end
  
  log("Board (CPU): " .. board)
  log("EEPROM: " .. eeprom)
  log("GPU/APU: " .. gpu)
  log("Filesystem: " .. fs)
  
  return {board = board, eeprom = eeprom, filesystem = fs, gpu = gpu}
end

local function generateFingerprint(c)
  return "b:" .. c.board .. "|e:" .. c.eeprom .. "|f:" .. c.filesystem .. "|g:" .. c.gpu
end

local function loadTemplate(fsAddr)
  local fs = component.proxy(fsAddr)
  if not fs then error("filesystem proxy failed") end
  local path = "/secure_bios_template.lua"
  if not fs.exists(path) then error("missing BIOS template") end
  local h = fs.open(path, "r")
  if not h then error("cannot open template") end
  local data = ""
  while true do
    local chunk = fs.read(h, 4096)
    if not chunk then break end
    data = data .. chunk
  end
  fs.close(h)
  return data
end

local function buildBios(template, c, fingerprint, lockId, hashHex)
  local t = template
  t = t:gsub("{{FINGERPRINT}}", fingerprint)
  t = t:gsub("{{LOCK_ID}}", lockId)
  t = t:gsub("{{FINGERPRINT_HASH}}", hashHex)
  return t
end

local function backupOriginalBIOS(fsAddr, eepromAddr)
  local fs = component.proxy(fsAddr)
  local eeprom = component.proxy(eepromAddr)
  if not fs or not eeprom then return false end
  local originalBIOS = eeprom.get()
  if not originalBIOS or #originalBIOS == 0 then return false end
  if not fs.exists("/secureboot") then
    fs.makeDirectory("/secureboot")
  end
  local h = fs.open("/secureboot/original_bios_backup.lua", "w")
  if not h then return false end
  fs.write(h, originalBIOS)
  fs.close(h)
  log("Original BIOS backed up to /secureboot/original_bios_backup.lua", "INFO")
  return true
end

local function flash(eepromAddr, bios)
  if #bios > 4096 then
    error("BIOS exceeds EEPROM limit (4KB)")
  end
  local eeprom = component.proxy(eepromAddr)
  if not eeprom then error("EEPROM unavailable") end
  log("Flashing EEPROM...")
  eeprom.set(bios)
  eeprom.setLabel("SecureBoot-APU")
  return true
end

local function main()
  log("======================================")
  log(" SecureBoot APU Installer " .. INSTALLER_VERSION)
  log("======================================")

  local c = collectCritical()
  
  local fingerprint = generateFingerprint(c)
  local hashHex = fnv1a(fingerprint)
  local lockId = generateLockId(fingerprint)

  log("Fingerprint: " .. fingerprint)
  log("Hash (HEX): " .. hashHex)
  log("LockID: " .. lockId)

  backupOriginalBIOS(c.filesystem, c.eeprom)

  local template = loadTemplate(c.filesystem)
  local bios = buildBios(template, c, fingerprint, lockId, hashHex)
  
  log("BIOS size: " .. #bios .. " bytes", "INFO")
  
  if #bios > 4096 then
    error("BIOS too large: " .. #bios .. " > 4096")
  end

  flash(c.eeprom, bios)

  log("======================================")
  log("INSTALL COMPLETE")
  log("")
  log("🔐 LOCK ID: " .. lockId)
  log("🔑 HASH: " .. hashHex)
  log("🖥️  GPU/APU BIND: " .. c.gpu)
  log("")
  log("⚠️  GPU/APU binded to license")
  log("")
  log("======================================")

  return true
end

main()
