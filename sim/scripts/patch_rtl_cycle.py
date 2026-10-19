# -*- coding: utf-8 -*-
"""字节级替换 riscv_pipeline.v（CRLF 行尾）。"""
path = r'D:\my_project\RISC-V\rtl\pipeline\riscv_pipeline.v'
data = open(path, 'rb').read()
n = data.count(b'\r\n')
print('CRLF count:', n)

# 1) 顶部 MEM 声明区
old1 = b"    // ---- MEM ----\r\n    wire [31:0] readdata_m;\r\n    wire        io_write_m;"
new1 = b"    // ---- MEM ----\r\n    wire [31:0] readdata_m;\r\n    wire [31:0] readdata_dmem;\r\n    wire        io_write_m;"
assert data.count(old1) == 1, 'decl block: %d' % data.count(old1)
data = data.replace(old1, new1, 1)

# 2) dmem_i 实例 .rd(readdata_m)
old2 = b"        .wd(writedata_m),\r\n        .rd(readdata_m)\r\n    );"
new2 = b"        .wd(writedata_m),\r\n        .rd(readdata_dmem)\r\n    );\r\n"
assert data.count(old2) == 1, 'dmem inst: %d' % data.count(old2)
data = data.replace(old2, new2, 1)

# 3) 在 dmem 实例后的 "    // MMIO" 注释（最后一处）前插入 cycle 计数器
anchor = b"    // MMIO"
last = data.rfind(anchor)
assert last > 0, 'MMIO anchor not found'
assert data.count(anchor) >= 2, 'MMIO anchor expect >=2: %d' % data.count(anchor)
ins = (b"    reg [31:0] cycle_cnt;\r\n"
       b"    always @(posedge clk or posedge reset) begin\r\n"
       b"        if (reset) cycle_cnt <= 32'b0;\r\n"
       b"        else       cycle_cnt <= cycle_cnt + 32'd1;\r\n"
       b"    end\r\n"
       b"    wire mmio_read_m = memread_m & valid_m & (alu_result_m == 32'hF0000004);\r\n"
       b"    assign readdata_m = mmio_read_m ? cycle_cnt : readdata_dmem;\r\n"
       b"\r\n")
data = data[:last] + ins + data[last:]

open(path, 'wb').write(data)
print('OK total bytes:', len(data))
