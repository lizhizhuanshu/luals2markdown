
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

if not isdir(args.out) then
  print("Error: output must be a directory.")
  os.exit(1)
end

local function saveDoc(input,out)
  local cache = a2d.decodeCommonFromFile(input)
  if args.all or  args.class and cache.classes then
    a2d.writeClassesTo(out,cache.classes)
  end
  if args.all or args.enum and cache.enums then
    a2d.writeEnumsTo(out,cache.enums)
  end
  if args.all or args.global and cache.globals then
    local path = a2d.pathJon(out,"globals.md")
    a2d.writeGlobalsTo(path,cache.globals,true)
    local file = io.open(path,"ab")
    assert(file)
    file:write("\r\n")
    file:close()
  end
  if args.all or args.module and cache.globals then
    a2d.writeModulesTo(out,cache.modules)
  end
end

if isdir(args.input) then
  for file in lfs.dir(args.input) do
    if file ~= "." and file ~= ".." then
      local path = a2d.pathJon(args.input,file)
      if isdir(path) then
        local out = a2d.pathJon(args.out,file)
        lfs.mkdir(out)
        saveDoc(path,out)
      elseif string.find(path,"%.lua$") then
        local out = a2d.pathJon(args.out,file)
        saveDoc(path,out)
      end
    end
  end
else
  saveDoc(args.input,args.out)
end

