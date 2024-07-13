
local a2d = require "annotation2doc"
local lfs = require "lfs"

local argparser = require "argparse"
local parser = argparser("annotation2doc", "Generate documentation from annotations in Lua source code.")
parser:flag("-v --version", "Print version and exit.", function()
  print("annotation2doc v" .. a2d.VERSION)
  os.exit(0)
end)

parser:option("-i --input","input file or dir")
parser:option("-o --out","output file or dir")
parser:flag("-c --class","build class documentation")
parser:flag("-e --enum","build enum documentation")
parser:flag("-g --global","build global documentation")
parser:flag("-m --module","build module documentation")
parser:flag("-a --all","build all documentation")

local args = parser:parse()
if not args.input then
  print("Error: input file or dir is required.")
  os.exit(1)
end

if not args.out then
  print("Error: output file or dir is required.")
  os.exit(1)
end


local function isdir(path)
  local attr = lfs.attributes(path)
  return attr and attr.mode == "directory"
end

local function createDirectories(path)
  local dirs = {}
  local path_separator = package.config:sub(1,1)

  for dir in string.gmatch(path, "([^"..path_separator.. "]+)") do
    dirs[#dirs+1] = dir
  end
  local current = ""
  for i, dir in ipairs(dirs) do
    current = current .. dir
    if not isdir(current) then
      lfs.mkdir(current)
    end
    current = current .. path_separator
  end
end

if not isdir(args.out) then
  createDirectories(args.out)
end

local function saveDoc(cache,out)
  if args.all or  args.class and cache.classes then
    a2d.writeClassesTo(out,cache.classes)
  end
  if args.all or args.enum and cache.enums then
    a2d.writeEnumsTo(out,cache.enums)
  end
  if args.all or args.module and cache.modules then
    a2d.writeModulesTo(out,cache.modules)
  end
end

local function saveGlobal(globals,out)
  if not globals or #globals ==0 then
    return
  end
  a2d.writeGlobalsTo(a2d.pathJon(out,"globals.md"),globals)
end

local function transformDir(dir,out,globals)
  globals = globals or {}
  for file in lfs.dir(dir) do
    if file ~= "." and file ~= ".." then
      local path = a2d.pathJon(dir,file)
      if isdir(path) then
        transformDir(path,out,globals)
      elseif string.find(path,"%.lua$") then
        print("start transform ",path)
        local cache = a2d.decodeCommonFromFile(path)
        saveDoc(cache,out)
        for index, value in ipairs(cache.globals) do
          globals[#globals+1] = value
        end
      end
    end
  end
end



if isdir(args.input) then
  local globals = {}
  transformDir(args.input,args.out,globals)
  saveGlobal(globals,args.out)
else
  local cache = a2d.decodeCommonFromFile(args.input)
  saveDoc(cache,args.out)
  saveGlobal(cache.globals,args.out)
end

