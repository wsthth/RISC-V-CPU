// ============================================================================
// tb_regfile.v - ¼Ä´æÆ÷¶Ñ²âÊÔ£ºÍ¬²½Ð´¡¢×éºÏ¶Á¡¢x0 ºã 0
// ============================================================================
`timescale 1ns/1ps
module tb_regfile;
    reg        clk = 0;
    reg        we3;
    reg  [4:0] a1, a2, a3;
    reg  [31:0] wd3;
    wire [31:0] rd1, rd2;
    integer errors = 0;

    regfile uut (.clk(clk), .we3(we3), .a1(a1), .a2(a2), .a3(a3),
                 .wd3(wd3), .rd1(rd1), .rd2(rd2));

    always #5 clk = ~clk;

    task check;
        input [31:0] exp;
        input [31:0] got;
        input [79:0] name;
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got %08X expect %08X", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("=== tb_regfile start ===");
        we3 = 0; a1 = 0; a2 = 0; a3 = 0; wd3 = 0;
        #10;
        // Ð´ x5 = 0xDEADBEEF
        a3 = 5'd5; wd3 = 32'hDEADBEEF; we3 = 1; #10;
        a3 = 5'd6; wd3 = 32'h12345678; #10;
        we3 = 0;
        // ¶Á»Ø
        a1 = 5'd5; a2 = 5'd6; #10;
        check(32'hDEADBEEF, rd1, "read x5");
        check(32'h12345678, rd2, "read x6");
        // x0 ºã 0
        a3 = 5'd0; wd3 = 32'hFFFFFFFF; we3 = 1; #10; we3 = 0;
        a1 = 5'd0; #10;
        check(32'h0, rd1, "x0 hardwired");
        // Î´Ð´¹ýµÄ¼Ä´æÆ÷Îª 0
        a1 = 5'd31; #10;
        check(32'h0, rd1, "unwritten reg");
        if (errors == 0)
            $display("TEST PASSED (regfile)");
        else
            $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
