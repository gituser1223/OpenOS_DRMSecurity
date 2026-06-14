-- OpenOS SecureBoot DRM BIOS
-- Template with DRM lock system
-- EEPROM-resident BIOS with CID-based hardware binding

-- ============================================================================
-- LICENSE STRUCTURE (POPULATED BY INSTALLER)
-- ============================================================================

local LICENSE = {
  board = "{{BOARD_CID}}",
  eeprom = "{{EEPROM_CID}}",
  filesystem = "{{FS_CID}}",

  fingerprint = "{{FINGERPRINT}}",
  lockId = "{{LOCK_ID}}",

  serverEnabled = false,
  serverAddress = "",

  attempts = 3,
  state = "OK"
}

-- ============================================================================
-- DRM SYSTEM STATE
-- ============================================================================

local DRM_STATE = {
  locked = false,
  reason = "",
  unlockAttempts = LICENSE.attempts
}

-- ============================================================================
-- HARDWARE FINGERPRINTING
-- ============================================================================

local function getCurrentFingerprint()
  local component_invoke = component.invoke
  local fpList = {}
  
  -- Critical: Motherboard
  local boardAddr = computer.address()
  table.insert(fpList, "board:" .. boardAddr)
  
  -- Critical: EEPROM
  local eepromList = component.list("eeprom")
  for addr in eepromList do
    table.insert(fpList, "eeprom:" .. addr)
    break  -- First EEPROM only
  end
  
  -- Critical: Filesystem
  local fsList = component.list("filesystem")
  for addr in fsList do
    table.insert(fpList, "filesystem:" .. addr)
    break  -- First filesystem only
  end
  
  -- Optional: GPU
  local gpuList = component.list("gpu")
  for addr in gpuList do
    table.insert(fpList, "gpu:" .. addr)
    break
  end
  
  -- Optional: Screen
  local screenList = component.list("screen")
  for addr in screenList do
    table.insert(fpList, "screen:" .. addr)
    break
  end
  
  -- Optional: Modem
  local modemList = component.list("modem")
  for addr in modemList do
    table.insert(fpList, "modem:" .. addr)
    break
  end
  
  -- Optional: Robot
  local robotList = component.list("robot")
  for addr in robotList do
    table.insert(fpList, "robot:" .. addr)
    break
  end
  
  -- Optional: Redstone
  local redstoneList = component.list("redstone")
  for addr in redstoneList do
    table.insert(fpList, "redstone:" .. addr)
    break
  end
  
  -- Sort and join
  table.sort(fpList)
  return table.concat(fpList, "|")
end

-- ============================================================================
-- DRM VALIDATION
-- ============================================================================

local function validateHardware()
  local currentFP = getCurrentFingerprint()
  local storedFP = LICENSE.fingerprint
  
  if currentFP == storedFP then
    return true, "Hardware fingerprint matches"
  end
  
  return false, "Hardware mismatch: fingerprint changed"
end

-- ============================================================================
-- LOCK SCREEN & USER INTERACTION
-- ============================================================================

local function clearScreen()
  local component_invoke = component.invoke
  local gpu = component.list("gpu")()
  local screen = component.list("screen")()
  
  if gpu and screen then
    component_invoke(gpu, "bind", screen)
    component_invoke(gpu, "fill", 1, 1, 160, 50, " ")
    component_invoke(gpu, "setForeground", 0xFF0000)
  end
end

local function drawLockScreen(reason)
  local component_invoke = component.invoke
  local gpu = component.list("gpu")()
  local screen = component.list("screen")()
  
  if not gpu or not screen then
    return
  end
  
  clearScreen()
  component_invoke(gpu, "bind", screen)
  component_invoke(gpu, "setForeground", 0xFF0000)
  component_invoke(gpu, "setCursor", 50, 10)
  component_invoke(gpu, "write", "SYSTEM LOCKED")
  
  component_invoke(gpu, "setForeground", 0xFFFFFF)
  component_invoke(gpu, "setCursor", 35, 15)
  component_invoke(gpu, "write", "Hardware configuration changed")
  
  component_invoke(gpu, "setCursor", 40, 20)
  component_invoke(gpu, "write", "Reason: " .. reason)
  
  component_invoke(gpu, "setForeground", 0xFFFF00)
  component_invoke(gpu, "setCursor", 30, 28)
  component_invoke(gpu, "write", "Enter Unlock ID to proceed")
  component_invoke(gpu, "write", "(or press ENTER for server mode)")
  
  component_invoke(gpu, "setForeground", 0xFFFFFF)
  component_invoke(gpu, "setCursor", 50, 35)
  component_invoke(gpu, "write", "Attempts remaining: " .. DRM_STATE.unlockAttempts)
end

local function promptUnlockId()
  local gpu = component.list("gpu")()
  local screen = component.list("screen")()
  
  if gpu and screen then
    local component_invoke = component.invoke
    component_invoke(gpu, "setCursor", 45, 40)
    component_invoke(gpu, "setForeground", 0x00FF00)
    component_invoke(gpu, "write", "Unlock ID: ")
  end
  
  -- Read user input (simplified - in real scenario would use keyboard)
  return ""
end

local function lockBoot(reason)
  DRM_STATE.locked = true
  DRM_STATE.reason = reason
  
  drawLockScreen(reason)
  
  while DRM_STATE.unlockAttempts > 0 do
    local input = promptUnlockId()
    
    if input == "" then
      -- Server mode (future hook)
      if LICENSE.serverEnabled then
        -- Future: authenticate with server
        break
      end
    elseif input == LICENSE.lockId then
      -- Unlock successful
      return true
    else
      -- Attempt failed
      DRM_STATE.unlockAttempts = DRM_STATE.unlockAttempts - 1
      drawLockScreen("Invalid unlock ID")
    end
  end
  
  -- Attempts exhausted
  error("System locked: too many unlock attempts", 0)
end

-- ============================================================================
-- OPENCOMPUTERS BOOTLOADER (STANDARD - PRESERVED)
-- ============================================================================

local init
do
  local component_invoke = component.invoke
  local function boot_invoke(address, method, ...)
    local result = table.pack(pcall(component_invoke, address, method, ...))
    if not result[1] then
      return nil, result[2]
    else
      return table.unpack(result, 2, result.n)
    end
  end

  local eeprom = component.list("eeprom")()
  computer.getBootAddress = function()
    return boot_invoke(eeprom, "getData")
  end

  computer.setBootAddress = function(address)
    return boot_invoke(eeprom, "setData", address)
  end

  do
    local screen = component.list("screen")()
    local gpu = component.list("gpu")()
    if gpu and screen then
      boot_invoke(gpu, "bind", screen)
    end
  end

  local function tryLoadFrom(address)
    local handle, reason = boot_invoke(address, "open", "/init.lua")
    if not handle then return nil, reason end

    local buffer = ""
    repeat
      local data, reason = boot_invoke(address, "read", handle, math.maxinteger or math.huge)
      if not data and reason then return nil, reason end
      buffer = buffer .. (data or "")
    until not data

    boot_invoke(address, "close", handle)
    return load(buffer, "=init")
  end

  local reason
  if computer.getBootAddress() then
    init, reason = tryLoadFrom(computer.getBootAddress())
  end

  if not init then
    computer.setBootAddress()
    for address in component.list("filesystem") do
      init, reason = tryLoadFrom(address)
      if init then
        computer.setBootAddress(address)
        break
      end
    end
  end

  if not init then
    error("no bootable medium found", 0)
  end

  -- ========================================================================
  -- DRM HOOK POINT (INSERT ONLY HERE - BEFORE INIT EXECUTION)
  -- ========================================================================
  
  local valid, message = validateHardware()
  if not valid then
    lockBoot(message)
  end
  
  LICENSE.state = "OK"
  
  -- ========================================================================
  -- END DRM HOOK POINT
  -- ========================================================================

  computer.beep(1000, 0.2)
end

return init()
