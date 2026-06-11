module lcd_controller_top (
    input  wire        clk,
    input  wire        rst,
    
    // Conexões internas com a CPU
    input  wire iniciar_escrita, // CPU sinaliza que há um novo resultado pronto
    input  wire [2:0]  opcode,          // Código da operação matemática executada (3 bits)
    input  wire [3:0]  endereco_reg,    // Endereço do registrador de destino (4 bits)
    input  wire [15:0] resultado_ula,   // Resultado numérico direto da ULA (16 bits)
    output wire        lcd_ocupado,     // Avisa à CPU para pausar enquanto o LCD desenha

    // Saídas para o LCD
    output wire  [7:0] lcd_data,   // Barramento físico de dados (D0 a D7) do LCD
    output wire        lcd_rs,     // Seleção de Registro (0 = Comando, 1 = Caractere/Texto)
    output wire        lcd_rw,     // Seleção de Leitura/Escrita (Sempre 0 = Modo Escrita)
    output wire        lcd_e       // Enable: Pulso que valida o dado na borda de descida
);

    // -----------------------------------------------------------------------
    // Instância do módulo de inicialização
    // -----------------------------------------------------------------------
    wire [7:0] init_data;
    wire       init_rs;
    wire       init_rw;
    wire       init_e;
    wire       init_done;
	 
    reg        start_init; // gerado pelo controlador

	 
    lcd_init_hd44780 lcd_init (
        .clk      (clk),
        .rst      (rst),
        .start    (start_init),
        .done     (init_done),
        .lcd_data (init_data),
        .lcd_rs   (init_rs),
        .lcd_rw   (init_rw),
        .lcd_e    (init_e)
    );
	
    // -----------------------------------------------------------------------
    // MUX: decide quem controla o LCD (init ou controlador principal)
    // -----------------------------------------------------------------------
    // Se controller_mode == 0: 'lcd_init' controla o LCD
    // Se controller_mode == 1: 'lcd_controller_top' assume 
	 
    wire controller_mode = init_done;
    assign lcd_data = (controller_mode == 0) ? init_data : wr_data;
    assign lcd_rs   = (controller_mode == 0) ? init_rs   : wr_rs;
    assign lcd_rw   = (controller_mode == 0) ? init_rw   : wr_rw;
    assign lcd_e    = (controller_mode == 0) ? init_e    : wr_e;
	
    // Lógica para ligar/desligar o display alternadamente a cada pulso de reset externo
    reg ligado = 1'b0;
    always @ (negedge rst) begin
        ligado <= ~ligado;
    end

    // -----------------------------------------------------------------------
    // Mensagem a ser exibida
    // -----------------------------------------------------------------------
    localparam integer TAM_MENSAGEM = 35;  // Tamanho total do array de varredura (Comandos + Caracteres)
    reg [7:0] message [0:TAM_MENSAGEM-1];  // Buffer que armazena os códigos ASCII de cada caractere
    reg [TAM_MENSAGEM-1:0] sinal_rs;       // Buffer paralelo que define se a posição é Comando (0) ou Texto (1)
    
    // Registradores Latch: Capturam os dados da CPU no instante exato do sinal 'iniciar_escrita'
    // Isso evita fantasmas ou distorções na tela se a CPU mudar de instrução no meio da varredura do LCD.
    reg [15:0] latched_dado; 
    reg [3:0]  latched_opcode;
    reg [3:0]  latched_addr;

    // -----------------------------------------------------------------------
    // Formatação BINÁRIO -> TEXTO / ASCII
    // -----------------------------------------------------------------------
    
    // Decodificador do opcode: Converte o número binário da instrução em uma string ASCII de 7 letras
    // Usamos 56 bits porque cada caractere ocupa exatamente 8 bits (7 * 8 = 56)
    reg [55:0] op_str;
	 
    always @(*) begin
        case (latched_opcode)
            4'd0: op_str = "LOAD   ";
            4'd1: op_str = "ADD    ";
            4'd2: op_str = "ADDI   ";
            4'd3: op_str = "SUB    ";
            4'd4: op_str = "SUBI   ";
            4'd5: op_str = "MUL    ";
            4'd6: op_str = "CLEAR  ";
            4'd7: op_str = "DPL    ";
            4'd8: op_str = "----   ";          // pro estado inicial pós-reset
            default: op_str = "UNK    ";       // default de proteção de circuito para opcodes desconhecidos
        endcase
    end

    // Tratamento do valor absoluto e sinal: O LCD precisa receber os caracteres isolados
    // Se o dado for negativo (bit 15 = 1), fazemos o complemento de dois para achar o valor absoluto e salvamos o caractere "-"
    wire [15:0] valor_absoluto = (latched_dado[15]) ? (~latched_dado + 16'd1) : latched_dado;
    wire [7:0] caractere_sinal = (latched_dado[15]) ? "-" : "+";

    // Função 'obter_digito': Isola uma ordem decimal de um binário de 16 bits usando divisões sucessivas.
    // Adiciona 0x30 ao resto para deslocar o valor numérico puro para a casa correspondente na Tabela ASCII (ex: 5 vira '5' ou 0x35).
    function [7:0] obter_digito;
        input [15:0] valor_binario;
        input [2:0] indice_digito;
        reg [15:0] temp;
        begin
            case (indice_digito)
                0: temp = (valor_binario % 10);          // Unidade
                1: temp = (valor_binario / 10) % 10;     // Dezena
                2: temp = (valor_binario / 100) % 10;    // Centena
                3: temp = (valor_binario / 1000) % 10;   // Milhar
                4: temp = (valor_binario / 10000) % 10;  // Dezena de Milhar
                default: temp = 0;
            endcase
            obter_digito = temp[7:0] + 8'h30;       // Ajuste final para mapeamento da Tabela ASCII
        end
    endfunction

    // -----------------------------------------------------------------------
    // Lyout da tela
    // -----------------------------------------------------------------------
    integer i;
    always @(*) begin
         // Laço de inicialização: inicia preenchendo todo o buffer com espaços em branco (ASCII 0x20)
         for (i = 0; i < TAM_MENSAGEM; i = i + 1) begin
            message[i] = 8'h20; 
            sinal_rs[i] = 1'b1; // Configuração padrão: Assume que o dado enviado é texto
         end
          
         // Índice 0: Comando para ligar ou apagar o visor fisicamente
         message[0] = (ligado ? 8'h0C : 8'h08); 
         sinal_rs[0] = 1'b0;  // RS = 0 (Sinaliza que é uma instrução de controle ao LCD)

         // Índice 1: Comando para forçar o cursor do LCD a se posicionar no início da linha 1 (0x80)
         message[1] = 8'h80;
         sinal_rs[1] = 1'b0;

         // Índices 2 a 8: Fatiamento da String do Opcode caractere por caractere (Linha 1)
         message[2] = op_str[55:48]; // Letra 1
         message[3] = op_str[47:40]; // Letra 2
         message[4] = op_str[39:32]; // Letra 3
         message[5] = op_str[31:24]; // Letra 4
         message[6] = op_str[23:16]; // Letra 5
         message[7] = op_str[15:8];  // Letra 6
         message[8] = op_str[7:0];   // Letra 7
         
         sinal_rs[2] = 1; sinal_rs[3] = 1; sinal_rs[4] = 1; sinal_rs[5] = 1;
         sinal_rs[6] = 1; sinal_rs[7] = 1; sinal_rs[8] = 1; // RS = 1 para escrita de caracteres textuais

         // Índice 12 a 17: Montagem visual do registrador de destino no formato [XXXX]
         message[12] = "["; 
         sinal_rs[12] = 1;
         
         if (latched_opcode == 4'd8) begin  // Se for o estado inicial, o endereço é omitido com traços '----'
              message[13] = "-"; message[14] = "-"; message[15] = "-"; message[16] = "-";
         end else begin   // Converte o endereço binário de 4 bits em caracteres legíveis '0' ou '1'
              message[13] = (latched_addr[3] ? 8'h31 : 8'h30); 
              message[14] = (latched_addr[2] ? 8'h31 : 8'h30);
              message[15] = (latched_addr[1] ? 8'h31 : 8'h30);
              message[16] = (latched_addr[0] ? 8'h31 : 8'h30);
         end
         
         sinal_rs[13] = 1; sinal_rs[14] = 1; sinal_rs[15] = 1; sinal_rs[16] = 1; sinal_rs[17] = 1;
         message[17] = "]"; 

         // Índice 18: Comando estrutural para forçar o cursor do LCD a quebrar para a LINHA 2 (0xC0)
         message[18] = 8'hC0; 
         sinal_rs[18] = 1'b0; // RS = 0 (Instrução de controle)

         // Índices 29 a 34: Preenchimento do bloco de dados numéricos formatados na segunda linha
         message[29] = caractere_sinal;                       // Caractere de sinal mapeado (+ ou -)
         message[30] = obter_digito(valor_absoluto, 4);       // Caractere correspondente à Dezena de Milhar
         message[31] = obter_digito(valor_absoluto, 3);       // Caractere correspondente ao Milhar
         message[32] = obter_digito(valor_absoluto, 2);       // Caractere correspondente à Centena
         message[33] = obter_digito(valor_absoluto, 1);       // Caractere correspondente à Dezena
         message[34] = obter_digito(valor_absoluto, 0);       // Caractere correspondente à Unidade
         
         sinal_rs[29] = 1; sinal_rs[30] = 1; sinal_rs[31] = 1; sinal_rs[32] = 1; sinal_rs[33] = 1;
    end

    // -----------------------------------------------------------------------
    // Temporizações para escrita de caracteres (ajustar ao clock real)
    // -----------------------------------------------------------------------
	 // Exemplo para 50 MHz:
    localparam [31:0] DELAY_WRITE = 32'd2000;  // ~40 us
    localparam [31:0] DELAY_PULSE = 32'd50;    // ~1 us

    // -----------------------------------------------------------------------
    // Estados da FSM principal
    // -----------------------------------------------------------------------
	 
    localparam [2:0] 
        S_WAIT_INIT = 3'd0,    // Bloqueio inicial: Aguarda a rotina do módulo 'lcd_init' terminar
        S_IDLE      = 3'd1,    // Repouso: Aguarda um comando de 'iniciar_escrita' vindo da CPU
        S_PREPARE   = 3'd2,    // Preparação: Estabiliza os dados e o RS nas linhas de barramento
        S_PULSE_E   = 3'd3,    // Amostragem: Eleva o pino Enable para 1 para o LCD ler o dado
        S_WAIT      = 3'd4,    // Atraso de hardware: Espera o LCD salvar internamente o caractere
        S_DONE      = 3'd5;    // Conclusão: Finaliza o ciclo de varredura e limpa as flags
        
    reg [2:0]  state, next_state;
    reg [31:0] delay_cnt, next_delay_cnt;
    reg [5:0]  msg_index, next_msg_index;   // Ponteiro que caminha de 0 a 34 no buffer da mensagem

    // sinal que mantém a linha de ocupado em nível lógico alto durante todo o processo de escrita
    // isso bloqueia o fluxo da Mini_CPU, impedindo sobreposição ou perda de dados
    assign lcd_ocupado = (iniciar_escrita || state == S_WAIT_INIT || state == S_PREPARE || state == S_PULSE_E || state == S_WAIT);

	
	 // =======================================================================
    // Bloco Sequencial: atualização de estados, contadores e amostragem do latch
    // =======================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= S_WAIT_INIT;
            delay_cnt      <= 32'd0;
            msg_index      <= 6'd0;
            latched_dado   <= 16'd0;
            latched_opcode <= 4'd8;   // Inicializa apontando para a string de hifens "----"
            latched_addr   <= 4'd0;
				
        end else begin
            state        <= next_state;
            delay_cnt    <= next_delay_cnt;
            msg_index    <= next_msg_index;
            
            // Captura os dados da ULA somente em repouso quando a CPU der o sinal de início
            if (state == S_IDLE && iniciar_escrita) begin
                latched_dado   <= resultado_ula;
                latched_opcode <= {1'b0, opcode}; // Expande o opcode recebido de 3 para 4 bits internos
                latched_addr   <= endereco_reg;
            end
        end
    end
	 
	 // =======================================================================
    // Bloco combinacional: cálculo do próximo estado/contador/índice
    // =======================================================================
    always @(*) begin 
        next_state     = state;
        next_delay_cnt = delay_cnt;
        next_msg_index = msg_index;

        case (state)
            // Espera a inicialização do LCD ser concluída
            S_WAIT_INIT: if (init_done) begin next_state = S_PREPARE; next_msg_index = 6'd0; end
            
            // Aguarda pulso da CPU em execução normal
            S_IDLE:      if (iniciar_escrita) begin next_state = S_PREPARE; next_msg_index = 6'd0; end
            
             // Prepara para escrever o caractere atual
            S_PREPARE:   begin next_state = S_PULSE_E; next_delay_cnt = DELAY_PULSE; end
            
            // Gera pulso de Enable
            S_PULSE_E:   if (delay_cnt > 0) next_delay_cnt = delay_cnt - 1; 
                         else begin next_state = S_WAIT; next_delay_cnt = DELAY_WRITE; end
            
            // Espera o tempo de escrita do caractere
            S_WAIT:      if (delay_cnt > 0) next_delay_cnt = delay_cnt - 1; 
                         else if (msg_index == (TAM_MENSAGEM-1)) next_state = S_DONE; 
                         else begin next_msg_index = msg_index + 1; next_state = S_PREPARE; end
            
            // Conclusão da varredura dos 35 índices, retorna para o repouso liberando o sinal ocupado
            S_DONE:      next_state = S_IDLE; 
            
            default:     begin next_state = S_WAIT_INIT; next_delay_cnt = 32'd0; next_msg_index = 6'd0; end
        endcase
    end

    // -----------------------------------------------------------------------
    //Bloco combinacional: Geração das saídas
    // -----------------------------------------------------------------------
    reg [7:0] wr_data; reg wr_rs; reg wr_rw; reg wr_e;

    always @(*) begin
        
		  // start_init: fica em '1' enquanto estamos esperando a inicialização
        // O módulo lcd_init só usa o nível de start para sair do IDLE
        start_init = (state == S_WAIT_INIT) ? 1'b1 : 1'b0;
        
        // Valores padrões preventivos
        wr_data = 8'h00; wr_rs = 1'b0; wr_rw = 1'b0; wr_e  = 1'b0;
        
        case (state)
            // Em preparação, o dado e o RS são estabilizados, mas o Enable fica inativo (0)
            S_PREPARE: begin wr_data = message[msg_index][7:0]; wr_rs = sinal_rs[msg_index]; wr_rw = 1'b0; wr_e = 1'b0; end
            // No estado de pulso, o pino Enable é elevado a 1 mantendo os mesmos dados estáveis
            S_PULSE_E: begin wr_data = message[msg_index][7:0]; wr_rs = sinal_rs[msg_index]; wr_rw = 1'b0; wr_e = 1'b1; end
            // No estado de espera, o Enable cai para 0, forçando o display a ler a informação
            S_WAIT:    begin wr_data = message[msg_index][7:0]; wr_rs = sinal_rs[msg_index]; wr_rw = 1'b0; wr_e = 1'b0; end
            
            default:   begin wr_rs = 1'b0; wr_rw = 1'b0; wr_e = 1'b0; wr_data = 8'h00; end
        endcase
    end
endmodule