// LAB3-23 · MM:SS 시계 — 자기검사 테스트벤치
// PDF: "tb_mmss_counter.sv" 슬라이드(19~20쪽)의 검증 내용을 기반으로,
// simulation.json이 요구하는 simulation_top="tb_design"에 맞춰 모듈명만 변경하고
// 검사마다 PASS 메시지를 추가했다.
`timescale 1ns/1ps
module tb_design;
    reg clk_50mhz = 0, rst_p = 1;
    wire [3:0] mt, mo, st, so;
    reg  [3:0] decode_digit;
    wire [7:0] decoded_segments;
    integer checks = 0;

    always #10 clk_50mhz = ~clk_50mhz;

    // CLK_HZ=2 : 실제 50MHz 대신 클록 2회(40ns)마다 1초 tick이 발생하도록 축소한다.
    // TB의 클록 주기(#10 → 20ns)는 실제 보드의 20ns(50MHz)와 동일하게 유지한다.
    mmss_counter #(.CLK_HZ(2)) dut (
        .clk(clk_50mhz), .rst_p(rst_p),
        .minute_tens(mt), .minute_ones(mo),
        .second_tens(st), .second_ones(so)
    );
    sevenseg_decode decoder (.digit(decode_digit), .segments(decoded_segments));

    task advance(input integer seconds);
        begin
            repeat (seconds * 2) @(posedge clk_50mhz);
        end
    endtask

    task check_time(input integer emt, input integer emo, input integer est, input integer eso);
        begin
            if (mt !== emt || mo !== emo || st !== est || so !== eso)
                $fatal(1, "time mismatch: got %0d%0d:%0d%0d expected %0d%0d:%0d%0d",
                       mt, mo, st, so, emt, emo, est, eso);
            checks = checks + 1;
            $display("PASS: check %0d time=%0d%0d:%0d%0d", checks, mt, mo, st, so);
        end
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_design);

        // 7-세그먼트 디코더 단독 검사 (0, 9)
        decode_digit = 0; #1;
        if (decoded_segments !== 8'b1111_1100) $fatal(1, "digit 0 decode mismatch");
        checks = checks + 1;
        $display("PASS: check %0d digit0 decode=%b", checks, decoded_segments);

        decode_digit = 9; #1;
        if (decoded_segments !== 8'b1111_0110) $fatal(1, "digit 9 decode mismatch");
        checks = checks + 1;
        $display("PASS: check %0d digit9 decode=%b", checks, decoded_segments);

        // 리셋 해제
        repeat (2) @(posedge clk_50mhz);
        rst_p = 0;
        check_time(0, 0, 0, 0);      // 리셋 해제 직후 00:00

        advance(10);
        check_time(0, 0, 1, 0);      // 00:09 -> 00:10 경계 (초 캐리)

        advance(50);
        check_time(0, 1, 0, 0);      // 00:59 -> 01:00 경계 (분 캐리)

        advance(3539);
        check_time(5, 9, 5, 9);      // 59:59 최대값

        advance(1);
        check_time(0, 0, 0, 0);      // 59:59 -> 00:00 롤오버 (전체 3600초 순환)

        $display("LAB3_MMSS_PASS checks=%0d", checks);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "timeout");
    end
endmodule
