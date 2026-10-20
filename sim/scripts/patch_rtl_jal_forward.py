# -*- coding: utf-8 -*-
# v0.13: fix forward data path for JAL link value
# Root cause: WB writes pcplus4 (link) for JAL (resultsrc=2'b10), but the forward
# data paths mem_result_m / wb_result_w use alu_result (branch target) for JAL.
# With predictor now doing direct jumps (no full flush), an instruction 1-2 cycles
# behind a JAL that reads x1 gets the WRONG forwarded value (target instead of link),
# e.g. __umodsi3's 'mv t0,ra' read 0x3354 (target) instead of 0x2890 (link) -> livelock.
# Fix: forward pcplus4 when resultsrc==2'b10.
import io, sys

def patch_file(path, edits):
    data = io.open(path, 'rb').read()
    eol = b'\r\n' if b'\r\n' in data else b'\n'
    for edit in edits:
        old, new = edit[0], edit[1]
        need = 2 if (len(edit) > 2 and edit[2]) else 1
        ob = old.replace('\n', eol.decode()).encode('ascii')
        nb = new.replace('\n', eol.decode()).encode('ascii')
        cnt = data.count(ob)
        if cnt < need:
            print('FAIL no match(%d<%d) in %s:' % (cnt, need, path)); print('---'); print(old); print('---')
            sys.exit(1)
        data = data.replace(ob, nb, need)
    io.open(path, 'wb').write(data)
    print('OK patched', path, '(%d edits)' % len(edits))

rtl = r'D:\my_project\RISC-V\rtl\pipeline\riscv_pipeline.v'
edits = [
    # MEM-stage forward: JAL -> pcplus4 (link), load -> readdata, else alu_result
    ("assign mem_result_m = resultsrc_m[0] ? readdata_m : alu_result_m;",
     "assign mem_result_m = (resultsrc_m == 2'b10) ? pcplus4_m :\n"
     "                      (resultsrc_m[0] ? readdata_m : alu_result_m);   // v0.13 JAL link forward"),
    # WB-stage forward: JAL -> pcplus4 (link), load -> readdata_final, else alu_result
    ("assign wb_result_w = resultsrc_w[0] ? readdata_final : alu_result_w;",
     "assign wb_result_w = (resultsrc_w == 2'b10) ? pcplus4_w :\n"
     "                      (resultsrc_w[0] ? readdata_final : alu_result_w);   // v0.13 JAL link forward"),
]
patch_file(rtl, edits)
print('ALL PATCHED')
