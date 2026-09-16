Hingewave 0.2.3. The Windows overlay painted a solid black frame on every fold: the full screen triangle winds counter-clockwise and Direct3D culls back faces by default, so the draw was discarded. Metal does not cull, which is why only the Windows port was affected. The WARP golden check now gates CI as well, instead of printing FAIL and passing anyway.

Blur now keeps 30 percent of its radius at the hinge, so the band on the rotation axis frosts with the rest of the panel rather than going dark while staying sharp. The macOS Dock and the Android icon row are where this shows most.

macOS builds are signed with the stable release certificate; they are not notarized.
