#import "@preview/zap:0.6.0"

#set page(width: 14cm, height: auto, margin: 1cm)

= Electronic circuit with Zap

Zap is a circuit-diagram package powered by CeTZ. Both packages are pinned and
declared as Bazel inputs for this target.

#align(center, zap.circuit({
  import zap: *

  vsource("source", (0, 0), (0, 4), label: "5 V")
  resistor("r1", "source.out", (rel: (4, 0)), label: $R_1$, i: $I$)
  capacitor("c1", "r1.out", (rel: (0, -4)), label: $C_1$)
  wire("c1.out", "source.in")
  node("output", "r1.out", label: (content: $V_"out"$, position: "east"))
}))
