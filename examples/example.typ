#set page(width: 14cm, height: auto)

= Multi-directory asset demo

This document loads images from multiple directories via Bazel targets.

#figure(
  image("assets/source/smile.svg", width: 50%),
  caption: [Static source image from `assets/source/`],
)

#figure(
  image("assets/derived/frown.svg", width: 50%),
  caption: [Copied image from `assets/derived/`],
)

#figure(
  image("./generated/python/diamond.svg", width: 50%),
  caption: [SVG generated with Python into `generated/python/`],
)

#figure(
  image("generated/python/stripes.svg", width: 50%),
  caption: [Second Python-generated SVG from another output],
)
