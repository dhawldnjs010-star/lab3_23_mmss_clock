# LAB3-23 · MM:SS 시계 — 실험 전 보고서

- 이름: 상혁 (2025440084, 서울시립대학교 전자전기컴퓨터공학부)
- 설계 top 모듈: `lab3_mmss_clock`
- FPGA Part: xc7s75fgga484-1 (Combo II-DLD S75)

## 1. 회로 목적

1초마다 발생하는 클록 인에이블(clock-enable)로 00:00부터 59:59까지 분:초를
BCD로 계수하고, 4자리 7-세그먼트 표시장치를 동적 스캔(dynamic scan) 방식으로
구동하여 "분:초" 시계를 표시하는 회로이다. 50MHz 단일 클록(`clk_50mhz`)만
사용하며, 느린 동작(1초 tick, 세그먼트 스캔)은 모두 이 클록으로부터 파생된
내부 clock-enable로 만든다.

## 2. 블록 흐름

```
clk_50mhz(50MHz), rst_p
        │
        ▼
  mmss_counter (u_counter)
  ── subsecond 카운터로 1초 tick 생성
  ── BCD 캐리 체인: second_ones → second_tens → minute_ones → minute_tens
        │  minute_tens[3:0], minute_ones[3:0], second_tens[3:0], second_ones[3:0]
        ▼
  sevenseg_decode × 4 (u_mt, u_mo, u_st, u_so)
  ── 각 BCD 자리를 7세그먼트 패턴으로 변환
        │  seg_mt, seg_mo, seg_st, seg_so [7:0]
        ▼
  스캔 카운터(scan_count/scan_select, SCAN_HZ 기준) + case문 멀티플렉서
        │
        ▼
  seg_com[7:0] (자리 선택, active-low), seg_data[7:0] (세그먼트 출력)
```

## 3. 파라미터 계산 (실제 숫자)

top 모듈 `lab3_mmss_clock`의 파라미터:
- `CLK_HZ = 50_000_000` (50MHz, 주기 20ns)
- `SCAN_HZ = 4_000` (4자리 동적 스캔 주파수)
- `SCAN_CYCLES = CLK_HZ / SCAN_HZ = 50,000,000 / 4,000 = 12,500` — 한 자리를
  표시하는 클록 수. 4자리를 모두 스캔하는 한 주기 = 12,500 × 4 = 50,000
  클록 = 1ms, 즉 전체 화면 갱신 주파수 = 1kHz (사람 눈에는 깜빡임 없이 보임).
- `SCAN_WIDTH = $clog2(12500) = 14` — `scan_count`의 비트 폭.

`mmss_counter`의 파라미터:
- `CLK_HZ = 50_000_000` (top에서 그대로 전달)
- `COUNT_WIDTH = $clog2(50_000_000) = 26` — `subsecond`의 비트 폭.
- 1초 tick 조건: `subsecond == CLK_HZ - 1` (0부터 49,999,999까지 센 뒤 리셋),
  즉 50,000,000클록 = 1.000000초 (20ns × 50,000,000 = 1s).

테스트벤치에서는 시뮬레이션 시간을 줄이기 위해 `CLK_HZ = 2`로 축소했다.
이때 1초 tick은 클록 2회(2 × 20ns = 40ns)마다 발생하며, TB의
`advance(seconds)` 태스크는 `seconds × 2`번의 `posedge clk_50mhz`만큼
대기하여 "축소된 1초"만큼 시간을 진행시킨다. TB의 클록 주기 자체(20ns,
`#10` 하프 피리어드)는 실제 보드의 50MHz(20ns) 그대로 유지했다.

## 4. 상태/타이밍 표 (캐리 규칙 포함)

| 신호 | 범위 | 캐리 조건 (다음 자리로 +1, 자신은 0으로 리셋) |
|---|---|---|
| `second_ones` | 0~9 | `second_ones == 9` → `second_tens` +1 |
| `second_tens` | 0~5 | `second_tens == 5` (& second_ones==9) → `minute_ones` +1 |
| `minute_ones` | 0~9 | `minute_ones == 9` (& second_tens==5, second_ones==9) → `minute_tens` +1 |
| `minute_tens` | 0~5 | `minute_tens == 5` (전체 최대) → 00:00으로 롤오버 |

경계 조건: 00:09→00:10 (초 캐리), 00:59→01:00 (분 캐리),
59:59→00:00 (전체 3,600초 순환, 최댓값에서 리셋 없이 자동 롤오버).

스캔 타이밍: `scan_select`는 0→1→2→3→0 순서로 2비트 순환하며 각각
`{minute_tens, minute_ones, second_tens, second_ones}`를 선택한다.
`scan_count == SCAN_CYCLES-1`일 때만 `scan_select`가 증가한다.

## 5. RTL·TB·XDC 역할 설명

- `src/lab3_mmss_clock.v` — top 모듈 `lab3_mmss_clock`. `mmss_counter`,
  `sevenseg_decode`(×4)를 인스턴스화하고, 스캔 카운터와 `seg_com`/`seg_data`
  출력 멀티플렉서(always @*)를 구현한다. 실제 합성 시 Vivado에서 이 모듈을
  design top으로 지정한다.
- `src/mmss_counter.v` — 분:초 BCD 카운터. `subsecond` 프리스케일러로 1초
  tick을 만들고, 4단 캐리 체인으로 초/분 자리를 갱신한다. `rst_p`는 비동기
  로직 리셋으로, top의 always 블록에서 posedge로 감지한다.
- `src/sevenseg_decode.v` — 4비트 BCD digit → 8비트 세그먼트 패턴
  조합 로직 디코더(순수 combinational, `case`문).
- `sim/tb_mmss_counter.sv` — `simulation.json`의 `simulation_top`(=`tb_design`)에
  맞춘 자기검사 테스트벤치. `mmss_counter`, `sevenseg_decode`를 직접
  인스턴스화하여 축소된 `CLK_HZ=2`로 여러 초를 진행시키며 캐리·롤오버를
  검사하고, `$fatal`/`$display`/`$dumpfile`/`$finish`를 포함한다.
- `constraints/lab3_mmss_clock.xdc` — top 모듈의 모든 포트(`clk_50mhz`, `rst_p`,
  `seg_data[7:0]`, `seg_com[7:0]`)에 `PACKAGE_PIN`과
  `IOSTANDARD LVCMOS33`을 지정하고, 50MHz 클록 제약과 리셋 경로의
  `set_false_path`를 선언한다. Icarus 시뮬레이션에는 사용되지 않으며,
  실제 보드 구현(Vivado synthesis/implementation) 단계에서만 적용된다.

## 6. TB 자극 → 기대 결과 표

| # | 자극 | 기대 결과 | 확인 내용 |
|---|---|---|---|
| 1 | `decode_digit=0` | `segments=8'b1111_1100` | 세그먼트 디코더 0 패턴 |
| 2 | `decode_digit=9` | `segments=8'b1111_0110` | 세그먼트 디코더 9 패턴 |
| 3 | 리셋 해제 직후 | `mt,mo,st,so = 0,0,0,0` (00:00) | 리셋 초기값 |
| 4 | `advance(10)` (10초 경과) | `0,0,1,0` (00:10) | 00:09→00:10 초 캐리 |
| 5 | `advance(50)` (총 60초) | `0,1,0,0` (01:00) | 00:59→01:00 분 캐리 |
| 6 | `advance(3539)` (총 3599초) | `5,9,5,9` (59:59) | 최댓값 도달 |
| 7 | `advance(1)` (총 3600초) | `0,0,0,0` (00:00) | 59:59→00:00 전체 롤오버 |

## 7. Icarus PASS 결과 핵심 로그

```
PASS: check 1 digit0 decode=11111100
PASS: check 2 digit9 decode=11110110
PASS: check 3 time=00:00
PASS: check 4 time=00:10
PASS: check 5 time=01:00
PASS: check 6 time=59:59
PASS: check 7 time=00:00
LAB3_MMSS_PASS checks=7
```

`python3 tools/fpga_lab.py simulate` 실행 결과 `result.json`의
`"status": "SIMULATED"`을 확인했으며, 컴파일/실행 오류 없이 `wave.vcd`가
생성되었다.

## 8. 한 항목 수정 실험과 복구 결과

PDF "수정 실험" 지침에 따라 TB의 `mmss_counter` 인스턴스에 전달하는
`CLK_HZ`(자리올림 간격 파라미터)를 의도적으로 틀리게 바꾸었다. TB 클록
주기(20ns, `#10`)는 그대로 유지했다.

| 단계 | 변경 내용 | 결과 |
|---|---|---|
| 정상 | `mmss_counter #(.CLK_HZ(2)) dut` | PASS, `LAB3_MMSS_PASS checks=7` |
| 수정(오류 주입) | `mmss_counter #(.CLK_HZ(3)) dut` | **FAIL** — check 4에서 `$fatal`: `time mismatch: got 00:06 expected 00:10` (Time: 430000, Scope: tb_design.check_time). 1초 tick 간격이 2클록→3클록으로 바뀌어 동일한 `advance(10)` 동안 실제로는 10×2/3≈6.67초만 진행되어 캐리 시점이 어긋남을 확인. |
| 복구 | `mmss_counter #(.CLK_HZ(2)) dut`로 되돌림 | PASS 복구, `LAB3_MMSS_PASS checks=7`. `sim/tb_mmss_counter.sv`의 sha256이 최초 PASS 실행 때와 동일(`14e3538b...`)함을 확인하여 완전 원복을 검증. |

TB의 기대값은 RTL 오류(또는 이번 실험처럼 TB 자체의 파라미터 오류)에 맞춰
바꾸지 않고 고정했다.

## 9. 실제 보드 확인 체크리스트

- [ ] 전원을 끈 상태에서 외부 부품 결선과 공통 GND를 먼저 확인한다.
- [ ] Vivado에서 XDC 저장 → Run Synthesis → Run Implementation →
      Generate Bitstream 순서로 실행한다.
- [ ] Open Elaborated Design 또는 I/O Planning에서 top 포트와
      PACKAGE_PIN을 대조한다.
- [ ] Reports → Timing → Report Clocks에서 `clk_50mhz` 주기 20.000ns를
      확인한다.
- [ ] Hardware Manager → Open Target → Auto Connect → Program Device로
      비트스트림을 보드에 로드하고 생성한 bit 파일명을 기록한다.
- [ ] 자리 순서(좌→우: 분십·분일·초십·초일)와 극성(active-low `seg_com`,
      세그먼트 패턴)이 올바른지 확인한다.
- [ ] 00:09→00:10, 00:59→01:00, 59:59→00:00 경계에서 실제 1초 간격과
      캐리 동작을 확인한다.
- [ ] 리셋(`rst_p`) 버튼 동작 시 즉시 00:00으로 복귀하는지 확인한다.
- [ ] 보드 전체 사진과 동작 영상을 촬영하고, 입력 조작(리셋)과 출력 변화가
      함께 보이도록 기록한다.
- [ ] GitHub 저장소 URL과 최종 commit hash를 기록한다.
- [ ] `src`·`sim`·`constraints`·`simulation.json`만 최종 원본으로
      관리하고 `build/` 등 생성물은 제외한다.

## 10. 핀 표 요약

| 신호명 | PACKAGE_PIN | IOSTANDARD | 비고 |
|---|---|---|---|
| `clk_50mhz` | B6 | LVCMOS33 | MAIN CLOCK, 50MHz, `create_clock -period 20.000` |
| `rst_p` | K4 | LVCMOS33 | 리셋 입력, `set_false_path -from` |
| `seg_data[0]` | H2 | LVCMOS33 | 세그먼트 출력 |
| `seg_data[1]` | J7 | LVCMOS33 | 세그먼트 출력 |
| `seg_data[2]` | H3 | LVCMOS33 | 세그먼트 출력 |
| `seg_data[3]` | J1 | LVCMOS33 | 세그먼트 출력 |
| `seg_data[4]` | E4 | LVCMOS33 | 세그먼트 출력 |
| `seg_data[5]` | E2 | LVCMOS33 | 세그먼트 출력 |
| `seg_data[6]` | F5 | LVCMOS33 | 세그먼트 출력 |
| `seg_data[7]` | F1 | LVCMOS33 | 세그먼트 출력 |
| `seg_com[0]` | K5 | LVCMOS33 | 자리 선택 (active-low) |
| `seg_com[1]` | K3 | LVCMOS33 | 자리 선택 (active-low) |
| `seg_com[2]` | K1 | LVCMOS33 | 자리 선택 (active-low) |
| `seg_com[3]` | L6 | LVCMOS33 | 자리 선택 (active-low) |
| `seg_com[4]` | G3 | LVCMOS33 | 자리 선택 (active-low) |
| `seg_com[5]` | G1 | LVCMOS33 | 자리 선택 (active-low) |
| `seg_com[6]` | H6 | LVCMOS33 | 자리 선택 (active-low) |
| `seg_com[7]` | H4 | LVCMOS33 | 자리 선택 (active-low) |

출처: `06.LAB3_05_MMSS_CLOCK_VIVADO.pdf` (Combo II-DLD S75 보드,
xc7s75fgga484-1).
