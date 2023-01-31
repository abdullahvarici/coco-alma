module s_bit2_sh3 (
  y2,
  w2,
  z1,
  x1,
  out3
);

    input wire y2;
    input wire w2;
    input wire z1;
    input wire x1;

    output wire out3;

    assign out3 = y2 & w2 ^ y2 & z1 ^ y2 & z1 & w2 ^ x1 & y2 & z1 ;

endmodule