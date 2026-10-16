#include <cstdio>
#include <cstdint>
#include "design.cpp"
// Reads vectors/all.vec; per cycle: drive inputs (clk low), settle, compare outputs+state to expected, clock.
int main(int argc,char**argv){
  cxxrtl_design::p_apb__timer t; FILE*f=fopen(argv[1],"r"); FILE*o=fopen(argv[2],"w");
  unsigned v[21]; long cyc=0;
  t.p_PCLK.set<bool>(false); t.p_PRESETn.set<bool>(false); t.step(); t.step();
  while(true){
    int n=0; for(int i=0;i<21;i++){ if(fscanf(f,"%x",&v[i])!=1){n=-1;break;} } if(n<0)break;
    t.p_PRESETn.set<bool>(v[1]); t.p_PSEL.set<bool>(v[2]); t.p_PENABLE.set<bool>(v[3]); t.p_PWRITE.set<bool>(v[4]);
    t.p_PADDR.set<uint32_t>(v[5]); t.p_PWDATA.set<uint32_t>(v[6]); t.step(); t.step();
    unsigned got[14]={t.p_PRDATA.get<uint32_t>(),t.p_PSLVERR.get<uint32_t>(),t.p_PREADY.get<uint32_t>(),t.p_irq.get<uint32_t>(),
      t.p_en.get<uint32_t>(),t.p_mode.get<uint32_t>(),t.p_ie.get<uint32_t>(),t.p_psc.get<uint32_t>(),t.p_shadow.get<uint32_t>(),
      t.p_active.get<uint32_t>(),t.p_count.get<uint32_t>(),t.p_pcnt.get<uint32_t>(),t.p_pend.get<uint32_t>(),t.p_ovf.get<uint32_t>()};
    int mo=0,ms=0; for(int i=0;i<4;i++) if(got[i]!=v[7+i]) mo=1; for(int i=4;i<14;i++) if(got[i]!=v[7+i]) ms=1;
    fprintf(o,"%ld %x %d %d\n",cyc,v[0],mo,ms);
    t.p_PCLK.set<bool>(true); t.step(); t.p_PCLK.set<bool>(false); t.step(); cyc++;
  }
  return 0;
}
