// Modulo da CPU funcionando!

module module_mini_cpu (
    input clk, b_ligar, b_enviar,
    input [2:0] opcode,
    input [3:0] end1,
    input [3:0] end2,
    input [6:0] end3_ou_imd, // end2 [6:3] ou imediato [6:0]

    // saidas para controlar o lcd
    output [7:0] lcd_data,
    output RS, RW, EN, lcd_on, lcd_blon
);

reg signed [15:0] imediato;

// para a instancia da memoria
reg [1:0] modo_ram;
reg [3:0] end_r1, end_r2;
reg signed [15:0] data_in;
wire [15:0] data_out1, data_out2;

// regs para usar na ula
wire signed [15:0] resultado_ula;
reg signed [15:0] operando_2;

// instancia do lcd
assign lcd_on = 1'b1;    // Display sempre energizado
assign lcd_blon = 1'b1;  // Luz sempre acesa
reg lcd_start;				// sinal para o lcd iniciar
wire lcd_ocupado;
wire rst_lcd = ~b_ligar;


// Parâmetros dos Opcodes
parameter   LOAD    = 3'b000,
            ADD     = 3'b001,
            ADDI    = 3'b010,
            SUB     = 3'b011,
            SUBI    = 3'b100,
            MUL     = 3'b101,
            CLEAR   = 3'b110,
            DISPLAY = 3'b111;
				

// estados da FSM
parameter off = 0, espera_envio = 1, ler_memoria = 2, ula = 3, salvar_memoria = 4, upd_lcd = 5;
reg [2:0] estado_cpu = off;

// parametros para o modo da ram
parameter LER = 0, SALVE = 1, CLEAR_RAM = 2;


// instancia da memoria
memory RAM(
    .clk(clk),
    .operation(modo_ram), 
    .address1(end_r1), 
    .address2(end_r2), 
    .data_in(data_in),  
    .data_out1(data_out1),
    .data_out2(data_out2)
);



// instancia da ula
module_alu ULA (
	 .op_code(opcode),   
    .reg_a_val(data_out1),  
    .reg_b_val(operando_2),       
    .alu_out(resultado_ula)         
);



lcd_controller_top display (
    .clk(clk),
    .rst(rst_lcd),
    .iniciar_escrita(lcd_start),             
    .opcode(opcode),               
    .endereco_reg(end1),  // sempre vou mostrar o registrador 1 no lcd          
    .resultado_ula(data_in),      
    .lcd_ocupado(lcd_ocupado),         
    
    .lcd_data(lcd_data),          
    .lcd_rs(RS),                   
    .lcd_rw(RW),                   
    .lcd_e(EN)
);


// para saber se apertou o botao de enviar
reg b_enviar_anterior;
wire enviou = (b_enviar_anterior == 1'b0 && b_enviar == 1'b1);


// definir se o sistema esta ligado ou não

reg sist_ligado = 0;
always @(posedge b_ligar) begin
    sist_ligado <= ~sist_ligado;    
end


// logica dos estados da MSF
always @(posedge clk) begin
    b_enviar_anterior <= b_enviar; // registra o estado do botao de enviar

    if (sist_ligado) begin

        case (estado_cpu)

        off: begin
            estado_cpu <= espera_envio;
        end

        espera_envio: begin
            if (enviou) begin
					 
                estado_cpu <= ler_memoria;
                if (opcode == CLEAR)
                    modo_ram <= CLEAR_RAM;
            end else begin
                estado_cpu <= espera_envio;
				end
        end

        ler_memoria: begin
            modo_ram <= LER;

            if(opcode == DISPLAY)
                end_r1 <= end1;
            else
                end_r1 <= end2;
        
            estado_cpu <= ula;
        end

        ula: begin
				// operacoes com imediato
            if (opcode == ADDI || opcode == SUBI || opcode == MUL) begin
                operando_2 <= imediato;
					 
            end else begin // operacao com 2 registradores
                operando_2 <= data_out2;
            end
            estado_cpu <= salvar_memoria;
        end

        salvar_memoria: begin
            
            end_r1 <= end1; // o mesmo end_r1 pode ser lido ou escrito
            
            if (opcode == DISPLAY) begin
                data_in <= data_out1;
                modo_ram <= LER;
            end else begin
                modo_ram <= SALVE;
            end
				
				
            if (opcode == LOAD) data_in <= imediato;
            
            if (opcode == CLEAR) data_in <= 0;

            if (opcode == ADD || opcode == ADDI || opcode == SUB || opcode == SUBI || opcode == MUL)
                data_in <= resultado_ula;

            lcd_start <= 1'b1; // sinal pro lcd inicializar
            estado_cpu <= upd_lcd;
        end

        upd_lcd: begin
            modo_ram = LER; // nao altera a memoria
				
            if (lcd_ocupado == 1) begin // condicao de espera do envio dos comandos
                lcd_start <= 1'b0;
            end
            
            if (lcd_start == 1'b0 && lcd_ocupado == 1'b0) begin
                estado_cpu <= espera_envio; // ja atualizou, esperar o botao de enviar novamente
            end
        end

        default: estado_cpu <= espera_envio;

        endcase

    end else begin // sistema desligado
        estado_cpu <= off;
        modo_ram <= CLEAR_RAM;
    end
end

// pegar o sinal do imediato e tratar o sinal
always @(*) begin

    if (opcode == LOAD || opcode == ADDI || opcode ==SUBI || opcode == MUL) begin
	 
        if (end3_ou_imd[6] == 1) begin // sinal negativo -> complemento a dois
            imediato = -{10'b0, end3_ou_imd[5:0]};
				
        end else begin // sinal positivo
            imediato = {10'b0, end3_ou_imd[5:0]};
        end
        // end de leitura 2 = 0, para evitar inconsistencias
        end_r2 = 0;
		  
		  
    end else begin // não é operacao com imediato
        end_r2 = end3_ou_imd[6:3];
        imediato = 0;
    end
end


endmodule