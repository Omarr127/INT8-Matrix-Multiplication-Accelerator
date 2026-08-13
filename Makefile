# =============================================================================
# Makefile - INT8 Matrix-Multiplication Accelerator
# -----------------------------------------------------------------------------
# Simulation with Icarus Verilog (open-source, matches what's used in CI /
# for quick iteration). For ModelSim/QuestaSim, see README.md for the
# equivalent `vlog`/`vsim` commands.
# =============================================================================

RTL_SOURCES = rtl/mac_unit.sv \
              rtl/requantize_unit.sv \
              rtl/control_fsm.sv \
              rtl/int8_matmul_accelerator.sv

TB_SOURCE   = tb/tb_int8_matmul_accelerator.sv

.PHONY: sim wave clean

sim:
	iverilog -g2012 -o sim.out $(RTL_SOURCES) $(TB_SOURCE)
	vvp sim.out

wave:
	iverilog -g2012 -DDUMP_VCD -o sim.out $(RTL_SOURCES) $(TB_SOURCE)
	vvp sim.out
	@echo "Open wave.vcd in GTKWave: gtkwave wave.vcd"

clean:
	rm -f sim.out wave.vcd
