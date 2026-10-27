# Anime4K

The two shaders here are taken verbatim from [bloc97/Anime4K](https://github.com/bloc97/Anime4K)
at the commit this was vendored from, under the MIT licence in `LICENSE`. They
are not edited by hand and should not be: they are weights.

* `Anime4K_Restore_CNN_S.glsl` — four convolution passes with a residual
  connection, trained to undo the blur and compression a low-bitrate encode
  leaves behind.
* `Anime4K_Upscale_CNN_x2_S.glsl` — four convolutions and a depth-to-space pass
  that doubles the picture.

`S` is the small variant. The repository also ships M, L, VL, UL and GAN
variants, up to 300 KB of weights each; those are sized for a desktop GPU
driving a 4K display and are not what a phone has to spend on a frame.

`Tools/convert-anime4k.py` translates them into Core Image Metal kernels, since
the originals are written for mpv's shader hook format. Run it again after
updating the files here — never edit the generated output.
