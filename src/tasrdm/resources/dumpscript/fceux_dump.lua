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
local resets = {};
local frame_total = 0;
local rerecord_count = 0;
local rom_hash = "";
local base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
local frame = 0;
local nes_controls = {"right", "left", "down", "up", "start", "select", "B", "A"};

local file_name = "";
local r_file_name = "";
local tcr_file_name = "";
local r_file;
local tcr_file;

local controller_input_buffer = "";


-- If reset and not start of movie, add reset to resets table
function detect_reset()
  if (frame > 0) then
    table.insert(resets, frame);
  elseif (movie.framecount() > 1) then
    table.insert(resets, frame);
  end
end

function setup_r_file()
  r_file_name = file_name .. ".r08";
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
  content = content .. "\"console\":\"NES\",";
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
  local content = encode_base64(controller_input_buffer) .. "\"]";
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
  if (emu.lagged() == false) then
    for i = 1, 2 do
      local controls = joypad.get(i);
      local controller_input = 0;
      for x = 1, #nes_controls do
        if (controls[nes_controls[x]]) then
          controller_input = controller_input + bit.lshift(1, x - 1);
        end
      end
      controller_input_buffer = (controller_input_buffer ..
                                 string.char(controller_input));
    end
    -- Only write to files if controller_input_buffer is divisible by
    -- 3 so it can be encoded perfectly into base64 for TCR file
    if (#controller_input_buffer > 0 and #controller_input_buffer % 3 == 0) then
      r_file:write(controller_input_buffer);
      tcr_file:write(encode_base64(controller_input_buffer));
      controller_input_buffer = "";
    end
  end
end

function setup_dump()
  -- Movie has not been started since the lua script started
  controller_input_buffer = "";
  reset_value = memory.readbyteunsigned(0xfffd) * 256;
  reset_value = reset_value + memory.readbyteunsigned(0xfffc);
  movie.playbeginning();
  movie_playing = true;
  frame_total = movie.length();
  rerecord_count = movie.rerecordcount();
  rom_hash = "md5:" .. rom.gethash("md5");
  file_name = movie.name():match("(.+)%..+$");
  file_name = file_name .. "-" .. os.date("!%Y%m%d%H%M%S", os.time());
  setup_r_file();
  setup_tcr_file();
  print("Starting movie.\n");
  print("Replay files will not be finished writing until the movie is " ..
        "finished.\n");
  emu.speedmode("maximum");
  resets = {};
  frame = 0;
  memory.registerexec(reset_value, detect_reset);
end

-- Movie loop
while (true) do
  if (movie.active()) then
    -- Movie is loaded/active
    if (movie_playing == false) then
      setup_dump();
    else
      if (movie.framecount() > movie.length()) then
        -- End of movie
        print("Movie finished.\n");
        finish_r_file();
        finish_tcr_file();
        movie_playing = false;
        movie.close();
        emu.speedmode("normal");
      elseif (movie.framecount() > 1) then
        handle_frame();
      end
    end
  end
  -- Go to next frame (allow ROM to progress forward)
  emu.frameadvance();
end
