/* The user's session, for tests/memory.nix: like a desktop or Claude waiting for the user,
   it holds memory it doesn't use for a while, then uses all of it.
   memory-session MB: every 5 seconds, goes over MB of memory and prints how many
   milliseconds that took. It is quick unless the memory was taken away (swapped out). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static long ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  size_t size = (size_t)atol(argv[1]) << 20;
  char *m = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (m == MAP_FAILED) return 1;
  uint64_t x = 2463534242ULL;
  for (size_t i = 0; i < size / 8; i++) {
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    ((uint64_t *)m)[i] = x;
  }
  for (;;) {
    sleep(5);
    long start = ms();
    for (size_t o = 0; o < size; o += 4096) m[o]++;
    printf("%ld\n", ms() - start);
    fflush(stdout);
  }
}
