
local path_separator = package.config:sub(1,1)

local function pathJoin(...)
  local r = {...}
  return table.concat(r,path_separator)
end

local parserDir = pathJoin("luaparser","src")
local commonFind = pathJoin(parserDir,"?.lua")
local initFind = pathJoin(parserDir,"?","init.lua")
local devFind = pathJoin("dev","?.lua")
package.path = package.path .. ";" .. commonFind .. ";" .. initFind .. ";" .. devFind

local parser = require "parser"
local util = require "utility"


local function printKey(t)
  for key, value in pairs(t) do
    print(key)
  end
end
---@class FieldType
---@field name string
---@field comment? string
---@field args? Field[]
---@field returns? Field[]

---@class Field
---@field name string
---@field comment? string
---@field types FieldType[]

---@class CustomType:FieldType
---@field fields Field[]
---@field parents? string[]

local function printT(t,indent,record)
  indent = indent or 0
  record = record or {}
  for key, value in pairs(t) do
    if key == "parent" then
      goto continue
    end
    if type(value) == "table" then
      if not record[value] then
        record[value] = true
        print(string.rep(" ",indent) .. key .. ":")
        printT(value,indent + 2,record)
      else
        print(string.rep(" ",indent) .. key .. " : " .. tostring(value))
      end
    else
      print(string.rep(" ",indent) .. key .. " : " .. tostring(value))
    end
    ::continue::
  end
end

---@type fun(field:parser.object):Field
local decodeField
---@type fun(field:parser.object):Field[]
local decodeFields
---@type fun(fieldType:parser.object):FieldType[]
local decodeFieldTypes


---@param fieldType parser.object
---@return FieldType
local function decodeFieldType(fieldType)
  if fieldType.type == "doc.type.function" then
    local args = decodeFields(fieldType.args)
    local returns = decodeFields(fieldType.returns)
    return {
      name = "function",
      args = args,
      returns = returns
    }
  else
    return {
      name = fieldType[1]
    }
  end
end

---@param types parser.object
decodeFieldTypes = function(types)
  local r = {}
  for index, value in ipairs(types) do
    table.insert(r,decodeFieldType(value))
  end
  return r
end

decodeField = function (field) 
  local name
  if field.field then
    name = field.field[1]
  elseif field.name then
    name = field.name[1]
  end
  local comment
  if field.comment then
    comment = field.comment.text
  end
  -- if not name then
  --   pringT(field)
  -- end
  local rTypes
  local types = field.types
  if not types then
    if field.extends then
      types = field.extends.types
    end
  end
  if types then
    rTypes = decodeFieldTypes(types)
  end

  return {
    name = name,
    comment = comment,
    types = rTypes
  }
end

decodeFields = function (fields)
  local r = {}
  for index, value in ipairs(fields) do
    table.insert(r,decodeField(value))
  end
  return r
end

---@param arg parser.object
---@return Field
local function decodeLocalFunctionArg(arg)
  local name = arg[1]
  local type = arg.type
  local ot
  if type == "self" then
    ot = {{name ="self"}}
  else
    if arg.bindDocs then
      ot = decodeFieldTypes(arg.bindDocs[1].extends.types)
    else
      ot = {{name="any"}}
    end
  end
  return {
    name = name,
    types = ot
  }
end

local function decodeLocalFunctionArgs(args)
  local r = {}
  for index, value in ipairs(args) do
    r[index] = decodeLocalFunctionArg(value)
  end
  return r
end

local function resetArg(args,argName,argType,comment)
  for index, arg in ipairs(args) do
    if arg.name == argName then
      arg.types = argType
      arg.comment = comment
      return
    end
  end
end

---@param docReturn parser.object
---@return Field
local function decodeReturn(docReturn)
  local comment
  if docReturn.comment then
    comment = docReturn.comment.text
  end
  local root = docReturn.returns[1]
  local name
  if root.name then
    name = root.name[1]
  end
  local types = decodeFieldTypes(root.types)
  return {
    name = name,
    comment = comment,
    types = types
  }
end

local function appendType(types,newType)
  for index, value in ipairs(types) do
    if value.name == newType.name then
      return
    end    
  end
  types[#types+1] = newType
end

---@param docs parser.object
---@param localField Field
local function perfectLocalField(docs,localField)
  local returns = localField.types[1].returns
  local args = localField.types[1].args
  local comments = {}
  for index, doc in ipairs(docs) do
    if doc.type == "doc.param" then
      local name = doc.param[1]
      local type = decodeFieldTypes(doc.extends.types)
      local comment 
      if doc.comment then
        comment = doc.comment.text
      end
      resetArg(args,name,type,comment)
    elseif doc.type == "doc.return" then
      returns[#returns+1] = decodeReturn(doc)
    elseif doc.type == "doc.comment" then
      comments[#comments+1] = doc.comment.text
    elseif doc.type == "doc.type" then
      local types = decodeFieldTypes(doc.types)
      localField.types = types
    elseif doc.type == "doc.enum" then
      localField.types = {{name=doc.enum[1]}}
    else
      -- error("unknown type:" .. doc.type)
    end
  end
  if #comments>0 then
    localField.comment = table.concat(comments,"\r\n")
  end
end

---@param setMethod parser.object
---@return Field
local function decodeSetMethod(setMethod)
  local name = setMethod.method[1]
  local method = setMethod.value
  print("set method",name)
  local args = decodeLocalFunctionArgs(method.args)
  local returns = {}
  local r = {
    name = name,
    types = {
      {
        name = "function",
        args = args,
        returns = returns
      }
    }
  }
  if method.bindDocs then
    perfectLocalField(method.bindDocs,r)
  end
  return r
end


---@param source parser.object
---@param callback fun(field:parser.object)
local function eachLocalTableAllSetMethod(source,callback)
  if not source then
    return
  end
  local ref = source.ref
  if not ref then
    return
  end
  for index, value in ipairs(ref) do
    local next = value.next
    while next do
      if next.type == "setmethod" or next.type == "setfield" then
        callback(next)
      else
        print("unknown type", next.type)
      end
      next = next.next
    end
  end
end


local function decodeSetField(setField,field)
  local name = setField.field[1]
  local value = setField.value
  local aType
  if value.type == "function" then
    aType = {
      name = "function",
      args = decodeLocalFunctionArgs(value.args),
      returns = {}
    }
  else
    aType = {
      name = value.type,
    }
  end
  local v 
  if type(value[1]) ~= "table" then
    v = value[1]
  end
  local r = {
    name = name,
    types = {aType},
    value = v
  }

  local docs = setField.bindDocs or value.bindDocs
  if docs then
    perfectLocalField(docs,r)
  end
  return r
end

local function decodeTableLocalField(source,fields)
  eachLocalTableAllSetMethod(source,function(setMethod)
    local field
    if setMethod.type == "setmethod" then
      field = decodeSetMethod(setMethod)
    else
      field = decodeSetField(setMethod)
    end
    fields[#fields+1] = field
  end)
end

local function decodeComments(comments)
  if not comments then
    return
  end
  local r = {}
  for index, value in ipairs(comments) do
    r[index] = value.comment.text
  end
  return table.concat(r,"\r\n")
end

---@param field parser.object
local function decodeTableField(field)
  local name = field.field[1]
  local v = field.value
  local type
  local value
  if v.type == "function" then
    type = {
      name = "function",
      args = decodeLocalFunctionArgs(v.args),
      returns = {}
    }
  else
    type = {
      name = v.type,
    }
    value = v[1]
  end
  local r = {
    name = name,
    types = {type},
    value = value
  }
  if field.bindDocs then
    perfectLocalField(field.bindDocs,r)
  end
  return r
end

---@param t parser.object
local function decodeTableFields(t)
  local r = {}
  for index, fieldInfo in ipairs(t) do
    r[index] = decodeTableField(fieldInfo)
  end
  return r
end

---@param clazz parser.object
---@return CustomType
local function decodeClass(clazz)
  local fields
  if clazz.bindSource then
    fields = decodeTableFields(clazz.bindSource.value)
  else
    fields = {}
  end
  local r = {
    name = clazz.class[1],
    comment = decodeComments(clazz.bindComments),
    fields = fields
  }
  if clazz.extends then
    local superClass = {}
    for index, value in ipairs(clazz.extends) do
      superClass[index] = value[1]
    end
    r.parents = superClass
  end
  local fields = decodeFields(clazz.fields)
  for index, value in ipairs(fields) do
    r.fields[#r.fields+1] = value
  end
  decodeTableLocalField(clazz.bindSource,r.fields)
  return r
end

local function decodeEnum(enum)
  local r = {
    name = enum.enum[1],
    comment = decodeComments(enum.bindComments),
    fields = decodeTableFields(enum.bindSource)
  }
  return r
end


---@param setGlobal parser.object
local function decodeSetGolbal(setGlobal,index)
  local name = setGlobal[1]
  local value = setGlobal.value
  local aType
  if value.type == "function" then
    aType = {
      name = "function",
      args = decodeLocalFunctionArgs(value.args),
      returns = {}
    }
  else
    aType = {
      name = value.type,
    }
  end
  local r = {
    name = name,
    types = {aType},
  }
  local docs = setGlobal.bindDocs or value.bindDocs
  if docs then
    perfectLocalField(docs,r)
  end
  return r
end

local function isClass(obj)
  if not obj.bindDocs then
    return false
  end
  for index, doc in ipairs(obj.bindDocs) do
    if doc.type == "doc.class" then
      return true
    end
  end
  return false
end

local function isModule(ast)
  local size = #ast
  local obj = ast[size]
  if obj == nil then
    return false
  end
  return obj.type == "return" and obj[1].node.type == "local"
    and not isClass(obj[1].node)
end

local function decodeModule(ast)
  local size = #ast
  local obj = ast[size][1].node.ref[1]
  local tableSource = obj.node.value
  local r = {
    fields = decodeTableFields(tableSource),
    types = {{name="table"}}
  }
  -- print(obj.node.type)

  decodeTableLocalField(obj.node,r.fields)
  if obj.node.bindDocs then
    perfectLocalField(obj.node.bindDocs,r)
  end
  
  return r
end

local function decodeCommonNode(typeCache,cache)
  if not typeCache then
    return
  end
  if typeCache['doc.enum'] then
    local enums = cache.enums
    for index, enum in ipairs(typeCache['doc.enum']) do
      enums[#enums+1] = decodeEnum(enum)
    end
  end
  if typeCache['doc.class'] then
    local classes = cache.classes
    for index, clazz in ipairs(typeCache['doc.class']) do
      classes[#classes+1] = decodeClass(clazz)
    end
  end

  if typeCache['setglobal'] then
    local globals = cache.globals
    for index, setGlobal in ipairs(typeCache['setglobal']) do
      globals[#globals+1] = decodeSetGolbal(setGlobal,index)
    end
  end

end

local function loadState(path)
  local state = parser.compile(util.loadFile(path),'Lua', 'Lua 5.4')
  parser.luadoc(state)
  return state
end

local function decodeCommonFromFile(path,cache)
  cache = cache or {
    enums = {},
    classes = {},
    globals = {},
    modules = {}
  }
  local state = loadState(path)
  decodeCommonNode(state.ast._typeCache,cache)
  if isModule(state.ast) then
    local m = decodeModule(state.ast)
    m.name = string.match(path,"([^/]+)%.lua$")
    cache.modules[#cache.modules+1] = m
  end
  return cache
end

local function printTypeCache(path)
  local state = parser.compile(util.loadFile(path),'Lua', 'Lua 5.4')
  parser.luadoc(state)
  printKey(state.ast._typeCache)
end

local string_find = string.find
local string_sub = string.sub
local function split(s,p)
    local last = 1
    local o = last
    local e
    local r = {}
    while o <=#s do
        o,e  = string_find(s,p,o,true)
        if o then
            r[#r+1] = string_sub(s,last,o-1)
            last = e+1
            o = last
        else
            r[#r+1] = string_sub(s,last,#s)
            break
        end
    end
    return r
end


local function repairOneComment(comment)
  local _,s = string.match(comment,"^([- ]*)(.-)$")
  return s
end

local function repairComment(comment)
  local t = split(comment,"\r\n")
  for index, value in ipairs(t) do
    t[index] = repairOneComment(value)
  end
  return table.concat(t,"\r\n")
end

---@return Field[]
local function findMemberVariable(fields)
  local r = {}
  for index, field in ipairs(fields) do
    if field.types[1].name ~= "function" then
      r[#r+1] = field
    end
  end
  return r
end

---@type fun(funType:FieldType):string
local generateSimFunTypeString

local function isNativateType(name)
  return name == "number" or 
  name == "string" or 
  name == "boolean" or 
  name == "table" or 
  name == "function" or
  name == "integer" or
  name == "nil" or
  name == "any" or
  name == "unknown"
end

local function generateSimTypeStr(fieldType)
  if fieldType.name == "function" then
    return generateSimFunTypeString(fieldType)
  else
    local name = fieldType.name
    if not name then
      return ""
    end
    return isNativateType(name) and name or string.format("[%s](%s.md)",name,name)
  end
end
local function generateTypesString(types)
  local r = {}
  for index, fieldType in ipairs(types) do
    r[#r+1] = generateSimTypeStr(fieldType)
  end
  return table.concat(r,"|")
end

---@param field Field
local function generateFieldStr(field)
  local r = generateTypesString(field.types)
  local comment = field.comment or ""
  local name = field.name or ""
  return string.format("%s : %s    %s",name,r,comment)
end

generateSimFunTypeString = function(funType)
  local args = generateTypesString(funType.args)
  local returns = generateTypesString(funType.returns)
  return string.format("function(%s)%s",args,returns)
end
---@return Field[]
local function findMemberMethod(fields)
  local r = {}
  for index, field in ipairs(fields) do
    if field.types[1].name == "function" then
      r[#r+1] = field
    end
  end
  return r
end

---@param funType FieldType
local function generateFunTypeString(funType,out)
  if funType.args and #funType.args>0 then
    if funType.args[1].name ~= "self" or #funType.args>1 then
      out[#out+1] = "#### 参数"
    end
    for index, arg in ipairs(funType.args) do
      if not(index == 1 and arg.name == "self") then
        out[#out+1] = string.format("- %s",generateFieldStr(arg))
      end

    end
  end
  if funType.returns and #funType.returns>0 then
    out[#out+1] = "#### 返回值"
    for index, ret in ipairs(funType.returns) do
      out[#out+1] = string.format("- %s",generateFieldStr(ret))
    end
  end
end


---@param aModule CustomType
local function generateModuleStr(aModule)
  local r = {}
  r[#r+1] = string.format("# %s 模块",aModule.name)
  if aModule.comment then
    r[#r+1] = repairComment(aModule.comment)
  end
  local variable = findMemberVariable(aModule.fields)
  if #variable>0 then
    r[#r+1] = "## 变量"
    for index, field in ipairs(variable) do
      r[#r+1] = string.format("### %s",field.name)
      if field.comment then
        r[#r+1] = repairComment(field.comment)
      end
      r[#r+1] = "#### 类型"
      r[#r+1] = generateTypesString(field.types)
    end
  end
  local funs = findMemberMethod(aModule.fields)
  if #funs>0 then
    r[#r+1] = "## 方法"
    for index, field in ipairs(funs) do
      r[#r+1] = string.format("### %s",field.name)
      if field.comment then
        r[#r+1] = repairComment(field.comment)
      end
      generateFunTypeString(field.types[1],r)
      r[#r+1] = ""
    end
  end
  return table.concat(r,"\r\n")
end
---@param parents string[]
local function generateParentClassesStr(parents)
  local r = {}
  for index, name in ipairs(parents) do
    r[index] = isNativateType(name) and name or string.format("[%s](%s.md)",name,name)
  end
  return table.concat(r,",")
end
---@param clazz CustomType
local function generateClassStr(clazz)
  local r = {}
  r[#r+1] = string.format("# %s 类",clazz.name)
  if clazz.parents then
    r[#r+1] = string.format("## 继承 %s",generateParentClassesStr(clazz.parents))
  end
  if clazz.comment then
    r[#r+1] = repairComment(clazz.comment)
  end
  local variable = findMemberVariable(clazz.fields)
  if #variable>0 then
    r[#r+1] = "## 变量"
    for index, field in ipairs(variable) do
      r[#r+1] = string.format("### %s : %s",field.name,generateTypesString(field.types))
      if field.comment then
        r[#r+1] = repairComment(field.comment)
      end
    end
  end
  local funs = findMemberMethod(clazz.fields)
  if #funs>0 then
    r[#r+1] = "## 方法"
    for index, field in ipairs(funs) do
      r[#r+1] = string.format("### %s",field.name)
      if field.comment then
        r[#r+1] = repairComment(field.comment)
      end
      generateFunTypeString(field.types[1],r)
      r[#r+1] = "\r\n"
    end
  end
  return table.concat(r,"\r\n")
end

local function generateEnumStr(enum)
  local r = {}
  r[#r+1] = string.format("# %s 枚举",enum.name)
  if enum.comment then
    r[#r+1] = repairComment(enum.comment)
  end
  for index, field in ipairs(enum.fields) do
    r[#r+1] = string.format("### %s",field.name)
    if field.comment then
      r[#r+1] = repairComment(field.comment)
    end
    r[#r+1] = "\r\n"
  end
  return table.concat(r,"\r\n")
end

---@param types FieldType[]
local function isAloneFun(types)
  return #types == 1 and types[1].name == "function"
end

local function generateGlobalsStr(globals)
  if not globals then
    return ""
  end
  local r = {}
  r[#r+1] = "# 全局变量"
  for index, global in ipairs(globals) do
    r[#r+1] = string.format("## %s",global.name)
    if global.comment then
      r[#r+1] = repairComment(global.comment)
    end
    if isAloneFun(global.types) then
      generateFunTypeString(global.types[1],r)
    else
      r[#r+1] = string.format("类型 %s",generateTypesString(global.types))
    end
  end
  return table.concat(r,"\r\n")
end

local function save(path,data)
  local f = io.open(path,"wb")
  assert(f,"can't open file:" .. path)
  f:write(data)
  f:close()
end


---@param classes CustomType[]
local function writeClassesTo(dir,classes)
  for index, value in ipairs(classes) do
    local data = generateClassStr(value)
    save(dir .. path_separator .. value.name .. ".md",data)
  end
end

local function writeModuleTo(dir,modules)
  for index, value in ipairs(modules) do
    local data = generateModuleStr(value)
    save(dir .. path_separator .. value.name .. ".md",data)
  end
end

local function writeEnumsTo(dir,enums)
  for index, value in ipairs(enums) do
    local data = generateEnumStr(value)
    save(dir .. path_separator .. value.name .. ".md",data)
  end
end

local function readData(path)
  local file = io.open(path,"rb")
  if file then
    local data = file:read("*a")
    file:close()
    return data
  end
end

local function writeGlobalsTo(path,cache)
  local data = generateGlobalsStr(cache)
  save(path,data)
end

local function writeCommonTo(dir,cache)
  writeClassesTo(dir,cache.classes)
  writeModuleTo(dir,cache.modules)
  writeEnumsTo(dir,cache.enums)
  writeGlobalsTo(dir,cache.globals)
end


return {
  VERSION = "0.0.1",
  pathJon = pathJoin,
  printT = printT,
  decodeCommonFromFile = decodeCommonFromFile,
  writeClassesTo = writeClassesTo,
  writeModulesTo = writeModuleTo,
  writeGlobalsTo = writeGlobalsTo,
  writeCommonTo = writeCommonTo,
  writeEnumsTo = writeEnumsTo
}