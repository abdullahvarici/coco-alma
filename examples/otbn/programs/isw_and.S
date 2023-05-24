# We start with
# - secret X in w6 and w7 (A and B share) - 0011 = 1010 ^ 1001
# - secret Y in w8 and w9 (A and B share) - 0101 = 1110 ^ 1011
# - fresh mask in w10 - 0110
# - expected result w11 & w12 == 0011 & 0101 = 0001 
#
# We end up with
# - Secret Q in x11 and x12 (A and B share)
#
# Where Q = X & Y
#
.section .text.start

# Set registers - Load secrets from DMEM
# x2 = 6
li x2, 6
# *x2 == w6 = dmem[0] # share 0
bn.lid x2, 0(x0)
# x2 = 7
li x2, 7
# *x2 == w7 = dmem[1] # share 0
bn.lid x2, 32(x0)
# x2 = 8
li x2, 8
# *x2 == w8 = dmem[2] # share 1
bn.lid x2, 64(x0)
# x2 = 9
li x2, 9
# *x2 == w9 = dmem[3] # share 1
bn.lid x2, 96(x0)
# x2 = 10
li x2, 10
# *x2 == w10 = dmem[4] # mask
bn.lid x2, 128(x0)

# Compute inner-domain terms.
bn.and w1, w6, w8
bn.and w0, w0, w0 # dummy
bn.and w2, w7, w9
bn.and w0, w0, w0 # dummy

# Compute cross-domain terms.
bn.and w3, w6, w9
bn.and w0, w0, w0 # dummy
bn.and w4, w7, w8
bn.and w0, w0, w0 # dummy

# Resharing of cross-domain terms.
bn.xor w14, w4, w10
bn.and w0, w0, w0 # dummy
bn.xor w13, w3, w10
bn.and w0, w0, w0 # dummy

# Integration
bn.xor w11, w1, w13
bn.and w0, w0, w0 # dummy
bn.xor w12, w2, w14
bn.and w0, w0, w0 # dummy

# # Compute result and compare it with the expected result
# # If the result is different than the expected one,
# # otbn cannot exit from the infinite loop
# bn.xor w15, w11, w12
# li x31, 15
# bn.sid x31, 0(x0)
# lw x31, 0(x0)
# li x30, 1
# inf_loop:
# bne x31, x30, inf_loop

ecall