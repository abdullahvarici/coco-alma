# We expect to see a leakage in stable mode

.section .text.start

# x2 = 0
li x2, 0
# *x2 == w0 = dmem[1] # share 0
bn.lid x2, 32(x0)
# x2 = 1
li x2, 1
# *x2 == w1 = dmem[2] # share 0
bn.lid x2, 64(x0)

# w2 = w0 ^ w1
bn.xor w2, w0, w1

ecall