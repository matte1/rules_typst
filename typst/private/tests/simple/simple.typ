#import "@test/example:1.0.0": package-message

$ A = pi r^2 $
$ "area" = pi dot "radius"^2 $
$ cal(A) :=
    { x in RR | x "is natural" } $
#let x = 5
$ #x < 17 $

#package-message

#figure(
  image("./smile.svg", width: 80%),
  caption: [
    Smile you have an image!
  ],
)

#figure(
  image("./frown.svg", width: 80%),
  caption: [
    Smile you have an image!
  ],
)
