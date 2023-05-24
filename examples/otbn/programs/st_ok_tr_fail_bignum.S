# We expect to see a leakage in transient mode
# Uncomment dummy operations to remove leakage
# Ignore u_dmem for now

.section .text.start

# x2 = 0
li x2, 0
# *x2 == w0 = dmem[1] # share 0
bn.lid x2, 32(x0)
# x2 = 1
li x2, 1
# *x2 == w1 = dmem[2] # share 0
bn.lid x2, 64(x0)

# w0 = w0 & w0
bn.and w0, w0, w0
# dummy operation
# bn.and w9, w9, w9
# w1 = w1 & w1
bn.and w1, w1, w1

ecall