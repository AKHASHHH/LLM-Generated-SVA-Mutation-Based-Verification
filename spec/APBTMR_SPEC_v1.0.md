# APB Programmable Timer: Functional Specification

**Document:** APBTMR-SPEC
**Version:** 1.0
**Status:** Normative. The words "shall" and "shall not" mark requirements. Sections marked *Informative* restate consequences of the normative rules and add no new requirements.

---

## 1. Overview

The design is a single 16-bit down-counting timer peripheral with:
* an APB3 slave register interface with no wait states;
* an 8-bit prescaler;
* a software-written shadow reload value and a hardware-held active reload value;
* periodic and one-shot modes;
* a sticky pending flag and a sticky overflow (missed-expiration) flag, both write-one-to-clear;
* a level interrupt output gated by an interrupt-enable bit;
* an asynchronous, active-low reset.

Each requirement has an identifier (for example R-TMR-4). Bug reports and checker messages should cite these identifiers.

## 2. Top-level interface

Module name: `apb_timer`. There are no parameters. Port names, directions and widths shall be exactly as listed.

| Port | Dir | Width | Description |
|---|---|---|---|
| `PCLK` | in | 1 | Clock. All state changes other than reset occur on its rising edge. |
| `PRESETn` | in | 1 | Asynchronous active-low reset. |
| `PSEL` | in | 1 | APB select. |
| `PENABLE` | in | 1 | APB enable. |
| `PWRITE` | in | 1 | 1 = write, 0 = read. |
| `PADDR` | in | 8 | Byte address. |
| `PWDATA` | in | 32 | Write data. |
| `PRDATA` | out | 32 | Read data. |
| `PREADY` | out | 1 | Transfer ready. |
| `PSLVERR` | out | 1 | Transfer error. |
| `irq` | out | 1 | Interrupt request, active high, level. |

## 3. Conventions and timing model

**C-1 Cycle.** A *cycle* is the interval between two consecutive rising edges of PCLK. "The value of X in cycle t" means the value X holds during that interval.

**C-2 End of cycle.** A state change that happens "at the end of cycle t" occurs on the rising edge that closes cycle t. It is visible from cycle t+1 onward.

**C-3 Held values.** Every condition in this specification is evaluated using the values of architectural state held in that cycle together with the input values during that cycle. A value being written in a cycle is never used to evaluate any condition in that same cycle.

**C-4 Outputs.** PRDATA, PREADY, PSLVERR and irq are defined in each cycle as functions of the state held in that cycle and, where stated, the inputs in that cycle.

**C-5 Bit numbering.** Bit 0 is the least significant bit. All arithmetic and comparisons are unsigned.

## 4. Reset

**R-RST-1.** While PRESETn is 0, every architectural state element (section 6) shall hold its reset value. When PRESETn falls, the state shall take its reset value immediately, without waiting for a clock edge.

**R-RST-2.** A rising PCLK edge that occurs while PRESETn is 0 shall not change any state.

**R-RST-3.** A rising PCLK edge that occurs while PRESETn is 1 is a normal edge. The first such edge after reset is released performs a normal update using reset-valued state. The environment shall not change PRESETn at the same instant as a rising PCLK edge, and every assertion of PRESETn shall remain 0 across at least one rising PCLK edge.

**R-RST-4.** The output rules of sections 5 and 9 apply unchanged during reset, evaluated on reset-valued state.

## 5. APB interface

**R-APB-1 Access cycle.** A cycle in which PSEL=1 and PENABLE=1 is an *access cycle*. Every access cycle is a complete transfer. Whether it is a read or a write is given by PWRITE in that cycle. The design shall not depend on the values of PSEL, PENABLE, PWRITE, PADDR or PWDATA in any earlier cycle. In particular it shall not require or check that a setup phase preceded the access cycle. Consecutive access cycles are each a separate, complete transfer.

**R-APB-2 Non-access cycles.** In a cycle that is not an access cycle, PWRITE, PADDR and PWDATA shall have no effect.

**R-APB-3 PREADY.** PREADY shall be 1 in every cycle.

**R-APB-4 Address decode.** The register is selected by PADDR[7:2]. PADDR[1:0] shall be ignored. The register *offset* is PADDR with bits [1:0] treated as 0.

**R-APB-5 Write.** In a write access cycle to a writable offset without error, the addressed register is updated at the end of the access cycle, according to its write rule in section 7. Write-data bits that are not defined as writable fields shall be ignored.

**R-APB-6 Read data.** In a read access cycle to a mapped offset, PRDATA shall equal that register's read value (section 7), formed from state held in the access cycle.

**R-APB-7 PRDATA otherwise zero.** In every other cycle PRDATA shall be 0. This includes non-access cycles, write access cycles and read access cycles to unmapped offsets.

**R-APB-8 PSLVERR.** PSLVERR shall be 1 in an access cycle if and only if the offset is unmapped, or the access is a write to a read-only offset. In all other cycles PSLVERR shall be 0.

**R-APB-9 Errored access.** An access cycle with PSLVERR=1 shall not change any state.

**R-APB-10 Reads have no side effects.** No read access, of any offset, shall change any state.

## 6. Architectural state

The design behaves as if it holds exactly the following state. An implementation may encode this state differently internally, but every externally observable behavior shall be as if this state existed and evolved as specified. All of it is software-visible through section 7.

| Name | Width | Reset | Meaning |
|---|---|---|---|
| EN | 1 | 0 | Timer enabled. |
| MODE | 1 | 0 | 0 = periodic, 1 = one-shot. |
| IE | 1 | 0 | Interrupt enable (mask). |
| PSC | 8 | 0 | Prescale value. |
| SHADOW | 16 | 0 | Software reload value. |
| ACTIVE | 16 | 0 | Reload value in use by the counter. |
| COUNT | 16 | 0 | Current counter value. |
| PCNT | 8 | 0 | Prescaler counter. |
| PEND | 1 | 0 | Expiration pending (sticky). |
| OVF | 1 | 0 | An expiration occurred while PEND was already 1 (sticky). |

## 7. Register map

All registers are 32 bits wide. Reserved bits read as 0, and writes to them are ignored. Offsets not listed in this table are unmapped, which covers every offset from 0x1C to 0xFC.

| Offset | Name | Access | Bits | Read value | Write rule |
|---|---|---|---|---|---|
| 0x00 | CTRL | RW | [0] EN, [1] MODE, [2] IE, [7:3] reserved, [15:8] PSC, [31:16] reserved | {16'b0, PSC, 5'b0, IE, MODE, EN} | Writes EN, MODE, IE, PSC, subject to section 8 and the priority rules of section 10. |
| 0x04 | LOAD | RW | [15:0] SHADOW | {16'b0, SHADOW} | SHADOW takes PWDATA[15:0]. No other state changes (R-TMR-11). |
| 0x08 | COUNT | RO | [15:0] COUNT | {16'b0, COUNT} | Write gives PSLVERR=1 and has no effect. |
| 0x0C | STATUS | RW1C | [0] PEND, [1] OVF | {30'b0, OVF, PEND} | Writing 1 to a bit clears it, subject to section 10. Writing 0 has no effect. |
| 0x10 | CMD | WO | [0] RESTART | Always 0; a read is not an error. | PWDATA[0]=1 issues a restart command (R-TMR-9). PWDATA[0]=0 does nothing. |
| 0x14 | ACTIVE | RO | [15:0] ACTIVE | {16'b0, ACTIVE} | Write gives PSLVERR=1 and has no effect. |
| 0x18 | PSCNT | RO | [7:0] PCNT | {24'b0, PCNT} | Write gives PSLVERR=1 and has no effect. |

## 8. Timer operation

### 8.1 Definitions

These terms are evaluated in each cycle from the values held in that cycle and the inputs during that cycle (C-3).

* **Enabled cycle:** a cycle in which EN = 1.
* **Tick:** an enabled cycle in which PCNT >= PSC.
* **Expiration:** a tick in which COUNT = 0.
* **Successful write to R:** a write access cycle to register R with PSLVERR = 0.
* **Start:** a successful write to CTRL with PWDATA[0] = 1, in a cycle in which EN = 0.
* **Restart command:** a successful write to CMD with PWDATA[0] = 1.
* **Reload transfer:** ACTIVE and COUNT both take the value of SHADOW held in the current cycle, at the end of that cycle.

Because a start requires EN = 0 and an expiration requires EN = 1, a start and an expiration never occur in the same cycle.

### 8.2 Rules

**R-TMR-1 Prescaler.** In an enabled cycle with no restart command: if the cycle is a tick, PCNT becomes 0 at the end of the cycle; otherwise PCNT increases by 1.

**R-TMR-2 Stopped timer.** In a cycle that is not enabled, COUNT, PCNT and ACTIVE shall not change, except through a start (R-TMR-7) or a restart command (R-TMR-9).

**R-TMR-3 Count down.** In a tick that is not an expiration, with no restart command, COUNT decreases by 1 at the end of the cycle. COUNT changes only as defined in section 8, so it never wraps.

**R-TMR-4 Periodic expiration.** In an expiration with MODE = 0, a reload transfer is performed. EN is not changed by the expiration.

**R-TMR-5 One-shot expiration.** In an expiration with MODE = 1, COUNT remains 0, ACTIVE is unchanged, and EN becomes 0 at the end of the cycle (see also R-PRI-2).

**R-TMR-6 Expiration flags.** Every expiration, in either mode, sets the flags as defined in section 9.

**R-TMR-7 Start.** In a start cycle, a reload transfer is performed, PCNT becomes 0, and EN becomes 1, all at the end of the cycle. The first enabled cycle is the cycle after the start. A start does not change PEND or OVF.

**R-TMR-8 Stop and re-enable.** A successful CTRL write with PWDATA[0] = 0 makes EN = 0 at the end of the access cycle. The access cycle itself is still an enabled cycle if EN = 1 in it. A later start always performs a reload transfer: the timer never resumes from the value COUNT held while stopped.

**R-TMR-9 Restart command.** A restart command causes a reload transfer and makes PCNT = 0 at the end of the cycle. This applies whether EN is 0 or 1, and it takes precedence over the R-TMR-1, R-TMR-3, R-TMR-4 and R-TMR-5 effects on COUNT, ACTIVE and PCNT in that cycle. A restart command never changes EN, PEND or OVF directly. An expiration in the same cycle still has its effects on EN, PEND and OVF.

**R-TMR-10 CTRL write while enabled.** A successful CTRL write with PWDATA[0] = 1 in a cycle in which EN = 1 is not a start. It does not cause a reload transfer and does not change PCNT. It only updates MODE, IE and PSC (and EN, see R-PRI-2).

**R-TMR-11 SHADOW.** SHADOW changes only through a successful write to LOAD. Writing LOAD never directly changes ACTIVE, COUNT or PCNT. A reload transfer in the same cycle as a LOAD write uses the SHADOW value held in that cycle (the old value).

**R-TMR-12 Configuration timing.** New values of MODE and PSC written in cycle t first govern the events of cycle t+1. The tick and expiration of cycle t, and the effect of that expiration, use the MODE and PSC held in cycle t.

**R-TMR-13 PSC change.** A change of PSC does not change PCNT. If PCNT > PSC after a PSC change, the next enabled cycle is a tick by definition.

## 9. Status flags and interrupt

**R-INT-1 PEND set.** PEND becomes 1 at the end of every expiration cycle, regardless of IE.

**R-INT-2 PEND clear.** A successful write to STATUS with PWDATA[0] = 1 makes PEND 0 at the end of the cycle, unless that cycle is an expiration (R-PRI-4).

**R-INT-3 OVF set.** OVF becomes 1 at the end of an expiration cycle in which PEND = 1. This applies even if software is clearing PEND in that same cycle.

**R-INT-4 OVF clear.** A successful write to STATUS with PWDATA[1] = 1 makes OVF 0 at the end of the cycle, unless OVF is being set in that same cycle by R-INT-3 (R-PRI-5).

**R-INT-5 Hardware only sets.** Software cannot set PEND or OVF. Only expirations set them.

**R-INT-6 irq.** In every cycle, irq = PEND AND IE, using the values held in that cycle. irq shall not depend combinationally on any input other than through PRESETn's asynchronous reset of state.

**R-INT-7 Mask independence.** IE affects only irq. It does not affect the setting or clearing of PEND or OVF.

## 10. Simultaneous-event priority

Within one cycle at most one APB access can occur, so the possible conflicts are between one software access and the hardware events of that cycle. The following rules are complete and normative.

| ID | State element | Resolution, highest priority first |
|---|---|---|
| R-PRI-1 | All state | PRESETn = 0 overrides everything (section 4). |
| R-PRI-2 | EN | (1) One-shot expiration: EN becomes 0, whatever value a coincident CTRL write carries. (2) Otherwise, a successful CTRL write: EN takes PWDATA[0]. (3) Otherwise EN holds. |
| R-PRI-3 | COUNT, ACTIVE, PCNT | (1) Start or restart command. (2) Expiration effect (R-TMR-4 or R-TMR-5). (3) Tick decrement and prescaler update (R-TMR-1, R-TMR-3). (4) Hold. |
| R-PRI-4 | PEND | (1) Set by expiration. (2) Clear by STATUS write. (3) Hold. |
| R-PRI-5 | OVF | (1) Set by R-INT-3. (2) Clear by STATUS write. (3) Hold. |
| R-PRI-6 | MODE, IE, PSC | Changed only by a successful CTRL write. No hardware event changes them. |
| R-PRI-7 | SHADOW | Changed only by a successful LOAD write. |

The coincidence cases below follow from the rules above. They are listed so that no reader has to derive them.

| Hardware event in cycle | Coincident successful access | Result at end of cycle |
|---|---|---|
| Periodic expiration | LOAD write of V | Reload transfer uses old SHADOW. SHADOW becomes V. PEND set. |
| Expiration with PEND=0 | STATUS write 0x1 | PEND = 1. OVF unchanged (0 unless already 1). |
| Expiration with PEND=1 | STATUS write 0x1 | PEND = 1. OVF = 1. |
| Expiration with PEND=1 | STATUS write 0x2 or 0x3 | PEND = 1. OVF = 1. |
| Periodic expiration | CTRL write with EN=0 | Reload transfer. PEND set. EN = 0. |
| One-shot expiration | CTRL write with EN=1 | EN = 0. MODE, IE, PSC take written values. Not a start. |
| Periodic expiration | CTRL write with MODE=1 | Handled as periodic (reload transfer, EN as written). Later expirations are one-shot. |
| One-shot expiration | CTRL write with MODE=0 | Handled as one-shot (EN = 0, COUNT stays 0). MODE = 0 afterwards. |
| Any expiration | CTRL write changing PSC or IE | Expiration uses old PSC. New PSC and IE apply from the next cycle. |
| Periodic expiration | Restart command | Reload transfer, PCNT = 0. PEND (and possibly OVF) set. EN unchanged. |
| One-shot expiration | Restart command | Reload transfer, PCNT = 0. EN = 0. PEND (and possibly OVF) set. |
| Tick, not expiration | Restart command | Reload transfer, PCNT = 0 (no decrement). |
| Tick, not expiration | CTRL write with EN=0 | Decrement and PCNT update happen. EN = 0. |
| Any | Errored access (PSLVERR=1) | Only the hardware event's effects. |

## 11. Boundary behavior (informative)

* **SHADOW = 0:** after a start or reload, COUNT = 0, so every tick is an expiration. In periodic mode the timer expires every PSC+1 cycles. In one-shot mode it completes on the first tick.
* **PSC = 0:** every enabled cycle is a tick.
* **PSC = 255:** a tick every 256 enabled cycles (PCNT runs 0 to 255).
* **SHADOW = 0xFFFF:** COUNT runs down from 65535 without wrapping.
* **First expiration after a start:** with no intervening writes that affect the timer, it occurs in enabled cycle number (SHADOW+1) * (PSC+1), counting the first enabled cycle after the start as number 1. The same interval separates consecutive periodic expirations, using ACTIVE.
* **irq latency:** with IE = 1, irq is 1 from the cycle after an expiration.
* **Restart while stopped:** COUNT, ACTIVE and PCNT are reloaded, and EN stays 0. A later start reloads again from the SHADOW held at that time.
* **One-shot after completion:** EN = 0 and COUNT = 0. Software restarts it by writing CTRL with EN = 1.
* **Reset during an access cycle:** the access has no effect (R-RST-2).

## 12. Freeze procedure and scope

**Freeze.** This document becomes v1.0 when its SHA-256 hash is recorded. After that, no edit is permitted. Defects found later are logged in a separate errata file, are never applied to v1.0, and are reported with the results.

**Out of scope.** The following are deliberately not specified:
* internal state encoding and structure;
* timing and area;
* behavior when inputs are X or Z after reset release (the environment drives only 0 or 1);
* PRESETn changing at the same instant as a rising PCLK edge, or a PRESETn pulse that contains no rising PCLK edge (both excluded by R-RST-3).

## 13. Cycle-by-cycle examples

**Reading the tables.**
* Each row is one cycle.
* The EN to OVF columns show architectural state held during that cycle.
* irq, PRDATA and PSLVERR are the outputs during that cycle. PREADY is always 1 and is not shown.
* The "APB activity" column describes the bus in that cycle:
  * *idle* means PSEL = 0 and PENABLE = 0;
  * *setup* means PSEL = 1 and PENABLE = 0;
  * **ACCESS** means PSEL = 1 and PENABLE = 1.
* PADDR, PWRITE and PWDATA in a setup cycle equal those of the following access cycle.
* A write shown in an access row takes effect in the next row.
* The "tick / expire" column is derived from the state in that row and is shown only for readability.
* Cycle numbers are relative to the start of each table. Rows before the table are summarized in "Initial condition", and every initial condition is reachable from reset.

### Example 1: Reset values and basic reads

**Initial condition.** Reset asserted, then released before cycle 1.

| cyc | PRESETn | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | PRESETn=0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | 1 | setup R CTRL | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 2 | 1 | **ACCESS R CTRL** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 3 | 1 | setup R STATUS | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 4 | 1 | **ACCESS R STATUS** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 5 | 1 | setup R CMD | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 6 | 1 | **ACCESS R CMD** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 7 | 1 | setup R 0x1C (unmapped) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 8 | 1 | **ACCESS R 0x1C (unmapped)** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 1 |  |

**Explanation.** All state is 0 after reset. PRDATA is non-zero only in a read access cycle to a mapped register; it is 0 in setup cycles. A read of unmapped offset 0x1C returns PRDATA=0 with PSLVERR=1. CMD reads as 0.

### Example 2: Periodic start, PSC=0, LOAD=2

**Initial condition.** From reset: write LOAD=2, then CTRL with EN=1, MODE=periodic, IE=1, PSC=0.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS W CTRL=0x5** | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 2 | idle | 1 | 0 | 1 | 0 | 2 | 2 | 2 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 3 | idle | 1 | 0 | 1 | 0 | 2 | 2 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 4 | setup R COUNT | 1 | 0 | 1 | 0 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 5 | **ACCESS R COUNT** | 1 | 0 | 1 | 0 | 2 | 2 | 2 | 0 | 1 | 0 | 1 | 0x2 | 0 | tick |
| 6 | idle | 1 | 0 | 1 | 0 | 2 | 2 | 1 | 0 | 1 | 0 | 1 | 0x0 | 0 | tick |
| 7 | idle | 1 | 0 | 1 | 0 | 2 | 2 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 | tick+**EXPIRE** |
| 8 | idle | 1 | 0 | 1 | 0 | 2 | 2 | 2 | 0 | 1 | 1 | 1 | 0x0 | 0 | tick |

**Explanation.** The CTRL write in cycle 1 is a start (EN was 0), so from cycle 2 ACTIVE=COUNT=SHADOW=2 and PCNT=0. With PSC=0 every enabled cycle is a tick. COUNT steps 2, 1, 0, and the tick taken while COUNT=0 (cycle 4) is the expiration: from cycle 5 PEND=1 and COUNT=2 again. The first expiration is in the 3rd enabled cycle, i.e. (SHADOW+1)*(PSC+1). irq equals PEND AND IE, so it rises in cycle 5. The COUNT read in cycle 5 returns 2, the value held during the access cycle, even though COUNT becomes 1 at the end of that cycle. The second expiration (cycle 7) finds PEND already 1, so OVF is also set from cycle 8.

### Example 3: Prescaler PSC=2

**Initial condition.** From reset: LOAD=1, then start with PSC=2, periodic, IE=1.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS W CTRL=0x205** | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 2 | idle | 1 | 0 | 1 | 2 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 3 | idle | 1 | 0 | 1 | 2 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 4 | idle | 1 | 0 | 1 | 2 | 1 | 1 | 1 | 2 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 5 | idle | 1 | 0 | 1 | 2 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 6 | idle | 1 | 0 | 1 | 2 | 1 | 1 | 0 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 7 | idle | 1 | 0 | 1 | 2 | 1 | 1 | 0 | 2 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 8 | idle | 1 | 0 | 1 | 2 | 1 | 1 | 1 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 9 | idle | 1 | 0 | 1 | 2 | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 0x0 | 0 |  |
| 10 | idle | 1 | 0 | 1 | 2 | 1 | 1 | 1 | 2 | 1 | 0 | 1 | 0x0 | 0 | tick |

**Explanation.** A tick occurs in each enabled cycle in which PCNT >= PSC; PCNT then returns to 0, otherwise it increments. Ticks therefore occur every PSC+1=3 cycles. COUNT 1 -> 0 at the first tick, and the second tick (with COUNT=0) is the expiration. Expiration period = (1+1)*(2+1)=6 cycles.

### Example 4: One-shot completion

**Initial condition.** From reset: LOAD=1, then start in one-shot mode, PSC=0, IE=1.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS W CTRL=0x7** | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 2 | idle | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 3 | idle | 1 | 1 | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 4 | idle | 0 | 1 | 1 | 0 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 5 | idle | 0 | 1 | 1 | 0 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 6 | setup R CTRL | 0 | 1 | 1 | 0 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 7 | **ACCESS R CTRL** | 0 | 1 | 1 | 0 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0x6 | 0 |  |

**Explanation.** The one-shot expiration sets PEND and clears EN. COUNT stays 0, ACTIVE is unchanged, and no further ticks or expirations occur. A CTRL read afterwards shows EN=0 with MODE and IE still 1.

### Example 5: Interrupt mask does not gate PEND

**Initial condition.** From reset: LOAD=0, start one-shot with IE=0. The expiration happens while IE=0. Window starts after completion.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | idle | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0x0 | 0 |  |
| 1 | setup W CTRL | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0x0 | 0 |  |
| 2 | **ACCESS W CTRL=0x6** | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0x0 | 0 |  |
| 3 | idle | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 4 | idle | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |

**Explanation.** PEND was set by the expiration even though IE=0, so irq stayed 0. Writing IE=1 (with EN=0, so this is not a start) makes irq=1 from the cycle after the write, because PEND is still 1.

### Example 6: W1C semantics of STATUS

**Initial condition.** State: one-shot finished, PEND=1, IE=1, irq=1.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W STATUS | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 1 | **ACCESS W STATUS=0x0** | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 2 | setup W STATUS | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 3 | **ACCESS W STATUS=0x1** | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 4 | idle | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 5 | idle | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |

**Explanation.** Writing 0 to STATUS changes nothing. Writing 1 to bit 0 clears PEND at the end of the access cycle, and irq falls in the following cycle.

### Example 7: W1C of PEND in the same cycle as an expiration

**Initial condition.** Periodic, LOAD=3, PSC=0, IE=1. PEND is already 1 from an earlier expiration. The STATUS access cycle is timed to coincide with the next expiration.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | idle | 1 | 0 | 1 | 0 | 3 | 3 | 2 | 0 | 1 | 0 | 1 | 0x0 | 0 | tick |
| 1 | setup W STATUS | 1 | 0 | 1 | 0 | 3 | 3 | 1 | 0 | 1 | 0 | 1 | 0x0 | 0 | tick |
| 2 | **ACCESS W STATUS=0x1** | 1 | 0 | 1 | 0 | 3 | 3 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 | tick+**EXPIRE** |
| 3 | idle | 1 | 0 | 1 | 0 | 3 | 3 | 3 | 0 | 1 | 1 | 1 | 0x0 | 0 | tick |
| 4 | idle | 1 | 0 | 1 | 0 | 3 | 3 | 2 | 0 | 1 | 1 | 1 | 0x0 | 0 | tick |
| 5 | idle | 1 | 0 | 1 | 0 | 3 | 3 | 1 | 0 | 1 | 1 | 1 | 0x0 | 0 | tick |

**Explanation.** Hardware set beats software clear: PEND remains 1. Because PEND was 1 at the start of the expiration cycle, OVF is set, even though software was clearing PEND in that same cycle.

### Example 8: Clearing PEND and OVF together

**Initial condition.** Continues example 7.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W STATUS | 1 | 0 | 1 | 0 | 3 | 3 | 0 | 0 | 1 | 1 | 1 | 0x0 | 0 | tick+**EXPIRE** |
| 1 | **ACCESS W STATUS=0x3** | 1 | 0 | 1 | 0 | 3 | 3 | 3 | 0 | 1 | 1 | 1 | 0x0 | 0 | tick |
| 2 | idle | 1 | 0 | 1 | 0 | 3 | 3 | 2 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |

**Explanation.** A STATUS write of 0x3 clears both bits (no expiration is coincident), and irq falls.

### Example 9: SHADOW write while running (non-coincident)

**Initial condition.** Periodic, LOAD=4, PSC=0, IE=0, running.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W LOAD | 1 | 0 | 0 | 0 | 4 | 4 | 3 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 1 | **ACCESS W LOAD=0x1** | 1 | 0 | 0 | 0 | 4 | 4 | 2 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 2 | idle | 1 | 0 | 0 | 0 | 1 | 4 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 3 | idle | 1 | 0 | 0 | 0 | 1 | 4 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 4 | idle | 1 | 0 | 0 | 0 | 1 | 1 | 1 | 0 | 1 | 0 | 0 | 0x0 | 0 | tick |
| 5 | idle | 1 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 6 | idle | 1 | 0 | 0 | 0 | 1 | 1 | 1 | 0 | 1 | 1 | 0 | 0x0 | 0 | tick |
| 7 | idle | 1 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1 | 1 | 0 | 0x0 | 0 | tick+**EXPIRE** |

**Explanation.** The LOAD write updates SHADOW only. ACTIVE and COUNT are unaffected and counting continues from the old value. At the next periodic expiration both ACTIVE and COUNT take SHADOW=1, so the following period is 2 cycles.

### Example 10: SHADOW write coincident with periodic expiration

**Initial condition.** Periodic, LOAD=2, PSC=0, running. The LOAD access cycle coincides with an expiration.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W LOAD | 1 | 0 | 0 | 0 | 2 | 2 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 1 | **ACCESS W LOAD=0x5** | 1 | 0 | 0 | 0 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 2 | idle | 1 | 0 | 0 | 0 | 5 | 2 | 2 | 0 | 1 | 0 | 0 | 0x0 | 0 | tick |
| 3 | idle | 1 | 0 | 0 | 0 | 5 | 2 | 1 | 0 | 1 | 0 | 0 | 0x0 | 0 | tick |
| 4 | idle | 1 | 0 | 0 | 0 | 5 | 2 | 0 | 0 | 1 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 5 | idle | 1 | 0 | 0 | 0 | 5 | 5 | 5 | 0 | 1 | 1 | 0 | 0x0 | 0 | tick |
| 6 | idle | 1 | 0 | 0 | 0 | 5 | 5 | 4 | 0 | 1 | 1 | 0 | 0x0 | 0 | tick |
| 7 | idle | 1 | 0 | 0 | 0 | 5 | 5 | 3 | 0 | 1 | 1 | 0 | 0x0 | 0 | tick |
| 8 | idle | 1 | 0 | 0 | 0 | 5 | 5 | 2 | 0 | 1 | 1 | 0 | 0x0 | 0 | tick |

**Explanation.** The reload performed by an expiration uses SHADOW as held at the start of the expiration cycle (2), not the value being written (5). The new SHADOW=5 is transferred at the following expiration.

### Example 11: Stop, then enable again (restart, not resume)

**Initial condition.** Periodic, LOAD=5, PSC=1, running.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 1 | 0 | 0 | 1 | 5 | 5 | 4 | 1 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 1 | **ACCESS W CTRL=0x100** | 1 | 0 | 0 | 1 | 5 | 5 | 3 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 2 | idle | 0 | 0 | 0 | 1 | 5 | 5 | 3 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 3 | idle | 0 | 0 | 0 | 1 | 5 | 5 | 3 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 4 | idle | 0 | 0 | 0 | 1 | 5 | 5 | 3 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 5 | setup W CTRL | 0 | 0 | 0 | 1 | 5 | 5 | 3 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 6 | **ACCESS W CTRL=0x101** | 0 | 0 | 0 | 1 | 5 | 5 | 3 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 7 | idle | 1 | 0 | 0 | 1 | 5 | 5 | 5 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 8 | idle | 1 | 0 | 0 | 1 | 5 | 5 | 5 | 1 | 0 | 0 | 0 | 0x0 | 0 | tick |

**Explanation.** The cycle in which EN=0 is written (cycle 1) is still an enabled cycle, so PCNT advances to 1 at its end. From cycle 2 the timer is stopped: COUNT, PCNT and ACTIVE hold. Writing EN=1 while EN=0 is a start: COUNT and ACTIVE reload from SHADOW and PCNT returns to 0. The timer does not resume from the held COUNT.

### Example 12: CTRL write with EN=1 while already enabled is not a start

**Initial condition.** Periodic, LOAD=6, PSC=3, running.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 1 | 0 | 0 | 3 | 6 | 6 | 6 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS W CTRL=0x5** | 1 | 0 | 0 | 3 | 6 | 6 | 6 | 2 | 0 | 0 | 0 | 0x0 | 0 |  |
| 2 | idle | 1 | 0 | 1 | 0 | 6 | 6 | 6 | 3 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 3 | idle | 1 | 0 | 1 | 0 | 6 | 6 | 5 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 4 | idle | 1 | 0 | 1 | 0 | 6 | 6 | 4 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 5 | idle | 1 | 0 | 1 | 0 | 6 | 6 | 3 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |

**Explanation.** EN was already 1, so this write is not a start: COUNT is not reloaded and PCNT is not cleared (PCNT advances 2 to 3 at the end of the write cycle, as usual). The new PSC=0 and IE=1 apply from cycle 2, where PCNT=3 >= PSC=0 gives a tick, and every cycle after that is a tick.

### Example 13: Lowering PSC below the current PCNT

**Initial condition.** Periodic, LOAD=3, PSC=5, running with PCNT partway through an interval.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 1 | 0 | 0 | 5 | 3 | 3 | 3 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS W CTRL=0x101** | 1 | 0 | 0 | 5 | 3 | 3 | 3 | 2 | 0 | 0 | 0 | 0x0 | 0 |  |
| 2 | idle | 1 | 0 | 0 | 1 | 3 | 3 | 3 | 3 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 3 | idle | 1 | 0 | 0 | 1 | 3 | 3 | 2 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 4 | idle | 1 | 0 | 0 | 1 | 3 | 3 | 2 | 1 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 5 | idle | 1 | 0 | 0 | 1 | 3 | 3 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |

**Explanation.** PCNT is not cleared by a PSC change. In cycle 2, the first cycle using PSC=1, PCNT=3 >= 1, so a tick occurs at once and PCNT returns to 0. A comparison for equality only would miss this tick and let PCNT run up to 255 and wrap.

### Example 14: RESTART command while running

**Initial condition.** Periodic, PSC=1, running from LOAD=4; SHADOW was then rewritten to 7.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CMD | 1 | 0 | 0 | 1 | 7 | 4 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS W CMD=0x1** | 1 | 0 | 0 | 1 | 7 | 4 | 1 | 1 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 2 | idle | 1 | 0 | 0 | 1 | 7 | 7 | 7 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 3 | idle | 1 | 0 | 0 | 1 | 7 | 7 | 7 | 1 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 4 | idle | 1 | 0 | 0 | 1 | 7 | 7 | 6 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |

**Explanation.** CMD.RESTART loads ACTIVE and COUNT from SHADOW and clears PCNT at the end of the access cycle, overriding the tick/decrement of that cycle. EN is unchanged.

### Example 15: RESTART coincident with one-shot expiration

**Initial condition.** One-shot, PSC=2, LOAD=1 at start, SHADOW then rewritten to 3. The CMD access cycle coincides with the expiration.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CMD | 1 | 1 | 1 | 2 | 3 | 1 | 0 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS W CMD=0x1** | 1 | 1 | 1 | 2 | 3 | 1 | 0 | 2 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 2 | idle | 0 | 1 | 1 | 2 | 3 | 3 | 3 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 3 | idle | 0 | 1 | 1 | 2 | 3 | 3 | 3 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 4 | idle | 0 | 1 | 1 | 2 | 3 | 3 | 3 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |

**Explanation.** The expiration still occurs (PEND sets, EN clears). RESTART takes precedence for COUNT, ACTIVE and PCNT, so they load SHADOW=3 and 0. EN stays 0, so the timer remains stopped with COUNT=3.

### Example 16: CTRL write with EN=1 coincident with one-shot expiration

**Initial condition.** One-shot, LOAD=1, IE=0, running. A CTRL write of EN=1, IE=1, PSC=2 coincides with the expiration.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 1 | 1 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 1 | **ACCESS W CTRL=0x207** | 1 | 1 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 2 | idle | 0 | 1 | 1 | 2 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 3 | idle | 0 | 1 | 1 | 2 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 4 | idle | 0 | 1 | 1 | 2 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |

**Explanation.** The one-shot completion forces EN to 0 regardless of the written EN value. The other written fields (IE=1, PSC=2) do take effect. This is not a start, because EN was 1 at the start of the cycle. Software must write EN=1 again to start.

### Example 17: Switching periodic to one-shot while running

**Initial condition.** Periodic, LOAD=3, PSC=0, running. The CTRL write (MODE=1, EN=1) is not coincident with an expiration.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 1 | 0 | 0 | 0 | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 1 | **ACCESS W CTRL=0x3** | 1 | 0 | 0 | 0 | 3 | 3 | 2 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 2 | idle | 1 | 1 | 0 | 0 | 3 | 3 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 3 | idle | 1 | 1 | 0 | 0 | 3 | 3 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 4 | idle | 0 | 1 | 0 | 0 | 3 | 3 | 0 | 0 | 1 | 0 | 0 | 0x0 | 0 |  |
| 5 | idle | 0 | 1 | 0 | 0 | 3 | 3 | 0 | 0 | 1 | 0 | 0 | 0x0 | 0 |  |
| 6 | idle | 0 | 1 | 0 | 0 | 3 | 3 | 0 | 0 | 1 | 0 | 0 | 0x0 | 0 |  |

**Explanation.** MODE applies to any expiration that occurs after the cycle of the write. The next expiration is therefore a one-shot completion: EN clears and COUNT stays 0.

### Example 18: Switching to one-shot in the same cycle as an expiration

**Initial condition.** Periodic, LOAD=2, PSC=0, running. The CTRL write (MODE=1) coincides with an expiration.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 1 | 0 | 0 | 0 | 2 | 2 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 1 | **ACCESS W CTRL=0x3** | 1 | 0 | 0 | 0 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 2 | idle | 1 | 1 | 0 | 0 | 2 | 2 | 2 | 0 | 1 | 0 | 0 | 0x0 | 0 | tick |
| 3 | idle | 1 | 1 | 0 | 0 | 2 | 2 | 1 | 0 | 1 | 0 | 0 | 0x0 | 0 | tick |
| 4 | idle | 1 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 1 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 5 | idle | 0 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 1 | 1 | 0 | 0x0 | 0 |  |

**Explanation.** The coincident expiration uses MODE as held at the start of the cycle (periodic), so it reloads COUNT and EN stays 1. The next expiration is one-shot.

### Example 19: Disabling in the same cycle as a periodic expiration

**Initial condition.** Periodic, LOAD=2, PSC=0, running. The CTRL write (EN=0) coincides with an expiration.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 1 | 0 | 0 | 0 | 2 | 2 | 1 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 1 | **ACCESS W CTRL=0x0** | 1 | 0 | 0 | 0 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 2 | idle | 0 | 0 | 0 | 0 | 2 | 2 | 2 | 0 | 1 | 0 | 0 | 0x0 | 0 |  |
| 3 | idle | 0 | 0 | 0 | 0 | 2 | 2 | 2 | 0 | 1 | 0 | 0 | 0x0 | 0 |  |
| 4 | idle | 0 | 0 | 0 | 0 | 2 | 2 | 2 | 0 | 1 | 0 | 0 | 0x0 | 0 |  |

**Explanation.** The expiration is fully processed (PEND set, COUNT and ACTIVE reloaded) and the timer is then stopped by the write.

### Example 20: APB error and decode cases

**Initial condition.** Periodic, LOAD=9, PSC=4, running.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W COUNT (read-only) | 1 | 0 | 0 | 4 | 9 | 9 | 9 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS W COUNT (read-only)=0x55** | 1 | 0 | 0 | 4 | 9 | 9 | 9 | 1 | 0 | 0 | 0 | 0x0 | 1 |  |
| 2 | setup W LOAD via PADDR=0x06 | 1 | 0 | 0 | 4 | 9 | 9 | 9 | 2 | 0 | 0 | 0 | 0x0 | 0 |  |
| 3 | **ACCESS W LOAD via PADDR=0x06=0x33** | 1 | 0 | 0 | 4 | 9 | 9 | 9 | 3 | 0 | 0 | 0 | 0x0 | 0 |  |
| 4 | setup W CMD | 1 | 0 | 0 | 4 | 51 | 9 | 9 | 4 | 0 | 0 | 0 | 0x0 | 0 | tick |
| 5 | **ACCESS W CMD=0x0** | 1 | 0 | 0 | 4 | 51 | 9 | 8 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 6 | setup R 0x24 (unmapped) | 1 | 0 | 0 | 4 | 51 | 9 | 8 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |
| 7 | **ACCESS R 0x24 (unmapped)** | 1 | 0 | 0 | 4 | 51 | 9 | 8 | 2 | 0 | 0 | 0 | 0x0 | 1 |  |

**Explanation.** A write to read-only COUNT gives PSLVERR=1 and has no effect. PADDR[1:0] are ignored, so PADDR=0x06 addresses LOAD. A CMD write with bit 0 = 0 does nothing. A read of an unmapped offset gives PSLVERR=1 and PRDATA=0. PSLVERR is only ever 1 in access cycles.

### Example 21: LOAD=0 in periodic mode

**Initial condition.** From reset: LOAD=0, start periodic with PSC=1, IE=1.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup W CTRL | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS W CTRL=0x105** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 2 | idle | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 3 | idle | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0x0 | 0 | tick+**EXPIRE** |
| 4 | idle | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0x0 | 0 |  |
| 5 | idle | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 1 | 1 | 0 | 1 | 0x0 | 0 | tick+**EXPIRE** |
| 6 | idle | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 1 | 1 | 0x0 | 0 |  |
| 7 | idle | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 1 | 1 | 1 | 1 | 0x0 | 0 | tick+**EXPIRE** |

**Explanation.** With ACTIVE=0 every tick is an expiration, giving a period of (0+1)*(1+1)=2 cycles. The second expiration sets OVF because PEND was not cleared.

### Example 22: Asynchronous reset during operation

**Initial condition.** Periodic, LOAD=3, PSC=0, IE=1, running, PEND=1 (irq=1).

| cyc | PRESETn | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1 | idle | 1 | 0 | 1 | 0 | 3 | 3 | 3 | 0 | 1 | 0 | 1 | 0x0 | 0 | tick |
| 1 | 0 | PRESETn=0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 2 | 0 | PRESETn=0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 3 | 1 | idle | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 4 | 1 | idle | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 5 | 1 | setup R CTRL | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 6 | 1 | **ACCESS R CTRL** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |

**Explanation.** PRESETn falls between clock edges, partway through the cycle shown as the first PRESETn=0 row. All state takes its reset value immediately, without waiting for a clock edge, so irq falls during that cycle. The row shows the state after the asynchronous reset. After release, the timer is disabled with all registers at 0.

### Example 23: Readback of internal state while running

**Initial condition.** Periodic, LOAD=4, PSC=3, running.

| cyc | APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | setup R ACTIVE | 1 | 0 | 0 | 3 | 4 | 4 | 4 | 2 | 0 | 0 | 0 | 0x0 | 0 |  |
| 1 | **ACCESS R ACTIVE** | 1 | 0 | 0 | 3 | 4 | 4 | 4 | 3 | 0 | 0 | 0 | 0x4 | 0 | tick |
| 2 | setup R PSCNT | 1 | 0 | 0 | 3 | 4 | 4 | 3 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 3 | **ACCESS R PSCNT** | 1 | 0 | 0 | 3 | 4 | 4 | 3 | 1 | 0 | 0 | 0 | 0x1 | 0 |  |
| 4 | setup R LOAD | 1 | 0 | 0 | 3 | 4 | 4 | 3 | 2 | 0 | 0 | 0 | 0x0 | 0 |  |
| 5 | **ACCESS R LOAD** | 1 | 0 | 0 | 3 | 4 | 4 | 3 | 3 | 0 | 0 | 0 | 0x4 | 0 | tick |
| 6 | setup R STATUS | 1 | 0 | 0 | 3 | 4 | 4 | 2 | 0 | 0 | 0 | 0 | 0x0 | 0 |  |
| 7 | **ACCESS R STATUS** | 1 | 0 | 0 | 3 | 4 | 4 | 2 | 1 | 0 | 0 | 0 | 0x0 | 0 |  |

**Explanation.** ACTIVE, PSCNT, LOAD and STATUS reads return the values held during the access cycle. PSCNT exposes PCNT directly.
