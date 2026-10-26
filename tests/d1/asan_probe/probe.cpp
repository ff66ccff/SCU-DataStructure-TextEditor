#include <cstdio>
int main(){ int* p = new int[3]; p[0] = 1; std::printf("ok %d\n", p[0]); delete[] p; return 0; }
