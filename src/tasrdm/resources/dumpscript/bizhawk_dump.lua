-- Copyright (C) 2021, Vi Grey
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
--
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED. IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
-- LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
-- OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.

local version = {};
local reset_value = 0;
local movie_playing = false;
local movie_started = false;
local file_name = "";
local player_active = {};
local player_controls = {};
local lag_frame = false;
local resets = {};
local frame_total = 0;
local rerecord_count = 0;
local rom_hash = gameinfo.getromhash();
local base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
local frame = 0;
local lastFrameNumber = 0;
local console = "";
local core = "";
local controller_last = -1;

-- GB(C/A) Specific
local gb_c_core_to_gba_ratio = 0;
local gb_cycles = 0;
local gba_to_gbc_delay = 948.84375;
local cycles_power_on = 0;

-- SNES Specific
local snes_controller_order = {1, 2, 3, 4, 5, 6, 7, 8};

local nes_controls = {"Right", "Left", "Down", "Up", "Start", "Select", "B", "A"};
local snes_controls = {"Right", "Left", "Down", "Up", "Start", "Select", "Y", "B", "", "", "", "", "R", "L", "X", "A"};
local gb_controls = {"A", "B", "Select", "Start", "Right", "Left", "Up", "Down"};
local gba_controls = {"A", "B", "Select", "Start", "Right", "Left", "Up", "Down", "L", "R"};
local max_players = {["NES"]=2, ["SNES"]=8, ["GB"]=1, ["GBC"]=1, ["GBA"]=1};


function get_version()
  for num in string.gmatch(client.getversion(), "[0-9]+") do
    table.insert(version, tonumber(num));
  end
end

function gb_check_version()
  local comp_version = {2, 6, 2};
  for i = 1, #comp_version do
    if version[i] == nil then
      return;
    end
    if version[i] < comp_version[i] then
      return;
    elseif version[i] > comp_version[i] then
      break;
    end
  end
  gba_to_gbc_delay = 0;
end

function snes_get_controller_order()
  if (movie.getinput(0, 1)["Toggle Multitap"] == nil) then
    snes_controller_order = {1, 6, 7, 8, 2, 3, 4, 5};
  end
end

function get_console()
  local c = emu.getsystemid();
  if (c == "NES") then
    return "NES";
  elseif (c == "SNES") then
    return "SNES";
  elseif (c == "GB") then
    return "GB";
  elseif (c == "GBC") then
    return "GBC";
  elseif (c == "GBA") then
    return "GBA";
  end
end

-- Write the r08/r16m file
function write_r_file()
  local r_file_name = "";
  local content = "";
  local x = 1;
  if (console == "NES") then
    r_file_name = file_name .. ".r08";
  elseif (console == "SNES") then
    r_file_name = file_name .. ".r16m";
  elseif (console == "GB" or console == "GBC" or console == "GBA") then
    r_file_name = file_name .. ".txt";
  end
  print("Writing to " .. r_file_name);
  print("Emulator may freeze for a moment.");
  print("Please be patient.\n");
  if (console == "NES" or console == "SNES") then
    while (x <= #player_controls[1]) do
      for i = 1, #player_controls do
        if (console == "NES") then
          content = content .. string.sub(player_controls[i], x, x);
        elseif (console == "SNES") then
          content = (content ..
                     string.sub(player_controls[snes_controller_order[i]],
                                x, x + 1));
        end
      end
      if (console == "SNES") then
        x = x + 1;
      end
      x = x + 1;
    end
  elseif (console == "GB" or console == "GBC" or console == "GBA") then
    content = player_controls[1];
  end
  rfile = io.open(r_file_name, "wb+");
  rfile:write(content);
  rfile:close();
  print("Finished writing to " .. r_file_name .. "\n");
end

-- Write the TCR (TAS Console Replay) file
function write_tcr_file()
  print("Writing to " .. file_name .. ".tcr");
  print("Emulator may freeze for a moment.");
  print("Please be patient.\n");
  local content = "{";
  content = content .. "\"console\":\"" .. console .. "\",";
  content = content .. "\"players\":";
  local players_str = "[";
  for x = 1, #player_active do
    if (player_active[x]) then
      players_str = players_str .. tostring(x) .. ",";
    end
  end
  if (#players_str > 0) then
    players_str = string.sub(players_str, 1, -2);
  end
  players_str = players_str .. "],";
  content = content .. players_str;
  content = content .. "\"frames\":" .. tostring(frame_total) .. ",";
  content = content .. "\"rom_hash\":\"" .. rom_hash .. "\",";
  content = content .. "\"rerecord_count\":" .. tostring(rerecord_count) .. ",";
  if (console ~= "GB" and console ~= "GBC" and console ~= "GBA") then
    content = content .. "\"clock_filter\":4,";
  end
  if (console == "NES") then
    content = content .. "\"dpcm\":true,";
  end
  if (console ~= "GB" and console ~= "GBC" and console ~= "GBA") then
    content = content .. "\"resets\":";
    local resets_str = "[";
    for x = 1, #resets do
      resets_str = resets_str .. tostring(resets[x]) .. ",";
    end
    if (#resets_str > 1) then
      resets_str = string.sub(resets_str, 1, -2);
    end
    resets_str = resets_str .. "],";
    content = content .. resets_str;
  end
  content = content .. "\"inputs\":";
  local inputs_str = "[";
  local inputs_count = 0;
  local player_val = 1;
  for x = 1, #player_controls do
    if (player_active[x]) then
      inputs_str = inputs_str .. "\"" .. encode_base64(player_controls[x]) .. "\",";
    end
  end
  if (#inputs_str > 0) then
    inputs_str = string.sub(inputs_str, 1, -2);
  end
  inputs_str = inputs_str .. "]";
  content = content .. inputs_str;
  content = content .. "}";
  tcrfile = io.open(file_name .. ".tcr", "wb+");
  tcrfile:write("");
  tcrfile:write(content);
  tcrfile:close();
  print("Finished writing to " .. file_name .. ".tcr" .. "\n");
end

-- Convert input to base64
function encode_base64(input)
  local base64_str = "base64:";
  local input_str_len = #input;
  for i = 1, #input, 3 do
    local b1 = math.floor(string.byte(string.sub(input, i, i)) / 4) + 1;
    if (input_str_len + 1 - i >= 3) then
      local b2 = ((string.byte(string.sub(input, i, i)) % 4) * 16 +
                  math.floor(string.byte(string.sub(input, i+1, i+1)) / 16) + 1);
      local b3 = ((string.byte(string.sub(input, i+1, i+1)) % 16) * 4 +
                  math.floor(string.byte(string.sub(input, i+2, i+2)) / 64) + 1);
      local b4 = string.byte(string.sub(input, i+2, i+2)) % 64 + 1;
      base64_str = base64_str .. string.sub(base64_chars, b1, b1);
      base64_str = base64_str .. string.sub(base64_chars, b2, b2);
      base64_str = base64_str .. string.sub(base64_chars, b3, b3);
      base64_str = base64_str .. string.sub(base64_chars, b4, b4);
    elseif (input_str_len + 1 - i == 2) then
      local b2 = ((string.byte(string.sub(input, i, i)) % 4) * 16 +
                  math.floor(string.byte(string.sub(input, i+1, i+1)) / 16) + 1);
      local b3 = (string.byte(string.sub(input, i+1, i+1)) % 16) * 4 + 1;
      base64_str = base64_str .. string.sub(base64_chars, b1, b1);
      base64_str = base64_str .. string.sub(base64_chars, b2, b2);
      base64_str = base64_str .. string.sub(base64_chars, b3, b3);
      base64_str = base64_str .. "=";
    else
      local b2 = (string.byte(string.sub(input, i, i)) % 4) * 16 + 1;
      base64_str = base64_str .. string.sub(base64_chars, b1, b1);
      base64_str = base64_str .. string.sub(base64_chars, b2, b2);
      base64_str = base64_str .. "==";
    end
  end
  return base64_str;
end

-- Get controller input for frame
function handle_frame()
  -- GBA is its own beast and will dump before a frame displays
  if (console == "GB" or console == "GBC" or console == "GBA") then
    handle_frame_gb_c_a();
  elseif (emu.framecount() > 0) then
    local controls = movie.getinput(emu.framecount() - 1);
    if (controls["Reset"]) then
      if (frame > 0) then
        table.insert(resets, frame + 1);
      else
        table.insert(resets, frame);
      end
    end
    if (emu.islagged() == false) then
      if (console == "NES" or console == "SNES") then
        handle_frame_s_nes();
        frame = frame + 1;
      end
    end
  end
end

-- Controller handling for GB, GBC, and GBA
function handle_frame_gb_c_a()
  local c = 0;
  local controller_input = 0;
  if (console ~= "GBA") then
    if (emu.framecount > 0) then
      local controls = movie.getinput(emu.framecount() - 1);
      for x = 1, #gb_controls do
        local button_name = gb_controls[x];
        if (core == "GBHawk" or core == "SubGBHawk") then
          button_name = "P1 " .. button_name;
        end
        if (controls[button_name]) then
          controller_input = controller_input + bit.lshift(1, x - 1);
        end
      end
      if (controls["Power"]) then
        cycles_power_on = c;
      end
      c = math.ceil((gb_cycles - cycles_power_on) / gb_c_core_to_gba_ratio +
                    gba_to_gbc_delay);
    end
    -- We grab the cycle count now and use that value for next frame
    gb_cycles = emu.totalexecutedcycles();
  else 
    local controls = movie.getinput(frame - 1);
    for x = 1, #gba_controls do
      if (controls[gba_controls[x]]) then
        controller_input = controller_input + bit.lshift(1, x - 1);
      end
    end
    c = math.floor((frame * 280896 - 83776) / 4096);
  end
  if (controller_input ~= controller_last) then
    player_active[1] = true;
    player_controls[1] = (player_controls[1] ..
                          string.format("%08X %04X", c, controller_input) ..
                          "\n");
    controller_last = controller_input;
  end
end

-- Controller handling for NES and SNES
function handle_frame_s_nes()
  for i = 1, #player_controls do
    local controls = movie.getinput(emu.framecount() - 1, i);
    local controller_input = 0;
    local byte_width = "";
    if (console == "NES") then
      for x = 1, #nes_controls do
        if (controls[nes_controls[x]]) then
          controller_input = controller_input + bit.lshift(1, x - 1);
          player_active[i] = true;
        end
      end
      player_controls[i] = player_controls[i] .. string.char(controller_input);
    else
      for x = 1, #snes_controls / 2 do
        if (controls[nes_controls[x]]) then
          controller_input = controller_input + bit.lshift(1, x - 1);
          player_active[i] = true;
        end
      end
      player_controls[i] = player_controls[i] .. string.char(controller_input);
      controller_input = 0;
      for x = 1, #snes_controls / 2 do
        if (controls[snes_controls[x + #snes_controls / 2]]) then
          controller_input = controller_input + bit.lshift(1, x - 1);
          player_active[i] = true;
        end
      end
      player_controls[i] = player_controls[i] .. string.char(controller_input);
    end
  end
end

-- Initialize values upon movie startup
function setup_dump()
  if (console ~= "GBA") then
    print("Starting movie. Replay file will be written after movie is finished.\n");
  else
    print("Dumping GBA movie file.");
    print("Emulator may freeze for a moment.");
    print("Please be patient.\n");
  end
  client.unpause();
  movie_playing = true;
  frame_total = movie.length();
  rerecord_count = movie.getrerecordcount();
  file_name = movie.filename():match("(.+)%..+$");
  client.speedmode(800);
  resets = {};
  frame = 0;
  if (console == "GB" or console == "GBC") then
    gb_check_version();
    if (core == "Gambatte") then
      gb_c_core_to_gba_ratio = 512
    elseif (core == "GBHawk" or core == "SubGBHawk") then
      gb_c_core_to_gba_ratio = 1024
    else
      movie_started = false;
      movie_playing = false;
      print("ERROR: Unknown " .. console .. " core " .. core .. "\n");
      return;
    end
  end
  for i = 1, max_players[console] do
    table.insert(player_active, false);
    table.insert(player_controls, "");
  end
end

-- Start of dumping script
if (rom_hash == "") then
  print("ERROR: ROM must be loaded.  Load a ROM and try running this Lua script again\n");
else
  rom_hash = "sha1:" .. rom_hash;
  -- Movie loop
  while (true) do
    if (movie_started == false) then
      if (emu.framecount() ~= 1 or movie.mode() ~= "PLAY") then
        client.reboot_core();
        client.pause();
        print("Select movie file and then unpause the emulator (Emulation > Pause)")
        print("DO NOT CHECK \"Last Frame\" OPTION IN \"Play Movie\" WINDOW\n");
      else
        movie_started = true;
      end
    end
    if (movie_started) then
      -- Movie is loaded/active
      if (movie_playing == false) then
        get_version()
        console = get_console();
        if (console == "SNES") then
          snes_get_controller_order()
        end
        if (max_players[console] == nil) then
          print("ERROR: Unsupported console type.  Load a ROM of a supported console type and try running this Lua script again.\n");
          break
        end 
        core = movie.getheader()["Core"]
        setup_dump();
      else
        if (console == "GBA") then
          for frame = 1, movie.length() do
            handle_frame();
          end
          write_tcr_file();
          write_r_file();
          movie_playing = false;
          client.speedmode(100);
          print("Starting movie.  Closing Lua Script.\n");
          break;
        else
          if (emu.framecount() > movie.length()) then
            -- End of movie
            print("Movie finished.\n")
            write_tcr_file();
            write_r_file();
            movie_playing = false;
            movie.stop();
            client.speedmode(100);
            print("Closing Lua Script.\n");
            break;
          end
          handle_frame();
        end
      end
    end
    -- Go to next frame (allow ROM to progress forward)
    emu.frameadvance();
  end
end
