#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double calc(double x) {
    return (x * (x + 1) * ((2 * x) + 1)) / 6;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s <bound> <length>\n", argv[0]);
        return 1;
    }

    int bound = atoi(argv[1]);
    int length = atoi(argv[2]);

    for (int i = 1; i <= bound; i++) {
        double result = sqrt(calc(i+length-1)-calc(i-1));
        if (ceilf(result) == result) {
            printf("i: %d, Result: %f\n", i, result);
        }
    }
}
