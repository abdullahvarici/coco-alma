/* Copyright lowRISC contributors. */
/* Licensed under the Apache License, Version 2.0, see LICENSE for details. */
/* SPDX-License-Identifier: Apache-2.0 */

# This program is taken from opentitan/sw/otbn/crypto/p256_key_from_seed_sca.s
# and opentitan/sw/otbn/crypto/p256.s. It is then simplified / modified to be
# used with the framework.

/**
 * Wrapper specifically for SCA/formal analysis of p256 keygen.
 *
 * Normally, the key generation routines called here would be used with key
 * manager seeds only. This wrapper uses software-provided seeds for analysis
 * purposes and should not be used for production code.
 */

.section .text.start

start:
  /* Read mode, then tail-call either p256_gen_secret_key or p256_gen_keypair */
  
  # Remove p256_gen_keypair option for this analysis
  
  beq   x0, x0, p256_gen_secret_key

  /* Invalid mode; fail. */
  unimp

p256_gen_secret_key:
  /* First, generate the masked secret key d and write to DMEM.
       dmem[d0] <= d0
       dmem[d1] <= d1 */
  jal       x1, run_gen_secret_key

  ecall

run_gen_secret_key:
  /* Init all-zero register. */
  bn.xor    w31, w31, w31

  /* Load shares of seed from DMEM.
       [w21,w20] <= dmem[seed0]
       [w23,w33] <= dmem[seed1] */
  # Load seeds from sideload interface instead of DMEM for this analysis
  # Comment this part to assume the seeds are already in bignum registers and
  # label registers instead of sideload interface input
  bn.wsrr w20, 0x4
  #bn.wsrr w21, 0x5
  bn.xor w31, w31, w31 # dummy
  bn.wsrr w22, 0x6
  #bn.wsrr w23, 0x7

  /* Generate the derived secret key.
       [w21,w20] <= d0
       [w23,w33] <= d1 */
  jal       x1, p256_key_from_seed

  /* Write the results to DMEM.
       dmem[d0] <= [w21, w20]
       dmem[d1] <= [w23, w22] */
  # Do not write the results to DMEM for this analysis

  ret

/**
 * Convert boolean shares to arithmetic ones using Goubin's algorithm.
 *
 * Returns x0, x1 such that (s0 ^ s1) = (x0 + x1) mod 2^321.
 *
 * The input consists of two 320-bit shares, s0 and s1. Bits at position 320
 * and above in the input shares will be ignored. We compute the result mod
 * 2^321 so that the high bit of x0 will reveal the carry modulo 2^320.
 *
 * We then use Goubin's boolean-to-arithmetic masking algorithm to switch from
 * this boolean masking scheme to an arithmetic one without ever unmasking the
 * seed. See Algorithm 1 here:
 * https://link.springer.com/content/pdf/10.1007/3-540-44709-1_2.pdf
 *
 * The algorithm is reproduced here for reference:
 *   Input:
 *     s0, s1: k-bit shares such that x = s0 ^ s1
 *     gamma: random k-bit number
 *   Output: x0, k-bit number such that x = (x0 + s1) mod 2^k
 *   Pseudocode:
 *     T := ((s0 ^ gamma) - gamma) mod 2^k
 *     T2 := T ^ s0
 *     G := gamma ^ s1
 *     A := ((s0 ^ G) - G) mod 2^k
 *     return x0 := (A ^ T2)
 *
 * The output x1 is always (s1 mod 2^320).
 *
 * This routine runs in constant time.
 *
 * Flags: Flags have no meaning beyond the scope of this subroutine.
 *
 * @param[in]  [w21, w20]: s0, first share of seed (320 bits)
 * @param[in]  [w23, w22]: s1, second share of seed (320 bits)
 * @param[in]         w31: all-zero
 * @param[out] [w21, w20]: result x0 (321 bits)
 * @param[out] [w23, w22]: result x1 (320 bits)
 *
 * clobbered registers: w1 to w5, w20 to w23
 * clobbered flag groups: FG0
 */
boolean_to_arithmetic:
  /* Mask out excess bits from seed shares.
       [w21, w20] <= s0 mod 2^320
       [w23, w22] <= s1 mod 2^320 = x1 */
  bn.rshi   w20, w20, w31 >> 2
  bn.rshi   w20, w31, w20 >> 254
  bn.xor    w31, w31, w31 # dummy
  bn.rshi   w22, w22, w31 >> 2
  bn.rshi   w22, w31, w22 >> 254

  /* Fetch 321 bits of randomness from URND.
       [w2, w1] <= gamma */
  # Use RND instead of URND for this analysis
  bn.wsrr   w1, 1
  #bn.wsrr   w2, 1
  #bn.rshi   w2, w31, w2 >> 192

  /* [w4, w3] <= [w21, w20] ^ [w2, w1] = s0 ^ gamma */
  bn.xor    w3, w20, w1
  #bn.xor    w4, w21, w2

  /* Subtract gamma. This may result in bits above 2^321, but these will be
     stripped off in the next step.
       [w4, w3] <= [w4, w3] - [w2, w1] = ((s0 ^ gamma) - gamma) mod 2^512 */
  bn.sub    w3, w3, w1
  #bn.subb   w4, w4, w2

  bn.sub w31, w31, w31 # dummy operation to clear flags

  /* Truncate subtraction result to 321 bits.
       [w4, w3] <= [w4, w3] mod 2^321 = T */
  bn.rshi   w3, w3, w31 >> 2
  bn.rshi   w3, w31, w3 >> 254

  /* [w4, w3] <= [w4, w3] ^ [w21, w20] = T2 */
  bn.xor    w3, w3, w20
  #bn.xor    w4, w4, w21

  bn.xor w31, w31, w31 # dummy, I think it is not necessary for full bit implementation 

  /* [w2, w1] <= [w2, w1] ^ [w23, w22] = gamma ^ s1 = G */
  bn.xor    w1, w1, w22
  #bn.xor    w2, w2, w23

  bn.xor w31, w31, w31 # dummy, I think it is not necessary for full bit implementation 

  /* [w21, w20] <= [w21, w20] ^ [w2, w1] = s0 ^ G */
  bn.xor    w20, w20, w1 
  # bn.xor    w21, w21, w2

  /* [w21, w20] <= [w21, w20] - [w2, w1] = ((s0 ^ G) - G) mod 2^512 */
  bn.sub    w20, w20, w1
  #bn.subb   w21, w21, w2

  bn.sub w31, w31, w31 # dummy operation to clear flags

  /* [w21, w20] <= [w21, w20] mod 2^321 = A */
  bn.rshi   w20, w20, w31 >> 2
  bn.rshi   w20, w31, w20 >> 254

  /* [w21, w20] <= [w21, w20] ^ [w4, w3] = A ^ T2 = x0 */
  bn.xor    w20, w20, w3
  #bn.xor    w21, w21, w4

  ret

/**
 * P-256 ECDSA secret key generation.
 *
 * Returns the secret key d in two 320-bit shares d0 and d1, such that:
 *    d = (d0 + d1) mod n
 * ...where n is the curve order.
 *
 * This implementation follows FIPS 186-4 section B.4.1, where we
 * generate d using N+64 random bits (320 bits in this case) as a seed. But
 * while FIPS computes d = (seed mod (n-1)) + 1 to ensure a nonzero key, we
 * instead just compute d = seed mod n. The caller MUST ensure that if this
 * routine is used, then other routines that use d (e.g. signing, public key
 * generation) are checking if d is 0.
 *
 * Most complexity in this routine comes from masking. The input seed is
 * provided in two 320-bit shares, seed0 and seed1, such that:
 *   seed = seed0 ^ seed1
 * Bits at position 320 and above in the input shares will be ignored.
 *
 * We then use Goubin's boolean-to-arithmetic masking algorithm to switch from
 * this boolean masking scheme to an arithmetic one without ever unmasking the
 * seed. See Algorithm 1 here:
 * https://link.springer.com/content/pdf/10.1007/3-540-44709-1_2.pdf
 *
 * For a Coq proof of the correctness of the basic computational logic here
 * see:
 *   https://gist.github.com/jadephilipoom/24f44c59cbe59327e2f753867564fa28#file-masked_reduce-v-L226
 *
 * The proof does not cover leakage properties; it mostly just shows that this
 * logic correctly computes (seed mod n) and the carry-handling works.
 *
 * This routine runs in constant time.
 *
 * Flags: Flags have no meaning beyond the scope of this subroutine.
 *
 * @param[in]  [w21, w20]: seed0, first share of seed (320 bits)
 * @param[in]  [w23, w22]: seed1, second share of seed (320 bits)
 * @param[in]         w31: all-zero
 * @param[out] [w21, w20]: d0, first share of private key d (320 bits)
 * @param[out] [w23, w22]: d1, second share of private key d (320 bits)
 *
 * clobbered registers: x2, x3, w1 to w4, w20 to w29
 * clobbered flag groups: FG0
 */
p256_key_from_seed:
  /* Convert from a boolean to an arithmetic mask using Goubin's algorithm.
       [w21, w20] <= ((seed0 ^ seed1) - seed1) mod 2^321 = x0 */
  jal       x1, boolean_to_arithmetic

# The rest of this routine commented out until completing the analysis to here
#  /* At this point, we have arithmetic shares modulo 2^321:
#       [w21, w20] : x0
#       [w23, w22] : x1
#
#     We know that x1=seed1, and seed and x1 are at most 320 bits. Therefore,
#     the highest bit of x0 holds a carry bit modulo 2^320:
#       x0 = (seed - x1) mod 2^321
#       x0 = (seed - x1) mod 2^320 + (if (x1 <= seed) then 0 else 2^320)
#
#     The carry bit then allows us to replace (mod 2^321) with a conditional
#     statement:
#       seed = (x0 mod 2^320) + x1 - (x0[320] << 320)
#
#     Note that the carry bit is not very sensitive from a side channel
#     perspective; x1 <= seed has some bias related to the highest bit of the
#     seed, but since the seed is 64 bits larger than n, this single-bit noisy
#     leakage should not be significant.
#
#     From here, we want to convert to shares modulo (n * 2^64) -- these shares
#     will be equivalent to the seed modulo n but still retain 64 bits of extra
#     masking. We compute the new shares as follows:
#       c = (x0[320] << 320) mod (n << 64)
#       d0 = ((x0 mod 2^320) - c) mod (n << 64))
#       d1 = x1 mod (n << 64)
#
#       d = seed mod n = (d0 + d1) mod n
#  */
#
#  /* Load curve order n from DMEM.
#       w29 <= dmem[p256_n] = n */
#  li        x2, 29
#  la        x3, p256_n
#  bn.lid    x2, 0(x3)
#
#  /* Compute (n << 64).
#       [w29,w28] <= w29 << 64 = n << 64 */
#  bn.rshi   w28, w29, w31 >> 192
#  bn.rshi   w29, w31, w29 >> 192
#
#  /* [w25,w24] <= (x1 - (n << 64)) mod 2^512 */
#  bn.sub    w24, w22, w28
#  bn.subb   w25, w23, w29
#
#  /* Compute d1. Because 2^320 < 2 * (n << 64), a conditional subtraction is
#     sufficient to reduce. Similarly to the carry bit, the conditional bit here
#     is not very sensitive because the shares are large relative to n.
#       [w23,w22] <= x1 mod (n << 64) = d1 */
#  bn.sel    w22, w22, w24, FG0.C
#  bn.sel    w23, w23, w25, FG0.C
#
#  /* Isolate the carry bit and shift it back into position.
#       w25 <= x0[320] << 64 */
#  bn.rshi   w25, w31, w21 >> 64
#  bn.rshi   w25, w25, w31 >> 192
#
#  /* Clear the carry bit from the original result.
#       [w21,w20] <= x0 mod 2^320 */
#  bn.xor    w21, w21, w25
#
#  /* Conditionally subtract (n << 64) to reduce.
#       [w21,w20] <= (x0 mod 2^320) mod (n << 64) */
#  bn.sub    w26, w20, w28
#  bn.subb   w27, w21, w29
#  bn.sel    w20, w20, w26, FG0.C
#  bn.sel    w21, w21, w27, FG0.C
#
#  /* Compute the correction factor.
#       [w25,w24] <= (x[320] << 320) mod (n << 64) = c */
#  bn.sub    w26, w31, w28
#  bn.subb   w27, w25, w29
#  bn.sel    w24, w31, w26, FG0.C
#  bn.sel    w25, w25, w27, FG0.C
#
#  /* Compute d0 with a modular subtraction. First we add (n << 64) to protect
#     against underflow, then conditionally subtract it again if needed.
#       [w21,w20] <= ([w21, w20] - [w25,w24]) mod (n << 64) = d1 */
#  bn.add    w20, w20, w28
#  bn.addc   w21, w21, w29
#  bn.sub    w20, w20, w24
#  bn.subb   w21, w21, w25
#  bn.sub    w26, w20, w28
#  bn.subb   w27, w21, w29
#  bn.sel    w20, w20, w26, FG0.C
#  bn.sel    w21, w21, w27, FG0.C

  ret

/**
 * Note: Technically this could be a .bss section, but it is convenient for
 * software to have zeroes already set on the high bits of the seeds.
 */
.data

/* P-256 domain parameter n (order of base point) */
.globl p256_n
.balign 32
p256_n:
  .word 0xfc632551
  .word 0xf3b9cac2
  .word 0xa7179e84
  .word 0xbce6faad
  .word 0xffffffff
  .word 0xffffffff
  .word 0x00000000
  .word 0xffffffff