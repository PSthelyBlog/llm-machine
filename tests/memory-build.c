/* A build that needs a lot of memory, for tests/memory.nix.
   memory-build MB RATE PASSES: takes MB of memory (0: more and more, until it is stopped) at
   RATE MB a second, then goes over all of it PASSES times, as a build working on it would.
   The memory holds data that doesn't compress, so zram can't make room by compressing it. */
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define CHUNK (8UL << 20)

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  size_t want = (size_t)atol(argv[1]) << 20;
  double rate = atof(argv[2]) * (1 << 20);
  long passes = atol(argv[3]);
  if (want == 0) want = (size_t)1 << 40;

  char **chunks = calloc(want / CHUNK + 1, sizeof *chunks);
  uint64_t x = 88172645463325252ULL;
  double start = now();
  size_t n = 0;
  for (; n * CHUNK < want; n++) {
    chunks[n] = mmap(NULL, CHUNK, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (chunks[n] == MAP_FAILED) return 1;
    uint64_t *words = (uint64_t *)chunks[n];
    for (size_t i = 0; i < CHUNK / 8; i++) {
      x ^= x << 13;
      x ^= x >> 7;
      x ^= x << 17;
      words[i] = x;
    }
    double ahead = (n + 1) * CHUNK / rate - (now() - start);
    if (ahead > 0) usleep(ahead * 1e6);
  }
  for (long p = 0; p < passes; p++)
    for (size_t i = 0; i < n; i++)
      for (size_t o = 0; o < CHUNK; o += 4096) chunks[i][o]++;

  const char *out = getenv("out");
  return out && close(open(out, O_CREAT | O_WRONLY, 0644)) != 0;
}
