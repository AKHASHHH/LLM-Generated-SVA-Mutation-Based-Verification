# The 23 APBTMR-SPEC v1.0 example sequences (identical stimulus to the spec tables, which were generated
# from these exact definitions). Each entry: (title, list of per-cycle input dicts, starting from reset).
from specmodel import *
def align(pre, op, want_exp=True, post=4, kmax=40):
    """insert k idle cycles so that op's ACCESS cycle is (or is not) an expiration cycle"""
    for k in range(kmax):
        seq=pre+I(k)+op
        rows,_=run(seq); exp=rows[len(seq)-1][6]
        if bool(exp)==want_exp: return pre+I(k)+op+I(post), len(pre)+k
    raise Exception("no alignment")
EX=[]
def ex(title, setup_txt, seq, start, notes, reset_col=False):
    EX.append((title,list(seq)))
C=lambda en=0,mode=0,ie=0,psc=0:(psc<<8)|(ie<<2)|(mode<<1)|en
# E1
seq=RST(1)+R(CTRL)+R(STATUS)+R(CMD)+R(0x1C,"R 0x1C (unmapped)")
ex("Reset values and basic reads","Reset asserted, then released before cycle 1.",seq,0,
 "All state is 0 after reset. PRDATA is non-zero only in a read access cycle to a mapped register; it is 0 in setup cycles. A read of unmapped offset 0x1C returns PRDATA=0 with PSLVERR=1. CMD reads as 0.",True)
# E2
pre=W(LOAD,2)+W(CTRL,C(en=1,ie=1))
seq=pre+I(2)+R(COUNT)+I(3)
ex("Periodic start, PSC=0, LOAD=2","From reset: write LOAD=2, then CTRL with EN=1, MODE=periodic, IE=1, PSC=0.",seq,2,
 "The CTRL write in cycle 1 is a start (EN was 0), so from cycle 2 ACTIVE=COUNT=SHADOW=2 and PCNT=0. With PSC=0 every enabled cycle is a tick. COUNT steps 2, 1, 0, and the tick taken while COUNT=0 (cycle 4) is the expiration: from cycle 5 PEND=1 and COUNT=2 again. The first expiration is in the 3rd enabled cycle, i.e. (SHADOW+1)*(PSC+1). irq equals PEND AND IE, so it rises in cycle 5. The COUNT read in cycle 5 returns 2, the value held during the access cycle, even though COUNT becomes 1 at the end of that cycle. The second expiration (cycle 7) finds PEND already 1, so OVF is also set from cycle 8.")
# E3
pre=W(LOAD,1)+W(CTRL,C(en=1,ie=1,psc=2))
seq=pre+I(9)
ex("Prescaler PSC=2","From reset: LOAD=1, then start with PSC=2, periodic, IE=1.",seq,2,
 "A tick occurs in each enabled cycle in which PCNT >= PSC; PCNT then returns to 0, otherwise it increments. Ticks therefore occur every PSC+1=3 cycles. COUNT 1 -> 0 at the first tick, and the second tick (with COUNT=0) is the expiration. Expiration period = (1+1)*(2+1)=6 cycles.")
# E4
pre=W(LOAD,1)+W(CTRL,C(en=1,mode=1,ie=1))
seq=pre+I(4)+R(CTRL)
ex("One-shot completion","From reset: LOAD=1, then start in one-shot mode, PSC=0, IE=1.",seq,2,
 "The one-shot expiration sets PEND and clears EN. COUNT stays 0, ACTIVE is unchanged, and no further ticks or expirations occur. A CTRL read afterwards shows EN=0 with MODE and IE still 1.")
# E5
pre=W(LOAD,0)+W(CTRL,C(en=1,mode=1,ie=0))+I(2)
seq=pre+W(CTRL,C(en=0,mode=1,ie=1))+I(2)
ex("Interrupt mask does not gate PEND","From reset: LOAD=0, start one-shot with IE=0. The expiration happens while IE=0. Window starts after completion.",seq,len(pre)-1,
 "PEND was set by the expiration even though IE=0, so irq stayed 0. Writing IE=1 (with EN=0, so this is not a start) makes irq=1 from the cycle after the write, because PEND is still 1.")
# E6
pre=W(LOAD,0)+W(CTRL,C(en=1,mode=1,ie=1))+I(2)
seq=pre+W(STATUS,0)+W(STATUS,1)+I(2)
ex("W1C semantics of STATUS","State: one-shot finished, PEND=1, IE=1, irq=1.",seq,len(pre),
 "Writing 0 to STATUS changes nothing. Writing 1 to bit 0 clears PEND at the end of the access cycle, and irq falls in the following cycle.")
# E7
pre=W(LOAD,3)+W(CTRL,C(en=1,ie=1))
pre2,k=align(pre+I(1),[],True,0)
# need PEND=1 first; first expiration sets it; align STATUS clear with second expiration
rows,_=run(pre+I(12)); 
seq,k=align(pre+I(5),W(STATUS,1),True,3)
ex("W1C of PEND in the same cycle as an expiration","Periodic, LOAD=3, PSC=0, IE=1. PEND is already 1 from an earlier expiration. The STATUS access cycle is timed to coincide with the next expiration.",seq,k-1,
 "Hardware set beats software clear: PEND remains 1. Because PEND was 1 at the start of the expiration cycle, OVF is set, even though software was clearing PEND in that same cycle.")
# E8
seq=seq+W(STATUS,3)+I(1)
ex("Clearing PEND and OVF together","Continues example 7.",seq,len(seq)-3,
 "A STATUS write of 0x3 clears both bits (no expiration is coincident), and irq falls.")
# E9
pre=W(LOAD,4)+W(CTRL,C(en=1,ie=0))+I(1)
seq=pre+W(LOAD,1)+I(6)
ex("SHADOW write while running (non-coincident)","Periodic, LOAD=4, PSC=0, IE=0, running.",seq,len(pre),
 "The LOAD write updates SHADOW only. ACTIVE and COUNT are unaffected and counting continues from the old value. At the next periodic expiration both ACTIVE and COUNT take SHADOW=1, so the following period is 2 cycles.")
# E10
pre=W(LOAD,2)+W(CTRL,C(en=1,ie=0))
seq,k=align(pre,W(LOAD,5),True,7)
ex("SHADOW write coincident with periodic expiration","Periodic, LOAD=2, PSC=0, running. The LOAD access cycle coincides with an expiration.",seq,k,
 "The reload performed by an expiration uses SHADOW as held at the start of the expiration cycle (2), not the value being written (5). The new SHADOW=5 is transferred at the following expiration.")
# E11
pre=W(LOAD,5)+W(CTRL,C(en=1,psc=1))+I(3)
seq=pre+W(CTRL,C(en=0,psc=1))+I(3)+W(CTRL,C(en=1,psc=1))+I(2)
ex("Stop, then enable again (restart, not resume)","Periodic, LOAD=5, PSC=1, running.",seq,len(pre),
 "The cycle in which EN=0 is written (cycle 1) is still an enabled cycle, so PCNT advances to 1 at its end. From cycle 2 the timer is stopped: COUNT, PCNT and ACTIVE hold. Writing EN=1 while EN=0 is a start: COUNT and ACTIVE reload from SHADOW and PCNT returns to 0. The timer does not resume from the held COUNT.")
# E12
pre=W(LOAD,6)+W(CTRL,C(en=1,psc=3))+I(1)
seq=pre+W(CTRL,C(en=1,ie=1,psc=0))+I(4)
ex("CTRL write with EN=1 while already enabled is not a start","Periodic, LOAD=6, PSC=3, running.",seq,len(pre),
 "EN was already 1, so this write is not a start: COUNT is not reloaded and PCNT is not cleared (PCNT advances 2 to 3 at the end of the write cycle, as usual). The new PSC=0 and IE=1 apply from cycle 2, where PCNT=3 >= PSC=0 gives a tick, and every cycle after that is a tick.")
# E13
pre=W(LOAD,3)+W(CTRL,C(en=1,psc=5))+I(1)
seq=pre+W(CTRL,C(en=1,psc=1))+I(4)
ex("Lowering PSC below the current PCNT","Periodic, LOAD=3, PSC=5, running with PCNT partway through an interval.",seq,len(pre),
 "PCNT is not cleared by a PSC change. In cycle 2, the first cycle using PSC=1, PCNT=3 >= 1, so a tick occurs at once and PCNT returns to 0. A comparison for equality only would miss this tick and let PCNT run up to 255 and wrap.")
# E14
pre=W(LOAD,4)+W(CTRL,C(en=1,psc=1))+I(4)+W(LOAD,7)
seq=pre+W(CMD,1)+I(3)
ex("RESTART command while running","Periodic, PSC=1, running from LOAD=4; SHADOW was then rewritten to 7.",seq,len(pre),
 "CMD.RESTART loads ACTIVE and COUNT from SHADOW and clears PCNT at the end of the access cycle, overriding the tick/decrement of that cycle. EN is unchanged.")
# E15
pre=W(LOAD,1)+W(CTRL,C(en=1,mode=1,ie=1,psc=2))+W(LOAD,3)
seq,k=align(pre,W(CMD,1),True,3)
ex("RESTART coincident with one-shot expiration","One-shot, PSC=2, LOAD=1 at start, SHADOW then rewritten to 3. The CMD access cycle coincides with the expiration.",seq,k,
 "The expiration still occurs (PEND sets, EN clears). RESTART takes precedence for COUNT, ACTIVE and PCNT, so they load SHADOW=3 and 0. EN stays 0, so the timer remains stopped with COUNT=3.")
# E16
pre=W(LOAD,1)+W(CTRL,C(en=1,mode=1,ie=0))
seq,k=align(pre,W(CTRL,C(en=1,mode=1,ie=1,psc=2)),True,3)
ex("CTRL write with EN=1 coincident with one-shot expiration","One-shot, LOAD=1, IE=0, running. A CTRL write of EN=1, IE=1, PSC=2 coincides with the expiration.",seq,k,
 "The one-shot completion forces EN to 0 regardless of the written EN value. The other written fields (IE=1, PSC=2) do take effect. This is not a start, because EN was 1 at the start of the cycle. Software must write EN=1 again to start.")
# E17
pre=W(LOAD,3)+W(CTRL,C(en=1))
seq,k=align(pre,W(CTRL,C(en=1,mode=1)),False,5)
ex("Switching periodic to one-shot while running","Periodic, LOAD=3, PSC=0, running. The CTRL write (MODE=1, EN=1) is not coincident with an expiration.",seq,k,
 "MODE applies to any expiration that occurs after the cycle of the write. The next expiration is therefore a one-shot completion: EN clears and COUNT stays 0.")
# E18
pre=W(LOAD,2)+W(CTRL,C(en=1))
seq,k=align(pre,W(CTRL,C(en=1,mode=1)),True,4)
ex("Switching to one-shot in the same cycle as an expiration","Periodic, LOAD=2, PSC=0, running. The CTRL write (MODE=1) coincides with an expiration.",seq,k,
 "The coincident expiration uses MODE as held at the start of the cycle (periodic), so it reloads COUNT and EN stays 1. The next expiration is one-shot.")
# E19
pre=W(LOAD,2)+W(CTRL,C(en=1))
seq,k=align(pre,W(CTRL,C(en=0)),True,3)
ex("Disabling in the same cycle as a periodic expiration","Periodic, LOAD=2, PSC=0, running. The CTRL write (EN=0) coincides with an expiration.",seq,k,
 "The expiration is fully processed (PEND set, COUNT and ACTIVE reloaded) and the timer is then stopped by the write.")
# E20
pre=W(LOAD,9)+W(CTRL,C(en=1,psc=4))
seq=pre+W(COUNT,0x55,"W COUNT (read-only)")+W(0x06,0x33,"W LOAD via PADDR=0x06")+W(CMD,0)+R(0x24,"R 0x24 (unmapped)")
ex("APB error and decode cases","Periodic, LOAD=9, PSC=4, running.",seq,len(pre),
 "A write to read-only COUNT gives PSLVERR=1 and has no effect. PADDR[1:0] are ignored, so PADDR=0x06 addresses LOAD. A CMD write with bit 0 = 0 does nothing. A read of an unmapped offset gives PSLVERR=1 and PRDATA=0. PSLVERR is only ever 1 in access cycles.")
# E21
pre=W(LOAD,0)+W(CTRL,C(en=1,ie=1,psc=1))
seq=pre+I(6)
ex("LOAD=0 in periodic mode","From reset: LOAD=0, start periodic with PSC=1, IE=1.",seq,2,
 "With ACTIVE=0 every tick is an expiration, giving a period of (0+1)*(1+1)=2 cycles. The second expiration sets OVF because PEND was not cleared.")
# E22
pre=W(LOAD,3)+W(CTRL,C(en=1,ie=1))+I(5)
seq=pre+RST(2)+I(2)+R(CTRL)
ex("Asynchronous reset during operation","Periodic, LOAD=3, PSC=0, IE=1, running, PEND=1 (irq=1).",seq,len(pre)-1,
 "PRESETn falls between clock edges, partway through the cycle shown as the first PRESETn=0 row. All state takes its reset value immediately, without waiting for a clock edge, so irq falls during that cycle. The row shows the state after the asynchronous reset. After release, the timer is disabled with all registers at 0.",True)
pre=W(LOAD,4)+W(CTRL,C(en=1,psc=3))+I(2)
seq=pre+R(ACTIVE)+R(PSCNT)+R(LOAD)+R(STATUS)
ex("Readback of internal state while running","Periodic, LOAD=4, PSC=3, running.",seq,len(pre),
 "ACTIVE, PSCNT, LOAD and STATUS reads return the values held during the access cycle. PSCNT exposes PCNT directly.")
