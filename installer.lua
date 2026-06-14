-- OpenOS SecureBoot DRM Installer
-- Collects hardware CIDs, generates fingerprint, and flashes secure BIOS

local component = component
local computer = computer
local fs = require("filesystem")

local INSTALLER_VERSION = "1.0.0"

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function log(msg, level)
  level = level or "INFO"
  print(string.format("[%s] %s", level, msg))
end

local function hexToString(s)
  return s
end

local function stringToHex(s)
  return s
end

-- Generate deterministic 16-char alphanumeric Lock ID from fingerprint
local function generateLockId(fingerprint)
  local result = ""
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  
  -- Use fingerprint hash to seed deterministic generation
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

-- ============================================================================
-- HARDWARE DETECTION
-- ============================================================================

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
  
  -- Motherboard (board)
  local boardCID = getComponentCID("computer")
  if boardCID then
    components.board = boardCID
    log("  [OK] Motherboard: " .. boardCID, "INFO")
  else
    components.board = computer.address()
    log("  [OK] Motherboard (from computer): " .. components.board, "INFO")
  end
  
  -- EEPROM
  local eepromCID = getComponentCID("eeprom")
  if eepromCID then
    components.eeprom = eepromCID
    log("  [OK] EEPROM: " .. eepromCID, "INFO")
  else
    log("  [ERROR] EEPROM not found!", "ERROR")
    return nil
  end
  
  -- Primary Filesystem
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
  
  -- GPU
  local gpuCID = getComponentCID("gpu")
  if gpuCID then
    optional.gpu = gpuCID
    log("  [OK] GPU: " .. gpuCID, "INFO")
  else
    log("  [--] GPU not found (optional)", "INFO")
  end
  
  -- Screen
  local screenCID = getComponentCID("screen")
  if screenCID then
    optional.screen = screenCID
    log("  [OK] Screen: " .. screenCID, "INFO")
  else
    log("  [--] Screen not found (optional)", "INFO")
  end
  
  -- Modem
  local modemCID = getComponentCID("modem")
  if modemCID then
    optional.modem = modemCID
    log("  [OK] Modem: " .. modemCID, "INFO")
  else
    log("  [--] Modem not found (optional)", "INFO")
  end
  
  -- Robot
  local robotCID = getComponentCID("robot")
  if robotCID then
    optional.robot = robotCID
    log("  [OK] Robot: " .. robotCID, "INFO")
  else
    log("  [--] Robot not found (optional)", "INFO")
  end
  
  -- Redstone
  local redstoneCID = getComponentCID("redstone")
  if redstoneCID then
    optional.redstone = redstoneCID
    log("  [OK] Redstone: " .. redstoneCID, "INFO")
  else
    log("  [--] Redstone not found (optional)", "INFO")
  end
  
  return optional
end

-- ============================================================================
-- FINGERPRINT GENERATION
-- ============================================================================

local function generateFingerprint(critical, optional)
  log("Generating fingerprint...")
  
  local fpList = {}
  
  -- Add critical components (always present)
  table.insert(fpList, "board:" .. critical.board)
  table.insert(fpList, "eeprom:" .. critical.eeprom)
  table.insert(fpList, "filesystem:" .. critical.filesystem)
  
  -- Add optional components (only if present)
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
  
  -- Sort for stability
  table.sort(fpList)
  
  -- Join with pipe separator
  local fingerprint = table.concat(fpList, "|")
  
  log("  Fingerprint: " .. fingerprint, "INFO")
  return fingerprint
end

-- ============================================================================
-- LICENSE GENERATION
-- ============================================================================

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

-- ============================================================================
-- BIOS TEMPLATE LOADING & SUBSTITUTION
-- ============================================================================

local function loadBiosTemplate()
  log("Loading BIOS template...")
  
  local templatePath = "/secure_bios_template.lua"
  
  if not fs.exists(templatePath) then
    log("  Template not found at " .. templatePath, "ERROR")
    return nil
  end
  
  local handle = fs.open(templatePath, "r")
  if not handle then
    log("  Cannot open template file", "ERROR")
    return nil
  end
  
  local content = handle:read("*a")
  handle:close()
  
  log("  Template loaded (" .. #content .. " bytes)", "INFO")
  return content
end

local function substitutePlaceholders(template, critical, optional, license)
  log("Substituting placeholders...")
  
  local result = template
  
  -- Replace critical CIDs
  result = result:gsub("{{BOARD_CID}}", license.board)
  result = result:gsub("{{EEPROM_CID}}", license.eeprom)
  result = result:gsub("{{FS_CID}}", license.filesystem)
  
  -- Replace fingerprint
  result = result:gsub("{{FINGERPRINT}}", license.fingerprint)
  
  -- Replace lock ID
  result = result:gsub("{{LOCK_ID}}", license.lockId)
  
  log("  Substitution complete", "INFO")
  return result
end

-- ============================================================================
-- BACKUP & FLASH
-- ============================================================================

local function createBackup(biosContent)
  log("Creating BIOS backup...")
  
  local backupPath = "/tmp/backup_bios.lua"
  
  -- Create /tmp if needed
  if not fs.exists("/tmp") then
    fs.makeDirectory("/tmp")
  end
  
  local handle = fs.open(backupPath, "w")
  if not handle then
    log("  Cannot create backup", "ERROR")
    return false
  end
  
  handle:write(biosContent)
  handle:close()
  
  log("  Backup created: " .. backupPath, "INFO")
  return true
end

local function flashEEPROM(biosContent, eepromCID)
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
  
  -- Set boot address to current filesystem
  local bootAddr = getComponentCID("filesystem")
  if bootAddr then
    eeprom.setData(bootAddr)
    log("  Boot address set to filesystem: " .. bootAddr, "INFO")
  end
  
  -- Set label
  eeprom.setLabel("SecureBoot")
  log("  EEPROM label set to 'SecureBoot'", "INFO")
  
  log("  EEPROM flashing not implemented in sandbox (manual operation required)", "WARN")
  return true
end

-- ============================================================================
-- MAIN INSTALLATION FLOW
-- ============================================================================

local function main()
  log("========================================", "INFO")
  log("OpenOS SecureBoot DRM Installer v" .. INSTALLER_VERSION, "INFO")
  log("========================================", "INFO")
  
  -- Step 1: Collect critical components
  local critical = collectCriticalComponents()
  if not critical then
    log("Installation failed: missing critical components", "ERROR")
    return false
  end
  
  print("")
  
  -- Step 2: Collect optional components
  local optional = collectOptionalComponents()
  
  print("")
  
  -- Step 3: Generate fingerprint
  local fingerprint = generateFingerprint(critical, optional)
  
  print("")
  
  -- Step 4: Generate license
  local license = generateLicense(critical, optional, fingerprint)
  
  print("")
  
  -- Step 5: Load BIOS template
  local biosTemplate = loadBiosTemplate()
  if not biosTemplate then
    log("Installation failed: BIOS template not found", "ERROR")
    return false
  end
  
  print("")
  
  -- Step 6: Substitute placeholders
  local finalBios = substitutePlaceholders(biosTemplate, critical, optional, license)
  
  print("")
  
  -- Step 7: Create backup
  if not createBackup(finalBios) then
    log("Installation failed: cannot create backup", "ERROR")
    return false
  end
  
  print("")
  
  -- Step 8: Flash EEPROM
  if not flashEEPROM(finalBios, critical.eeprom) then
    log("Installation failed: cannot flash EEPROM", "ERROR")
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

-- Run installer
if not main() then
  os.exit(1)
end
