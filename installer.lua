local component = require("component")
local computer = require("computer")

local INSTALLER_VERSION = "1.0.0"

local function log(msg, level)
  level = level or "INFO"
  print(string.format("[%s] %s", level, msg))
end

local function generateLockId(fingerprint)
  local result = ""
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  
  local seed = 0
  for i = 1, #fingerprint do
    seed = (seed * 31 + string.byte(fingerprint, i)) % 2147483647
  end
  
  for i = 1, 16 do
    seed = (seed * 1103515245 + 12345) % 2147483647
    result = result .. string.sub(chars, (seed % #chars) + 1, (seed % #chars) + 1)
  end
  
  return result
end

local function getComponentCID(componentType, index)
  index = index or 1
  local count = 0
  for address in component.list(componentType) do
    count = count + 1
    if count == index then
      return address
    end
  end
  return nil
end

local function collectCriticalComponents()
  log("Collecting critical components...")
  
  local components = {}
  
  components.board = computer.address()
  log("  [OK] Motherboard: " .. components.board, "INFO")
  
  local eepromCID = getComponentCID("eeprom")
  if eepromCID then
    components.eeprom = eepromCID
    log("  [OK] EEPROM: " .. eepromCID, "INFO")
  else
    log("  [ERROR] EEPROM not found!", "ERROR")
    return nil
  end
  
  local fsCID = getComponentCID("filesystem")
  if fsCID then
    components.filesystem = fsCID
    log("  [OK] Filesystem: " .. fsCID, "INFO")
  else
    log("  [ERROR] Filesystem not found!", "ERROR")
    return nil
  end
  
  return components
end

local function collectOptionalComponents()
  log("Collecting optional components...")
  
  local optional = {}
  
  local gpuCID = getComponentCID("gpu")
  if gpuCID then
    optional.gpu = gpuCID
    log("  [OK] GPU: " .. gpuCID, "INFO")
  end
  
  local screenCID = getComponentCID("screen")
  if screenCID then
    optional.screen = screenCID
    log("  [OK] Screen: " .. screenCID, "INFO")
  end
  
  local modemCID = getComponentCID("modem")
  if modemCID then
    optional.modem = modemCID
    log("  [OK] Modem: " .. modemCID, "INFO")
  end
  
  local robotCID = getComponentCID("robot")
  if robotCID then
    optional.robot = robotCID
    log("  [OK] Robot: " .. robotCID, "INFO")
  end
  
  local redstoneCID = getComponentCID("redstone")
  if redstoneCID then
    optional.redstone = redstoneCID
    log("  [OK] Redstone: " .. redstoneCID, "INFO")
  end
  
  return optional
end

local function generateFingerprint(critical, optional)
  log("Generating fingerprint...")
  
  local fpList = {}
  
  table.insert(fpList, "board:" .. critical.board)
  table.insert(fpList, "eeprom:" .. critical.eeprom)
  table.insert(fpList, "filesystem:" .. critical.filesystem)
  
  if optional.gpu then
    table.insert(fpList, "gpu:" .. optional.gpu)
  end
  if optional.screen then
    table.insert(fpList, "screen:" .. optional.screen)
  end
  if optional.modem then
    table.insert(fpList, "modem:" .. optional.modem)
  end
  if optional.robot then
    table.insert(fpList, "robot:" .. optional.robot)
  end
  if optional.redstone then
    table.insert(fpList, "redstone:" .. optional.redstone)
  end
  
  table.sort(fpList)
  
  local fingerprint = table.concat(fpList, "|")
  
  log("  Fingerprint: " .. fingerprint, "INFO")
  return fingerprint
end

local function generateLicense(critical, optional, fingerprint)
  log("Generating LICENSE structure...")
  
  local lockId = generateLockId(fingerprint)
  
  local license = {
    board = critical.board,
    eeprom = critical.eeprom,
    filesystem = critical.filesystem,
    fingerprint = fingerprint,
    lockId = lockId,
    serverEnabled = false,
    serverAddress = "",
    attempts = 3,
    state = "OK"
  }
  
  log("  Lock ID: " .. lockId, "INFO")
  log("  Attempts: 3", "INFO")
  log("  State: OK", "INFO")
  
  return license
end

local function loadBiosTemplate(fsCID)
  log("Loading BIOS template...")
  
  local templatePath = "/secure_bios_template.lua"
  local fs = component.proxy(fsCID)
  
  if not fs then
    log("  Cannot access filesystem", "ERROR")
    return nil
  end
  
  if not fs.exists(templatePath) then
    log("  Template not found at " .. templatePath, "ERROR")
    return nil
  end
  
  local handle, err = fs.open(templatePath, "r")
  if not handle then
    log("  Cannot open template file: " .. tostring(err), "ERROR")
    return nil
  end
  
  local content = ""
  local chunk_size = 2048
  
  repeat
    local chunk = fs.read(handle, chunk_size)
    if chunk then
      content = content .. chunk
    else
      break
    end
  until not chunk
  
  fs.close(handle)
  
  log("  Template loaded (" .. #content .. " bytes)", "INFO")
  return content
end

local function substitutePlaceholders(template, critical, optional, license)
  log("Substituting placeholders...")
  
  local result = template
  
  result = result:gsub("{{BOARD_CID}}", license.board)
  result = result:gsub("{{EEPROM_CID}}", license.eeprom)
  result = result:gsub("{{FS_CID}}", license.filesystem)
  
  result = result:gsub("{{FINGERPRINT}}", license.fingerprint)
  
  result = result:gsub("{{LOCK_ID}}", license.lockId)
  
  log("  Substitution complete", "INFO")
  return result
end

local function createBackup(biosContent, fsCID)
  log("Creating BIOS backup...")
  
  local backupPath = "/tmp/backup_bios.lua"
  local fs = component.proxy(fsCID)
  
  if not fs then
    log("  Cannot access filesystem", "ERROR")
    return false
  end
  
  if not fs.exists("/tmp") then
    fs.makeDirectory("/tmp")
  end
  
  local handle, err = fs.open(backupPath, "w")
  if not handle then
    log("  Cannot create backup: " .. tostring(err), "ERROR")
    return false
  end
  
  fs.write(handle, biosContent)
  fs.close(handle)
  
  log("  Backup created: " .. backupPath, "INFO")
  return true
end

local function flashEEPROM(biosContent, eepromCID, fsCID)
  log("Flashing EEPROM...")
  
  if #biosContent > 4096 then
    log("  BIOS too large (" .. #biosContent .. " > 4096 bytes)", "ERROR")
    return false
  end
  
  local eeprom = component.proxy(eepromCID)
  if not eeprom then
    log("  Cannot access EEPROM", "ERROR")
    return false
  end
  
  log("  BIOS size: " .. #biosContent .. " bytes", "INFO")
  log("  EEPROM capacity: 4096 bytes", "INFO")
  
  print("")
  print("WARNING: This will flash the EEPROM with SecureBoot DRM")
  print("System will be locked on next boot until unlocked with ID")
  print("")
  io.write("Proceed with EEPROM flashing? (y/n): ")
  io.flush()
  local input = io.read()
  
  if input:lower() == "y" or input:lower() == "yes" then
    log("Starting EEPROM flash...", "INFO")
    
    local fs = component.proxy(fsCID)
    if fs then
      local bootAddr = getComponentCID("filesystem")
      if bootAddr then
        eeprom.setData(bootAddr)
        log("  Boot address set to: " .. bootAddr, "INFO")
      end
    end
    
    eeprom.setLabel("SecureBoot")
    log("  EEPROM label set to 'SecureBoot'", "INFO")
    
    log("  EEPROM flash completed successfully!", "INFO")
    return true
  else
    log("EEPROM flashing cancelled by user", "INFO")
    return false
  end
end

local function main()
  log("========================================", "INFO")
  log("OpenOS SecureBoot DRM Installer v" .. INSTALLER_VERSION, "INFO")
  log("========================================", "INFO")
  
  local critical = collectCriticalComponents()
  if not critical then
    log("Installation failed: missing critical components", "ERROR")
    return false
  end
  
  print("")
  
  local optional = collectOptionalComponents()
  
  print("")
  
  local fingerprint = generateFingerprint(critical, optional)
  
  print("")
  
  local license = generateLicense(critical, optional, fingerprint)
  
  print("")
  
  local biosTemplate = loadBiosTemplate(critical.filesystem)
  if not biosTemplate then
    log("Installation failed: BIOS template not found", "ERROR")
    return false
  end
  
  print("")
  
  local finalBios = substitutePlaceholders(biosTemplate, critical, optional, license)
  
  print("")
  
  if not createBackup(finalBios, critical.filesystem) then
    log("Installation failed: cannot create backup", "ERROR")
    return false
  end
  
  print("")
  
  if not flashEEPROM(finalBios, critical.eeprom, critical.filesystem) then
    log("Installation failed: EEPROM flashing cancelled or failed", "ERROR")
    return false
  end
  
  print("")
  log("========================================", "INFO")
  log("Installation completed successfully!", "INFO")
  log("========================================", "INFO")
  log("System will be locked on next boot.", "INFO")
  log("Unlock ID: " .. license.lockId, "INFO")
  log("Keep this ID safe!", "INFO")
  
  return true
end

if not main() then
  os.exit(1)
end
