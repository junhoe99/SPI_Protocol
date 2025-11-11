# 📡 SPI (Serial Peripheral Interface) Protocol Implementation

## 1️⃣ SPI Protocol Overview

### 📊 Block Diagram

<img width="2292" height="2508" alt="image" src="https://github.com/user-attachments/assets/7820acea-3486-47a1-8984-a050c6f19e7f" />

### 🔄 ASM Chart

<img width="4772" height="4184" alt="image" src="https://github.com/user-attachments/assets/bb4cd94a-59de-4cb8-9dc7-e6d232748a59" />


### ⏱️ Timing Diagram - Mode 0 (CPOL=0, CPHA=0 기준)

<img width="2808" height="1296" alt="image" src="https://github.com/user-attachments/assets/09bd93cd-e91d-457e-ad35-55b641fdfb28" />


---


### 🔌 Protocol Characteristics
| Property | Description |
|----------|-------------|
| **Type** | Synchronous Serial Communication |
| **Direction** | Full-Duplex (Simultaneous TX/RX) |
| **Topology** | Master-Slave (1 Master : N Slaves) |
| **Data Width** | 8-bit per transfer |
| **Clock** | Master generates SCLK (1MHz) |
| **Speed** | 1 Mbps (8 μs/byte) |

### 📌 Signal Interface

| Signal | Direction | Description |
|--------|-----------|-------------|
| `clk` | Input | 100MHz System Clock |
| `reset` | Input | Asynchronous Reset (Active High) |
| `sclk` | Master→Slave | SPI Clock (1MHz) |
| `mosi` | Master→Slave | Master Out Slave In (Data TX) |
| `miso` | Slave→Master | Master In Slave Out (Data RX) |
| `cs` | Master→Slave | Chip Select (Active Low) |
| `cpol` | Config | Clock Polarity (IDLE level) |
| `cpha` | Config | Clock Phase (Sample/Setup timing) |

---

## 2️⃣ System Architecture


| State | Operation | Timing | Next Condition |
|-------|-----------|--------|----------------|
| `IDLE` | Wait, tx_ready=1 | - | start=1 → CP_DELAY(CPHA=1) or CP0(CPHA=0) |
| `CP0` | SCLK Low half | 500ns | counter=49 → CP1 |
| `CP1` | SCLK High half, Shift data | 500ns | counter=49, bit<7 → CP0<br>bit=7 → CP_DELAY or IDLE |
| `CP_DELAY` | Half-clock alignment | 500ns | counter=49 → CP0 or IDLE |

**Slave FSM (SI Phase - MOSI RX):**
```
SI_IDLE ──[cs=0]──> SI_PHASE ──[bit_cnt=7]──> SI_IDLE (si_done=1)
                        │  ▲
                        └──┘ (sclk_rising_edge)
```

**Slave FSM (SO Phase - MISO TX):**
```
SO_IDLE ──[so_start=1]──> SO_PHASE ──[bit_cnt=7]──> SO_IDLE
  (so_ready=1)               │  ▲
                             └──┘ (sclk_falling_edge)
```



### 📝 SPI Mode Comparison

| Mode | CPOL | CPHA | SCLK IDLE | Setup Edge | Sample Edge | Initial Delay |
|------|------|------|-----------|------------|-------------|---------------|
| **0** | 0 | 0 | Low | Falling | Rising | No |
| **1** | 0 | 1 | Low | Rising | Falling | Yes (500ns) |
| **2** | 1 | 0 | High | Rising | Falling | No |
| **3** | 1 | 1 | High | Falling | Rising | Yes (500ns) |

### � Protocol Operation Summary

**SPI Mode 0 기준 동작 흐름:**

1. **시작**: Master가 `cs=0`으로 Slave 선택, `start=1`로 전송 시작
2. **데이터 전송**: 
   - SCLK의 **falling edge**에서 MOSI/MISO 데이터 준비 (Setup)
   - SCLK의 **rising edge**에서 데이터 샘플링 (Sample)
   - MSB(D7)부터 LSB(D0) 순서로 8-bit 전송
3. **완료**: 8-bit 전송 완료 후 `done=1`, 500ns 후 `cs=1`로 해제

**Full-Duplex 특징:**
- Master→Slave (MOSI)와 Slave→Master (MISO) 동시 전송
- 하나의 SCLK 주기에 1-bit씩 양방향 교환

---

## 4️⃣ Key Design Features

### 🔧 핵심 설계 요소

#### 1️⃣ Clock Domain Crossing (CDC) 해결

**문제:**
- Master SCLK (1MHz, 비동기) ↔ Slave System Clock (100MHz)
- Metastability 발생 가능 → 데이터 손실/오류

**해결책: 2-Stage Synchronizer + Edge Detector**
<img width="8308" height="1800" alt="image" src="https://github.com/user-attachments/assets/981950f7-6b84-4dca-a348-fa75b94b57b9" />

```systemverilog
// Synchronizer
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        sclk_sync0 <= 1'b0;
        sclk_sync1 <= 1'b0;
    end else begin
        sclk_sync0 <= sclk;          // Stage 1: Metastable
        sclk_sync1 <= sclk_sync0;    // Stage 2: Stable
    end
end

// Edge Detection
assign sclk_rising_edge  = (sclk_sync0 & ~sclk_sync1);
assign sclk_falling_edge = (~sclk_sync0 & sclk_sync1);
```
- **MTBF**: 2-Stage로 10^9년 이상의 고신뢰성 확보
- **Latency**: 20~30ns (2 system clocks) 추가되나 1MHz SCLK 대비 무시 가능

#### 2️⃣ CPOL/CPHA Mode 구현

**CPOL (Clock Polarity):**
```systemverilog
// IDLE 상태의 SCLK 레벨 제어
assign spi_clk_next = cpol ? ~p_clk : p_clk;
// CPOL=0: IDLE=Low, CPOL=1: IDLE=High
```

**CPHA (Clock Phase):**
```systemverilog
// p_clk: 실제 데이터 valid 시점 결정
assign p_clk = ((state_next == CP0) && (cpha == 1)) ||
               ((state_next == CP1) && (cpha == 0));
// CPHA=0: 첫 edge 샘플링, CPHA=1: 두 번째 edge 샘플링
```

**CP_DELAY State:**
- CPHA=1일 때: 시작 전 반 클럭 대기 (데이터 안정화)
- CPHA=0일 때: 종료 후 반 클럭 대기 (CS timing 보장)

#### 3️⃣ SI/SO Phase 분리 (Slave)

**설계 이유:**
- **Modularity**: MOSI 수신(SI)과 MISO 전송(SO) 독립 제어
- **Flexibility**: Master/Slave가 비대칭 데이터 전송 가능
- **Clarity**: 각 Phase의 역할(RX/TX) 명확화

**구현:**
- SI Phase: `sclk_rising_edge`에서 MOSI 샘플링
- SO Phase: `sclk_falling_edge`에서 MISO 업데이트
- 각 Phase별 독립 FSM 및 done 신호

### ⚙️ Design Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| System Clock | 100 MHz | Basys3 FPGA |
| SCLK Frequency | 1 MHz | 50 sys clocks per half period |
| Throughput | 1 Mbps | 1MHz × 1-bit |
| Byte Transfer Time | 8 μs | 8 bits × 1 μs |
| CDC Latency | 20~30 ns | 2-stage synchronizer delay |

### ✅ Design Decisions

**Why 1MHz SCLK?**
- **Fast enough**: 8μs/byte는 대부분 응용에 충분
- **Slow enough**: CDC 안정성 확보 (100MHz 대비 1/100)
- **Practical**: 일반적인 SPI 디바이스 지원 범위

**Why Separate SI/SO Phase?**
- Full-duplex이지만 Master 주도형이므로 RX/TX 타이밍 다름
- 독립적 제어로 확장성 및 디버깅 용이

### 🚨 Known Limitations

- **Single Master**: 1:N 토폴로지만 지원 (Multi-master 불가)
- **No Error Detection**: CRC/Parity 미구현
- **Fixed Clock**: 1MHz 하드코딩 (파라미터화 가능하나 미구현)
- **No FIFO**: 연속 스트리밍 불가, 바이트마다 핸드셰이크 필요

---

## � References

- [Motorola SPI Block Guide](https://www.nxp.com/docs/en/data-sheet/MC68HC11E.pdf) - Original SPI Specification
- [Analog Devices: Introduction to SPI](https://www.analog.com/en/analog-dialogue/articles/introduction-to-spi-interface.html)
- [Xilinx UG912: CDC Techniques](https://www.xilinx.com/support/documentation/sw_manuals/xilinx2020_2/ug912-vivado-properties.pdf)

---

## 📊 Revision History

| Version | Date | Description |
|---------|------|-------------|
| v1.0 | 2025-11-10 | Initial implementation with CPOL/CPHA support |
| v1.1 | 2025-11-10 | Fixed SI/SO phase bugs, Added 2-stage synchronizer |

---

**Author**: FPGA_Harman_25  
**Date**: November 10, 2025  
**Purpose**: Serial Communication Protocol Learning - SPI Implementation
