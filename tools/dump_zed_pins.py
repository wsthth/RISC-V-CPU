import re
xml = open(r'D:\Xilinx\Vivado\2019.1\data\boards\board_files\zed\1.4\part0_pins.xml', encoding='utf-8', errors='replace').read()
# 打印剩余引脚（时钟等）
for line in xml.splitlines():
    if 'pin' in line:
        print(line.strip())
