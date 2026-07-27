#import "@preview/cetz:0.5.2"

#set page(width: 12cm, height: auto, margin: 1cm)

= CeTZ diagram

This diagram is rendered from a pinned CeTZ package fetched by Bazel.

#align(center, cetz.canvas(length: 2.2cm, {
  import cetz.draw: *

  set-style(
    mark: (fill: black, scale: 1.5),
    stroke: (thickness: 0.5pt, cap: "round"),
  )

  grid((-1.5, -1.5), (1.5, 1.5), step: 0.5, stroke: gray + 0.2pt)
  circle((0, 0), radius: 1, stroke: blue + 1pt)
  line((-1.5, 0), (1.5, 0), mark: (end: "stealth"))
  line((0, -1.5), (0, 1.5), mark: (end: "stealth"))
  line((0, 0), (45deg, 1), stroke: red + 1pt)
  content((45deg, 1), $P$, anchor: "south-west")
}))
