// MX64-H Phase 32: integer effective-address generation and access checks.
module mx64_address_generation_unit #(
  parameter int ADDR_W = 64,
  parameter int BYTE_LANES = 8
) (
  input  logic [ADDR_W-1:0] base_value,
  input  logic [ADDR_W-1:0] immediate,
  input  logic [2:0] size_log2, // 0=1B, 1=2B, 2=4B, 3=8B
  output logic [ADDR_W-1:0] effective_addr,
  output logic [BYTE_LANES-1:0] byte_mask,
  output logic size_valid,
  output logic misaligned
);
  logic [ADDR_W-1:0] size_bytes;

  always_comb begin
    effective_addr = base_value + immediate;
    size_valid = (size_log2 <= 3) && (BYTE_LANES == 8);
    size_bytes = ADDR_W'(1) << size_log2;
    byte_mask = '0;
    if (size_valid) begin
      for (int b = 0; b < BYTE_LANES; b++)
        byte_mask[b] = (b < size_bytes);
    end
    misaligned = !size_valid || ((effective_addr & (size_bytes - ADDR_W'(1))) != '0);
  end
endmodule
