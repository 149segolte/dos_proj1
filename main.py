import sys
import math

def calc(x: float) -> float:
    return (x * (x + 1) * ((2 * x) + 1)) / 6

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <bound> <length>")
        sys.exit(1)

    bound = int(sys.argv[1])
    length = int(sys.argv[2])

    for i in range(1, bound + 1):
        result = math.sqrt(calc(i + length - 1) - calc(i - 1))
        if math.ceil(result) == result:
            print(f"i: {i}, Result: {result}")

if __name__ == "__main__":
    main()
