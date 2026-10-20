# -*- coding: utf-8 -*-
# v0.15: replace the fetch-address based dup_fetch (false positives after
# load-use stall release) with a CONTENT based rule:
#   dup = (pc_f2 == pc_id) && valid_id && ~pred_taken_eff
# The IF2 register lags a_r by one cycle; after a stall release the IF2 holds
# the same instruction for an extra cycle and reg_ifid re-captures it (double
# commit), while a_r has already advanced - so address equality misses the dup
# and later false-positives on the legitimate next capture. Comparing the IF2
# content against the ID content catches the dup exactly (same instruction still
# in ID). ~pred_taken_eff keeps self-loops / branch chains (predict-taken
# re-execution is architecturally correct) untouched. prev_cap_valid no longer
# needed: the mispredict target capture is protected by valid_id==0 (flushed ID).
import io, sys

def patch_file(path, edits):
    data = io.open(path, 'rb').read()
    eol = b'\r\n' if b'\r\n' in data else b'\n'
    for edit in edits:
        old, new, need = edit[0], edit[1], (edit[2] if len(edit) > 2 else 1)
        ob = old.replace('\n', eol.decode()).encode('ascii')
        nb = new.replace('\n', eol.decode()).encode('ascii')
        cnt = data.count(ob)
        if cnt < need:
            print('FAIL no match(%d<%d) in %s:' % (cnt, need, path)); print('---'); print(old); print('---')
            sys.exit(1)
        data = data.replace(ob, nb, need)
    io.open(path, 'wb').write(data)
    print('OK patched', path)

rtl = r'D:\my_project\RISC-V\rtl\pipeline\riscv_pipeline.v'
edits = [
    ("    assign instr_f = instr_f2;\n"
     "    // v0.14 FINAL: kill ONLY the spurious duplicate target read after a\n"
     "    // PRED-TAKEN redirect (double commit). The registered valid_f2\n"
     "    // suppression updates one cycle late, so reg_ifid samples the pre-edge\n"
     "    // value and lets the duplicate enter ID valid. Suppress combinationally:\n"
     "    //  - prev_cap_valid: the previous capture was valid (pred redirect);\n"
     "    //    after a mispredict the previous capture was flushed (valid=0) and\n"
     "    //    the re-read is the INTENDED target capture - never suppress it.\n"
     "    //  - ~pred_taken_eff: self-loops / branch chains must re-execute the\n"
     "    //    predicted-taken address (j to itself) - never suppress those.\n"
     "    reg         prev_cap_valid;\n"
     "    wire        dup_fetch;\n"
     "    wire        valid_ifid_in;\n"
     "    always @(posedge clk or posedge reset) begin\n"
     "        if (reset || reset_d)        prev_cap_valid <= 1'b0;\n"
     "        else if (mispredict)         prev_cap_valid <= 1'b0;\n"
     "        else if (stalld)             prev_cap_valid <= prev_cap_valid;\n"
     "        else                         prev_cap_valid <= valid_ifid_in;\n"
     "    end\n"
     "    assign dup_fetch = (a_r == addr_prev) && (pcf != pcf_prev) && prev_cap_valid && ~pred_taken_eff;\n"
     "    assign valid_ifid_in = dup_fetch ? 1'b0 : valid_f2;",
     "    assign instr_f = instr_f2;\n"
     "    // v0.15: suppress the spurious DOUBLE CAPTURE at reg_ifid by comparing\n"
     "    // the IF2 content against the ID content (NOT the fetch address):\n"
     "    //   dup = (pc_f2 == pc_id) && valid_id && ~pred_taken_eff\n"
     "    // The IF2 register lags a_r by one cycle. After a load-use stall release\n"
     "    // the else-branch re-captures the frozen a_r, so the IF2 holds the same\n"
     "    // instruction for an extra cycle and reg_ifid re-captures it (double\n"
     "    // commit), while a_r has already advanced - an address-based rule misses\n"
     "    // this dup and later false-positives on the legitimate next capture.\n"
     "    // Content equality (same pc still valid in ID) catches all dup sources:\n"
     "    //  - stall-release lag (lbu re-captured, sw skipped - full.s FAIL)\n"
     "    //  - pred-taken redirect target re-read (CoreMark double commit)\n"
     "    //  - mispredict target repeat (flush clears valid_id -> not suppressed,\n"
     "    //    the intended target capture is protected)\n"
     "    // ~pred_taken_eff: self-loops / branch chains whose address IS predicted\n"
     "    // taken (j to itself) are architecturally correct re-executions - never\n"
     "    // suppress them.\n"
     "    wire        dup_fetch;\n"
     "    wire        valid_ifid_in;\n"
     "    assign dup_fetch = (pc_f2 == pc_id) && valid_id && ~pred_taken_eff;\n"
     "    assign valid_ifid_in = dup_fetch ? 1'b0 : valid_f2;"),
]
patch_file(rtl, edits)
print('ALL PATCHED v0.15')
