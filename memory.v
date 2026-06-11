// memoria funcionando

module memory (
    input clk,
    input [2:0] operation, 
    input [3:0] address1, 
    input [3:0] address2, 
    input [15:0] data_in,  
    output wire [15:0] data_out1,
    output wire [15:0] data_out2
);

parameter OP_LER = 0, OP_SALVE = 1, OP_CLEAR = 2; // nome das operacoes(diminui para 3 estados)

reg [15:0] ram [15:0];
reg [15:0] reg_data_out1; 
reg [15:0] reg_data_out2;

always @(posedge clk) begin
    case (operation)

        OP_LER: begin 
            reg_data_out1 <= ram[address1]; 
            reg_data_out2 <= ram[address2];
        end

        OP_SALVE: begin
            ram[address1] <= data_in;  
        end

        OP_CLEAR: begin
            ram[0] <= 0;	    ram[1] <= 0;		    ram[2] <= 0;
			ram[3] <= 0;		ram[4] <= 0;			ram[5] <= 0;
			ram[6] <= 0;		ram[7] <= 0;			ram[8] <= 0;
			ram[9] <= 0;		ram[10] <= 0;		    ram[11] <= 0;
			ram[12] <= 0;	    ram[13] <= 0;		    ram[14] <= 0;
			ram[15] <= 0;
        end

        default: begin
            reg_data_out1 <= 16'h0000;
            reg_data_out2 <= 16'h0000;
        end
        
    endcase
end

assign data_out1 = reg_data_out1;
assign data_out2 = reg_data_out2;
endmodule