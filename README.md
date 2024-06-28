

# luals2markdown
将luaLS的注解提取出来并转换成markdown的文档

## 依赖
### lua运行依赖以下库
- argparse
- luafilesystem
- lpeglabel

使用luarocks安装
```shell
sudo luarocks install argparse luafilesystem lpeglabel
```

## 使用
```shell
cd luals2markdown
lua main.lua -i [输入文件或目录] -o [输入文件或目录] -a
```
更详细参见[main.lua](./main.lua)