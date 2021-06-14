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

local file_name = "";
local r_file_name = "";
local tcr_file_name = "";
local r_file;
local tcr_file;

local controller_input_buffer = "";
local controller_tcr_input_buffer = "";

function get_version()
  for num in string.gmatch(client.getversion(), "[0-9]+") do
    table.insert(version, tonumber(num));
  end
end

function gb_check_version()
  local comp_version = {2, 6, 2};
  for i = 1, #comp_version do
    if (version[i] == nil) then
      return;
    end
    if (version[i] < comp_version[i]) then
      return;
    elseif (version[i] > comp_version[i]) then
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

function setup_r_file()
  if (console == "NES") then
    r_file_name = file_name .. ".r08";
  elseif (console == "SNES") then
    r_file_name = file_name .. ".r16m";
  elseif (console == "GB" or console == "GBC" or console == "GBA") then
    r_file_name = file_name .. ".txt";
  end
  r_file = io.open(r_file_name, "wb+");
  print("Created replay dump file " .. r_file_name .. "\n");
end

function finish_r_file()
  r_file:write(controller_input_buffer);
  r_file:close();
  print("Finished writing " .. r_file_name .. "\n");
end

function setup_tcr_file()
  tcr_file_name = file_name .. ".tcr";
  tcr_file = io.open(tcr_file_name, "wb+");
  print("Created replay dump file " .. tcr_file_name .. "\n");
  initialize_tcr_file();
end

-- Write the TCR (TAS Console Replay) file
function initialize_tcr_file()
  local content = "{";
  content = content .. "\"console\":\"" .. console .. "\",";
  content = content .. "\"frames\":" .. tostring(frame_total) .. ",";
  content = content .. "\"rom_hash\":\"" .. rom_hash .. "\",";
  content = content .. ("\"rerecord_count\":" .. tostring(rerecord_count) ..
                        ",");
  if (console ~= "GB" and console ~= "GBC" and console ~= "GBA") then
    content = content .. "\"clock_filter\":4,";
  end
  if (console == "NES") then
    content = content .. "\"dpcm\":true,";
  end
  content = content .. "\"inputs\":[\"base64:";
  tcr_file:write(content);
end

function finish_tcr_file()
  local content = encode_base64(controller_tcr_input_buffer) .. "\"]";
  if (console ~= "GB" and console ~= "GBC" and console ~= "GBA") then
    content = content .. ",\"resets\":[";
    for x = 1, #resets do
      content = content .. tostring(resets[x]);
      if (x < #resets) then
        content = content .. ",";
      end
    end
    content = content .. "]";
  end
  content = content .. "}";
  tcr_file:write(content);
  tcr_file:close();
  print("Finished writing " .. tcr_file_name .. "\n");
end

-- Convert input to base64
function encode_base64(input)
  local base64_str = "";
  if (#input > 0) then
    for i = 1, #input, 3 do
      local b1 = math.floor(string.byte(string.sub(input, i, i)) / 4) + 1;
      if (#input + 1 - i >= 3) then
        local b2 = ((string.byte(string.sub(input, i, i)) % 4) * 16 +
                    math.floor(string.byte(string.sub(input, i+1, i+1)) / 16) + 1);
        local b3 = ((string.byte(string.sub(input, i+1, i+1)) % 16) * 4 +
                    math.floor(string.byte(string.sub(input, i+2, i+2)) / 64) + 1);
        local b4 = string.byte(string.sub(input, i+2, i+2)) % 64 + 1;
        base64_str = base64_str .. string.sub(base64_chars, b1, b1);
        base64_str = base64_str .. string.sub(base64_chars, b2, b2);
        base64_str = base64_str .. string.sub(base64_chars, b3, b3);
        base64_str = base64_str .. string.sub(base64_chars, b4, b4);
      elseif (#input + 1 - i == 2) then
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
  r_file:write(controller_input_buffer);
  controller_input_buffer = "";
  -- Only write to files if controller_tcr_input_buffer is divisible by
  -- 3 so it can be encoded perfectly into base64 for TCR file
  if (#controller_tcr_input_buffer > 0 and
      #controller_tcr_input_buffer % 3 == 0) then
    tcr_file:write(encode_base64(controller_tcr_input_buffer));
    controller_tcr_input_buffer = "";
  end
end

-- Controller handling for GB, GBC, and GBA
function handle_frame_gb_c_a()
  local c = 0;
  local controller_input = 0;
  if (console ~= "GBA") then
    if (emu.framecount() > 0) then
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
    controller_input_buffer = (controller_input_buffer ..
      string.format("%08X %04X", c, controller_input) .. "\n");
    for mod = 24, 0, -8 do
      controller_tcr_input_buffer = (controller_tcr_input_buffer ..
        string.char(bit.band(bit.rshift(c, mod), 0xff)));
    end
    for mod = 8, 0, -8 do
      controller_tcr_input_buffer = (controller_tcr_input_buffer ..
        string.char(bit.band(bit.rshift(controller_input, mod), 0xff)));
    end
    controller_last = controller_input;
  end
end

-- Controller handling for NES and SNES
function handle_frame_s_nes()
  for i = 1, max_players[console] do
    local controller_input = 0;
    if (console == "NES") then
      local controls = movie.getinput(emu.framecount() - 1, i);
      for x = 1, #nes_controls do
        if (controls[nes_controls[x]]) then
          controller_input = controller_input + bit.lshift(1, x - 1);
        end
      end
      controller_input_buffer = (controller_input_buffer ..
                                 string.char(controller_input));
      controller_tcr_input_buffer = (controller_tcr_input_buffer ..
                                     string.char(controller_input));
    else
      -- Use snes_controller_order[i] because P2-P4 may be in
      -- controller port 1 if a multitap is connected to port 1
      local controls = movie.getinput(emu.framecount() - 1,
                                      snes_controller_order[i]);
      -- Get first byte of SNES controller data
      for x = 1, #snes_controls / 2 do
        if (controls[snes_controls[x]]) then
          controller_input = controller_input + bit.lshift(1, x - 1);
        end
      end
      controller_input_buffer = (controller_input_buffer ..
                                 string.char(controller_input));
      controller_tcr_input_buffer = (controller_tcr_input_buffer ..
                                     string.char(controller_input));
      -- Get second byte of SNES controller data
      controller_input = 0;
      for x = 1, #snes_controls / 2 do
        if (controls[snes_controls[x + #snes_controls / 2]]) then
          controller_input = controller_input + bit.lshift(1, x - 1);
        end
      end
      controller_input_buffer = (controller_input_buffer ..
                                 string.char(controller_input));
      controller_tcr_input_buffer = (controller_tcr_input_buffer ..
                                     string.char(controller_input));
    end
  end
end

-- Initialize values upon movie startup
function setup_dump()
  controller_input_buffer = "";
  controller_tcr_input_buffer = "";
  client.unpause();
  movie_playing = true;
  frame_total = movie.length();
  rerecord_count = movie.getrerecordcount();
  local cur_time = os.time();
  file_name = movie.filename():match("(.+)%..+$");
  file_name = file_name .. "-" .. os.date("!%Y%m%d%H%M%S", os.time());
  setup_r_file();
  setup_tcr_file();
  if (console ~= "GBA") then
    print("Starting movie.\n");
    print("Replay files will not be finished writing until the movie is " ..
          "finished.\n");
  else
    print("Dumping GBA movie file.");
    print("GBA movie will start after replay file is finished being written.");
    print("Emulator may freeze for a moment.");
    print("Please be patient.\n");
  end
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
end

-- Start of dumping script
get_version();
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
        print("Select movie file and then unpause the emulator (Emulation > Pause)");
        print("DO NOT CHECK \"Last Frame\" OPTION IN \"Play Movie\" WINDOW\n");
      else
        movie_started = true;
      end
    end
    if (movie_started) then
      -- Movie is loaded/active
      if (movie_playing == false) then
        console = get_console();
        core = movie.getheader()["Core"];
        if (console == "SNES") then
          snes_get_controller_order();
        end
        if (max_players[console] == nil) then
          print("ERROR: Unsupported console type.  Load a ROM of a supported console type and try running this Lua script again.\n");
          break
        end
        setup_dump();
      else
        if (console == "GBA") then
          for i = 1, movie.length() do
            frame = i;
            handle_frame();
          end
          finish_r_file();
          finish_tcr_file();
          movie_playing = false;
          client.speedmode(100);
          print("Finished dumping GBA replay file.  Closing Lua Script.\n");
          break;
        else
          if (emu.framecount() > movie.length()) then
            -- End of movie
            print("Movie finished.\n");
            finish_r_file();
            finish_tcr_file();
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
