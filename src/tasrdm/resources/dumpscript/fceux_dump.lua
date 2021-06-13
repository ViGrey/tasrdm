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

local reset_value = 0;
local movie_playing = false;
local file_name = "";
local player_active = {};
local player_controls = {};
local lag_frame = false;
local resets = {};
local frame_total = 0;
local rerecord_count = 0;
local rom_hash = "";
local base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
local frame = 0;
local nes_controls = {"right", "left", "down", "up", "start", "select", "B", "A"}


-- Write the r08/r16m file
function write_r_file()
  local r_file_name = file_name .. ".r08"
  print("Writing to " .. r_file_name)
  print("Emulator may freeze for a moment.")
  print("Please be patient.\n");
  local content = ""
  for x = 1, #player_controls[1] do
    for i = 1, #player_controls do
      content = content .. string.sub(player_controls[i], x, x)
    end
  end
  rfile = io.open(r_file_name, "wb+");
  rfile:write(content);
  rfile:close();
  print("Finished writing to " .. r_file_name .. "\n");
end

-- Write the TCR (TAS Console Replay) file
function write_tcr_file()
  print("Writing to " .. file_name .. ".tcr")
  print("Emulator may freeze for a moment.")
  print("Please be patient.\n");
  local content = "{";
  content = content .. "\"console\":\"NES\",";
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
  content = content .. "\"blank\":0,";
  content = content .. "\"clock_filter\":4,";
  content = content .. "\"dpcm\":true,";
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
  content = content .. "\"inputs\":";
  local inputs_str = "[";
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
  tcrfile:write(content);
  tcrfile:close();
  print("Finished writing to " .. file_name .. ".tcr\n");
end

-- If reset and not start of movie, add reset to resets table
function detect_reset()
  if (frame > 0) then
    table.insert(resets, frame);
  elseif (movie.framecount() > 1) then
    table.insert(resets, frame);
  end
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
  if (emu.lagged() == false) then
    for i = 1, #player_controls do
      local controls = joypad.get(i);
      local controller_input = 0;
      for x = 1, #nes_controls do
        if (controls[nes_controls[x]]) then
          controller_input = controller_input + bit.lshift(1, x - 1);
          player_active[i] = true;
        end
      end
      player_controls[i] = player_controls[i] .. string.char(controller_input)
    end
    frame = frame + 1;
  end
end

function setup_dump()
  -- Movie has not been started since the lua script started
  print("Starting movie. Replay file will be written after movie is finished.\n");
  reset_value = memory.readbyteunsigned(0xfffd) * 256;
  reset_value = reset_value + memory.readbyteunsigned(0xfffc);
  movie.playbeginning();
  movie_playing = true;
  frame_total = movie.length();
  rerecord_count = movie.rerecordcount();
  rom_hash = "md5:" .. rom.gethash("md5");
  file_name = movie.name():match("(.+)%..+$");
  emu.speedmode("maximum");
  resets = {};
  frame = 0
  player_active = { false, false };
  player_controls = { "", "" };
  memory.registerexec(reset_value, detect_reset);
end

-- Movie loop
while (true) do
  if (movie.active()) then
    -- Movie is loaded/active
    if (movie_playing == false) then
      setup_dump();
    else
      if (movie.framecount() > movie.length() + 1) then
        -- End of movie
        print("Movie finished.\n")
        write_tcr_file();
        write_r_file();
        movie_playing = false;
        movie.close();
        emu.speedmode("normal");
      end
      if (movie.framecount() > 1) then
        handle_frame();
      end
    end
  end
  -- Go to next frame (allow ROM to progress forward)
  emu.frameadvance();
end
