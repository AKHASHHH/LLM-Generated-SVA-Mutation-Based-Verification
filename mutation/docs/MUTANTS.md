# Controlled mutants (10)

These are **intentional, single-edit defects** created by `scripts/make_mutants.py` from the Opus-assisted reference.
They are never to be described as natural bugs. Each mutant file = reference renamed to `apb_timer` + exactly one edit (see `mutants/mutants.diff`).

| ID | File | Violates | Misconception represented | Local pre-check: first activation (CXXRTL, preliminary) | Diverging / port-visible cycles |
|---|---|---|---|---|---|
| M01 | `mutants/M01_PEND_CLEAR_BEATS_SET.sv` | R-PRI-4, R-INT-2 | Software W1C clear given priority over the hardware expiration set of PEND. | EX07 (global cyc 84) | 71 / 28 |
| M02 | `mutants/M02_OVF_USES_POSTCLEAR_PEND.sv` | R-INT-3 | OVF set condition looks at PEND after a same-cycle W1C clear instead of the held PEND. | EX07 (global cyc 84) | 76 / 1 |
| M03 | `mutants/M03_RELOAD_USES_WRITTEN_LOAD.sv` | R-TMR-11 | Periodic reload transfer takes the value being written to LOAD in the same cycle (new SHADOW) instead of the held SHADOW. | EX10 (global cyc 128) | 618 / 14 |
| M04 | `mutants/M04_SW_EN_BEATS_ONESHOT_COMPLETION.sv` | R-PRI-2 | A coincident CTRL write of EN wins over the one-shot completion clearing EN. | EX16 (global cyc 213) | 15 / 0 |
| M05 | `mutants/M05_LEVEL_SENSITIVE_START.sv` | R-TMR-10, R-TMR-7 | Any CTRL write with EN=1 is treated as a start (reload + PCNT clear), even when already enabled. | EX12 (global cyc 160) | 1196 / 125 |
| M06 | `mutants/M06_START_KEEPS_PRESCALER_PHASE.sv` | R-TMR-7 | A start reloads COUNT and ACTIVE but does not clear PCNT, so a re-enabled timer resumes its old prescaler phase. | EX11 (global cyc 150) | 115 / 2 |
| M07 | `mutants/M07_PRESCALER_EQUALITY_COMPARE.sv` | R-TMR-13, R-TMR-1 | Tick uses PCNT == PSC instead of PCNT >= PSC, so lowering PSC below PCNT misses ticks until PCNT wraps. | EX12 (global cyc 161) | 1187 / 373 |
| M08 | `mutants/M08_RESTART_REQUIRES_EN.sv` | R-TMR-9 | CMD.RESTART is ignored while the timer is stopped (EN=0). | D06_RESTART_WHILE_STOPPED (global cyc 396) | 1158 / 40 |
| M09 | `mutants/M09_IE_GATES_PEND.sv` | R-INT-7, R-INT-1 | The interrupt-enable mask is applied to the status flag: expirations with IE=0 do not set PEND. | EX05 (global cyc 53) | 1481 / 146 |
| M10 | `mutants/M10_IRQ_REGISTERED.sv` | R-INT-6 | irq is registered (APB-template habit), so it lags PEND & IE by one cycle. | EX02 (global cyc 18) | 159 / 159 |

Activation in the table above comes from the local CXXRTL pre-check (`evidence/local_precheck/`).
The authoritative activation result is `scripts/run_activation.sh` in VCS.

## Exact edits

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M01_PEND_CLEAR_BEATS_SET.sv
@@ -111,5 +111,5 @@
         end
         // R-PRI-4 / R-INT-1,2
-        pend_n = expire ? 1'b1 : ((w_stat & PWDATA[0]) ? 1'b0 : pend);
+        pend_n = (w_stat & PWDATA[0]) ? 1'b0 : (expire ? 1'b1 : pend);
         // R-PRI-5 / R-INT-3,4 (set condition reads HELD pend)
         ovf_n  = (expire & pend) ? 1'b1 : ((w_stat & PWDATA[1]) ? 1'b0 : ovf);
```

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M02_OVF_USES_POSTCLEAR_PEND.sv
@@ -113,5 +113,5 @@
         pend_n = expire ? 1'b1 : ((w_stat & PWDATA[0]) ? 1'b0 : pend);
         // R-PRI-5 / R-INT-3,4 (set condition reads HELD pend)
-        ovf_n  = (expire & pend) ? 1'b1 : ((w_stat & PWDATA[1]) ? 1'b0 : ovf);
+        ovf_n  = (expire & pend & ~(w_stat & PWDATA[0])) ? 1'b1 : ((w_stat & PWDATA[1]) ? 1'b0 : ovf);
     end
```

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M03_RELOAD_USES_WRITTEN_LOAD.sv
@@ -104,5 +104,5 @@
             pcnt_n = tick ? 8'd0 : pcnt + 8'd1;          // R-TMR-1
             if (expire) begin
-                if (!mode) begin active_n = shadow; count_n = shadow; end  // R-TMR-4
+                if (!mode) begin active_n = shadow_n; count_n = shadow_n; end  // R-TMR-4
                 // one-shot: COUNT stays 0, ACTIVE unchanged (R-TMR-5)
             end else if (tick) begin
```

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M04_SW_EN_BEATS_ONESHOT_COMPLETION.sv
@@ -90,6 +90,6 @@
         shadow_n = w_load ? PWDATA[15:0] : shadow;
         // R-PRI-2: one-shot completion > CTRL write > hold
-        if (expire & mode)  en_n = 1'b0;
-        else if (w_ctrl)    en_n = PWDATA[0];
+        if (w_ctrl)         en_n = PWDATA[0];
+        else if (expire & mode) en_n = 1'b0;
         else                en_n = en;
         // R-PRI-3: start/restart > expiration effect > tick/prescaler > hold
```

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M05_LEVEL_SENSITIVE_START.sv
@@ -54,5 +54,5 @@
     assign tick   = en & (pcnt >= psc);
     assign expire = tick & (count == 16'd0);
-    assign start  = w_ctrl & PWDATA[0] & ~en;
+    assign start  = w_ctrl & PWDATA[0];
     assign rcmd   = w_cmd  & PWDATA[0];
```

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M06_START_KEEPS_PRESCALER_PHASE.sv
@@ -100,5 +100,5 @@
             active_n = shadow;          // reload transfer uses held SHADOW
             count_n  = shadow;
-            pcnt_n   = 8'd0;
+            pcnt_n   = rcmd ? 8'd0 : pcnt;
         end else if (en) begin
             pcnt_n = tick ? 8'd0 : pcnt + 8'd1;          // R-TMR-1
```

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M07_PRESCALER_EQUALITY_COMPARE.sv
@@ -52,5 +52,5 @@
     // ---------------- events (spec section 8.1) ----------------
     logic tick, expire, start, rcmd;
-    assign tick   = en & (pcnt >= psc);
+    assign tick   = en & (pcnt == psc);
     assign expire = tick & (count == 16'd0);
     assign start  = w_ctrl & PWDATA[0] & ~en;
```

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M08_RESTART_REQUIRES_EN.sv
@@ -55,5 +55,5 @@
     assign expire = tick & (count == 16'd0);
     assign start  = w_ctrl & PWDATA[0] & ~en;
-    assign rcmd   = w_cmd  & PWDATA[0];
+    assign rcmd   = w_cmd  & PWDATA[0] & en;
 
     // ---------------- outputs (R-APB-3, 6, 7, 8; R-INT-6) ----------------
```

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M09_IE_GATES_PEND.sv
@@ -111,5 +111,5 @@
         end
         // R-PRI-4 / R-INT-1,2
-        pend_n = expire ? 1'b1 : ((w_stat & PWDATA[0]) ? 1'b0 : pend);
+        pend_n = (expire & ie) ? 1'b1 : ((w_stat & PWDATA[0]) ? 1'b0 : pend);
         // R-PRI-5 / R-INT-3,4 (set condition reads HELD pend)
         ovf_n  = (expire & pend) ? 1'b1 : ((w_stat & PWDATA[1]) ? 1'b0 : ovf);
```

```diff
--- ref/apb_timer_refdut.sv
+++ mutants/M10_IRQ_REGISTERED.sv
@@ -60,5 +60,8 @@
     assign PREADY  = 1'b1;
     assign PSLVERR = err;
-    assign irq     = pend & ie;
+    logic irq_q;
+    always_ff @(posedge PCLK or negedge PRESETn)
+        if (!PRESETn) irq_q <= 1'b0; else irq_q <= pend & ie;
+    assign irq     = irq_q;
     always_comb begin
         PRDATA = 32'h0;
```

