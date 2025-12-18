# SiliconJackets Calculator-SRAM Interface

This repository contains my full RTL-to-GDSII onboarding project for the SiliconJackets chip design team. The goal was to design a 64-bit unsigned integer calculator that interfaces with an external SRAM, verify it with a constrained-random testbench, and run it through physical design tools to check timing.

## <u>**Digital Design**</u>
I implemented the calculator logic using SystemVerilog. Since the system has a 32-bit data bus, I designed a controller with a Finite State Machine (FSM) to handle the multi-cycle operations required for 64-bit addition. The system reads two operands from memory (fetching upper and lower 32-bit halves separately), performs the addition using a generated adder module, and writes the results back to sequential memory addresses.

## <u>**Design Verification**</u>
To verify the design, I built a layered testbench environment rather than just using simple directed tests. I implemented a driver to push transactions to the DUT and a monitor/scoreboard system to compare the hardware output against a Python-based golden model. I used constrained random testing to cover edge cases like zero-value additions and overflows, achieving >96% functional coverage to ensure the FSM handled all state transitions correctly.

## <u>**Physical Design**</u>
Finally, I took the design through the physical flow to prepare it for tapeout. I wrote TCL scripts to automate synthesis and mapped the RTL to a standard cell library. I also performed Static Timing Analysis (STA) to define clock constraints and check for setup/hold violations. I used custom Python scripts to parse the generated timing reports and verify that the design met positive slack requirements.

## <u>**Tools Used**</u>
SystemVerilog, Python, TCL, C-Shell, Cadence Genus (Synthesis), Cadence Innovus (Place & Route), Cadence Tempus (Timing Analysis), Verisium Debug, Verdi.
