# We don't expect any leakage at all in stable or transient modes

.section .text.start

# x2 = dmem[1] # share 0
lw x2, 32(x0)
# x30 = dmem[3] # share 0
lw x30, 96(x0)
# x3 = dmem[2] # share 0
lw x3, 64(x0)

ecall