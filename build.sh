set -e

# 1
# gcc -c C/renderer.c C/renderer.c C/rencache.c C/api/api.c C/api/api_renderer.c C/api/renderer_font.c C/api/system.c C/lib/stb/stb_truetype.c -I C/

# 2
gcc -c -O2 -g C/rencache.c C/api/api.c C/api/api_renderer.c C/api/renderer_font.c C/api/system.c -I C/

ar rcs liblite.a *.o
rm *.o
